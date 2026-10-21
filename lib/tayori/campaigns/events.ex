defmodule Tayori.Campaigns.Events do
  @moduledoc false
  # The events the app tracks (Tayori.track/3), kept for the days of the
  # :keep_events_days option of :campaigns (400), then deleted.

  import Ecto.Query

  alias Tayori.Campaigns.Event
  alias Tayori.Config

  @doc false
  def insert!(%Config{} = config, person_id, name, meta, %DateTime{} = at) do
    changeset =
      Event.changeset(%Event{}, %{
        person: person_id,
        name: name,
        meta: meta,
        occurred_at: usec(at)
      })

    case changeset do
      %{valid?: true} ->
        config.repo.insert!(changeset, prefix: config.prefix)

      %{errors: errors} ->
        raise ArgumentError,
              "Tayori.track/3 takes a person's id of 255 characters at most and a name of 1 " <>
                "to 64, got: #{inspect(errors)}"
    end
  end

  @doc false
  # Deletes the events older than the days the config keeps them, at a
  # time; how many it deleted.
  @spec delete_old(Config.t(), DateTime.t()) :: non_neg_integer()
  def delete_old(%Config{campaigns: %{keep_events_days: days}} = config, %DateTime{} = now) do
    before = DateTime.add(now, -days, :day)

    {count, _} =
      config.repo.delete_all(from(e in Event, where: e.occurred_at < ^before),
        prefix: config.prefix
      )

    count
  end

  def delete_old(%Config{campaigns: nil}, _now), do: 0

  defp usec(%DateTime{microsecond: {value, _}} = at), do: %{at | microsecond: {value, 6}}
end
