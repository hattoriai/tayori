if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.CreateCampaign do
    @moduledoc false
    use Sake.Tool,
      name: "create_campaign",
      title: "Create a campaign",
      description:
        "Create a campaign, a draft that sends nothing. A sequence: a person enters on " <>
          "an event (trigger_event) or by hand, then gets its steps' letters at their times " <>
          "after entry (add_step), until the goal matches them, the steps end or max_days " <>
          "pass. A broadcast: one letter to everyone in its audience; it is made with its " <>
          "one step, whose letter you write with update_step. Returns the campaign whole, " <>
          "as get_campaign does.",
      scope: "tayori:campaigns:write",
      annotations: [read_only: false, destructive: false, idempotent: false, open_world: false]

    arg :name, :string, required: true, max_length: 160, description: "Its name, for the team"

    arg :kind, {:enum, ["sequence", "broadcast"]},
      required: true,
      description: "sequence or broadcast"

    arg :purpose, {:enum, ["product", "marketing"]},
      description:
        "product (the default): what the product needs to say; marketing: news and " <>
          "offers, which people may refuse. A person unsubscribes from one or both"

    arg :trigger_event, :string,
      max_length: 64,
      description:
        "Of a sequence: the event that enrolls a person (list_audience); none for by hand"

    arg :audience, :any,
      description:
        "Who may enter the sequence, or who gets the broadcast: a condition (list_audience); " <>
          "everyone if not given"

    arg :goal, :any,
      description: "Of a sequence: a condition; a person who matches it leaves it, done"

    arg :min_gap_hours, :integer,
      min: 0,
      max: 8760,
      description: "Of a sequence: the hours at least between two letters to a person (24)"

    arg :max_days, :integer,
      min: 0,
      max: 3650,
      description: "Of a sequence: the days a person stays in it after entry; none for no end"

    arg :from_name, :string,
      max_length: 160,
      description: "The sender's name, instead of the app's"

    arg :reply_to, :string, max_length: 320, description: "The address replies go to"

    alias Tayori.MCP.{Campaigns, Support}

    @impl true
    def execute(args, ctx) do
      with {:ok, attrs} <- Campaigns.settings(args),
           {:ok, campaign} <- Tayori.Campaigns.create(attrs, author: Support.author(ctx)) do
        {:ok, Campaigns.campaign_detail(campaign)}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end
  end
end
