if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.UpdateStep do
    @moduledoc false
    use Sake.Tool,
      name: "update_step",
      title: "Change a step and its letter",
      description:
        "Change a step: its time after entry (of a sequence), its skip_if ({} takes it " <>
          "off), and its letter in one language (the app's first by default; a language it " <>
          "does not have yet is added, with a subject). Only what is given changes; the " <>
          "body is replaced whole, in Markdown, with merge tags such as " <>
          "{{first_name|there}}; an empty preheader or button takes it off. This is how a " <>
          "broadcast's letter is written: its one step's id is in get_campaign. A running " <>
          "sequence's step changes for those still before it.",
      scope: "tayori:campaigns:write",
      annotations: [read_only: false, destructive: true, idempotent: true, open_world: false]

    arg :step_id, :string,
      required: true,
      max_length: 64,
      description: "The step's id (get_campaign)"

    arg :after_days, :integer, min: 0, max: 3650, description: "Days after entry"
    arg :after_hours, :integer, min: 0, max: 87_600, description: "Hours after entry, added"
    arg :after_minutes, :integer, min: 0, max: 5_256_000, description: "Minutes, added"
    arg :skip_if, :any, description: "A condition (list_audience); {} for none"

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

      with {:ok, step, campaign} <- Campaigns.fetch_step(args.step_id),
           {:ok, skip_if} <- Campaigns.condition(args[:skip_if], "skip_if", clear: true),
           {:ok, locale} <- Campaigns.locale(args[:locale], config),
           step_attrs = step_attrs(Campaigns.wait(args), skip_if),
           letter = Campaigns.letter_attrs(args),
           :ok <- something(step_attrs, letter),
           :ok <- timed(campaign, step_attrs),
           {:ok, _step} <- update_step(step, step_attrs),
           {:ok, _letter} <- put_letter(step, locale, letter) do
        {:ok, Campaigns.step(Tayori.Campaigns.get_step(step.id), config)}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end

    defp step_attrs(wait, skip_if) do
      [{"wait", wait}, {"skip_if", skip_if}]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn
        {key, :clear} -> {key, nil}
        pair -> pair
      end)
    end

    defp something(step_attrs, letter) when step_attrs == %{} and letter == %{},
      do: {:error, "Nothing to change: give a time, a skip_if or a part of the letter."}

    defp something(_step_attrs, _letter), do: :ok

    defp timed(%{kind: "broadcast"}, %{"wait" => _}),
      do: {:error, "A broadcast's letter goes when it is sent: it has no time after entry."}

    defp timed(_campaign, _attrs), do: :ok

    defp update_step(step, attrs) when attrs == %{}, do: {:ok, step}
    defp update_step(step, attrs), do: Tayori.Campaigns.update_step(step, attrs)

    defp put_letter(step, _locale, letter) when letter == %{}, do: {:ok, step}
    defp put_letter(step, locale, letter), do: Tayori.Campaigns.put_letter(step, locale, letter)
  end
end
