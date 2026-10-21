if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.StartCampaign do
    @moduledoc false
    use Sake.Tool,
      name: "start_campaign",
      title: "Start a sequence",
      description:
        "Start a sequence, a draft, or resume a paused one. Call it only when the person " <>
          "asks for this sequence to start: from then, the people who enter it are emailed " <>
          "its letters, and a resumed one's people get the letters whose time came while it " <>
          "was paused. Before, tell them how many people its audience has now " <>
          "(get_campaign), and what makes a person enter (its trigger). It needs a step at " <>
          "least, each with a letter in the app's first language with a subject and a body. " <>
          "For a broadcast, use send_broadcast.",
      scope: "tayori:campaigns:send",
      annotations: [read_only: false, destructive: true, idempotent: false, open_world: true]

    arg :id, :string, required: true, max_length: 64, description: "The sequence's id"

    alias Tayori.MCP.Campaigns

    @impl true
    def execute(%{id: id}, _ctx) do
      with {:ok, campaign} <- Campaigns.fetch_campaign(id),
           {:ok, campaign} <- start(campaign) do
        {:ok, Campaigns.campaign_detail(campaign)}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end

    defp start(%{kind: "broadcast"}),
      do: {:error, "This is a broadcast: send it with send_broadcast."}

    defp start(%{status: "draft"} = campaign), do: Tayori.Campaigns.start(campaign)
    defp start(%{status: "paused"} = campaign), do: Tayori.Campaigns.resume(campaign)

    defp start(%{status: "active"}), do: {:error, "The sequence is active already."}

    defp start(%{status: status}),
      do: {:error, "The sequence is #{status}: it cannot start again."}
  end
end
