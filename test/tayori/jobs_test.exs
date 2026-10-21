defmodule Tayori.JobsTest do
  use TayoriTest.DataCase

  import Swoosh.TestAssertions

  alias Tayori.{Scheduler, Subscribers}

  defmodule Notifier do
    @behaviour Tayori.Notifier
    @impl true
    def published(entry) do
      send(:persistent_term.get(:tayori_test_notified), {:notified, entry.id})
    end
  end

  setup do
    :persistent_term.put(:tayori_test_notified, self())
    :ok
  end

  for_each_repo do
    test "without Oban, a publication emails the subscribers and calls the notifier",
         %{config: config} do
      config = subscriptions(config)
      reader = subscriber!("ada@example.com")

      entry = entry!("Timeline", %{email: true, published_at: minutes(-1)})
      Scheduler.announce_due(config)

      # Sent from a task.
      assert_receive {:email, %{to: [{"", address}]}}, 1_000
      assert address == reader.email
      assert_receive {:notified, id} when id == entry.id, 1_000

      # Announced once: the claim keeps a second run from sending again.
      Scheduler.announce_due(config)
      refute_receive {:email, _}, 100
    end

    test "with Oban, each email and the notifier's call is a job of Tayori.Worker",
         %{config: config, repo: repo} do
      oban = oban_of(repo)
      config = subscriptions(config, oban: [name: oban, queue: :news])
      ada = subscriber!("ada@example.com")
      grace = subscriber!("grace@example.com")

      entry = entry!("Timeline", %{email: true, published_at: minutes(-1)})
      Scheduler.announce_due(config)

      # Nothing is sent before Oban runs the jobs.
      refute_email_sent()
      refute_received {:notified, _}

      jobs = enqueued(repo)
      assert length(jobs) == 3
      assert Enum.all?(jobs, &(&1.queue == "news"))

      assert jobs |> Enum.map(& &1.args["job"]) |> Enum.sort() ==
               ["email", "email", "notify"]

      for job <- jobs, do: assert(:ok = Tayori.Worker.perform(job))

      assert_received {:email, first}
      assert_received {:email, second}
      assert Enum.sort(first.to ++ second.to) == [{"", ada.email}, {"", grace.email}]
      assert_receive {:notified, id} when id == entry.id
    end

    test "with Oban, an email to someone who unsubscribed since is nothing to send",
         %{config: config, repo: repo} do
      oban = oban_of(repo)
      config = subscriptions(config, oban: oban)
      reader = subscriber!("ada@example.com")

      entry!("Timeline", %{email: true, published_at: minutes(-1)})
      Scheduler.announce_due(config)
      :ok = Subscribers.unsubscribe(reader.token)

      for job <- enqueued(repo),
          do: assert(:ok = Tayori.Worker.perform(job))

      refute_email_sent()
    end

    test "an entry not to email makes no email job", %{config: config, repo: repo} do
      oban = oban_of(repo)
      subscriptions(config, oban: oban)
      subscriber!("ada@example.com")

      entry!("Quiet", %{published_at: minutes(-1)})
      Tayori.Test.announce!()

      assert [%{args: %{"job" => "notify"}}] =
               enqueued(repo)
    end

    test "with Oban, an entry's announcement is a job at its time, moved with it",
         %{config: config, repo: repo} do
      config = subscriptions(config, oban: oban_of(repo))
      at = DateTime.add(DateTime.utc_now(), 3600)

      entry = entry!("Later", %{published_at: at})
      assert [job] = jobs(repo, "announce")
      assert job.args["entry_id"] == entry.id
      assert_in_delta DateTime.to_unix(job.scheduled_at), DateTime.to_unix(at), 1

      later = DateTime.add(at, 3600)
      {:ok, entry} = Tayori.Entries.publish(entry, later)
      assert [job] = jobs(repo, "announce")
      assert_in_delta DateTime.to_unix(job.scheduled_at), DateTime.to_unix(later), 1

      # A draft again: its job finds nothing to announce.
      {:ok, _entry} = Tayori.Entries.unpublish(entry)
      assert :ok = Tayori.Jobs.perform(config, job.args)
      refute_received {:notified, _}
      assert enqueued(repo) == []
    end

    test "with Oban, the announcement's job announces the entry once",
         %{config: config, repo: repo} do
      config = subscriptions(config, oban: oban_of(repo))
      entry = entry!("Now", %{published_at: minutes(-1)})

      assert [job] = jobs(repo, "announce")
      assert :ok = Tayori.Jobs.perform(config, job.args)
      assert [%{args: %{"job" => "notify", "entry_id" => id}}] = enqueued(repo)
      assert id == entry.id

      assert :ok = Tayori.Jobs.perform(config, job.args)
      assert length(enqueued(repo)) == 1
    end

    test "with Oban, boot gives Oban the announcements that have no job, and the schedules",
         %{config: config, repo: repo} do
      # Written before Tayori ran with Oban: no job.
      subscriptions(config)
      entry = entry!("Waiting", %{published_at: DateTime.add(DateTime.utc_now(), 600)})
      assert jobs(repo) == []

      config =
        subscriptions(config,
          oban: oban_of(repo),
          digest: [every: {:weekly, :monday}, at: ~T[09:00:00]]
        )

      assert :ok = Tayori.Jobs.boot(config)
      assert [%{args: %{"entry_id" => id}}] = jobs(repo, "announce")
      assert id == entry.id

      # Again, as another node of the cluster: the same jobs.
      assert :ok = Tayori.Jobs.boot(config)
      assert length(jobs(repo, "announce")) == 1
      assert [schedules] = jobs(repo, "schedules")

      # The schedules' job runs what is due and gives Oban the next time:
      # a Monday at nine.
      assert :ok = Tayori.Jobs.perform(config, schedules.args)
      assert [next] = jobs(repo, "schedules")
      assert Date.day_of_week(next.scheduled_at) == 1
      assert Time.compare(DateTime.to_time(next.scheduled_at), ~T[09:00:00]) == :eq
    end

    test "without a schedule, boot gives Oban no schedules' job", %{config: config, repo: repo} do
      config = subscriptions(config, oban: oban_of(repo))
      assert :ok = Tayori.Jobs.boot(config)
      assert jobs(repo, "schedules") == []
    end
  end

  test "the :oban option names an instance and a queue" do
    base = [repo: TayoriTest.SQLiteRepo, pubsub: TayoriTest.PubSub]

    assert Tayori.Config.new(base).oban == nil
    assert Tayori.Config.new(base ++ [oban: Oban]).oban == %{name: Oban, queue: :default}

    assert Tayori.Config.new(base ++ [oban: [name: MyApp.Oban, queue: :news]]).oban ==
             %{name: MyApp.Oban, queue: :news}

    assert_raise ArgumentError, ~r/:oban must be/, fn -> Tayori.Config.new(base ++ [oban: 1]) end
  end

  test "a webhook a place refuses for good is not tried again" do
    assert Tayori.Webhooks.retry?(:timeout)
    assert Tayori.Webhooks.retry?({:status, 500})
    assert Tayori.Webhooks.retry?({:status, 429})
    refute Tayori.Webhooks.retry?({:status, 404})
    refute Tayori.Webhooks.retry?({:status, 410})
  end

  defp subscriptions(config, opts \\ []) do
    config =
      Tayori.Config.new(
        [
          repo: config.repo,
          pubsub: config.pubsub,
          locales: config.locales,
          secret_key_base: config.secret_key_base,
          features: [:subscriptions],
          mailer: TayoriTest.Mailer,
          email_from: {"Atelier", "news@atelier.test"},
          page_url: "https://atelier.test/changelog",
          notifier: Notifier
        ] ++ opts
      )

    Tayori.Config.put(config)
    config
  end

  # A confirmed subscriber; the confirmation email is not the test's.
  defp subscriber!(email) do
    :ok = Subscribers.subscribe(email)
    assert_email_sent(to: [{"", email}])
    config = Tayori.Config.get()
    subscriber = config.repo.get_by!(Subscribers, [email: email], prefix: config.prefix)
    {:ok, subscriber} = Subscribers.confirm(subscriber.token)
    subscriber
  end

  # What a publication sends: the jobs but the announcements and the
  # schedules, which jobs/1 gives.
  defp enqueued(repo), do: Enum.reject(jobs(repo), &(&1.args["job"] in ["announce", "schedules"]))

  defp jobs(TayoriTest.SQLiteRepo = repo) do
    Oban.Testing.all_enqueued(repo: repo, engine: Oban.Engines.Lite, worker: Tayori.Worker)
  end

  defp jobs(repo), do: Oban.Testing.all_enqueued(repo: repo, worker: Tayori.Worker)

  defp jobs(repo, job), do: Enum.filter(jobs(repo), &(&1.args["job"] == job))

  defp oban_of(TayoriTest.SQLiteRepo), do: TayoriTest.SQLiteOban
  defp oban_of(TayoriTest.PostgresRepo), do: TayoriTest.PostgresOban
end
