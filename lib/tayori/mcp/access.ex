if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Access do
    @moduledoc false
    # What the principal may do over MCP, asked of the app's resolver on
    # every request, as the admin asks it (`resolve_access/1`): `:all`, every
    # tool its token's scopes allow; `:read_only`, only those of the read
    # scopes (`tayori:read`, `tayori:campaigns:read`); anything else,
    # nothing. Without a resolver in the `:mcp` config, nobody may: a person
    # signed in to the app is not one who writes its news until the app says
    # so.
    #
    # The tools of a module that is off (Tayori.Config) are not there: the
    # campaigns' tools are those under Tayori.MCP.Tools.Campaigns, the rest
    # are the changelog's.
    #
    # It filters the lists, and so the calls, since Sake asks `:after_list`
    # again before a call reaches a tool: a tool the principal is not shown,
    # it cannot call.

    alias Tayori.Config
    alias Tayori.MCP.Support

    def init(opts), do: opts

    def call(%{items: items, ctx: ctx} = payload, _opts) do
      config = Config.get()
      items = Enum.filter(items, &Config.module?(config, module_of(&1)))

      items =
        case Support.access(ctx.scope) do
          :all -> items
          :read_only -> Enum.filter(items, &read?/1)
          :forbidden -> []
        end

      {:cont, %{payload | items: items}}
    end

    defp read?(item),
      do: item |> Map.get(:scopes, []) |> Enum.all?(&String.ends_with?(&1, ":read"))

    @doc false
    # The module a tool belongs to.
    def module_of(%{module: module}) when is_atom(module) do
      if match?(["Tayori", "MCP", "Tools", "Campaigns" | _], Module.split(module)),
        do: :campaigns,
        else: :changelog
    end

    def module_of(_item), do: :changelog
  end
end
