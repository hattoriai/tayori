defmodule Tayori.Scheduler do
  @moduledoc false
  # Announces each entry once when it is published, at once or at its
  # scheduled time: it tells the PubSub, and Tayori.Jobs sends the rest
  # (emails, webhooks, the app's notifier), as Oban jobs or from tasks.
  #
  # The GenServer runs only without Oban. With Oban, the same work is
  # jobs (Tayori.Jobs): an entry's announcement at its time, the schedules
  # at theirs, and nothing looks every minute. announce_due/2 and
  # run_due/2 are the work either way.
  #
  # One runs in the cluster, a PhoenixMountable.Singleton. The announcement
  # is also claimed in the database (the row whose announced_at is still
  # nil), so that an entry is announced once even while a node takes the
  # scheduler over from another. It wakes at the next scheduled time, when
  # an entry changes, and every minute.
  #
  # Each minute, it also starts the scheduled digest of the inbox
  # (Tayori.Digest) and the email of a period's entries (the :emails
  # config) when their time has come: the time of the run is kept in the
  # settings first, then the work goes to Tayori.Jobs.
  #
  # Without the changelog, it announces nothing and runs no schedule of
  # it. With the campaigns, it also advances the people of the sequences
  # whose time came, sends the broadcasts whose time came
  # (Tayori.Campaigns.Runner.run_due/3), and deletes the old events once
  # a day; Tayori.Campaigns wakes it after a write.
  #
  # A wake is cheap, as it comes after every write: a message to the
  # scheduler, found by a global name (a local lookup), and the ticks
  # that came while it ran are one run.

  use GenServer

  import Ecto.Query

  alias Tayori.Campaigns.Runner
  alias Tayori.{Config, Entry}

  require Logger

  @interval :timer.minutes(1)
  @wake {__MODULE__, :wake}

  def start_link(%Config{} = config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc "Looks for entries to announce now, on whichever node the scheduler runs."
  def wake do
    case :global.whereis_name(@wake) do
      pid when is_pid(pid) -> send(pid, :tick)
      :undefined -> :ok
    end

    :ok
  end

  @doc false
  # The tests run the announcements in their own process.
  def announce_due(config, now \\ DateTime.utc_now())

  def announce_due(%Config{} = config, now) do
    if Config.module?(config, :changelog), do: announce_all(config, now), else: []
  end

  defp announce_all(config, now) do
    due =
      config.repo.all(
        from(e in Entry,
          where: not is_nil(e.published_at) and e.published_at <= ^now and is_nil(e.announced_at),
          select: e.id
        ),
        prefix: config.prefix
      )

    for id <- due, claim(config, id, now) do
      announce(config, id)
    end
  end

  @doc false
  # Starts what a schedule says is due: the digest of the inbox (the
  # :digest config) and the email of a period's entries (the :emails
  # config). The tests run it in their own process.
  def run_due(config, now \\ DateTime.utc_now())

  def run_due(%Config{} = config, now) do
    if Config.module?(config, :changelog) do
      Tayori.Digest.tick(config, now)
      Tayori.Subscribers.tick(config, now)
    end

    :ok
  end

  @impl GenServer
  def init(config) do
    :global.re_register_name(@wake, self(), &:global.random_notify_name/3)
    send(self(), :tick)

    # A deploy's new code may bring new changes (Tayori.Inbox).
    if Config.module?(config, :changelog) and config.inbox.ingest_on_start and
         config.inbox.sources != [] do
      Task.Supervisor.start_child(Tayori.TaskSupervisor, &Tayori.Inbox.ingest/0)
    end

    {:ok, %{config: config, timer: nil}}
  end

  @impl GenServer
  def handle_info(:tick, %{config: config} = state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    drain_ticks()

    try do
      announce_due(config)
    rescue
      error -> Logger.error("Tayori could not announce the news: " <> Exception.message(error))
    end

    try do
      run_due(config)
    rescue
      error -> Logger.error("Tayori could not run its schedules: " <> Exception.message(error))
    end

    if Config.module?(config, :campaigns) do
      try do
        now = DateTime.utc_now()
        Runner.run_due(config, now)
        Runner.daily_cleanup(config, now)
      rescue
        error ->
          Logger.error("Tayori could not run its campaigns: " <> Exception.message(error))
      end
    end

    {:noreply, %{state | timer: Process.send_after(self(), :tick, next_tick(config))}}
  end

  # Anything else (a message of a task it started) is nothing to it.
  def handle_info(_message, state), do: {:noreply, state}

  # The wakes that came meanwhile: this run is theirs.
  defp drain_ticks do
    receive do
      :tick -> drain_ticks()
    after
      0 -> :ok
    end
  end

  defp claim(config, id, now) do
    {count, _} =
      config.repo.update_all(
        from(e in Entry, where: e.id == ^id and is_nil(e.announced_at)),
        [set: [announced_at: now]],
        prefix: config.prefix
      )

    count == 1
  end

  defp announce(config, id) do
    Tayori.broadcast({Tayori, :published, id})
    Tayori.Jobs.published(config, id)
  end

  # The next time there is work: an entry's publication, a campaign's
  # next time, else a minute from now.
  defp next_tick(config) do
    Enum.min([
      if(Config.module?(config, :changelog), do: next_announcement(config), else: @interval),
      if(Config.module?(config, :campaigns), do: next_campaign(config), else: @interval)
    ])
  end

  defp next_campaign(config) do
    case Runner.next_due(config) do
      nil -> @interval
      at -> at |> DateTime.diff(DateTime.utc_now(), :millisecond) |> max(0) |> min(@interval)
    end
  rescue
    _ -> @interval
  end

  defp next_announcement(config) do
    now = DateTime.utc_now()

    next =
      config.repo.one(
        from(e in Entry,
          where: e.published_at > ^now and is_nil(e.announced_at),
          select: min(e.published_at)
        ),
        prefix: config.prefix
      )

    case next do
      nil -> @interval
      at -> at |> to_datetime() |> DateTime.diff(now, :millisecond) |> max(0) |> min(@interval)
    end
  rescue
    _ -> @interval
  end

  defp to_datetime(%DateTime{} = at), do: at
  defp to_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp to_datetime(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _} -> at
      _ -> text |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
    end
  end
end
