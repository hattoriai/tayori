if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.MCP.Campaigns do
    @moduledoc false
    # What the campaigns' tools share (Tayori.MCP.Tools.Campaigns): the
    # campaigns, steps, letters and segments as the model reads them, the
    # conditions it gives checked and put in words, and the errors of the
    # campaigns in words it can act on.

    alias Tayori.{Audience, Conditions, Config, Recipient}
    alias Tayori.Campaigns
    alias Tayori.Campaigns.{Campaign, Letter, Letters, Segment, Segments, Step}
    alias Tayori.MCP.Support

    @letter_fields [:subject, :preheader, :body, :cta_label, :cta_url]

    # ---- the audience

    @doc "The attributes of the app's audience."
    def attributes, do: Audience.attributes(Audience.current())

    @doc "The events of the app's audience, `[{name, label}]`."
    def events, do: Audience.events(Audience.current())

    @doc "Whether conditions may test events: the audience gives `person_id/0`."
    def events?, do: Audience.person_id(Audience.current()) != nil

    @doc "A person as a list shows them."
    def person(%Recipient{} = r),
      do: %{id: r.id, name: r.name, email: r.email, locale: r.locale}

    @doc "A person of the app by their id."
    def fetch_person(id) when is_binary(id) do
      case Audience.get(String.trim(id)) do
        %Recipient{} = recipient ->
          {:ok, recipient}

        nil ->
          {:error,
           "No person with the id #{inspect(id)}: give the id of a person as " <>
             "preview_segment lists them."}
      end
    end

    # ---- conditions

    @doc """
    A condition the model gives, checked: `{:ok, normalized}`, or the
    errors in words with the name of the argument. Nil stays nil (the
    argument is not given); `{}` is `:clear` when `clear?`.
    """
    def condition(nil, _name, _opts), do: {:ok, nil}

    def condition(%{} = condition, _name, clear: true) when map_size(condition) == 0,
      do: {:ok, :clear}

    def condition(%{} = condition, name, _opts) do
      case Conditions.validate(condition, attributes()) do
        {:ok, normalized} ->
          {:ok, normalized}

        {:error, messages} ->
          {:error,
           "The #{name} is not a condition Tayori can run: #{Enum.join(messages, " ")} " <>
             "list_audience gives the attributes, their operators and the events."}
      end
    end

    def condition(other, name, _opts),
      do:
        {:error,
         ~s(The #{name} must be a JSON object, as {"attribute": "plan", "op": "in", ) <>
           ~s("value": ["pro"]}, not #{inspect(other)}.)}

    @doc "A condition with its sentence, for the model."
    def condition_view(nil), do: nil

    def condition_view(condition),
      do: %{condition: condition, sentence: describe(condition)}

    @doc "A condition in words."
    def describe(condition), do: Conditions.describe(condition, attributes())

    @doc "A condition with its sentence and how many people match it now."
    def counted(condition) do
      %{
        condition: condition,
        sentence: describe(condition),
        count: Audience.count(condition)
      }
    end

    # ---- segments

    @doc "A segment by its id."
    def fetch_segment(id) when is_binary(id) do
      case Segments.get(String.trim(id)) do
        %Segment{} = segment ->
          {:ok, segment}

        nil ->
          {:error, "No segment with the id #{inspect(id)}: list_audience gives the segments."}
      end
    end

    @doc "A segment, with its sentence and its count now."
    def segment(%Segment{} = segment) do
      %{
        id: segment.id,
        name: segment.name,
        description: segment.description,
        condition: segment.condition,
        sentence: describe(segment.condition),
        count: segment.count || Audience.count(segment.condition)
      }
    end

    # ---- campaigns

    @doc "A campaign by its id, with its steps and letters."
    def fetch_campaign(id) when is_binary(id) do
      case Campaigns.get(String.trim(id)) do
        %Campaign{} = campaign ->
          {:ok, campaign}

        nil ->
          {:error, "No campaign with the id #{inspect(id)}: list_campaigns gives them."}
      end
    end

    @doc "A step by its id, with its letters, and its campaign."
    def fetch_step(id) when is_binary(id) do
      case Campaigns.get_step(String.trim(id)) do
        %Step{} = step ->
          {:ok, step, Campaigns.get(step.campaign_id)}

        nil ->
          {:error, "No step with the id #{inspect(id)}: get_campaign gives a campaign's steps."}
      end
    end

    @doc "A step of a campaign: the one given, or a broadcast's one step."
    def campaign_step(%Campaign{steps: steps}, nil) do
      case steps do
        [step] ->
          {:ok, step}

        [] ->
          {:error, "The campaign has no step yet: add one with add_step."}

        _many ->
          {:error, "The sequence has several steps: give the step_id (get_campaign)."}
      end
    end

    def campaign_step(%Campaign{steps: steps}, step_id) do
      case Enum.find(steps, &(&1.id == String.trim(step_id))) do
        %Step{} = step -> {:ok, step}
        nil -> {:error, "The campaign has no step with the id #{inspect(step_id)}."}
      end
    end

    @doc "A campaign in a line, for a list."
    def campaign_summary(%Campaign{} = campaign) do
      %{
        id: campaign.id,
        name: campaign.name,
        kind: campaign.kind,
        purpose: campaign.purpose,
        status: campaign.status,
        trigger: trigger(campaign.trigger),
        steps: length(campaign.steps),
        send_at: Support.timestamp(campaign.send_at),
        started_at: Support.timestamp(campaign.started_at),
        sent_at: Support.timestamp(campaign.sent_at)
      }
    end

    @doc "A campaign whole: its settings, its steps and their letters, its results."
    def campaign_detail(%Campaign{} = campaign) do
      config = Config.get()
      campaign = Campaigns.with_steps(config, campaign)

      campaign
      |> campaign_summary()
      |> Map.merge(%{
        audience: counted(campaign.audience),
        goal: condition_view(campaign.goal),
        min_gap_hours: campaign.min_gap_hours,
        max_days: campaign.max_days,
        from_name: campaign.from_name,
        reply_to: campaign.reply_to,
        author: campaign.author,
        steps: Enum.map(campaign.steps, &step(&1, config)),
        merge_tags: Letters.tags(campaign),
        problems: problems(campaign, config),
        results: Campaigns.results(campaign)
      })
    end

    defp trigger(%{"type" => "event", "event" => event}), do: %{type: "event", event: event}
    defp trigger(%{"type" => "manual"}), do: %{type: "manual"}
    defp trigger(_none), do: nil

    @doc "A step, its letters in Markdown."
    def step(%Step{} = step, config) do
      present = Enum.map(step.letters, & &1.locale)

      %{
        id: step.id,
        position: step.position,
        wait_minutes: step.wait,
        after: wait_text(step.wait),
        skip_if: condition_view(step.skip_if),
        letters: Enum.map(step.letters, &letter/1),
        missing_locales: Enum.reject(config.locales, &(&1 in present))
      }
    end

    @doc "A letter, its body in Markdown."
    def letter(%Letter{} = letter) do
      %{
        locale: letter.locale,
        subject: letter.subject,
        preheader: letter.preheader,
        body: Support.markdown(letter.body),
        cta_label: letter.cta_label,
        cta_url: letter.cta_url,
        complete: Campaigns.complete?(letter)
      }
    end

    # What keeps a draft from starting, in words.
    defp problems(%Campaign{status: status}, _config)
         when status not in ["draft", "scheduled"],
         do: []

    defp problems(%Campaign{steps: []}, _config), do: ["It has no steps: add one with add_step."]

    defp problems(%Campaign{steps: steps}, config) do
      locale = Config.default_locale(config)

      for step <- steps,
          not Campaigns.complete?(Enum.find(step.letters, &(&1.locale == locale))) do
        "The step #{step.id} (#{wait_text(step.wait)}) needs a letter in #{locale} " <>
          "with a subject and a body."
      end
    end

    @doc "A wait in minutes, in words: \"2 days 4 hours after entry\"."
    def wait_text(0), do: "at entry"

    def wait_text(minutes) do
      days = div(minutes, 1440)
      hours = div(rem(minutes, 1440), 60)
      rest = rem(minutes, 60)

      [{days, "day"}, {hours, "hour"}, {rest, "minute"}]
      |> Enum.reject(fn {n, _unit} -> n == 0 end)
      |> Enum.map_join(" ", fn
        {1, unit} -> "1 #{unit}"
        {n, unit} -> "#{n} #{unit}s"
      end)
      |> Kernel.<>(" after entry")
    end

    @doc "The minutes of a wait given in days, hours and minutes; nil when none is given."
    def wait(args) do
      parts = [args[:after_days], args[:after_hours], args[:after_minutes]]

      if Enum.all?(parts, &is_nil/1) do
        nil
      else
        [days, hours, minutes] = Enum.map(parts, &(&1 || 0))
        days * 1440 + hours * 60 + minutes
      end
    end

    # ---- settings

    @doc """
    The settings of a campaign given to `create_campaign` or
    `update_campaign`, as `Tayori.Campaigns.create/2` takes them: only
    those given, the conditions checked, `{}` and 0 taking a setting off.
    """
    def settings(args) do
      with {:ok, audience} <- condition(args[:audience], "audience", clear: true),
           {:ok, goal} <- condition(args[:goal], "goal", clear: true) do
        given =
          [
            {"name", args[:name]},
            {"kind", args[:kind]},
            {"purpose", args[:purpose]},
            {"trigger", trigger_of(args[:trigger_event])},
            {"audience", audience},
            {"goal", goal},
            {"min_gap_hours", args[:min_gap_hours]},
            {"max_days", args[:max_days]},
            {"from_name", args[:from_name]},
            {"reply_to", args[:reply_to]}
          ]
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new(fn
            {_key, :clear} = pair -> put_elem(pair, 1, nil)
            {"max_days", 0} -> {"max_days", nil}
            pair -> pair
          end)

        {:ok, given}
      end
    end

    defp trigger_of(nil), do: nil

    defp trigger_of(event) do
      case String.trim(event) do
        "" -> %{"type" => "manual"}
        event -> %{"type" => "event", "event" => event}
      end
    end

    # ---- letters

    @doc """
    The fields of a letter given to a tool, as `Tayori.Campaigns.put_letter/3`
    takes them, the body made of its Markdown; `%{}` when none is given.
    """
    def letter_attrs(args) do
      args
      |> Map.take(@letter_fields)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn
        {:body, markdown} -> {"body", Support.body(markdown)}
        {key, value} -> {Atom.to_string(key), value}
      end)
    end

    @doc "A locale of the app for a letter, the first by default."
    def locale(nil, config), do: {:ok, Config.default_locale(config)}

    def locale(locale, config) do
      if locale in config.locales,
        do: {:ok, locale},
        else:
          {:error,
           "Unknown language #{inspect(locale)}: the letters are written in " <>
             "#{Enum.join(config.locales, ", ")}."}
    end

    # ---- errors

    @doc "An error of the campaigns, in words the model can act on."
    def error(:locked),
      do:
        "The campaign is locked: an archived campaign, or a broadcast sent or being sent, " <>
          "stays as it went. Make a new campaign instead."

    def error(:one_step),
      do:
        "A broadcast has one step, made with it: write its letter with update_step, " <>
          "with the step_id of get_campaign."

    def error(:no_steps), do: "The sequence has no steps: add one with add_step."

    def error({:incomplete, ids}) do
      locale = Config.default_locale(Config.get())

      "Each step needs a letter in #{locale} with a subject and a body; these do not: " <>
        "#{Enum.join(ids, ", ")}. Write them with update_step."
    end

    def error(:sending), do: "The broadcast is being sent: it can no longer change."
    def error(:not_draft), do: "Only a draft or an archived campaign can be deleted."

    def error({:status, status}), do: "The campaign is #{status}: it cannot do that now."

    def error({:kind, kind}), do: "That is not for a #{kind}."

    def error(other), do: Support.error(other)
  end
end
