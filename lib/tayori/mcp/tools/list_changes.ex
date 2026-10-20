if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.ListChanges do
    @moduledoc false
    use Sake.Tool,
      name: "list_changes",
      title: "List the inbox",
      description:
        "List the changes of the inbox, what shipped, the newest first: new ones wait " <>
          "for an entry, drafted ones are in one (entry_id), hidden ones were put " <>
          "aside. Only new public changes go into a draft_entry.",
      scope: "tayori:read",
      annotations: [read_only: true, idempotent: true, open_world: false]

    arg :state, {:enum, ["new", "drafted", "hidden"]},
      description: "Only the changes in this state"

    arg :source, :string,
      max_length: 32,
      description: "Only those of this source (\"github\", \"mcp\")"

    arg :audience, {:enum, ["public", "internal"]},
      description: "Only those for readers (public) or for the team (internal)"

    arg :limit, :integer, min: 1, max: 200, description: "The most changes to list (50)"

    alias Tayori.Inbox
    alias Tayori.MCP.Support

    @impl true
    def execute(args, _ctx) do
      changes =
        Inbox.list(
          state: args[:state],
          source: args[:source],
          audience: args[:audience],
          limit: args[:limit] || 50
        )

      {:ok, %{changes: Enum.map(changes, &Support.change/1)}}
    end
  end
end
