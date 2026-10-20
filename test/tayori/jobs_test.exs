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

  defp enqueued(TayoriTest.SQLiteRepo = repo) do
    Oban.Testing.all_enqueued(repo: repo, engine: Oban.Engines.Lite, worker: Tayori.Worker)
  end

  defp enqueued(repo), do: Oban.Testing.all_enqueued(repo: repo, worker: Tayori.Worker)

  defp oban_of(TayoriTest.SQLiteRepo), do: TayoriTest.SQLiteOban
  defp oban_of(TayoriTest.PostgresRepo), do: TayoriTest.PostgresOban
end
