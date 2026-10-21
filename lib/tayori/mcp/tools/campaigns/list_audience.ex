if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.ListAudience do
    @moduledoc false
    use Sake.Tool,
      name: "list_audience",
      title: "List the audience",
      description:
        "What the app says of its people, the words of every condition: the attributes " <>
          "(key, label, type, the values of an enum, the operators of its type), the events " <>
          "it tracks, and the saved segments with how many people each has now. Read it " <>
          "before you write a condition. A condition is a JSON object: " <>
          ~s({"all": [c, ...]}, {"any": [c, ...]}, {"not": c}, ) <>
          ~s({"attribute": "plan", "op": "in", "value": ["pro"]}, ) <>
          ~s({"event": "signed_up", "op": "happened", "within_days": 30} ) <>
          ~s[(within_days optional), {"segment": "<segment id>", "op": "in"}; ] <>
          ~s({"all": []} is everyone. Dates and times are ISO 8601; days ago a positive ) <>
          "number.",
      scope: "tayori:campaigns:read",
      annotations: [read_only: true, idempotent: true, open_world: false]

    alias Tayori.Audience.Attribute
    alias Tayori.Campaigns.Segments
    alias Tayori.Conditions
    alias Tayori.MCP.Campaigns

    @impl true
    def execute(_args, _ctx) do
      events? = Campaigns.events?()

      {:ok,
       %{
         attributes: Enum.map(Campaigns.attributes(), &attribute/1),
         events:
           Enum.map(Campaigns.events(), fn {name, label} -> %{name: name, label: label} end),
         events_in_conditions: events?,
         event_operators: if(events?, do: Conditions.event_operators(), else: []),
         segments: Enum.map(Segments.list(counts: true), &Campaigns.segment/1),
         limits: Conditions.limits()
       }}
    end

    defp attribute(%Attribute{} = attribute) do
      %{
        key: attribute.key,
        label: attribute.label,
        type: attribute |> Attribute.type_name() |> Atom.to_string(),
        operators: Conditions.operators(attribute.type),
        description: attribute.description
      }
      |> values(attribute.type)
    end

    defp values(map, {:enum, values}),
      do: Map.put(map, :values, Enum.map(values, fn {v, l} -> %{value: v, label: l} end))

    defp values(map, _type), do: map
  end
end
