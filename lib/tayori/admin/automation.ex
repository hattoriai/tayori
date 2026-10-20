defmodule Tayori.Admin.Automation do
  @moduledoc false
  # What the inbox and the settings say of the automation: the sources
  # and the last time the admin read them, the digest's cadence in words,
  # and the ingest token and GitHub secret, when Tayori has them.

  alias Tayori.{Inbox, Settings, Source}

  # The ingest endpoint, GitHub's webhook and the digest's status come
  # with modules of their own: the admin shows them when they are there.
  @setting "inbox"

  @doc "The sources of the `:inbox` config: their names, modules and paths."
  def sources(config) do
    for {module, opts} <- config.inbox.sources do
      %{name: Source.name(module, opts), module: inspect(module), path: path(opts[:path])}
    end
  end

  defp path(nil), do: nil
  defp path({app, path}) when is_atom(app), do: "#{path} (#{app})"
  defp path(path) when is_binary(path), do: path
  defp path(other), do: inspect(other)

  @doc """
  Reads the sources, and keeps what each gave for the settings. Returns
  `Tayori.Inbox.ingest/0`'s results.
  """
  def read_sources do
    results = Inbox.ingest()

    sources =
      Map.new(results, fn
        {name, {:ok, counts}} ->
          {name,
           %{
             "added" => counts.added,
             "existing" => counts.existing,
             "errors" => length(counts.errors)
           }}

        {name, {:error, reason}} ->
          {name, %{"error" => reason(reason)}}
      end)

    :ok =
      Settings.put(@setting, %{
        "read_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "sources" => sources
      })

    results
  end

  @doc "When the admin last read the sources, and what each gave: `{at, sources}`, or nil."
  def last_read do
    with %{"read_at" => at, "sources" => sources} <- Settings.get(@setting),
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      {at, sources}
    else
      _ -> nil
    end
  end

  @doc "What reading the sources gave, in a sentence for a flash."
  def summary(results) when map_size(results) == 0, do: "There is no source to read."

  def summary(results) do
    results
    |> Enum.sort()
    |> Enum.map_join(" ", fn
      {name, {:ok, counts}} -> "#{name}: #{counted(counts)}."
      {name, {:error, reason}} -> "#{name}: not read (#{reason(reason)})."
    end)
  end

  @doc "A source's counts, from `read_sources/0` or as kept, in words."
  def counted(%{"error" => error}), do: "not read (#{error})"

  def counted(%{"added" => added, "existing" => existing} = counts),
    do: counted(%{added: added, existing: existing, errors: counts["errors"] || 0})

  def counted(%{added: added, existing: existing, errors: errors}) do
    [
      "#{added} new",
      "#{existing} already in",
      if(errors not in [0, []], do: "#{count(errors)} not valid")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp count(errors) when is_list(errors), do: length(errors)
  defp count(errors), do: errors

  defp reason(reason) when is_binary(reason), do: reason
  defp reason({:file, path, posix}), do: "#{path}: #{:file.format_error(posix)}"
  defp reason(reason), do: inspect(reason)

  @doc "When the digest runs, in words."
  def cadence(%{every: :manual}), do: "When you ask"
  def cadence(%{every: :ingest}), do: "When changes come"

  def cadence(%{every: {:weekly, day}, at: at}),
    do: "Every #{day |> Atom.to_string() |> String.capitalize()} at #{time(at)}"

  def cadence(%{every: :monthly, at: at}), do: "On the first of each month at #{time(at)}"
  def cadence(%{every: {:days, 1}, at: at}), do: "Every day at #{time(at)}"
  def cadence(%{every: {:days, n}, at: at}), do: "Every #{n} days at #{time(at)}"

  defp time(at), do: Calendar.strftime(at, "%H:%M UTC")

  @doc "The digest's status (`Tayori.Digest.status/0`)."
  defdelegate digest_status, to: Tayori.Digest, as: :status

  @doc "Whether there is an ingest token."
  defdelegate token?, to: Tayori.Ingest

  @doc "Makes a new ingest token, in place of the one there is."
  defdelegate new_token, to: Tayori.Ingest

  @doc "Revokes the ingest token."
  defdelegate revoke_token, to: Tayori.Ingest

  @doc "Whether there is a GitHub secret."
  defdelegate secret?, to: Tayori.GitHub

  @doc "Makes a new GitHub secret, in place of the one there is."
  defdelegate new_secret, to: Tayori.GitHub

  @doc "Removes the GitHub secret."
  defdelegate remove_secret, to: Tayori.GitHub

  @doc """
  The address of a mount of the JSON API: `:embed`, the one the embed's
  sites read (`as: :tayori_embed`, else the last mount that is not for
  machines, as the guides mount the sites' after the app's own), or
  `:machines`, the one CI and GitHub send to (`as: :tayori_machines`, as
  the Automation guide mounts it). Nil when there is none.
  """
  def api_url(socket, kind) do
    mounts =
      socket.router
      |> PhoenixMountable.mounts()
      |> Enum.filter(&(&1.definition == Tayori.Router.API))

    case pick(mounts, kind) do
      nil -> nil
      mount -> String.trim_trailing(socket.endpoint.url(), "/") <> mount.path
    end
  end

  defp pick(mounts, :machines), do: Enum.find(mounts, &named?(&1, "machines"))

  defp pick(mounts, :embed) do
    Enum.find(mounts, &named?(&1, "embed")) ||
      mounts |> Enum.reject(&named?(&1, "machines")) |> List.last()
  end

  defp named?(%{name: name}, word) when is_atom(name) and name != nil,
    do: name |> Atom.to_string() |> String.contains?(word)

  defp named?(_mount, _word), do: false
end
