if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Access do
    @moduledoc false
    # What the principal may do over MCP, asked of the app's resolver on
    # every request, as the admin asks it (`resolve_access/1`): `:all`, every
    # tool its token's scopes allow; `:read_only`, only those of
    # `tayori:read`; anything else, nothing. Without a resolver in the `:mcp`
    # config, nobody may: a person signed in to the app is not one who
    # writes its news until the app says so.
    #
    # It filters the lists, and so the calls, since Sake asks `:after_list`
    # again before a call reaches a tool: a tool the principal is not shown,
    # it cannot call.

    alias Tayori.MCP.Support

    def init(opts), do: opts

    def call(%{items: items, ctx: ctx} = payload, _opts) do
      items =
        case Support.access(ctx.scope) do
          :all -> items
          :read_only -> Enum.reject(items, &("tayori:write" in Map.get(&1, :scopes, [])))
          :forbidden -> []
        end

      {:cont, %{payload | items: items}}
    end
  end
end
