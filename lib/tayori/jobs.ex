defmodule Tayori.Jobs do
  @moduledoc """
  What a publication sends, and how: the emails to the subscribers (the
  `:subscriptions` feature), the webhooks (the `:webhooks` feature) and
  the call to the app's `:notifier`.

  An entry is announced once, by one node of the cluster, when it is
  published or when its scheduled time comes (the entry is claimed in the
  database first). Its readers see it on time whatever happens next: what
  follows is only what it sends.

  The schedules go the same way: a digest of the inbox (`Tayori.Digest`),
  and, with the `:emails` config, the email of a period's entries to
  each subscriber. A digest is one job at a time: asked for again while
  one waits, it is the same job, which takes the changes that came
  meanwhile.

  ## With Oban

  When the app runs [Oban](https://hexdocs.pm/oban), Tayori gives it the
  work, as jobs of `Tayori.Worker`:

      {Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub, oban: Oban}

  Start Tayori after Oban in the supervision tree.

  Nothing then looks at the database on a timer. Each write of an entry
  gives Oban its announcement, a job at its publication time, in the
  write's own transaction: the entry and its job are kept together, or
  neither is. There is one job for each entry, moved when the time
  changes, doing nothing when the entry is a draft again or was
  announced already. A scheduled digest and the email of a period are a
  job at their next time, which gives Oban the one after. At boot, a task
  gives Oban what may have none: the announcements of entries published
  before Tayori ran with Oban, the schedules, and the reading of the
  inbox's sources (`:ingest_on_start`).

  Two things this asks of the app:

    * **Oban in the same repo as Tayori**, for the job to be in the
      write's transaction. An Oban of another repo still gets the job, just
      after the write; the boot task then gives a job to an entry whose
      insert failed.
    * **Tayori after Oban in the supervision tree**, so that the boot
      task finds Oban running.

  Each email, each webhook and the notifier's call is a job of its own,
  retried with Oban's backoff, through deploys and crashes, and seen in
  Oban's dashboards. A webhook a place refuses for good (a 4xx) is
  cancelled, not retried. The jobs go to the `:default` queue, or the
  one given (`oban: [name: Oban, queue: :news]`), which must be one the
  app runs: Tayori logs an error when it is not.

  `mix tayori.install` sets `oban: Oban` when the app has Oban.

  With the `:campaigns` module, each person of a sequence is a job at
  their next time (one job each, moved when the time changes), a
  scheduled broadcast a job at its time, and each letter a job of its
  own, tried five times: a letter that fails its last attempt is marked
  `"failed"`. The events are cleaned once a day by a job. A sweep, one
  job at boot and then every hour, gives Oban what lost its job (written
  before Tayori ran with Oban, by an Oban of another repo, or a job
  discarded): the people of the sequences more than 5 minutes past their
  time, the broadcasts more than 5 minutes past theirs, or being sent
  with no batch in 5 minutes, and the letters queued for more than 15
  minutes, but those of a paused sequence, which wait for it. A letter
  is claimed before it is sent, so that one given two jobs goes once.

  ## Without Oban

  A scheduler, one in the cluster, announces the entries and runs the
  schedules: it wakes when an entry changes, at the next publication
  time, and every minute. Tayori sends the rest from tasks in the node
  that announced the entry. A
  webhook is tried three times, a few seconds apart; an email and a
  digest once. A failure is logged. A node stopped while it sends (a deploy, a crash)
  loses what it had not sent yet: the entry is not sent twice, but some
  subscribers may not get it. For a changelog with subscribers or
  webhooks that matter, run Oban.

  The campaigns, without Oban, go the same way: the scheduler advances
  each person whose time came and sends the broadcasts whose time came,
  or that a stopped node left half sent, every minute and when a
  campaign changes, and each letter is tried once, from a task, and
  marked `"failed"` when it fails.
  """

  import Ecto.Query

  alias Tayori.Campaigns.{Campaign, Delivery, Enrollment, Events, Runner}
  alias Tayori.{Config, Entry, Scheduler, Subscribers, Webhooks}

  require Logger

  # Oban is an optional dependency, used with the :oban option.
  @compile {:no_warn_undefined, [Oban, Tayori.Worker]}

  @letter_attempts 5
  # The jobs given to Oban.insert_all at once.
  @insert_chunk 500
  # How long work may be past its time before the sweep gives it a job:
  # the people and the broadcasts, then the letters.
  @overdue 300
  @overdue_letters 900
  @sweep_every 3600

  @doc false
  # Sends what the publication of an entry sends, from the scheduler.
  @spec published(Config.t(), Ecto.UUID.t()) :: :ok
  def published(%Config{} = config, entry_id) do
    jobs =
      Enum.map(Subscribers.claim_entry(config, entry_id), &{:email, entry_id, &1}) ++
        Enum.map(Webhooks.targets(config, entry_id), &{:webhook, entry_id, &1}) ++
        if(config.notifier, do: [{:notify, entry_id}], else: [])

    run(config, jobs)
  end

  @doc false
  # Starts a digest of the inbox (Tayori.Digest), from the scheduler or
  # after changes came: one Oban job, which stays one when asked again
  # before it runs, or a task.
  @spec digest(Config.t()) :: :ok
  def digest(%Config{oban: nil} = config) do
    start(fn -> try_once(config, :digest) end)
    :ok
  end

  def digest(%Config{oban: oban} = config) do
    check_queue(oban)
    {:ok, _job} = Oban.insert(oban.name, Tayori.Worker.new(args(:digest), opts(:digest, oban)))
    :ok
  rescue
    error ->
      Logger.error(
        "Tayori could not give Oban the digest, and makes it in a task: " <>
          Exception.message(error)
      )

      digest(%{config | oban: nil})
  end

  @doc false
  # Sends the email of a period's entries (the :emails config), from the
  # scheduler: the entries are claimed once, then one email goes to each
  # subscriber.
  @spec email_digest(Config.t(), DateTime.t()) :: :ok
  def email_digest(%Config{} = config, since) do
    {entry_ids, subscriber_ids} = Subscribers.claim_digest(config, since)
    run(config, Enum.map(subscriber_ids, &{:digest_email, entry_ids, &1}))
  end

  @doc false
  # With Oban, in the transaction of an entry's write (Tayori.Entries):
  # its announcement, a job at its publication time. A failure fails the
  # write, so an entry is never published without its job.
  @spec entry_written(Config.t(), Entry.t()) :: :ok
  def entry_written(%Config{oban: nil}, _entry), do: :ok

  def entry_written(%Config{oban: oban}, %Entry{} = entry) do
    if unannounced?(entry), do: announce_at(oban, entry.id, entry.published_at)
    :ok
  end

  @doc false
  # With Oban, at boot, on each node: the announcements of the entries
  # published and not announced (those written before Tayori ran with
  # Oban, or by an Oban of another repo), the schedules, and the reading of
  # the inbox's sources. The jobs are unique: the nodes of a cluster give
  # Oban each one once. Without the changelog, none of it.
  @spec boot(Config.t()) :: :ok
  def boot(%Config{oban: oban} = config) do
    check_queue(oban)
    if Config.module?(config, :changelog), do: boot_changelog(config)
    if Config.module?(config, :campaigns), do: boot_campaigns(config)
    :ok
  rescue
    error ->
      Logger.error("Tayori could not give Oban its work at boot: " <> Exception.message(error))
      :ok
  end

  defp boot_changelog(%Config{oban: oban} = config) do
    from(e in Entry,
      where: not is_nil(e.published_at) and is_nil(e.announced_at),
      select: {e.id, e.published_at}
    )
    |> config.repo.all(prefix: config.prefix)
    |> Enum.each(fn {id, at} -> announce_at(oban, id, at) end)

    if schedules?(config), do: insert!(oban, :schedules, DateTime.utc_now())

    if config.inbox.ingest_on_start and config.inbox.sources != [] do
      insert!(oban, :ingest, DateTime.utc_now())
    end
  end

  # The campaigns' sweep, which gives Oban what lost its job, and the
  # events' daily cleanup: one job each in the cluster. A node that boots
  # moves the sweep to now.
  defp boot_campaigns(%Config{oban: oban}) do
    now = DateTime.utc_now()
    insert!(oban, :campaigns_sweep, now)
    insert!(oban, :campaigns_cleanup, now)
  end

  @doc false
  # The campaigns' work that lost its job, at a time: the people of the
  # sequences more than 5 minutes past their next_at, the broadcasts more
  # than 5 minutes past their send_at or being sent with no batch in 5
  # minutes, and the letters queued for more than 15 minutes, but those of
  # a paused sequence. Each is given a job, a batch at a time (the jobs
  # are not unique: an enrollment and a letter are claimed, and a
  # broadcast's deliveries are unique, so that a second job does
  # nothing).
  @spec sweep_campaigns(Config.t(), DateTime.t()) :: :ok
  def sweep_campaigns(%Config{oban: nil}, _now), do: :ok

  def sweep_campaigns(%Config{} = config, %DateTime{} = now) do
    late = DateTime.add(now, -@overdue)
    late_letters = DateTime.add(now, -@overdue_letters)

    from(e in Enrollment,
      where: e.state == "active" and not is_nil(e.next_at) and e.next_at < ^late
    )
    |> Runner.each_id(
      config,
      &campaign_requeued(config, Enum.map(&1, fn id -> {:enrollment, id, now} end))
    )

    from(c in Campaign,
      where:
        c.kind == "broadcast" and
          ((c.status == "scheduled" and c.send_at < ^late) or
             (c.status == "sending" and c.updated_at < ^late))
    )
    |> Runner.each_id(
      config,
      &campaign_requeued(config, Enum.map(&1, fn id -> {:broadcast, id, now} end))
    )

    from(d in Delivery,
      join: c in Campaign,
      on: c.id == d.campaign_id,
      where: d.status == "queued" and d.updated_at < ^late_letters and c.status != "paused"
    )
    |> Runner.each_id(
      config,
      &campaign_requeued(config, Enum.map(&1, fn id -> {:letter, id} end))
    )
  end

  @doc false
  # With Oban, in the transaction of a campaign's write (Tayori.Campaigns,
  # Tayori.Campaigns.Runner): an enrollment's job at its next time, a
  # broadcast's at its time (one job each, moved when the time changes),
  # and a job for each letter. Without Oban, nothing: the scheduler finds
  # the times, and the letters go after the write (campaign_committed/3).
  @spec campaign_written(Config.t(), [tuple()]) :: :ok
  def campaign_written(%Config{oban: nil}, _jobs), do: :ok
  def campaign_written(_config, []), do: :ok

  def campaign_written(%Config{oban: oban} = config, jobs) do
    check_queue(oban)
    {letters, timed} = Enum.split_with(jobs, &match?({:letter, _}, &1))
    Enum.each(timed, fn {kind, id, at} -> insert!(oban, {kind, id}, at) end)
    campaign_requeued(config, letters)
  end

  @doc false
  # With Oban, jobs for the campaigns' work, given to Oban.insert_all a
  # chunk at a time: the letters, and what resume/2 and the sweep take up
  # again. insert_all keeps no job unique: a second job of an enrollment
  # or a letter finds it claimed, or done, and does nothing.
  @spec campaign_requeued(Config.t(), [tuple()]) :: :ok
  def campaign_requeued(%Config{oban: nil}, _jobs), do: :ok
  def campaign_requeued(_config, []), do: :ok

  def campaign_requeued(%Config{oban: oban}, jobs) do
    jobs
    |> Enum.map(fn
      {:letter, _id} = job ->
        Tayori.Worker.new(args(job), opts(job, oban))

      {kind, id, at} ->
        Tayori.Worker.new(args({kind, id}), [scheduled_at: at] ++ opts({kind, id}, oban))
    end)
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.each(&Oban.insert_all(oban.name, &1))
  end

  @doc false
  # Without Oban, after resume/2: the letters of a campaign still queued,
  # from a task, one after the other, each tried once.
  @spec send_queued(Config.t(), Ecto.UUID.t()) :: :ok
  def send_queued(%Config{oban: nil} = config, campaign_id) do
    start(fn ->
      campaign_id
      |> Runner.queued()
      |> Runner.each_id(config, fn ids -> Enum.each(ids, &try_once(config, {:letter, &1})) end)
    end)

    :ok
  end

  def send_queued(_config, _campaign_id), do: :ok

  @doc false
  # Without Oban, after the write that queued them: the letters, from a
  # task, one after the other, each tried once (a failure marks it
  # "failed"). Options: `:inline` - sent here, in the caller's process;
  # `:now` - the time they are sent at. With Oban, nothing: they are jobs.
  @spec campaign_committed(Config.t(), [tuple()], keyword()) :: :ok
  def campaign_committed(%Config{oban: nil} = config, jobs, opts),
    do: send_letters(config, for({:letter, id} <- jobs, do: id), opts)

  def campaign_committed(_config, _jobs, _opts), do: :ok

  defp send_letters(_config, [], _opts), do: :ok

  defp send_letters(config, ids, opts) do
    if opts[:inline] do
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      Enum.each(ids, &Runner.deliver_letter(config, &1, now, true))
    else
      start(fn -> Enum.each(ids, &try_once(config, {:letter, &1})) end)
    end

    :ok
  end

  defp unannounced?(%Entry{__meta__: %{state: :deleted}}), do: false
  defp unannounced?(%Entry{published_at: nil}), do: false
  defp unannounced?(%Entry{announced_at: nil}), do: true
  defp unannounced?(_entry), do: false

  defp announce_at(oban, entry_id, at), do: insert!(oban, {:announce, entry_id}, at)

  # A scheduled digest, or the email of a period's entries.
  defp schedules?(config) do
    Tayori.Digest.timed?(config.digest) or
      (Config.feature?(config, :subscriptions) and config.emails.every != :each)
  end

  # The next time a schedule is due, as a job: the digest's or the email's,
  # whichever comes first; a minute from now at the soonest, so that a time
  # a run did not move cannot run again at once.
  defp schedule_next(%Config{oban: oban} = config, now) do
    times =
      Enum.reject(
        [
          Tayori.Digest.next_at(config, now),
          if(Config.feature?(config, :subscriptions), do: Subscribers.next_email_at(config, now))
        ],
        &is_nil/1
      )

    if times != [] do
      at = Enum.max([Enum.min(times, DateTime), DateTime.add(now, 60)], DateTime)
      insert!(oban, :schedules, at)
    end

    :ok
  end

  defp insert!(oban, job, at) do
    {:ok, _job} =
      Oban.insert(oban.name, Tayori.Worker.new(args(job), [scheduled_at: at] ++ opts(job, oban)))

    :ok
  end

  defp run(_config, []), do: :ok
  defp run(%Config{oban: nil} = config, jobs), do: run_in_tasks(config, jobs)

  defp run(%Config{oban: oban} = config, jobs) do
    check_queue(oban)
    Oban.insert_all(oban.name, Enum.map(jobs, &Tayori.Worker.new(args(&1), opts(&1, oban))))
    :ok
  rescue
    error ->
      Logger.error(
        "Tayori could not give Oban the work of a publication, and sends it from tasks: " <>
          Exception.message(error)
      )

      run_in_tasks(config, jobs)
  end

  defp args({:email, entry_id, subscriber_id}),
    do: %{"job" => "email", "entry_id" => entry_id, "subscriber_id" => subscriber_id}

  defp args({:webhook, entry_id, hook_id}),
    do: %{"job" => "webhook", "entry_id" => entry_id, "hook_id" => hook_id}

  defp args({:notify, entry_id}), do: %{"job" => "notify", "entry_id" => entry_id}

  defp args({:digest_email, entry_ids, subscriber_id}),
    do: %{"job" => "digest_email", "entry_ids" => entry_ids, "subscriber_id" => subscriber_id}

  defp args(:digest), do: %{"job" => "digest"}
  defp args(:schedules), do: %{"job" => "schedules"}
  defp args(:ingest), do: %{"job" => "ingest"}
  defp args({:announce, entry_id}), do: %{"job" => "announce", "entry_id" => entry_id}
  defp args({:enrollment, id}), do: %{"job" => "enrollment", "id" => id}
  defp args({:broadcast, id}), do: %{"job" => "broadcast", "id" => id}
  defp args({:letter, delivery_id}), do: %{"job" => "letter", "delivery_id" => delivery_id}
  defp args(:campaigns_cleanup), do: %{"job" => "campaigns_cleanup"}
  defp args(:campaigns_sweep), do: %{"job" => "campaigns_sweep"}

  defp opts({:email, _, _}, oban), do: [queue: oban.queue, max_attempts: 5]
  defp opts({:webhook, _, _}, oban), do: [queue: oban.queue, max_attempts: 8]
  defp opts({:notify, _}, oban), do: [queue: oban.queue, max_attempts: 5]
  defp opts({:digest_email, _, _}, oban), do: [queue: oban.queue, max_attempts: 5]
  defp opts({:letter, _}, oban), do: [queue: oban.queue, max_attempts: @letter_attempts]

  # One job for each enrollment and each broadcast: a later write moves
  # the time of the one that waits.
  defp opts({:enrollment, _}, oban), do: once(oban, [:job, :id])
  defp opts({:broadcast, _}, oban), do: once(oban, [:job, :id])

  # One in the cluster: a node that starts moves it to now.
  defp opts(:campaigns_sweep, oban), do: once(oban, [:job])

  # One a day: a node that starts does not move it.
  defp opts(:campaigns_cleanup, oban) do
    [
      queue: oban.queue,
      max_attempts: 3,
      unique: [period: :infinity, keys: [:job], states: [:available, :scheduled, :retryable]]
    ]
  end

  # One job for each entry, and one for the schedules: a later write moves
  # the time of the one that waits.
  defp opts({:announce, _}, oban), do: once(oban, [:job, :entry_id])
  defp opts(:schedules, oban), do: once(oban, [:job])

  # Read once by the nodes that start together.
  defp opts(:ingest, oban) do
    [
      queue: oban.queue,
      max_attempts: 3,
      unique: [period: 300, keys: [:job], states: [:available, :scheduled, :executing]]
    ]
  end

  # A digest waiting for its turn takes the changes that come meanwhile:
  # there is no need of another.
  defp opts(:digest, oban) do
    [
      queue: oban.queue,
      max_attempts: 3,
      unique: [period: :infinity, keys: [:job], states: [:available, :scheduled, :retryable]]
    ]
  end

  defp once(oban, keys) do
    [
      queue: oban.queue,
      max_attempts: 10,
      unique: [period: :infinity, keys: keys, states: [:available, :scheduled, :retryable]],
      replace: [scheduled: [:scheduled_at], available: [:scheduled_at]]
    ]
  end

  @doc false
  # Does one job, in an Oban worker or a task. `attempt` is Oban's
  # `%{attempt: n, max_attempts: n}`: a letter that fails its last
  # attempt is "failed" (without it, this attempt is the last).
  @spec perform(Config.t(), map(), map()) :: :ok | {:error, term()} | {:cancel, term()}
  def perform(config, args, attempt)

  def perform(config, %{"job" => "enrollment", "id" => id}, _attempt),
    do: Runner.advance(config, id, DateTime.utc_now())

  def perform(config, %{"job" => "broadcast", "id" => id}, _attempt),
    do: Runner.send_broadcast(config, id, DateTime.utc_now(), resume: true)

  def perform(config, %{"job" => "letter", "delivery_id" => id}, attempt) do
    last? = Map.get(attempt, :attempt, 1) >= Map.get(attempt, :max_attempts, 1)
    Runner.deliver_letter(config, id, DateTime.utc_now(), last?)
  end

  # The events' retention, then the next day's.
  def perform(%Config{oban: oban} = config, %{"job" => "campaigns_cleanup"}, _attempt) do
    now = DateTime.utc_now()
    Events.delete_old(config, now)

    if oban && Config.module?(config, :campaigns),
      do: insert!(oban, :campaigns_cleanup, DateTime.add(now, 1, :day))

    :ok
  end

  # What lost its job, then the next hour's sweep.
  def perform(%Config{oban: oban} = config, %{"job" => "campaigns_sweep"}, _attempt) do
    now = DateTime.utc_now()

    if oban && Config.module?(config, :campaigns) do
      sweep_campaigns(config, now)
      insert!(oban, :campaigns_sweep, DateTime.add(now, @sweep_every))
    end

    :ok
  end

  def perform(config, args, _attempt), do: perform(config, args)

  @doc false
  @spec perform(Config.t(), map()) :: :ok | {:error, term()} | {:cancel, term()}
  def perform(config, %{"job" => job} = args)
      when job in ["enrollment", "broadcast", "letter", "campaigns_cleanup", "campaigns_sweep"],
      do: perform(config, args, %{})

  def perform(config, %{"job" => "email", "entry_id" => entry, "subscriber_id" => subscriber}),
    do: Subscribers.email(config, entry, subscriber)

  def perform(config, %{
        "job" => "digest_email",
        "entry_ids" => entries,
        "subscriber_id" => subscriber
      }),
      do: Subscribers.email_digest(config, entries, subscriber)

  # An entry's time came: what is due is announced, each once. A time
  # moved later than this job has its own job then.
  def perform(config, %{"job" => "announce", "entry_id" => entry_id}) do
    Scheduler.announce_due(config)

    case config.repo.get(Entry, entry_id, prefix: config.prefix) do
      %Entry{} = entry ->
        if unannounced?(entry) and DateTime.after?(entry.published_at, DateTime.utc_now()),
          do: announce_at(config.oban, entry.id, entry.published_at)

      nil ->
        :ok
    end

    :ok
  end

  def perform(config, %{"job" => "schedules"}) do
    now = DateTime.utc_now()
    Scheduler.run_due(config, now)
    schedule_next(config, now)
  end

  def perform(_config, %{"job" => "ingest"}) do
    Tayori.Inbox.ingest()
    :ok
  end

  def perform(_config, %{"job" => "digest"}) do
    case Tayori.Digest.scheduled() do
      {:ok, _entry} -> :ok
      {:error, :nothing} -> :ok
      {:error, changeset} -> {:cancel, inspect(changeset.errors)}
    end
  end

  def perform(config, %{"job" => "webhook", "entry_id" => entry, "hook_id" => hook}) do
    case Webhooks.deliver(config, entry, hook) do
      :ok ->
        :ok

      {:error, reason} ->
        if Webhooks.retry?(reason), do: {:error, reason}, else: {:cancel, reason}
    end
  end

  def perform(config, %{"job" => "notify", "entry_id" => entry_id}) do
    case Tayori.Entries.get(entry_id) do
      nil -> :ok
      entry -> config.notifier.published(entry)
    end

    :ok
  end

  # -- without Oban ------------------------------------------------------------

  defp run_in_tasks(config, jobs) do
    {emails, others} = Enum.split_with(jobs, &email?/1)

    # The emails one after the other, so that a mailer is not flooded.
    if emails != [] do
      start(fn -> Enum.each(emails, &try_once(config, &1)) end)
    end

    Enum.each(others, fn job -> start(fn -> try_again(config, job, 1) end) end)
    :ok
  end

  defp email?({:email, _, _}), do: true
  defp email?({:digest_email, _, _}), do: true
  defp email?({:letter, _}), do: true
  defp email?(_job), do: false

  defp start(fun), do: Task.Supervisor.start_child(Tayori.TaskSupervisor, fun)

  defp try_once(config, job) do
    case perform(config, args(job)) do
      :ok -> :ok
      {_error, reason} -> failed(job, reason)
    end
  end

  defp try_again(config, job, attempt) do
    case perform(config, args(job)) do
      :ok ->
        :ok

      {:error, _reason} when attempt < 3 ->
        Process.sleep(attempt * 2_000)
        try_again(config, job, attempt + 1)

      {_error, reason} ->
        failed(job, reason)
    end
  end

  defp failed({:email, _entry_id, subscriber_id}, reason),
    do: Logger.warning("Tayori could not email #{subscriber_id}: #{inspect(reason)}")

  defp failed({:digest_email, _entry_ids, subscriber_id}, reason),
    do: Logger.warning("Tayori could not email #{subscriber_id}: #{inspect(reason)}")

  defp failed({:letter, delivery_id}, reason),
    do: Logger.warning("Tayori could not send the letter #{delivery_id}: #{inspect(reason)}")

  defp failed(:digest, reason),
    do: Logger.warning("Tayori could not make the digest: #{inspect(reason)}")

  defp failed({:webhook, _entry_id, hook_id}, reason),
    do: Logger.warning("Tayori could not tell #{Webhooks.name(hook_id)}: #{inspect(reason)}")

  # -- the queue ---------------------------------------------------------------

  # A job in a queue the app does not run waits for ever: Tayori says so,
  # once a node, rather than lose the emails without a word.
  defp check_queue(%{name: name, queue: queue}) do
    key = {__MODULE__, :checked, name, queue}

    unless :persistent_term.get(key, false) do
      oban = Oban.config(name)

      if oban.testing == :disabled and not Keyword.has_key?(oban.queues, queue) do
        Logger.error(
          "Tayori gives its jobs to the #{inspect(queue)} queue of #{inspect(name)}, " <>
            "which does not run it: add it to the :queues of your Oban config, " <>
            "or give Tayori another (oban: [name: #{inspect(name)}, queue: ...])"
        )
      end

      :persistent_term.put(key, true)
    end
  end
end
