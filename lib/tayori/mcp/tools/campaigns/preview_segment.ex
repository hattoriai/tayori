if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.PreviewSegment do
    @moduledoc false
    use Sake.Tool,
      name: "preview_segment",
      title: "Preview a segment",
      description:
        "Who a condition, or a saved segment, matches now: how many people, the first 10 " <>
          "(id, name, email, language), and the condition in words. It checks the " <>
          "condition and says what is wrong with it. Try a condition here before you " <>
          "save it (save_segment) or give it to a campaign. The conditions are as " <>
          "list_audience says.",
      scope: "tayori:campaigns:read",
      annotations: [read_only: true, idempotent: true, open_world: false]

    arg :condition, :any,
      description:
        ~s(A condition, a JSON object: {"attribute": "plan", "op": "in", "value": ["pro"]})

    arg :segment_id, :string, max_length: 64, description: "Or the id of a saved segment"

    alias Tayori.Audience
    alias Tayori.MCP.Campaigns

    @impl true
    def execute(args, _ctx) do
      with {:ok, condition, segment} <- condition(args[:condition], args[:segment_id]) do
        {:ok,
         condition
         |> Campaigns.counted()
         |> Map.put(:people, Enum.map(Audience.sample(condition, 10), &Campaigns.person/1))
         |> Map.put(:segment, segment && %{id: segment.id, name: segment.name})}
      end
    end

    defp condition(nil, nil),
      do: {:error, "Give a condition, or the segment_id of a saved segment."}

    defp condition(nil, id) do
      with {:ok, segment} <- Campaigns.fetch_segment(id),
           do: {:ok, segment.condition, segment}
    end

    defp condition(condition, nil) do
      with {:ok, normalized} <- Campaigns.condition(condition, "condition", []),
           do: {:ok, normalized, nil}
    end

    defp condition(_condition, _id), do: {:error, "Give a condition or a segment_id, not both."}
  end
end
