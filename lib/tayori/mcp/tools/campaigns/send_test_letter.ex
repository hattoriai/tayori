if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.SendTestLetter do
    @moduledoc false
    use Sake.Tool,
      name: "send_test_letter",
      title: "Send a test letter",
      description:
        "Send a step's letter as a test to one address, for the person to read it in " <>
          "their mail: its subject begins with \"[Test] \", its merge tags are those of a " <>
          "person (person_id) or empty, and nothing counts it in the results. It goes to " <>
          "the address given, or to the writer's own when the app knows it; to no one " <>
          "else. Use preview_letter to read a letter without sending it.",
      scope: "tayori:campaigns:write",
      annotations: [read_only: false, destructive: false, idempotent: false, open_world: true]

    arg :campaign_id, :string, required: true, max_length: 64, description: "The campaign's id"

    arg :step_id, :string,
      max_length: 64,
      description: "The step's id (get_campaign); not needed for a broadcast"

    arg :to, :string, max_length: 320, description: "The address it goes to (the writer's)"

    arg :person_id, :string,
      max_length: 255,
      description: "A person whose merge tags it takes (preview_segment)"

    alias Tayori.Campaigns.Letters
    alias Tayori.MCP.{Campaigns, Support}

    @impl true
    def execute(args, ctx) do
      with {:ok, campaign} <- Campaigns.fetch_campaign(args.campaign_id),
           {:ok, step} <- Campaigns.campaign_step(campaign, args[:step_id]),
           :ok <- written(step),
           {:ok, address} <- address(args[:to], Support.author(ctx)),
           {:ok, person} <- person(args[:person_id]),
           {:ok, _meta} <- deliver(campaign, step, person, address) do
        letter = Letters.letter(step, person && person.locale)
        {:ok, %{sent_to: address, locale: letter.locale, subject: "[Test] " <> letter.subject}}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end

    defp written(%{letters: []}),
      do: {:error, "The step has no letter yet: write one with update_step."}

    defp written(_step), do: :ok

    defp address(nil, author) do
      case author && (author["email"] || author[:email]) do
        email when is_binary(email) -> address(email, nil)
        _none -> {:error, "Give the address to send the test to (to)."}
      end
    end

    defp address(address, _author) do
      address = String.trim(address)

      if address =~ ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/,
        do: {:ok, address},
        else: {:error, "#{inspect(address)} is not an email address."}
    end

    defp deliver(campaign, step, person, address) do
      case Letters.send_test(campaign, step, person, address) do
        {:ok, meta} -> {:ok, meta}
        {:error, reason} -> {:error, "The mailer did not send it: #{inspect(reason)}."}
      end
    end

    defp person(nil), do: {:ok, nil}
    defp person(id), do: Campaigns.fetch_person(id)
  end
end
