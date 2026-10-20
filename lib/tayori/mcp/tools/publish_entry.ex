if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.PublishEntry do
    @moduledoc false
    use Sake.Tool,
      name: "publish_entry",
      title: "Publish an entry",
      description:
        "Publish an entry, now or at a time (a time to come schedules it). Call it only " <>
          "when the person asks for this entry to be published: it reaches the app's " <>
          "readers, in the app, on the public page and in the feeds, and may be emailed " <>
          "to the subscribers. Returns the entry with its URL.",
      scope: "tayori:write",
      annotations: [read_only: false, destructive: true, idempotent: false, open_world: true]

    arg :id, :string, required: true, max_length: 160, description: "The entry's id, or its slug"

    arg :at, :string,
      format: "date-time",
      description: "When, in ISO 8601 (2026-11-02T09:00:00Z); now if not given"

    alias Tayori.{Config, Entries, Entry}
    alias Tayori.MCP.Support

    @impl true
    def execute(args, _ctx) do
      with {:ok, entry} <- Support.fetch_entry(args.id),
           :ok <- unpublished(entry),
           {:ok, at} <- at(args[:at]),
           {:ok, entry} <- Entries.publish(entry, at) do
        {:ok, Support.entry_detail(Entries.get!(entry.id), Config.get())}
      else
        {:error, reason} -> {:error, Support.error(reason)}
      end
    end

    # Published again, an entry would be announced again.
    defp unpublished(entry) do
      case Entry.status(entry) do
        :published ->
          {:error,
           "The entry is already published, since #{Support.timestamp(entry.published_at)}."}

        _draft_or_scheduled ->
          :ok
      end
    end

    defp at(nil), do: {:ok, DateTime.utc_now()}
    defp at(text), do: Support.time(text)
  end
end
