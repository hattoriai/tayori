if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.ListEntries do
    @moduledoc false
    use Sake.Tool,
      name: "list_entries",
      title: "List entries",
      description:
        "List the entries of the news: the drafts and the scheduled first, then the " <>
          "published, the newest first. Use get_entry for an entry whole.",
      scope: "tayori:read",
      annotations: [read_only: true, idempotent: true, open_world: false]

    arg :status, {:enum, ["draft", "scheduled", "published", "all"]},
      description: "Only the entries of this status (all by default)"

    arg :search, :string, max_length: 200, description: "Words of a title or a slug"
    arg :limit, :integer, min: 1, max: 200, description: "The most entries to list (50)"

    alias Tayori.{Config, Entries}
    alias Tayori.MCP.Support

    @impl true
    def execute(args, _ctx) do
      config = Config.get()
      limit = args[:limit] || 50

      entries =
        Entries.list(status: status(args[:status]), search: args[:search])

      {:ok,
       %{
         entries: entries |> Enum.take(limit) |> Enum.map(&Support.entry_summary(&1, config)),
         more: length(entries) > limit
       }}
    end

    defp status(status) when status in ["draft", "scheduled", "published"],
      do: String.to_existing_atom(status)

    defp status(_all), do: nil
  end
end
