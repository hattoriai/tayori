if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.ListCampaigns do
    @moduledoc false
    use Sake.Tool,
      name: "list_campaigns",
      title: "List the campaigns",
      description:
        "List the campaigns, the newest first: sequences (letters to a person at times " <>
          "after they enter, on an event or by hand) and broadcasts (one letter to everyone " <>
          "in an audience, now or at a time), each with its id, name, purpose, status and " <>
          "number of steps. Use get_campaign for one whole, with its letters and results.",
      scope: "tayori:campaigns:read",
      annotations: [read_only: true, idempotent: true, open_world: false]

    arg :kind, {:enum, ["sequence", "broadcast", "all"]},
      description: "Only the sequences or the broadcasts (all by default)"

    arg :archived, :boolean, description: "With the archived campaigns (false)"

    alias Tayori.{Campaigns, Config}
    alias Tayori.MCP.Campaigns, as: Views

    @impl true
    def execute(args, _ctx) do
      config = Config.get()
      kind = if args[:kind] in ["sequence", "broadcast"], do: args[:kind]

      campaigns =
        [kind: kind, archived: args[:archived] == true]
        |> Campaigns.list()
        |> config.repo.preload(:steps, prefix: config.prefix)

      {:ok, %{campaigns: Enum.map(campaigns, &Views.campaign_summary/1)}}
    end
  end
end
