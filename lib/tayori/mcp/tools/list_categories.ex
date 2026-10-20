if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.ListCategories do
    @moduledoc false
    use Sake.Tool,
      name: "list_categories",
      title: "List the categories",
      description:
        "List the categories of the news, in their order: an entry or a change names " <>
          "them by their key.",
      scope: "tayori:read",
      annotations: [read_only: true, idempotent: true, open_world: false]

    alias Tayori.{Categories, Config}
    alias Tayori.MCP.Support

    @impl true
    def execute(_args, _ctx) do
      config = Config.get()
      {:ok, %{categories: Enum.map(Categories.list(), &Support.category(&1, config))}}
    end
  end
end
