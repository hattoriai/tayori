if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.RemoveStep do
    @moduledoc false
    use Sake.Tool,
      name: "remove_step",
      title: "Remove a step from a sequence",
      description:
        "Remove a step from a sequence, with its letters in every language: no one gets " <>
          "it from now. The letters it sent stay in the results. A broadcast's one step " <>
          "is not removed. Returns the campaign whole.",
      scope: "tayori:campaigns:write",
      annotations: [read_only: false, destructive: true, idempotent: true, open_world: false]

    arg :step_id, :string,
      required: true,
      max_length: 64,
      description: "The step's id (get_campaign)"

    alias Tayori.MCP.Campaigns

    @impl true
    def execute(%{step_id: id}, _ctx) do
      with {:ok, step, campaign} <- Campaigns.fetch_step(id),
           {:ok, _step} <- Tayori.Campaigns.remove_step(step) do
        {:ok, Campaigns.campaign_detail(campaign)}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end
  end
end
