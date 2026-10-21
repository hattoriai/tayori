defmodule Tayori.Campaigns.Webhooks do
  @moduledoc false
  # What every provider's webhook does (Tayori.Campaigns.Provider): a hard
  # bounce or a complaint suppresses the address for everything and marks
  # its letter; a delivery or a soft bounce changes nothing. The same
  # event twice is the same.

  import Ecto.Query

  alias Tayori.{Campaigns, Config}
  alias Tayori.Campaigns.Delivery

  require Logger

  @doc false
  # The provider of a name in the config, `{module, opts}`, or nil. The
  # name is the last part of the webhook's path: it is compared to the
  # configured names as a string, never made an atom.
  @spec provider(Config.t(), String.t()) :: {module(), map()} | nil
  def provider(%Config{campaigns: %{providers: providers}}, name) when is_binary(name) do
    Enum.find_value(providers, fn {key, provider} ->
      if Atom.to_string(key) == name, do: provider
    end)
  end

  def provider(_config, _name), do: nil

  @doc false
  # Handles the events of a provider's payload. Returns how many were
  # handled.
  @spec handle(Config.t(), module(), map()) :: non_neg_integer()
  def handle(%Config{} = config, module, payload) when is_map(payload) do
    events = module.events(payload)
    Enum.each(events, &event(config, &1))
    length(events)
  end

  defp event(config, %{type: :bounced, hard?: true, email: email} = event) do
    suppress(email, "bounced")
    mark(config, event[:provider_id], "bounced")
  end

  defp event(config, %{type: :complained, email: email} = event) do
    suppress(email, "complained")
    mark(config, event[:provider_id], "complained")
  end

  defp event(_config, _delivered_or_soft), do: :ok

  defp suppress(email, reason) when is_binary(email) do
    case Campaigns.suppress(email, "all", reason) do
      :ok ->
        :ok

      {:error, _changeset} ->
        Logger.warning("Tayori got a #{reason} of an address it cannot keep: #{inspect(email)}")
    end
  end

  defp suppress(_email, _reason), do: :ok

  # A complaint after a bounce stays a complaint.
  defp mark(_config, nil, _status), do: :ok

  defp mark(config, provider_id, status) when is_binary(provider_id) do
    from(d in Delivery, where: d.provider_id == ^provider_id and d.status != "complained")
    |> config.repo.update_all(
      [set: [status: status, updated_at: DateTime.utc_now()]],
      prefix: config.prefix
    )

    :ok
  end

  defp mark(_config, _provider_id, _status), do: :ok
end
