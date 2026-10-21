if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.PauseCampaign do
    @moduledoc false
    use Sake.Tool,
      name: "pause_campaign",
      title: "Pause a campaign",
      description:
        "Stop a campaign from sending, at once. An active sequence pauses: no one enters " <>
          "and no letter goes until it is started again (start_campaign), when its people " <>
          "go on where they were. A scheduled broadcast goes back to a draft, not sent. " <>
          "A broadcast being sent or sent cannot be stopped.",
      scope: "tayori:campaigns:write",
      annotations: [read_only: false, destructive: false, idempotent: false, open_world: false]

    arg :id, :string, required: true, max_length: 64, description: "The campaign's id"

    alias Tayori.MCP.Campaigns

    @impl true
    def execute(%{id: id}, _ctx) do
      with {:ok, campaign} <- Campaigns.fetch_campaign(id),
           {:ok, campaign} <- pause(campaign) do
        {:ok, Campaigns.campaign_detail(campaign)}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end

    defp pause(%{kind: "sequence", status: "active"} = campaign),
      do: Tayori.Campaigns.pause(campaign)

    defp pause(%{kind: "broadcast", status: "scheduled"} = campaign),
      do: Tayori.Campaigns.cancel_broadcast(campaign)

    defp pause(%{kind: "sequence", status: status}),
      do: {:error, "The sequence is #{status}: only an active one pauses."}

    defp pause(%{kind: "broadcast", status: status}),
      do: {:error, "The broadcast is #{status}: only a scheduled one can be stopped."}
  end
end
