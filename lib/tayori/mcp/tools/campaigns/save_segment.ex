if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.SaveSegment do
    @moduledoc false
    use Sake.Tool,
      name: "save_segment",
      title: "Save a segment",
      description:
        "Save a condition with a name, as a segment that campaigns and other conditions " <>
          ~s[can name ({"segment": "<id>", "op": "in"}): a new one, or with an id, ] <>
          "a change of one (only what is given changes; a campaign that names it sees the " <>
          "change at once). Returns the segment with its sentence and how many people it " <>
          "has now. Try the condition with preview_segment first.",
      scope: "tayori:campaigns:write",
      annotations: [read_only: false, destructive: true, idempotent: false, open_world: false]

    arg :id, :string,
      max_length: 64,
      description: "The id of the segment to change; none for a new one"

    arg :name, :string, max_length: 160, description: "Its name, as \"Pro, signed up this month\""
    arg :description, :string, max_length: 2000, description: "What it is for; empty takes it off"

    arg :condition, :any,
      description: "The condition, a JSON object as list_audience says; needed for a new segment"

    alias Tayori.Campaigns.Segments
    alias Tayori.MCP.{Campaigns, Support}

    @impl true
    def execute(args, _ctx) do
      with {:ok, condition} <- Campaigns.condition(args[:condition], "condition", []),
           attrs = attrs(args, condition),
           {:ok, segment} <- save(args[:id], attrs) do
        {:ok, Campaigns.segment(segment)}
      else
        {:error, reason} -> {:error, Support.error(reason)}
      end
    end

    defp attrs(args, condition) do
      %{"name" => args[:name], "description" => args[:description], "condition" => condition}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)
    end

    defp save(nil, attrs) do
      cond do
        attrs["name"] in [nil, ""] -> {:error, "A new segment needs a name."}
        attrs["condition"] == nil -> {:error, "A new segment needs a condition."}
        true -> Segments.create(attrs)
      end
    end

    defp save(id, attrs) do
      with {:ok, segment} <- Campaigns.fetch_segment(id) do
        if attrs == %{},
          do: {:error, "Nothing to change: give a name, a description or a condition."},
          else: Segments.update(segment, attrs)
      end
    end
  end
end
