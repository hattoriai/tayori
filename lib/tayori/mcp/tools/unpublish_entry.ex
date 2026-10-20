if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.UnpublishEntry do
    @moduledoc false
    use Sake.Tool,
      name: "unpublish_entry",
      title: "Unpublish an entry",
      description:
        "Make a published or scheduled entry a draft again: its readers no longer see " <>
          "it. Published again later, it is announced again.",
      scope: "tayori:write",
      annotations: [read_only: false, destructive: true, idempotent: true, open_world: false]

    arg :id, :string, required: true, max_length: 160, description: "The entry's id, or its slug"

    alias Tayori.{Config, Entries}
    alias Tayori.MCP.Support

    @impl true
    def execute(%{id: id}, _ctx) do
      with {:ok, entry} <- Support.fetch_entry(id),
           {:ok, entry} <- unpublish(entry) do
        {:ok, Support.entry_detail(Entries.get!(entry.id), Config.get())}
      else
        {:error, reason} -> {:error, Support.error(reason)}
      end
    end

    defp unpublish(%{published_at: nil} = entry), do: {:ok, entry}
    defp unpublish(entry), do: Entries.unpublish(entry)
  end
end
