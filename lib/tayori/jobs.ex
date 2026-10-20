defmodule Tayori.Jobs do
  @moduledoc """
  What a publication sends, and how: the emails to the subscribers (the
  `:subscriptions` feature), the webhooks (the `:webhooks` feature) and
  the call to the app's `:notifier`.

  An entry is announced once, by one node of the cluster, when it is
  published or when its scheduled time comes (the entry is claimed in the
  database first). Its readers see it on time whatever happens next: what
  follows is only what it sends.

  ## With Oban

  When the app runs [Oban](https://hexdocs.pm/oban), Tayori gives it the
  work, as jobs of `Tayori.Worker`:

      {Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub, oban: Oban}

  Each email, each webhook and the notifier's call is a job of its own,
  retried with Oban's backoff, through deploys and crashes, and seen in
  Oban's dashboards. A webhook a place refuses for good (a 4xx) is
  cancelled, not retried. The jobs go to the `:default` queue, or the
  one given (`oban: [name: Oban, queue: :news]`), which must be one the
  app runs: Tayori logs an error when it is not.

  `mix tayori.install` sets `oban: Oban` when the app has Oban.

  ## Without Oban

  Tayori sends them from tasks in the node that announced the entry. A
  webhook is tried three times, a few seconds apart; an email once. A
  failure is logged. A node stopped while it sends (a deploy, a crash)
  loses what it had not sent yet: the entry is not sent twice, but some
  subscribers may not get it. For a changelog with subscribers or
  webhooks that matter, run Oban.
  """

  alias Tayori.{Config, Subscribers, Webhooks}

  require Logger

  # Oban is an optional dependency, used with the :oban option.
  @compile {:no_warn_undefined, [Oban, Tayori.Worker]}

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

  defp opts({:email, _, _}, oban), do: [queue: oban.queue, max_attempts: 5]
  defp opts({:webhook, _, _}, oban), do: [queue: oban.queue, max_attempts: 8]
  defp opts({:notify, _}, oban), do: [queue: oban.queue, max_attempts: 5]

  @doc false
  # Does one job, in an Oban worker or a task.
  @spec perform(Config.t(), map()) :: :ok | {:error, term()} | {:cancel, term()}
  def perform(config, %{"job" => "email", "entry_id" => entry, "subscriber_id" => subscriber}),
    do: Subscribers.email(config, entry, subscriber)

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
    {emails, others} = Enum.split_with(jobs, &match?({:email, _, _}, &1))

    # The emails one after the other, so that a mailer is not flooded.
    if emails != [] do
      start(fn -> Enum.each(emails, &try_once(config, &1)) end)
    end

    Enum.each(others, fn job -> start(fn -> try_again(config, job, 1) end) end)
    :ok
  end

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
