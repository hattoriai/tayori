if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.SendBroadcast do
    @moduledoc false
    use Sake.Tool,
      name: "send_broadcast",
      title: "Send a broadcast",
      description:
        "Send a broadcast's letter to everyone in its audience, now or at a time (a time " <>
          "to come schedules it; pause_campaign takes a schedule back). Call it only when " <>
          "the person asks for this broadcast to be sent, after telling them how many " <>
          "people it reaches: get_campaign gives the audience's count, which you pass as " <>
          "expected_recipients. If the count is not that, nothing is sent and the error " <>
          "gives the count now: tell the person, and ask again. Those who unsubscribed, " <>
          "bounced or may not be emailed are left out when it goes. Its letter needs a " <>
          "subject and a body in the app's first language.",
      scope: "tayori:campaigns:send",
      annotations: [read_only: false, destructive: true, idempotent: false, open_world: true]

    arg :id, :string, required: true, max_length: 64, description: "The broadcast's id"

    arg :expected_recipients, :integer,
      required: true,
      min: 0,
      description: "How many people its audience has now, as the person was told"

    arg :at, :string,
      format: "date-time",
      description: "When, in ISO 8601 (2026-11-02T09:00:00Z); now if not given"

    alias Tayori.Audience
    alias Tayori.MCP.{Campaigns, Support}

    @impl true
    def execute(args, _ctx) do
      now = DateTime.utc_now()

      with {:ok, campaign} <- Campaigns.fetch_campaign(args.id),
           :ok <- broadcast(campaign),
           {:ok, at} <- at(args[:at], now),
           count = Audience.count(campaign.audience, now),
           :ok <- expected(count, args.expected_recipients),
           {:ok, campaign} <- Tayori.Campaigns.schedule_broadcast(campaign, at) do
        {:ok,
         campaign
         |> Campaigns.campaign_summary()
         |> Map.put(:recipients, count)}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end

    defp broadcast(%{kind: "broadcast", status: status}) when status in ["draft", "scheduled"],
      do: :ok

    defp broadcast(%{kind: "broadcast", status: status}),
      do: {:error, "The broadcast is #{status}: it cannot be sent again."}

    defp broadcast(_sequence),
      do: {:error, "This is a sequence: start it with start_campaign."}

    defp at(nil, now), do: {:ok, now}

    defp at(text, now) do
      with {:ok, at} <- Support.time(text) do
        {:ok, if(DateTime.compare(at, now) == :lt, do: now, else: at)}
      end
    end

    defp expected(count, count), do: :ok

    defp expected(count, expected) do
      {:error,
       "The audience has #{count} #{people(count)} now, not #{expected}: nothing was sent. " <>
         "Tell the person it reaches #{count}, and send it with expected_recipients " <>
         "#{count} if they still want it."}
    end

    defp people(1), do: "person"
    defp people(_count), do: "people"
  end
end
