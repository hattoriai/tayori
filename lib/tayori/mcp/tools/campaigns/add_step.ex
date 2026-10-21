if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.AddStep do
    @moduledoc false
    use Sake.Tool,
      name: "add_step",
      title: "Add a step to a sequence",
      description:
        "Add a step to a sequence: a letter that goes at a time after the person entered " <>
          "(after_days, after_hours, after_minutes; at entry if none), unless its skip_if " <>
          "matches them when its time comes. Two steps cannot go at the same time. Write " <>
          "its letter here or later with update_step, in one language (the app's first by " <>
          "default), in Markdown; merge tags such as {{first_name|there}} or {{email}} " <>
          "take the person's values. A sequence that is no longer a draft needs the letter " <>
          "here, in the app's first language, with a subject and a body. A broadcast has " <>
          "its one step already.",
      scope: "tayori:campaigns:write",
      annotations: [read_only: false, destructive: false, idempotent: false, open_world: false]

    arg :campaign_id, :string, required: true, max_length: 64, description: "The sequence's id"
    arg :after_days, :integer, min: 0, max: 3650, description: "Days after entry"
    arg :after_hours, :integer, min: 0, max: 87_600, description: "Hours after entry, added"
    arg :after_minutes, :integer, min: 0, max: 5_256_000, description: "Minutes, added"

    arg :skip_if, :any,
      description: "A condition (list_audience): the letter is not sent to who matches it"

    arg :locale, :string,
      max_length: 35,
      description: "The language of the letter (the app's first)"

    arg :subject, :string, max_length: 255, description: "The letter's subject"

    arg :preheader, :string,
      max_length: 255,
      description: "The line a mail client shows after the subject"

    arg :body, :string, max_length: 200_000, description: "The letter, in Markdown"
    arg :cta_label, :string, max_length: 80, description: "A button's label"
    arg :cta_url, :string, max_length: 2048, description: "The button's http(s) address"

    alias Tayori.Config
    alias Tayori.MCP.Campaigns

    @impl true
    def execute(args, _ctx) do
      config = Config.get()

      with {:ok, campaign} <- Campaigns.fetch_campaign(args.campaign_id),
           {:ok, skip_if} <- Campaigns.condition(args[:skip_if], "skip_if", []),
           {:ok, locale} <- Campaigns.locale(args[:locale], config),
           {:ok, letters} <- letters(args, locale),
           attrs = %{
             "wait" => Campaigns.wait(args) || 0,
             "skip_if" => skip_if,
             "letters" => letters
           },
           {:ok, step} <- Tayori.Campaigns.add_step(campaign, attrs) do
        {:ok, Campaigns.step(Tayori.Campaigns.get_step(step.id), config)}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end

    defp letters(args, locale) do
      case Campaigns.letter_attrs(args) do
        empty when empty == %{} ->
          {:ok, []}

        %{"subject" => _} = letter ->
          {:ok, [Map.put(letter, "locale", locale)]}

        _no_subject ->
          {:error, "A letter needs a subject."}
      end
    end
  end
end
