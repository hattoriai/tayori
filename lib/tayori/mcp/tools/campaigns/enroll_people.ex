if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Tools.Campaigns.EnrollPeople do
    @moduledoc false
    use Sake.Tool,
      name: "enroll_people",
      title: "Take people into a sequence",
      description:
        "Take people into an active sequence by hand: some by their ids (person_ids, as " <>
          "list_audience and preview_segment give them), or everyone a condition or a " <>
          "saved segment matches. Each then gets the sequence's letters at their times, " <>
          "from now. Only those in the sequence's audience enter, and never twice. Call " <>
          "it only when the person asks, after telling them how many people enter: for a " <>
          "condition or a segment, expected_people is required and must be the number " <>
          "who would enter now (they match it and the audience, and are not in the " <>
          "sequence yet); if it is not, no one enters and the error gives the number. " <>
          "Say how many entered.",
      scope: "tayori:campaigns:send",
      annotations: [read_only: false, destructive: true, idempotent: true, open_world: true]

    @max_ids 500

    arg :campaign_id, :string, required: true, max_length: 64, description: "The sequence's id"

    arg :person_ids, {:array, :string},
      description: "The ids of the people to take in, #{@max_ids} at most"

    arg :condition, :any,
      description:
        ~s(Or everyone a condition matches, a JSON object: {"attribute": "plan", "op": "in", "value": ["pro"]})

    arg :segment_id, :string, max_length: 64, description: "Or everyone in a saved segment"

    arg :expected_people, :integer,
      min: 0,
      description:
        "With a condition or a segment: how many would enter now, as the person was told"

    alias Tayori.Campaigns, as: Context
    alias Tayori.MCP.Campaigns

    @impl true
    def execute(args, _ctx) do
      with {:ok, campaign} <- Campaigns.fetch_campaign(args.campaign_id),
           :ok <- active(campaign),
           {:ok, who} <- who(args),
           {:ok, entered, refused} <- enroll(campaign, who, args[:expected_people]) do
        {:ok,
         %{
           entered: entered,
           not_entered: refused,
           campaign: Campaigns.campaign_summary(Context.get(campaign.id))
         }}
      else
        {:error, reason} -> {:error, Campaigns.error(reason)}
      end
    end

    defp active(%{kind: "sequence", status: "active"}), do: :ok

    defp active(%{kind: "sequence", status: status}),
      do: {:error, "The sequence is #{status}: only an active sequence takes people in."}

    defp active(_broadcast),
      do: {:error, "This is a broadcast: send it with send_broadcast."}

    defp who(%{person_ids: ids} = args) when is_list(ids) do
      cond do
        args[:condition] != nil or args[:segment_id] != nil ->
          {:error, "Give person_ids, a condition or a segment_id: one of them."}

        ids == [] ->
          {:error, "person_ids is empty: give the ids of the people to take in."}

        length(ids) > @max_ids ->
          {:error,
           "#{length(ids)} ids is too many at once: give #{@max_ids} at most, or a condition."}

        true ->
          {:ok, {:ids, Enum.uniq(ids)}}
      end
    end

    defp who(%{condition: condition, segment_id: id}) when condition != nil and id != nil,
      do: {:error, "Give a condition or a segment_id, not both."}

    defp who(%{segment_id: id}) when is_binary(id) do
      with {:ok, segment} <- Campaigns.fetch_segment(id), do: {:ok, {:matching, segment}}
    end

    defp who(%{condition: condition}) when condition != nil do
      with {:ok, normalized} <- Campaigns.condition(condition, "condition", []),
           do: {:ok, {:matching, normalized}}
    end

    defp who(_args),
      do: {:error, "Give the people to take in: person_ids, a condition or a segment_id."}

    # By their ids: each enters, or is said why not.
    defp enroll(campaign, {:ids, ids}, _expected) do
      now = DateTime.utc_now()

      {entered, refused} =
        Enum.reduce(ids, {0, []}, fn id, {entered, refused} ->
          case Context.enroll(campaign, id, now) do
            {:ok, _enrollment} -> {entered + 1, refused}
            {:error, reason} -> {entered, [%{person_id: id, reason: reason(reason)} | refused]}
          end
        end)

      {:ok, entered, Enum.reverse(refused)}
    end

    # No number given: none enter, and the error says how many would.
    defp enroll(campaign, {:matching, who}, nil) do
      with {:ok, count} <- Context.count_enrollable(campaign, who) do
        {:error,
         "Give expected_people: #{count} #{people(count)} would enter now (those who match " <>
           "it and the sequence's audience, less those in it before). Tell the person, and " <>
           "call it with expected_people #{count} if they want it."}
      end
    end

    defp enroll(campaign, {:matching, who}, expected) do
      now = DateTime.utc_now()

      with {:ok, count} <- Context.count_enrollable(campaign, who, now),
           :ok <- expected(count, expected),
           {:ok, entered} <- Context.enroll_segment(campaign, who, now) do
        {:ok, entered, []}
      end
    end

    defp expected(count, count), do: :ok

    defp expected(count, expected) do
      {:error,
       "#{count} #{people(count)} would enter now, not #{expected}: no one entered. Tell " <>
         "the person it takes in #{count}, and call it with expected_people #{count} if " <>
         "they still want it."}
    end

    defp reason(:not_found), do: "No one in the app has this id."
    defp reason(:not_in_audience), do: "Not in the sequence's audience."
    defp reason(:already), do: "In the sequence before: a person enters once."
    defp reason(:not_active), do: "The sequence is not active."
    defp reason(other), do: inspect(other)

    defp people(1), do: "person"
    defp people(_count), do: "people"
  end
end
