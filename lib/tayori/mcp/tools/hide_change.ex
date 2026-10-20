if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.HideChange do
    @moduledoc false
    use Sake.Tool,
      name: "hide_change",
      title: "Put a change aside",
      description:
        "Put a change of the inbox aside, one readers need not know of: no draft takes " <>
          "it. The admin can bring it back.",
      scope: "tayori:write",
      annotations: [read_only: false, destructive: false, idempotent: true, open_world: false]

    arg :id, :string, required: true, max_length: 64, description: "The change's id"

    alias Tayori.Inbox
    alias Tayori.MCP.Support

    @impl true
    def execute(%{id: id}, _ctx) do
      with {:ok, change} <- Support.fetch_change(id),
           {:ok, change} <- Inbox.hide(change) do
        {:ok, Support.change(change)}
      else
        {:error, reason} -> {:error, Support.error(reason)}
      end
    end
  end
end
