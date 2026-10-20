if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.GetEntry do
    @moduledoc false
    use Sake.Tool,
      name: "get_entry",
      title: "Get an entry",
      description:
        "Get an entry whole: its status, categories, segments, the URL on the public page " <>
          "when it has one, and each language's title, summary and body in Markdown, " <>
          "with the languages it is missing.",
      scope: "tayori:read",
      annotations: [read_only: true, idempotent: true, open_world: false]

    arg :id, :string, required: true, max_length: 160, description: "The entry's id, or its slug"

    alias Tayori.Config
    alias Tayori.MCP.Support

    @impl true
    def execute(%{id: id}, _ctx) do
      with {:ok, entry} <- Support.fetch_entry(id) do
        {:ok, Support.entry_detail(entry, Config.get())}
      end
    end
  end
end
