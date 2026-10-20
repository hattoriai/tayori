defmodule Tayori.Scheduler do
  @moduledoc false
  # Announces each entry once when it is published, at once or at its
  # scheduled time: it tells the PubSub, and the app's notifier.
  #
  # Every node runs one. The announcement is claimed in the database (the
  # row whose announced_at is still nil), so that one node announces an
  # entry, whatever the number of nodes. It wakes at the next scheduled
  # time, when an entry changes on this node, and every minute, for the
  # entries changed on another node.

  use GenServer

  import Ecto.Query

  alias Tayori.{Config, Entry}

  require Logger

  @interval :timer.minutes(1)

  def start_link(%Config{} = config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc "Looks for entries to announce now."
  def wake do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> send(pid, :tick)
    end

    :ok
  end

  @doc false
  # The tests run the announcements in their own process.
  def announce_due(%Config{} = config, now \\ DateTime.utc_now()) do
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

  @impl GenServer
  def init(config) do
    send(self(), :tick)
    {:ok, %{config: config, timer: nil}}
  end

  @impl GenServer
  def handle_info(:tick, %{config: config} = state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    try do
      announce_due(config)
    rescue
      error -> Logger.error("Tayori could not announce the news: " <> Exception.message(error))
    end

    {:noreply, %{state | timer: Process.send_after(self(), :tick, next_tick(config))}}
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

    if config.notifier do
      Task.Supervisor.start_child(Tayori.TaskSupervisor, fn ->
        config.notifier.published(Tayori.Entries.get!(id))
      end)
    end
  end

  defp next_tick(config) do
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
