if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.UpdateCampaign do
    @moduledoc false
    use Sake.Tool,
      name: "update_campaign",
      title: "Change a campaign",
      description:
        "Change a campaign's settings: only what is given changes. An empty object {} " <>
          "takes the goal off, or makes the audience everyone; an empty trigger_event makes " <>
          "a sequence by hand; max_days 0 takes the end off. Its kind and status never " <>
          "change here (start_campaign, pause_campaign, send_broadcast). A running " <>
          "sequence changes for its people at once. An archived campaign, or a broadcast " <>
          "sent, is locked.",
      scope: "tayori:campaigns:write",
      annotations: [read_only: false, destructive: true, idempotent: true, open_world: false]

    arg :id, :string, required: true, max_length: 64, description: "The campaign's id"
    arg :name, :string, max_length: 160, description: "Its name"

    arg :purpose, {:enum, ["product", "marketing"]},
      description: "product or marketing (see create_campaign)"

    arg :trigger_event, :string,
      max_length: 64,
      description: "Of a sequence: the event that enrolls a person; empty for by hand"

    arg :audience, :any, description: "A condition (list_audience); {} for everyone"
    arg :goal, :any, description: "Of a sequence: a condition; {} for none"

    arg :min_gap_hours, :integer,
      min: 0,
      max: 8760,
      description: "Of a sequence: the hours at least between two letters to a person"

    arg :max_days, :integer,
      min: 0,
      max: 3650,
      description: "Of a sequence: the days a person stays in it; 0 for no end"

    arg :from_name, :string,
      max_length: 160,
      description: "The sender's name; empty for the app's"

    arg :reply_to, :string,
      max_length: 320,
      description: "The address replies go to; empty for the app's"

    alias Tayori.MCP.Campaigns

    @impl true
    def execute(args, _ctx) do
      with {:ok, campaign} <- Campaigns.fetch_campaign(args.id),
           {:ok, attrs} <- Campaigns.settings(Map.delete(args, :kind)),
           :ok <- something(attrs),
           {:ok, campaign} <- Tayori.Campaigns.update(campaign, attrs) do
        {:ok, Campaigns.campaign_detail(campaign)}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end

    defp something(attrs) when attrs == %{}, do: {:error, "Nothing to change: give a setting."}
    defp something(_attrs), do: :ok
  end
end
