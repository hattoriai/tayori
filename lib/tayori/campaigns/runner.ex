defmodule Tayori.Campaigns.Runner do
  @moduledoc false
  # Runs the campaigns: takes people into sequences, advances them step
  # by step, sends the broadcasts, and sends each letter. Every function
  # takes the time, so that the tests run it on a clock of their own.
  #
  # The work is the same with Oban and without (Tayori.Jobs): with Oban,
  # an enrollment has one job at its next_at, a broadcast one at its
  # send_at, and each letter is a job; without, the scheduler calls
  # run_due/3 each minute and when woken, and the letters go from a task
  # after the write that queued them.
  #
  # An enrollment is advanced by one node at a time: the claim sets its
  # next_at to nil where it is still the value read, in the transaction
  # of the advance, so that a second claim finds nothing. A crash rolls
  # the claim back with the rest, and the enrollment is due again. A
  # letter is claimed the same way (claimed_at) before it is sent, so
  # that a delivery given two jobs goes once.
  #
  # The pages hear of a campaign once for each run that changed it (an
  # enrollment's job, a run of run_due/3, a batch of a broadcast), not
  # once for each person.

  import Ecto.Query

  alias Tayori.{Audience, Campaigns, Config, Jobs}
  alias Tayori.Campaigns.{Campaign, Delivery, Enrollment, Events, Letters, Step}

  require Logger

  @compile {:no_warn_undefined, [Tayori.Campaigns.Letters]}

  @batch 200
  @broadcast_batch 500
  @id_batch 1000
  # How long a letter's job keeps it, sending it, from the others.
  @claim_seconds 600

  # ── Entry ───────────────────────────────────────────────────────

  @doc false
  # An event was tracked: the active sequences it triggers take the
  # person in, at the event's time.
  @spec event_tracked(Config.t(), String.t(), String.t(), DateTime.t()) :: :ok
  def event_tracked(%Config{} = config, person_id, name, %DateTime{} = at) do
    if Config.module?(config, :campaigns) do
      trigger = %{"type" => "event", "event" => name}

      from(c in Campaign, where: c.kind == "sequence" and c.status == "active")
      |> config.repo.all(prefix: config.prefix)
      |> Enum.filter(&(&1.trigger == trigger))
      |> Enum.each(&Campaigns.enroll(&1, person_id, at))
    end

    :ok
  end

  # ── Advancing a person ──────────────────────────────────────────

  @doc false
  # Advances an enrollment whose time came: see the steps below. Options:
  # `:inline` - the letters are sent here, not from a task (the tests'
  # run_campaigns!/1), without Oban.
  @spec advance(Config.t(), Ecto.UUID.t(), DateTime.t(), keyword()) :: :ok
  def advance(%Config{} = config, id, %DateTime{} = now, opts \\ []) do
    if Config.module?(config, :campaigns) do
      config |> advance_one(id, now, opts) |> List.wrap() |> changed()
    end

    :ok
  end

  # Advances one enrollment: the id of its campaign when the person's
  # state changed (they left it, or finished), else nil.
  defp advance_one(config, id, now, opts) do
    {:ok, {jobs, changed}} = transaction(config, fn -> advance_due(config, id, now) end)
    Jobs.campaign_committed(config, jobs, Keyword.put(opts, :now, now))
    changed
  end

  defp advance_due(config, id, now) do
    case config.repo.get(Enrollment, id, prefix: config.prefix) do
      %Enrollment{state: "active", next_at: %DateTime{} = next_at} = enrollment ->
        if DateTime.after?(next_at, now) do
          # Moved later since its job was made: a job at the new time.
          Jobs.campaign_written(config, [{:enrollment, id, next_at}])
          {[], nil}
        else
          claimed(config, enrollment, now)
        end

      _gone_ended_or_held ->
        {[], nil}
    end
  end

  defp claimed(config, enrollment, now) do
    {count, _} =
      from(e in Enrollment, where: e.id == ^enrollment.id and e.next_at == ^enrollment.next_at)
      |> config.repo.update_all([set: [next_at: nil]], prefix: config.prefix)

    if count == 1 do
      campaign = config.repo.get(Campaign, enrollment.campaign_id, prefix: config.prefix)
      {changes, jobs} = judge(config, campaign, enrollment, now)
      save(config, campaign, enrollment, Map.put(changes, :updated_at, usec(now)), jobs)
    else
      # Another node has it.
      {[], nil}
    end
  end

  # The enrollment as judged, and its jobs, with the campaign's id when the
  # person's state changed. No row when the campaign, and its people with
  # it, was deleted meanwhile: there is nothing to do.
  defp save(config, campaign, enrollment, changes, jobs) do
    {count, _} =
      config.repo.update_all(
        from(e in Enrollment, where: e.id == ^enrollment.id),
        [set: Enum.to_list(changes)],
        prefix: config.prefix
      )

    if count == 1 do
      next = for {:next_at, %DateTime{} = at} <- changes, do: {:enrollment, enrollment.id, at}
      jobs = next ++ jobs
      Jobs.campaign_written(config, jobs)
      {jobs, if(changes[:state], do: campaign.id)}
    else
      {[], nil}
    end
  end

  # 1. The sequence is not active: the person waits, with no next_at;
  #    resume/2 gives them one.
  defp judge(_config, nil, _enrollment, _now), do: {%{}, []}

  defp judge(_config, %Campaign{status: status}, _enrollment, _now) when status != "active",
    do: {%{}, []}

  defp judge(config, campaign, enrollment, now) do
    recipient = Audience.get(enrollment.person)

    case stop(config, campaign, enrollment, recipient, now) do
      {state, reason} ->
        {ended(state, reason, now), []}

      nil ->
        steps =
          from(s in Step,
            where: s.campaign_id == ^campaign.id,
            order_by: [asc: s.wait, asc: s.position],
            preload: :letters
          )
          |> config.repo.all(prefix: config.prefix)

        ctx = %{
          config: config,
          campaign: campaign,
          enrollment: enrollment,
          recipient: recipient,
          steps: steps,
          now: now
        }

        walk(ctx, %{cursor: enrollment.cursor, last_sent_at: enrollment.last_sent_at, jobs: []})
    end
  end

  # Why a person leaves the sequence now, or nil.
  # 2. No longer one of the app's people.
  defp stop(_config, _campaign, _enrollment, nil, _now), do: {"exited", "left"}

  defp stop(config, campaign, enrollment, recipient, now) do
    purpose = purpose(campaign)

    cond do
      # 3. The goal is reached.
      campaign.goal && Audience.match?(enrollment.person, campaign.goal, now) ->
        {"completed", "goal"}

      # 4. Past the days of the sequence.
      expired?(campaign, enrollment, now) ->
        {"completed", "expired"}

      # 5. Unsubscribed, or the app says not to.
      Campaigns.suppressed?(recipient.email, purpose) ->
        {"exited", "unsubscribed"}

      not Audience.can_email?(config.campaigns.audience, recipient, purpose) ->
        {"exited", "cannot_email"}

      true ->
        nil
    end
  end

  defp expired?(%Campaign{max_days: nil}, _enrollment, _now), do: false

  defp expired?(%Campaign{max_days: days}, enrollment, now),
    do: DateTime.after?(now, DateTime.add(enrollment.entered_at, days, :day))

  # 6. The next step after the cursor: not yet its time, skipped, held by
  #    the gap since the last letter, or sent; then the one after.
  defp walk(ctx, state) do
    case Enum.find(ctx.steps, &(&1.wait > state.cursor)) do
      nil ->
        {Map.merge(ended("completed", "finished", ctx.now), position(state)), state.jobs}

      step ->
        case judge_step(ctx, state, step) do
          {:wait, at} ->
            {Map.put(position(state), :next_at, usec(at)), state.jobs}

          {:skip, reason} ->
            delivery(ctx, step, "skipped", reason)
            walk(ctx, %{state | cursor: step.wait})

          :send ->
            walk(ctx, sent(ctx, state, step))
        end
    end
  end

  defp judge_step(ctx, state, step) do
    at = DateTime.add(ctx.enrollment.entered_at, step.wait * 60, :second)

    cond do
      DateTime.after?(at, ctx.now) ->
        {:wait, at}

      step.skip_if && Audience.match?(ctx.enrollment.person, step.skip_if, ctx.now) ->
        {:skip, "skip_if"}

      # A step an admin left with no letter, in any language: there is
      # nothing to send, and the sequence goes on.
      step.letters == [] ->
        {:skip, "no_letter"}

      true ->
        sendable(ctx, state)
    end
  end

  # A step whose letter is wanted now: held by the gap since the last
  # letter, or sent, if the person has an address.
  defp sendable(ctx, state) do
    gap_until =
      state.last_sent_at &&
        DateTime.add(state.last_sent_at, ctx.campaign.min_gap_hours * 3600, :second)

    cond do
      gap_until && DateTime.after?(gap_until, ctx.now) -> {:wait, gap_until}
      ctx.recipient.email in [nil, ""] -> {:skip, "no_email"}
      true -> :send
    end
  end

  defp sent(ctx, state, step) do
    case delivery(ctx, step, "queued", nil) do
      {:ok, id} ->
        %{
          state
          | cursor: step.wait,
            last_sent_at: usec(ctx.now),
            jobs: state.jobs ++ [{:letter, id}]
        }

      # Sent already: on to the next.
      :exists ->
        %{state | cursor: step.wait}
    end
  end

  defp position(state), do: %{cursor: state.cursor, last_sent_at: state.last_sent_at}

  defp ended(state, reason, now),
    do: %{state: state, reason: reason, next_at: nil, ended_at: usec(now)}

  # A step's letter to a person, once: {:ok, id}, or :exists.
  defp delivery(ctx, step, status, reason) do
    %{config: config, campaign: campaign, recipient: recipient, now: now} = ctx
    id = Ecto.UUID.generate()
    stamp = usec(now)

    {count, _} =
      config.repo.insert_all(
        Delivery,
        [
          %{
            id: id,
            campaign_id: campaign.id,
            step_id: step.id,
            person: recipient.id,
            email: address(recipient.email),
            locale: recipient.locale,
            status: status,
            reason: reason,
            inserted_at: stamp,
            updated_at: stamp
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:campaign_id, :step_id, :person],
        prefix: config.prefix
      )

    if count == 1, do: {:ok, id}, else: :exists
  end

  # ── Broadcasts ──────────────────────────────────────────────────

  @doc false
  # Sends a broadcast whose time came: claimed once (scheduled to
  # sending), then each person of its audience, in batches, gets a
  # delivery and a letter, once; each batch marks its progress
  # (updated_at), which the sweep reads (Tayori.Jobs). Options: `:resume`
  # - a broadcast being sent is walked again (an Oban job tried again
  # after a crash, a broadcast the sweep found stopped, a run of run_due/3
  # after a crash: the deliveries are unique, so no one gets two);
  # `:batch_size` (500); `:inline`.
  @spec send_broadcast(Config.t(), Ecto.UUID.t(), DateTime.t(), keyword()) :: :ok
  def send_broadcast(%Config{} = config, id, %DateTime{} = now, opts \\ []) do
    if Config.module?(config, :campaigns) do
      config.repo.get(Campaign, id, prefix: config.prefix)
      |> broadcast_due(config, now, opts)
    end

    :ok
  end

  defp broadcast_due(
         %Campaign{kind: "broadcast", status: "scheduled", send_at: %DateTime{} = at} = campaign,
         config,
         now,
         opts
       ) do
    cond do
      DateTime.after?(at, now) -> Jobs.campaign_written(config, [{:broadcast, campaign.id, at}])
      claim_broadcast(config, campaign) -> walk_broadcast(config, campaign, now, opts)
      true -> :ok
    end
  end

  defp broadcast_due(
         %Campaign{kind: "broadcast", status: "sending"} = campaign,
         config,
         now,
         opts
       ) do
    if opts[:resume], do: walk_broadcast(config, campaign, now, opts), else: :ok
  end

  defp broadcast_due(_other, _config, _now, _opts), do: :ok

  defp claim_broadcast(config, campaign) do
    {count, _} =
      from(c in Campaign, where: c.id == ^campaign.id and c.status == "scheduled")
      |> config.repo.update_all([set: [status: "sending", updated_at: stamp()]],
        prefix: config.prefix
      )

    if count == 1, do: changed([campaign.id])
    count == 1
  end

  defp walk_broadcast(config, campaign, now, opts) do
    case config.repo.preload(campaign, :steps, prefix: config.prefix).steps do
      [step | _] ->
        Audience.each_batch(
          campaign.audience,
          Keyword.get(opts, :batch_size, @broadcast_batch),
          fn recipients ->
            send_batch(recipients, config, campaign, step, now, opts)
            progressed(config, campaign)
          end,
          now
        )

      [] ->
        :ok
    end

    from(c in Campaign, where: c.id == ^campaign.id and c.status == "sending")
    |> config.repo.update_all([set: [status: "sent", sent_at: usec(now), updated_at: usec(now)]],
      prefix: config.prefix
    )

    changed([campaign.id])
    :ok
  end

  # A batch of a broadcast went: its time, for the sweep, and a word to
  # the pages.
  defp progressed(config, campaign) do
    from(c in Campaign, where: c.id == ^campaign.id and c.status == "sending")
    |> config.repo.update_all([set: [updated_at: stamp()]], prefix: config.prefix)

    changed([campaign.id])
  end

  # The people of a batch who may be written to: a delivery each, and a
  # letter.
  defp send_batch(recipients, config, campaign, step, now, opts) do
    purpose = purpose(campaign)
    audience = config.campaigns.audience
    suppressed = Campaigns.suppressed(config, Enum.map(recipients, & &1.email), purpose)

    recipients
    |> Enum.filter(fn recipient ->
      recipient.email not in [nil, ""] and
        not MapSet.member?(suppressed, Campaigns.normalize(recipient.email)) and
        Audience.can_email?(audience, recipient, purpose)
    end)
    |> queue_batch(config, campaign, step, now)
    |> then(&Jobs.campaign_committed(config, &1, Keyword.put(opts, :now, now)))
  end

  defp queue_batch([], _config, _campaign, _step, _now), do: []

  defp queue_batch(recipients, config, campaign, step, now) do
    stamp = usec(now)

    rows =
      Enum.map(recipients, fn recipient ->
        %{
          id: Ecto.UUID.generate(),
          campaign_id: campaign.id,
          step_id: step.id,
          person: recipient.id,
          email: address(recipient.email),
          locale: recipient.locale,
          status: "queued",
          inserted_at: stamp,
          updated_at: stamp
        }
      end)

    {:ok, jobs} =
      transaction(config, fn ->
        config.repo.insert_all(Delivery, rows,
          on_conflict: :nothing,
          conflict_target: [:campaign_id, :step_id, :person],
          prefix: config.prefix
        )

        ids = Enum.map(rows, & &1.id)

        jobs =
          from(d in Delivery, where: d.id in ^ids, select: d.id)
          |> config.repo.all(prefix: config.prefix)
          |> Enum.map(&{:letter, &1})

        Jobs.campaign_written(config, jobs)
        jobs
      end)

    jobs
  end

  # ── The letter ──────────────────────────────────────────────────

  @doc false
  # Sends a delivery's letter, once: the person is read again, and the
  # address checked again (unsubscribed since, or the app says not to:
  # skipped). A paused sequence's letter stays queued, sent by resume/2; an
  # archived campaign's is skipped, "stopped". The letter is claimed
  # first: a delivery given two jobs goes once. An error is tried again,
  # unless this is the last attempt: the delivery is then "failed".
  @spec deliver_letter(Config.t(), Ecto.UUID.t(), DateTime.t(), boolean()) ::
          :ok | {:error, term()}
  def deliver_letter(%Config{} = config, id, %DateTime{} = now, last_attempt?) do
    with true <- Config.module?(config, :campaigns),
         %Delivery{status: "queued"} = delivery <-
           config.repo.get(Delivery, id, prefix: config.prefix),
         # Deleted since, with its deliveries: nothing to send.
         %Campaign{} = campaign <-
           config.repo.get(Campaign, delivery.campaign_id, prefix: config.prefix),
         :ok <- going(config, campaign, delivery, now),
         true <- claim_letter(config, delivery, now) do
      send_letter(config, campaign, delivery, now, last_attempt?)
    else
      _ -> :ok
    end
  end

  defp going(_config, %Campaign{status: "paused"}, _delivery, _now), do: :paused

  defp going(config, %Campaign{status: "archived"}, delivery, now) do
    finish(config, delivery, "skipped", "stopped", now)
    :stopped
  end

  defp going(_config, _campaign, _delivery, _now), do: :ok

  # The letter, taken by this job, where no other took it in the last ten
  # minutes. A failure gives it back, for the next attempt.
  defp claim_letter(config, delivery, now) do
    free = usec(DateTime.add(now, -@claim_seconds))

    {count, _} =
      from(d in Delivery,
        where:
          d.id == ^delivery.id and d.status == "queued" and
            (is_nil(d.claimed_at) or d.claimed_at < ^free)
      )
      |> config.repo.update_all([set: [claimed_at: usec(now), updated_at: usec(now)]],
        prefix: config.prefix
      )

    count == 1
  end

  defp send_letter(config, campaign, delivery, now, last_attempt?) do
    purpose = purpose(campaign)

    step =
      delivery.step_id &&
        config.repo.get(Step, delivery.step_id, prefix: config.prefix)
        |> config.repo.preload(:letters, prefix: config.prefix)

    recipient = Audience.get(delivery.person)

    cond do
      step == nil ->
        finish(config, delivery, "skipped", "step_removed", now)

      step.letters == [] ->
        finish(config, delivery, "skipped", "no_letter", now)

      recipient == nil ->
        finish(config, delivery, "skipped", "left", now)

      recipient.email in [nil, ""] ->
        finish(config, delivery, "skipped", "no_email", now)

      Campaigns.suppressed?(recipient.email, purpose) ->
        finish(config, delivery, "skipped", "unsubscribed", now)

      not Audience.can_email?(config.campaigns.audience, recipient, purpose) ->
        finish(config, delivery, "skipped", "cannot_email", now)

      true ->
        mail(
          config,
          delivery,
          Letters.render(campaign, step, recipient),
          recipient,
          now,
          last_attempt?
        )
    end
  end

  defp mail(config, delivery, email, recipient, now, last_attempt?) do
    case config.mailer.deliver(email) do
      {:ok, meta} ->
        set(config, delivery,
          status: "sent",
          sent_at: usec(now),
          email: address(recipient.email),
          provider_id: provider_id(meta),
          claimed_at: nil,
          updated_at: usec(now)
        )

      {:error, reason} ->
        if last_attempt?,
          do: finish(config, delivery, "failed", reason(reason), now),
          else: set(config, delivery, claimed_at: nil, updated_at: usec(now))

        {:error, reason}
    end
  end

  defp finish(config, delivery, status, reason, now) do
    set(config, delivery, status: status, reason: reason, claimed_at: nil, updated_at: usec(now))
  end

  defp set(config, delivery, changes) do
    from(d in Delivery, where: d.id == ^delivery.id)
    |> config.repo.update_all([set: changes], prefix: config.prefix)

    :ok
  end

  defp provider_id(%{id: id}) when is_binary(id), do: String.slice(id, 0, 255)
  defp provider_id(meta) when is_list(meta), do: provider_id(Map.new(meta))
  defp provider_id(_meta), do: nil

  defp reason(reason) when is_binary(reason), do: String.slice(reason, 0, 64)
  defp reason(reason), do: reason |> inspect() |> String.slice(0, 64)

  # ── Without Oban ────────────────────────────────────────────────

  @doc false
  # What is due at a time, from the scheduler (or the tests): the
  # enrollments whose next_at came, in batches of 200, the broadcasts
  # whose send_at came, and those being sent, walked again: a node that
  # stopped, or a walk that raised, left them half way (their deliveries
  # are unique: no one gets two). Each campaign whose people changed is
  # told once, at the end. Options: those of advance/4 and
  # send_broadcast/4.
  @spec run_due(Config.t(), DateTime.t(), keyword()) :: :ok
  def run_due(%Config{} = config, %DateTime{} = now, opts \\ []) do
    if Config.module?(config, :campaigns) do
      config |> run_enrollments(now, opts, MapSet.new(), MapSet.new()) |> changed()

      from(c in Campaign,
        where:
          c.kind == "broadcast" and
            ((c.status == "scheduled" and c.send_at <= ^now) or c.status == "sending"),
        order_by: [asc: c.send_at, asc: c.id],
        select: c.id
      )
      |> config.repo.all(prefix: config.prefix)
      |> Enum.each(&broadcast_logged(config, &1, now, opts))
    end

    :ok
  end

  defp broadcast_logged(config, id, now, opts) do
    send_broadcast(config, id, now, Keyword.put(opts, :resume, true))
  rescue
    error ->
      Logger.error(
        "Tayori could not send the broadcast #{id}, and tries again: " <> Exception.message(error)
      )
  end

  # The ids of the campaigns whose people changed.
  defp run_enrollments(config, now, opts, seen, changed) do
    ids =
      from(e in Enrollment,
        where: e.state == "active" and not is_nil(e.next_at) and e.next_at <= ^now,
        order_by: [asc: e.next_at, asc: e.id],
        limit: @batch,
        select: e.id
      )
      |> config.repo.all(prefix: config.prefix)

    new = Enum.reject(ids, &MapSet.member?(seen, &1))

    changed =
      new
      |> Enum.map(&advance_logged(config, &1, now, opts))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()
      |> MapSet.union(changed)

    # A full batch has more after it; one whose every id was seen is held
    # elsewhere, or failed: the next run tries again.
    if length(ids) == @batch and new != [],
      do: run_enrollments(config, now, opts, MapSet.union(seen, MapSet.new(ids)), changed),
      else: changed
  end

  defp advance_logged(config, id, now, opts) do
    if Config.module?(config, :campaigns), do: advance_one(config, id, now, opts)
  rescue
    error ->
      Logger.error("Tayori could not advance #{id} in its campaign: " <> Exception.message(error))
      nil
  end

  @doc false
  # The deliveries of a campaign still queued, for resume/2.
  @spec queued(Ecto.UUID.t()) :: Ecto.Query.t()
  def queued(campaign_id) do
    from(d in Delivery, where: d.campaign_id == ^campaign_id and d.status == "queued")
  end

  @doc false
  # Walks the ids of a query's rows, 1000 at a time, each batch after the
  # last id of the one before: `fun` gets each batch.
  @spec each_id(Ecto.Query.t(), Config.t(), ([Ecto.UUID.t()] -> term())) :: :ok
  def each_id(query, %Config{} = config, fun), do: each_id(query, config, fun, nil)

  defp each_id(query, config, fun, last) do
    ids =
      query
      |> then(fn query -> if last, do: where(query, [r], r.id > ^last), else: query end)
      |> order_by([r], asc: r.id)
      |> limit(@id_batch)
      |> select([r], r.id)
      |> config.repo.all(prefix: config.prefix)

    if ids != [], do: fun.(ids)

    if length(ids) == @id_batch,
      do: each_id(query, config, fun, List.last(ids)),
      else: :ok
  end

  @doc false
  # The next time the campaigns have work, for the scheduler's timer.
  @spec next_due(Config.t()) :: DateTime.t() | nil
  def next_due(%Config{} = config) do
    if Config.module?(config, :campaigns) do
      [
        from(e in Enrollment, where: e.state == "active", select: min(e.next_at))
        |> config.repo.one(prefix: config.prefix),
        from(c in Campaign,
          where: c.kind == "broadcast" and c.status == "scheduled",
          select: min(c.send_at)
        )
        |> config.repo.one(prefix: config.prefix)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_datetime/1)
      |> Enum.min(DateTime, fn -> nil end)
    end
  end

  @doc false
  # The events' retention, once a day on this node, from the scheduler.
  @spec daily_cleanup(Config.t(), DateTime.t()) :: :ok
  def daily_cleanup(%Config{} = config, %DateTime{} = now) do
    key = {__MODULE__, :cleaned, config.repo, config.prefix}
    today = DateTime.to_date(now)

    if Config.module?(config, :campaigns) and :persistent_term.get(key, nil) != today do
      :persistent_term.put(key, today)
      Events.delete_old(config, now)
    end

    :ok
  end

  # ── Helpers ─────────────────────────────────────────────────────

  @doc false
  # A transaction of the campaigns. On SQLite it takes the write lock as
  # it begins (BEGIN IMMEDIATE): a transaction that reads first and
  # writes after (the claim of an enrollment reads it, then updates it)
  # would otherwise fail at once with "Database busy" when another
  # connection wrote meanwhile, as SQLite cannot wait for a lock it would
  # take over a read that is no longer current. Begun immediate, it waits
  # its turn, for the repo's busy timeout.
  @spec transaction(Config.t(), (-> result)) :: {:ok, result} | {:error, term()}
        when result: term()
  def transaction(%Config{repo: repo}, fun) do
    if repo.__adapter__() == Ecto.Adapters.SQLite3,
      do: repo.transaction(fun, mode: :immediate),
      else: repo.transaction(fun)
  end

  # The campaigns whose people or letters changed, each told once.
  defp changed(ids),
    do: ids |> Enum.uniq() |> Enum.each(&Tayori.broadcast({Tayori, :campaign_changed, &1}))

  # An address as the deliveries keep it: lowercased, as the suppressions.
  defp address(nil), do: nil
  defp address(email), do: Campaigns.normalize(email)

  defp stamp, do: usec(DateTime.utc_now())

  defp purpose(%Campaign{purpose: "marketing"}), do: :marketing
  defp purpose(%Campaign{}), do: :product

  defp usec(nil), do: nil
  defp usec(%DateTime{microsecond: {value, _}} = at), do: %{at | microsecond: {value, 6}}

  defp to_datetime(%DateTime{} = at), do: at
  defp to_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp to_datetime(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _} -> at
      _ -> text |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
    end
  end
end
