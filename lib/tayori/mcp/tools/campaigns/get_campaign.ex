if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.GetCampaign do
    @moduledoc false
    use Sake.Tool,
      name: "get_campaign",
      title: "Get a campaign",
      description:
        "Get a campaign whole: its settings (kind, purpose, status, trigger, the audience " <>
          "and the goal with their sentences, and how many people the audience has now), " <>
          "its steps in order, each with its time after entry, its skip_if and its letters " <>
          "by language (subject, preheader, body in Markdown, button), the merge tags its " <>
          "letters use, what keeps it from starting (problems), and its results.",
      scope: "tayori:campaigns:read",
      annotations: [read_only: true, idempotent: true, open_world: false]

    arg :id, :string, required: true, max_length: 64, description: "The campaign's id"

    alias Tayori.MCP.Campaigns

    @impl true
    def execute(%{id: id}, _ctx) do
      with {:ok, campaign} <- Campaigns.fetch_campaign(id) do
        {:ok, Campaigns.campaign_detail(campaign)}
      end
    end
  end
end
