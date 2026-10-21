defmodule Tayori.Campaigns do
  @moduledoc ~S"""
  Letters to each of the app's people, by what they did, at their own
  time: the `:campaigns` module (`Tayori.Config`). What the admin does,
  for a script, a seed or the app's own code too.

      {:ok, onboarding} =
        Tayori.Campaigns.create(%{
          "name" => "Onboarding",
          "kind" => "sequence",
          "trigger" => %{"type" => "event", "event" => "signed_up"},
          "goal" => %{"attribute" => "published", "op" => "true"},
          "min_gap_hours" => 40,
          "max_days" => 14
        })

      {:ok, _step} =
        Tayori.Campaigns.add_step(onboarding, %{
          "wait" => 0,
          "letters" => [
            %{"locale" => "en", "subject" => "Welcome, {{first_name|there}}",
              "body" => Kotoba.Content.from_markdown("Glad you came.")}
          ]
        })

      {:ok, onboarding} = Tayori.Campaigns.start(onboarding)

  Two kinds (`Tayori.Campaigns.Campaign`):

    * A **sequence**: a person enters on an event (`Tayori.track/3`), by
      hand (`enroll/3`) or with a segment (`enroll_segment/3`), then gets
      its steps' letters, each at its wait after their entry, unless its
      `skip_if` matches them then, until the goal is reached, the steps
      end, `max_days` pass, or they cannot be emailed. Two letters of a
      sequence are `min_gap_hours` apart at least: a step whose time
      comes sooner waits. It starts as a draft, then `start/1`,
      `pause/1`, `resume/1`, `archive/1`.
    * A **broadcast**: one letter to everyone in its audience, at a time
      (`schedule_broadcast/2`) or now (`send_broadcast_now/1`).

  The steps are read when a person reaches them: a step edited, added or
  removed in a running sequence counts for those still before it. A step
  added with a wait at or before where a person is goes to those who come
  after, not to them.

  Each letter goes once to a person (`Tayori.Campaigns.Delivery`). An
  address that unsubscribed, bounced or complained is not written to
  (`suppress/3`), nor a person whose `c:Tayori.Audience.can_email?/2` says
  no.

  Each change is told on the PubSub as `{Tayori, :campaign_changed, id}`
  (see `Tayori.subscribe/0`).

  The functions that depend on the time take `now`, the current time by
  default.
  """

  import Ecto.Query

  alias Tayori.{Audience, Conditions, Config, Jobs, Recipient}

  alias Tayori.Campaigns.{
    Campaign,
    Delivery,
    Enrollment,
    Letter,
    Segment,
    Segments,
    Step,
    Suppression
  }

  # The statuses of a delivery (Delivery.statuses/0), as the keys of the
  # results.
  @statuses %{
    "queued" => :queued,
    "sent" => :sent,
    "skipped" => :skipped,
    "failed" => :failed,
    "bounced" => :bounced,
    "complained" => :complained
  }

  @typedoc "The results of a campaign, as `results/1` gives them."
  @type results :: map()

  # ── Reading ─────────────────────────────────────────────────────

  @doc """
  The campaigns, the newest first. Options: `:kind` - `"sequence"` or
  `"broadcast"`; `:archived` - with the archived ones (`false`).
  """
  @spec list(keyword()) :: [Campaign.t()]
  def list(opts \\ []) do
    config = Config.get()

    from(c in Campaign, order_by: [desc: c.inserted_at, desc: c.id])
    |> then(fn query ->
      if kind = opts[:kind], do: where(query, [c], c.kind == ^kind), else: query
    end)
    |> then(fn query ->
      if opts[:archived], do: query, else: where(query, [c], c.status != "archived")
    end)
    |> config.repo.all(prefix: config.prefix)
  end

  @doc "A campaign by its id, with its steps and their letters, or nil."
  @spec get(String.t()) :: Campaign.t() | nil
  def get(id) when is_binary(id) do
    config = Config.get()

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Campaign{} = campaign <- config.repo.get(Campaign, uuid, prefix: config.prefix) do
      with_steps(config, campaign)
    else
      _ -> nil
    end
  end

  @doc "A step by its id, with its letters, or nil."
  @spec get_step(String.t()) :: Step.t() | nil
  def get_step(id) when is_binary(id) do
    config = Config.get()

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Step{} = step <- config.repo.get(Step, uuid, prefix: config.prefix) do
      config.repo.preload(step, :letters, prefix: config.prefix)
    else
      _ -> nil
    end
  end

  @doc false
  def with_steps(config, campaign) do
    config.repo.preload(campaign, [steps: :letters], prefix: config.prefix, force: true)
  end

  # ── Campaigns ───────────────────────────────────────────────────

  @doc "A changeset of a campaign, for a form."
  @spec change(Campaign.t(), map()) :: Ecto.Changeset.t()
  def change(%Campaign{} = campaign, attrs \\ %{}) do
    Campaign.changeset(campaign, attrs, Audience.attributes(audience!()))
  end

  @doc """
  Creates a campaign, a draft: its name, kind, purpose, and the settings
  of `Tayori.Campaigns.Campaign`. A broadcast is made with its one step,
  whose letter is then written with `put_letter/3`.

  Options: `:author` - who made it, a map.
  """
  @spec create(map(), keyword()) :: {:ok, Campaign.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs, opts \\ []) do
    config = Config.get()
    attrs = attrs |> stringify() |> Map.drop(["status", "send_at"])

    changeset =
      %Campaign{}
      |> change(attrs)
      |> Ecto.Changeset.put_change(:author, opts[:author])

    write(config, fn ->
      with {:ok, campaign} <- config.repo.insert(changeset, prefix: config.prefix) do
        one_step(config, campaign)
        {:ok, with_steps(config, campaign)}
      end
    end)
  end

  defp one_step(config, %Campaign{kind: "broadcast"} = campaign),
    do:
      config.repo.insert!(%Step{campaign_id: campaign.id, position: 0, wait: 0},
        prefix: config.prefix
      )

  defp one_step(_config, _campaign), do: :ok

  @doc """
  Updates a campaign's settings. Its kind and status are not changed here
  (see `start/1` and the others). An archived campaign, or a broadcast
  sent or being sent, is `{:error, :locked}`.
  """
  @spec update(Campaign.t(), map()) ::
          {:ok, Campaign.t()} | {:error, Ecto.Changeset.t() | :locked}
  def update(%Campaign{} = campaign, attrs) do
    config = Config.get()
    attrs = attrs |> stringify() |> Map.drop(["kind", "status", "send_at"])

    if locked?(campaign) do
      {:error, :locked}
    else
      write(config, fn ->
        campaign
        |> change(attrs)
        |> config.repo.update(prefix: config.prefix)
        |> preloaded(config)
      end)
    end
  end

  @doc """
  Archives a campaign: a sequence takes no one in and its people leave it
  (reason `"stopped"`); a scheduled broadcast is not sent. A broadcast
  being sent is `{:error, :sending}`.
  """
  @spec archive(Campaign.t(), DateTime.t()) :: {:ok, Campaign.t()} | {:error, term()}
  def archive(%Campaign{} = campaign, now \\ DateTime.utc_now()) do
    config = Config.get()

    cond do
      campaign.status == "archived" ->
        {:ok, campaign}

      campaign.status == "sending" ->
        {:error, :sending}

      true ->
        write(config, fn ->
          stop_enrollments(config, campaign, now)
          put_status(config, campaign, status: "archived")
        end)
    end
  end

  defp stop_enrollments(_config, %Campaign{kind: "broadcast"}, _now), do: :ok

  defp stop_enrollments(config, %Campaign{id: campaign_id}, now) do
    from(e in Enrollment, where: e.campaign_id == ^campaign_id and e.state == "active")
    |> config.repo.update_all(
      [
        set: [
          state: "exited",
          reason: "stopped",
          next_at: nil,
          ended_at: usec(now),
          updated_at: usec(now)
        ]
      ],
      prefix: config.prefix
    )
  end

  @doc """
  Deletes a campaign with its steps, letters, people and deliveries. Only
  a draft or an archived campaign: `{:error, :not_draft}` else.
  """
  @spec delete(Campaign.t()) :: {:ok, Campaign.t()} | {:error, term()}
  def delete(%Campaign{status: status} = campaign) when status in ["draft", "archived"] do
    config = Config.get()
    write(config, fn -> config.repo.delete(campaign, prefix: config.prefix) end)
  end

  def delete(%Campaign{}), do: {:error, :not_draft}

  # ── Steps and letters ───────────────────────────────────────────

  @doc """
  Adds a step at the end: its `"wait"` in minutes after the entry, its
  `"skip_if"` condition, and its `"letters"`, a list of
  `%{"locale", "subject", "preheader", "body", "cta_label", "cta_url"}`
  (`Tayori.Campaigns.Letter`). Two steps of a sequence cannot have the
  same wait. A broadcast has its one step already: `{:error, :one_step}`.
  """
  @spec add_step(Campaign.t(), map()) ::
          {:ok, Step.t()} | {:error, Ecto.Changeset.t() | :locked | :one_step}
  def add_step(%Campaign{} = campaign, attrs) do
    config = Config.get()
    attrs = stringify(attrs)

    cond do
      locked?(campaign) ->
        {:error, :locked}

      campaign.kind == "broadcast" ->
        {:error, :one_step}

      true ->
        position =
          from(s in Step, where: s.campaign_id == ^campaign.id, select: max(s.position))
          |> config.repo.one(prefix: config.prefix)

        attrs = Map.put_new(attrs, "position", (position || -1) + 1)

        write(config, campaign.id, fn ->
          %Step{campaign_id: campaign.id, letters: []}
          |> step_changeset(attrs, campaign)
          |> config.repo.insert(prefix: config.prefix)
        end)
    end
  end

  @doc """
  Updates a step: its wait, its skip, its position, and its letters when
  `"letters"` is given (all of them: a letter not in the list is
  deleted; see `put_letter/3` for one language).
  """
  @spec update_step(Step.t(), map()) ::
          {:ok, Step.t()} | {:error, Ecto.Changeset.t() | :locked}
  def update_step(%Step{} = step, attrs) do
    config = Config.get()
    campaign = config.repo.get!(Campaign, step.campaign_id, prefix: config.prefix)
    attrs = stringify(attrs)

    attrs =
      if campaign.kind == "broadcast", do: Map.drop(attrs, ["wait", "position"]), else: attrs

    if locked?(campaign) do
      {:error, :locked}
    else
      write(config, campaign.id, fn ->
        step
        |> config.repo.preload(:letters, prefix: config.prefix)
        |> step_changeset(attrs, campaign)
        |> config.repo.update(prefix: config.prefix)
      end)
    end
  end

  defp step_changeset(step, attrs, campaign) do
    config = Config.get()

    step
    |> Step.changeset(attrs, Audience.attributes(audience!()), config.locales)
    |> distinct_wait(config, campaign)
  end

  # A sequence goes from step to step by their waits: two at the same
  # time would be one.
  defp distinct_wait(%{valid?: true} = changeset, config, %Campaign{kind: "sequence"} = campaign) do
    wait = Ecto.Changeset.get_field(changeset, :wait)
    id = changeset.data.id

    taken =
      from(s in Step, where: s.campaign_id == ^campaign.id and s.wait == ^wait)
      |> then(fn query -> if id, do: where(query, [s], s.id != ^id), else: query end)
      |> config.repo.exists?(prefix: config.prefix)

    if taken,
      do: Ecto.Changeset.add_error(changeset, :wait, "another step goes at this time"),
      else: changeset
  end

  defp distinct_wait(changeset, _config, _campaign), do: changeset

  @doc """
  Writes a step's letter in a language, the one it has or a new one:
  `%{"subject", "preheader", "body", "cta_label", "cta_url"}`.
  """
  @spec put_letter(Step.t(), String.t(), map()) ::
          {:ok, Letter.t()} | {:error, Ecto.Changeset.t() | :locked}
  def put_letter(%Step{} = step, locale, attrs) when is_binary(locale) do
    config = Config.get()
    campaign = config.repo.get!(Campaign, step.campaign_id, prefix: config.prefix)

    letter =
      config.repo.get_by(Letter, [step_id: step.id, locale: locale], prefix: config.prefix) ||
        %Letter{step_id: step.id}

    if locked?(campaign) do
      {:error, :locked}
    else
      write(config, campaign.id, fn ->
        letter
        |> Letter.changeset(Map.put(stringify(attrs), "locale", locale), config.locales)
        |> config.repo.insert_or_update(prefix: config.prefix)
      end)
    end
  end

  @doc "Deletes a step's letter in a language."
  @spec delete_letter(Step.t(), String.t()) :: :ok | {:error, :locked}
  def delete_letter(%Step{} = step, locale) when is_binary(locale) do
    config = Config.get()
    campaign = config.repo.get!(Campaign, step.campaign_id, prefix: config.prefix)

    if locked?(campaign) do
      {:error, :locked}
    else
      {:ok, _} =
        write(config, campaign.id, fn ->
          from(l in Letter, where: l.step_id == ^step.id and l.locale == ^locale)
          |> config.repo.delete_all(prefix: config.prefix)

          {:ok, step}
        end)

      :ok
    end
  end

  @doc """
  Removes a step and its letters. The deliveries of its letters stay,
  for the results. The one step of a broadcast is not removed:
  `{:error, :one_step}`.
  """
  @spec remove_step(Step.t()) :: {:ok, Step.t()} | {:error, :locked | :one_step}
  def remove_step(%Step{} = step) do
    config = Config.get()
    campaign = config.repo.get!(Campaign, step.campaign_id, prefix: config.prefix)

    cond do
      locked?(campaign) ->
        {:error, :locked}

      campaign.kind == "broadcast" ->
        {:error, :one_step}

      true ->
        write(config, campaign.id, fn -> config.repo.delete(step, prefix: config.prefix) end)
    end
  end

  @doc """
  Moves a step up or down the sequence: it trades places with the step
  before or after it, and their times too, so that the times stay where
  they were and the letters change order. At the top or the bottom
  already, it stays.
  """
  @spec move_step(Step.t(), :up | :down) :: {:ok, Step.t()} | {:error, :locked}
  def move_step(%Step{} = step, direction) when direction in [:up, :down] do
    config = Config.get()
    campaign = config.repo.get!(Campaign, step.campaign_id, prefix: config.prefix)

    steps =
      from(s in Step,
        where: s.campaign_id == ^campaign.id,
        order_by: [asc: s.wait, asc: s.position]
      )
      |> config.repo.all(prefix: config.prefix)

    index = Enum.find_index(steps, &(&1.id == step.id))
    other_index = if direction == :up, do: index - 1, else: index + 1

    cond do
      locked?(campaign) ->
        {:error, :locked}

      other_index < 0 or other_index >= length(steps) ->
        {:ok, Enum.at(steps, index)}

      true ->
        me = Enum.at(steps, index)
        other = Enum.at(steps, other_index)

        write(config, campaign.id, fn ->
          # The waits are distinct: one goes out of the way first.
          swap(config, me, other)
        end)
    end
  end

  defp swap(config, me, other) do
    now = usec(DateTime.utc_now())

    set = fn step, wait, position ->
      from(s in Step, where: s.id == ^step.id)
      |> config.repo.update_all([set: [wait: wait, position: position, updated_at: now]],
        prefix: config.prefix
      )
    end

    set.(me, -1, me.position)
    set.(other, me.wait, me.position)
    set.(me, other.wait, other.position)
    {:ok, config.repo.get!(Step, me.id, prefix: config.prefix)}
  end

  # ── A sequence's life ───────────────────────────────────────────

  @doc """
  Starts a sequence, a draft: it takes people in from now. It needs a
  step at least, and each step a letter in the first language with a
  subject and a body: else `{:error, :no_steps}` or
  `{:error, {:incomplete, step_ids}}`.
  """
  @spec start(Campaign.t(), DateTime.t()) :: {:ok, Campaign.t()} | {:error, term()}
  def start(%Campaign{} = campaign, now \\ DateTime.utc_now()) do
    config = Config.get()
    campaign = with_steps(config, campaign)

    with :ok <- expect(campaign, "sequence", ["draft"]),
         :ok <- ready(config, campaign) do
      write(config, fn ->
        put_status(config, campaign, status: "active", started_at: usec(now))
      end)
    end
  end

  @doc """
  Pauses an active sequence: no one enters, and no letter goes, until it
  is resumed.
  """
  @spec pause(Campaign.t()) :: {:ok, Campaign.t()} | {:error, term()}
  def pause(%Campaign{} = campaign) do
    config = Config.get()

    with :ok <- expect(campaign, "sequence", ["active"]) do
      write(config, fn -> put_status(config, campaign, status: "paused") end)
    end
  end

  @doc """
  Resumes a paused sequence: its people go on where they were, at once
  for those whose time came while it was paused.
  """
  @spec resume(Campaign.t(), DateTime.t()) :: {:ok, Campaign.t()} | {:error, term()}
  def resume(%Campaign{} = campaign, now \\ DateTime.utc_now()) do
    config = Config.get()

    with :ok <- expect(campaign, "sequence", ["paused"]) do
      write(config, fn ->
        # Those looked at while it was paused wait for nothing: now.
        waiting =
          from(e in Enrollment,
            where: e.campaign_id == ^campaign.id and e.state == "active" and is_nil(e.next_at),
            select: e.id
          )
          |> config.repo.all(prefix: config.prefix)

        from(e in Enrollment, where: e.id in ^waiting)
        |> config.repo.update_all([set: [next_at: usec(now), updated_at: usec(now)]],
          prefix: config.prefix
        )

        Jobs.campaign_written(config, Enum.map(waiting, &{:enrollment, &1, now}))
        put_status(config, campaign, status: "active")
      end)
    end
  end

  @doc """
  Takes a person into an active sequence, by their id (that of their
  `Tayori.Recipient`), at a time. The person must be one of the app's,
  in the sequence's audience, and never in it before. Returns
  `{:error, :not_active}`, `{:error, :not_found}`, `{:error,
  :not_in_audience}` or `{:error, :already}` else.
  """
  @spec enroll(Campaign.t(), String.t(), DateTime.t()) ::
          {:ok, Enrollment.t()} | {:error, atom()}
  def enroll(%Campaign{} = campaign, person_id, now \\ DateTime.utc_now())
      when is_binary(person_id) do
    config = Config.get()

    with :ok <- active_sequence(campaign),
         {:person, %Recipient{}} <- {:person, Audience.get(person_id)},
         {:audience, true} <- {:audience, Audience.match?(person_id, campaign.audience, now)},
         first = first_at(config, campaign, now),
         {:ok, enrollment} <-
           config.repo.transaction(fn ->
             insert_enrollment(config, campaign, person_id, now, first)
           end) do
      changed(config, campaign.id)
      {:ok, enrollment}
    else
      {:person, nil} -> {:error, :not_found}
      {:audience, false} -> {:error, :not_in_audience}
      error -> error
    end
  end

  # The enrollment and its job, or :already, rolled back.
  defp insert_enrollment(config, campaign, person_id, now, first) do
    changeset =
      Enrollment.changeset(%Enrollment{}, %{
        campaign_id: campaign.id,
        person: person_id,
        state: "active",
        entered_at: usec(now),
        cursor: -1,
        next_at: usec(first)
      })

    {:ok, enrollment} =
      config.repo.insert(changeset,
        on_conflict: :nothing,
        conflict_target: [:campaign_id, :person],
        prefix: config.prefix
      )

    case config.repo.get(Enrollment, enrollment.id, prefix: config.prefix) do
      nil ->
        config.repo.rollback(:already)

      enrollment ->
        Jobs.campaign_written(config, [{:enrollment, enrollment.id, first}])
        enrollment
    end
  end

  @doc """
  Takes into an active sequence everyone who matches a condition, or is
  in a segment (a `Tayori.Campaigns.Segment` or its id), and is in the
  sequence's audience; those in it before are left as they are. Returns
  how many entered.
  """
  @spec enroll_segment(Campaign.t(), Conditions.t() | Segment.t() | String.t(), DateTime.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def enroll_segment(%Campaign{} = campaign, condition, now \\ DateTime.utc_now()) do
    config = Config.get()

    with :ok <- active_sequence(campaign),
         {:ok, condition} <- who(condition) do
      first = first_at(config, campaign, now)
      both = both(campaign.audience, condition)
      counter = :counters.new(1, [])

      Audience.each_batch(
        both,
        500,
        fn recipients ->
          ids = enroll_batch(config, campaign, recipients, now, first)
          :counters.add(counter, 1, length(ids))
        end,
        now
      )

      changed(config, campaign.id)
      {:ok, :counters.get(counter, 1)}
    end
  end

  defp enroll_batch(config, campaign, recipients, now, first) do
    stamp = usec(now)

    rows =
      Enum.map(recipients, fn recipient ->
        %{
          id: Ecto.UUID.generate(),
          campaign_id: campaign.id,
          person: recipient.id,
          state: "active",
          entered_at: stamp,
          cursor: -1,
          next_at: usec(first),
          inserted_at: stamp,
          updated_at: stamp
        }
      end)

    {:ok, ids} =
      config.repo.transaction(fn ->
        config.repo.insert_all(Enrollment, rows,
          on_conflict: :nothing,
          conflict_target: [:campaign_id, :person],
          prefix: config.prefix
        )

        ids = Enum.map(rows, & &1.id)

        inserted =
          from(e in Enrollment, where: e.id in ^ids, select: e.id)
          |> config.repo.all(prefix: config.prefix)

        Jobs.campaign_written(config, Enum.map(inserted, &{:enrollment, &1, first}))
        inserted
      end)

    ids
  end

  defp who(%Segment{id: id}), do: {:ok, %{"segment" => id, "op" => "in"}}

  defp who(id) when is_binary(id) do
    case Segments.get(id) do
      nil -> {:error, :not_found}
      segment -> who(segment)
    end
  end

  defp who(condition) when is_map(condition) or is_nil(condition) do
    Conditions.validate(condition, Audience.attributes(audience!()))
  end

  defp both(nil, condition), do: condition
  defp both(audience, condition), do: %{"all" => [audience, condition]}

  # The time of a person's first step, from an entry now.
  defp first_at(config, campaign, now) do
    wait =
      from(s in Step, where: s.campaign_id == ^campaign.id, select: min(s.wait))
      |> config.repo.one(prefix: config.prefix)

    DateTime.add(now, (wait || 0) * 60, :second)
  end

  defp active_sequence(%Campaign{kind: "sequence", status: "active"}), do: :ok
  defp active_sequence(%Campaign{}), do: {:error, :not_active}

  # ── Broadcasts ──────────────────────────────────────────────────

  @doc """
  Schedules a broadcast, a draft or scheduled already, at a time: its
  audience is read then, and each person in it gets its letter. Its
  letter must have a subject and a body in the first language:
  `{:error, {:incomplete, step_ids}}` else.
  """
  @spec schedule_broadcast(Campaign.t(), DateTime.t()) :: {:ok, Campaign.t()} | {:error, term()}
  def schedule_broadcast(%Campaign{} = campaign, %DateTime{} = at) do
    config = Config.get()
    campaign = with_steps(config, campaign)

    with :ok <- expect(campaign, "broadcast", ["draft", "scheduled"]),
         :ok <- ready(config, campaign) do
      write(config, fn ->
        Jobs.campaign_written(config, [{:broadcast, campaign.id, at}])
        put_status(config, campaign, status: "scheduled", send_at: usec(at))
      end)
    end
  end

  @doc "Sends a broadcast now: it is scheduled at this time."
  @spec send_broadcast_now(Campaign.t(), DateTime.t()) :: {:ok, Campaign.t()} | {:error, term()}
  def send_broadcast_now(%Campaign{} = campaign, now \\ DateTime.utc_now()),
    do: schedule_broadcast(campaign, now)

  @doc "Takes a scheduled broadcast back to a draft, before it is sent."
  @spec cancel_broadcast(Campaign.t()) :: {:ok, Campaign.t()} | {:error, term()}
  def cancel_broadcast(%Campaign{} = campaign) do
    config = Config.get()

    with :ok <- expect(campaign, "broadcast", ["scheduled"]) do
      write(config, fn -> unschedule(config, campaign) end)
    end
  end

  # Claimed by the sender in the meantime: it goes.
  defp unschedule(config, campaign) do
    {count, _} =
      from(c in Campaign, where: c.id == ^campaign.id and c.status == "scheduled")
      |> config.repo.update_all([set: [status: "draft", send_at: nil]], prefix: config.prefix)

    if count == 1,
      do:
        {:ok, with_steps(config, config.repo.get!(Campaign, campaign.id, prefix: config.prefix))},
      else: {:error, :sending}
  end

  # ── Suppressions ────────────────────────────────────────────────

  @doc """
  Writes no more to an address for a purpose: `"marketing"`, `"product"`
  or `"all"`, for a reason: `"unsubscribed"`, `"bounced"`, `"complained"`
  or `"manual"`. For an app that takes the provider's webhooks itself.
  Done twice, it is the same.
  """
  @spec suppress(String.t(), String.t(), String.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def suppress(email, purpose, reason) when is_binary(email) do
    config = Config.get()

    changeset =
      Suppression.changeset(%Suppression{}, %{email: email, purpose: purpose, reason: reason})

    case config.repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:email, :purpose],
           prefix: config.prefix
         ) do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Writes to an address for a purpose again (`\"all\"` too)."
  @spec unsuppress(String.t(), String.t()) :: :ok
  def unsuppress(email, purpose) when is_binary(email) and is_binary(purpose) do
    config = Config.get()
    email = normalize(email)

    from(s in Suppression, where: s.email == ^email and s.purpose == ^purpose)
    |> config.repo.delete_all(prefix: config.prefix)

    :ok
  end

  @doc """
  Whether an address is not written to for a purpose (`"marketing"` or
  `"product"`): for that purpose, or for all.
  """
  @spec suppressed?(String.t() | nil, String.t() | atom()) :: boolean()
  def suppressed?(nil, _purpose), do: false

  def suppressed?(email, purpose) when is_binary(email) do
    config = Config.get()
    email = normalize(email)
    purposes = ["all", to_string(purpose)]

    from(s in Suppression, where: s.email == ^email and s.purpose in ^purposes)
    |> config.repo.exists?(prefix: config.prefix)
  end

  @doc false
  # The addresses of a list that are not written to for a purpose.
  def suppressed(config, emails, purpose) do
    emails = emails |> Enum.reject(&is_nil/1) |> Enum.map(&normalize/1)
    purposes = ["all", to_string(purpose)]

    from(s in Suppression, where: s.email in ^emails and s.purpose in ^purposes, select: s.email)
    |> config.repo.all(prefix: config.prefix)
    |> MapSet.new()
  end

  @doc false
  def normalize(email), do: email |> String.trim() |> String.downcase()

  # ── Results ─────────────────────────────────────────────────────

  @doc """
  What a campaign did. Of a sequence: how many `:entered`, are `:active`,
  reached the `:goal` (and `:goal_rate`, of those who entered), and how
  many `:ended` by each reason; for each step, its letters by status
  (`:sent`, `:skipped`, `:failed`, `:bounced`, `:complained`, `:queued`)
  and `:goal_after`, the people who reached the goal after this step's
  letter was their last. Of a broadcast: its `:recipients` and their
  letters by status.
  """
  @spec results(Campaign.t()) :: results()
  def results(%Campaign{kind: "broadcast"} = campaign) do
    config = Config.get()
    counts = delivery_counts(config, campaign.id) |> Map.get(:all, %{})
    Map.put(statuses(counts), :recipients, counts |> Map.values() |> Enum.sum())
  end

  def results(%Campaign{kind: "sequence"} = campaign) do
    config = Config.get()
    campaign = with_steps(config, campaign)

    rows =
      from(e in Enrollment,
        where: e.campaign_id == ^campaign.id,
        group_by: [e.state, e.reason],
        select: {e.state, e.reason, count(e.id)}
      )
      |> config.repo.all(prefix: config.prefix)

    entered = rows |> Enum.map(&elem(&1, 2)) |> Enum.sum()
    goal = for({"completed", "goal", n} <- rows, do: n) |> Enum.sum()
    by_step = delivery_counts(config, campaign.id)
    goal_after = goal_after(config, campaign.id)

    %{
      entered: entered,
      active: for({"active", _, n} <- rows, do: n) |> Enum.sum(),
      goal: goal,
      goal_rate: if(entered > 0, do: goal / entered),
      ended:
        rows
        |> Enum.filter(fn {state, _reason, _n} -> state != "active" end)
        |> Enum.group_by(&elem(&1, 1), &elem(&1, 2))
        |> Map.new(fn {reason, ns} -> {reason, Enum.sum(ns)} end),
      steps:
        Enum.map(campaign.steps, fn step ->
          step_counts = Map.get(by_step, step.id, %{})

          step_counts
          |> statuses()
          |> Map.merge(%{
            step_id: step.id,
            wait: step.wait,
            position: step.position,
            goal_after: Map.get(goal_after, step.id, 0)
          })
        end)
    }
  end

  defp statuses(counts) do
    Map.new(@statuses, fn {status, key} -> {key, Map.get(counts, status, 0)} end)
  end

  # The deliveries by step and status, and of the whole campaign (:all).
  defp delivery_counts(config, campaign_id) do
    rows =
      from(d in Delivery,
        where: d.campaign_id == ^campaign_id,
        group_by: [d.step_id, d.status],
        select: {d.step_id, d.status, count(d.id)}
      )
      |> config.repo.all(prefix: config.prefix)

    by_step =
      Enum.reduce(rows, %{}, fn {step_id, status, n}, acc ->
        Map.update(acc, step_id, %{status => n}, &Map.update(&1, status, n, fn m -> m + n end))
      end)

    all =
      Enum.reduce(rows, %{}, fn {_step_id, status, n}, acc ->
        Map.update(acc, status, n, &(&1 + n))
      end)

    Map.put(by_step, :all, all)
  end

  # For each step, the people who reached the goal and whose last letter
  # sent was this step's.
  defp goal_after(config, campaign_id) do
    from(d in Delivery,
      join: e in Enrollment,
      on: e.campaign_id == d.campaign_id and e.person == d.person,
      where:
        d.campaign_id == ^campaign_id and e.state == "completed" and e.reason == "goal" and
          d.status in ["sent", "bounced", "complained"] and not is_nil(d.step_id),
      select: {d.person, d.step_id, d.sent_at}
    )
    |> config.repo.all(prefix: config.prefix)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {_person, rows} ->
      rows |> Enum.max_by(&elem(&1, 2), &later_or_same?/2) |> elem(1)
    end)
    |> Enum.frequencies()
  end

  defp later_or_same?(nil, _b), do: false
  defp later_or_same?(_a, nil), do: true
  defp later_or_same?(a, b), do: DateTime.compare(a, b) != :lt

  # ── Helpers ─────────────────────────────────────────────────────

  defp expect(%Campaign{kind: kind, status: status}, kind, statuses) do
    if status in statuses, do: :ok, else: {:error, {:status, status}}
  end

  defp expect(%Campaign{kind: kind}, _kind, _statuses), do: {:error, {:kind, kind}}

  # Each step's letter in the first language, with a subject and a body.
  defp ready(_config, %Campaign{steps: []}), do: {:error, :no_steps}

  defp ready(config, %Campaign{steps: steps}) do
    locale = Config.default_locale(config)

    incomplete =
      steps
      |> Enum.reject(fn step -> complete?(Enum.find(step.letters, &(&1.locale == locale))) end)
      |> Enum.map(& &1.id)

    if incomplete == [], do: :ok, else: {:error, {:incomplete, incomplete}}
  end

  @doc false
  def complete?(nil), do: false

  def complete?(%Letter{subject: subject, text: text, body: body}) do
    present?(subject) and
      (present?(text) or (match?(%Kotoba.Content{}, body) and body.html =~ "<img"))
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  # Archived, or a broadcast sent or being sent: its letters stay as they went.
  defp locked?(%Campaign{status: "archived"}), do: true

  defp locked?(%Campaign{kind: "broadcast", status: status}) when status in ["sending", "sent"],
    do: true

  defp locked?(%Campaign{}), do: false

  defp put_status(config, campaign, changes) do
    campaign
    |> Ecto.Changeset.change(changes)
    |> config.repo.update(prefix: config.prefix)
    |> preloaded(config)
  end

  defp preloaded({:ok, campaign}, config), do: {:ok, with_steps(config, campaign)}
  defp preloaded(error, _config), do: error

  # A write of a campaign, with its jobs (Oban), in one transaction; then
  # the pages hear of it, and without Oban the scheduler looks again.
  defp write(config, campaign_id \\ nil, fun) do
    config.repo.transaction(fn ->
      case fun.() do
        {:ok, result} -> result
        {:error, error} -> config.repo.rollback(error)
      end
    end)
    |> case do
      {:ok, result} ->
        changed(config, campaign_id || result.id)
        {:ok, result}

      error ->
        error
    end
  end

  defp changed(config, id) do
    Tayori.broadcast({Tayori, :campaign_changed, id})
    if config.oban == nil, do: Tayori.Scheduler.wake()
    :ok
  end

  defp stringify(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  defp usec(nil), do: nil
  defp usec(%DateTime{microsecond: {value, _}} = at), do: %{at | microsecond: {value, 6}}

  defp audience! do
    Audience.current() ||
      raise ArgumentError, "the :campaigns module is off: add it to the :modules of Tayori"
  end
end
