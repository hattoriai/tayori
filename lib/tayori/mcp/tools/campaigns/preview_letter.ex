if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.PreviewLetter do
    @moduledoc false
    use Sake.Tool,
      name: "preview_letter",
      title: "Preview a letter",
      description:
        "A step's letter as one person would get it: in their language, with their merge " <>
          "tags ({{first_name|there}}) filled in: the subject, the preheader, the text " <>
          "with the button and the link to unsubscribe, and the merge tags they have no " <>
          "value for. Nothing is sent. The person is the first of the campaign's audience " <>
          "unless given.",
      scope: "tayori:campaigns:read",
      annotations: [read_only: true, idempotent: true, open_world: false]

    arg :campaign_id, :string, required: true, max_length: 64, description: "The campaign's id"

    arg :step_id, :string,
      max_length: 64,
      description: "The step's id (get_campaign); not needed for a broadcast"

    arg :person_id, :string,
      max_length: 255,
      description: "The id of a person (preview_segment); the audience's first by default"

    alias Tayori.Audience
    alias Tayori.Campaigns.Letters
    alias Tayori.MCP.Campaigns

    @impl true
    def execute(args, _ctx) do
      with {:ok, campaign} <- Campaigns.fetch_campaign(args.campaign_id),
           {:ok, step} <- Campaigns.campaign_step(campaign, args[:step_id]),
           :ok <- written(step),
           {:ok, person} <- person(campaign, args[:person_id]),
           :ok <- email(person) do
        letter = Letters.letter(step, person.locale)
        email = Letters.render(campaign, step, person)

        {:ok,
         %{
           person: Campaigns.person(person),
           locale: letter.locale,
           subject: email.subject,
           preheader: letter.preheader && Letters.merge(letter.preheader, values(person)),
           text: email.text_body,
           missing_tags: Letters.missing(campaign, person)
         }}
      end
    end

    defp written(%{letters: []}),
      do: {:error, "The step has no letter yet: write one with update_step."}

    defp written(_step), do: :ok

    defp person(_campaign, id) when is_binary(id), do: Campaigns.fetch_person(id)

    defp person(campaign, nil) do
      case Audience.sample(campaign.audience, 1) do
        [person] -> {:ok, person}
        [] -> {:error, "No one is in the campaign's audience: give a person_id."}
      end
    end

    defp email(%{email: email}) when is_binary(email) and email != "", do: :ok

    defp email(person),
      do: {:error, "#{person.id} has no email address: no letter goes to them."}

    defp values(person) do
      (person.data || %{})
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.merge(%{"name" => person.name, "email" => person.email})
    end
  end
end
