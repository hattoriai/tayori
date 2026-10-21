defmodule Tayori.CadenceTest do
  use TayoriTest.DataCase

  import Swoosh.TestAssertions

  alias Tayori.{Digest, Inbox, Mail, Scheduler, Settings, Subscribers}

  for_each_repo do
    test "its first time is after the scheduler first looks; then it runs once, in a job",
         %{config: config, repo: repo} do
      config = put_config(config, oban: oban_of(repo), digest: [every: {:weekly, :tuesday}])
      {:ok, _} = Inbox.add(%{ref: "a", title: "Exports"})

      # The first look begins the schedule: the time that passed is not missed.
      Scheduler.run_due(config, ~U[2026-10-20 12:00:00Z])
      assert enqueued(repo) == []
      assert Settings.get("digest")["since"] == "2026-10-20T12:00:00Z"
      refute Digest.due?(config, ~U[2026-10-27 08:59:00Z])

      # A week later, at the time.
      assert Digest.due?(config, ~U[2026-10-27 09:00:30Z])
      Scheduler.run_due(config, ~U[2026-10-27 09:00:30Z])
      Scheduler.run_due(config, ~U[2026-10-27 09:01:30Z])

      assert [%{args: %{"job" => "digest"}} = job] = enqueued(repo)
      assert Digest.status().last_run_at == ~U[2026-10-27 09:00:30Z]
      assert Digest.status().next_run_at == ~U[2026-11-03 09:00:00Z]

      assert :ok = Tayori.Worker.perform(job)
      assert [%{state: "drafted"}] = Inbox.list()
    end

    test "fewer changes than the minimum: nothing, and they wait for the next time", %{
      config: config,
      repo: repo
    } do
      config = put_config(config, oban: oban_of(repo), digest: [every: {:days, 1}, minimum: 2])
      :ok = Digest.begin("digest", ~U[2026-10-19 10:00:00Z])
      {:ok, _} = Inbox.add(%{ref: "a", title: "Exports"})

      Scheduler.run_due(config, ~U[2026-10-20 09:00:00Z])
      assert [job] = enqueued(repo)
      assert :ok = Tayori.Worker.perform(job)
      assert [%{state: "new"}] = Inbox.list()

      # Recorded all the same: the next is tomorrow.
      refute Digest.due?(config, ~U[2026-10-20 09:01:00Z])
      assert Digest.status().next_run_at == ~U[2026-10-21 09:00:00Z]
    end

    test "without Oban, it runs in a task", %{config: config} do
      config = put_config(config, digest: [every: :monthly, publish: :publish])
      :ok = Digest.begin("digest", ~U[2026-10-02 10:00:00Z])
      {:ok, _} = Inbox.add(%{ref: "a", title: "Exports"})

      Tayori.subscribe()
      Scheduler.run_due(config, ~U[2026-11-01 09:00:00Z])

      assert_receive {Tayori, :changed, id}, 2_000
      assert eventually(fn -> Inbox.list() |> hd() |> Map.get(:entry_id) == id end)
    end

    test "manual and ingest schedules are left alone", %{config: config, repo: repo} do
      config = put_config(config, oban: oban_of(repo))
      {:ok, _} = Inbox.add(%{ref: "a", title: "Exports"})

      Scheduler.run_due(config, ~U[2026-10-20 09:00:00Z])
      assert Settings.get("digest") == %{}
      assert enqueued(repo) == []
    end

    test "new changes start a digest, which waits as one job", %{config: config, repo: repo} do
      put_config(config, oban: oban_of(repo), digest: [every: :ingest])

      assert :ok = Digest.after_ingest(0)
      assert enqueued(repo) == []

      {:ok, _} = Inbox.add(%{ref: "a", title: "Exports"})
      assert :ok = Digest.after_ingest(1)
      assert :ok = Digest.after_ingest(2)
      assert [job] = enqueued(repo)
      assert %DateTime{} = Digest.status().last_run_at

      assert :ok = Tayori.Worker.perform(job)
      assert [%{state: "drafted"}] = Inbox.list()
    end

    @tag :tmp_dir
    test "ingest starts it when a source brought something new",
         %{config: config, repo: repo, tmp_dir: dir} do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "exports.md"), "Exports in two clicks.")

      put_config(config,
        oban: oban_of(repo),
        digest: [every: :ingest],
        inbox: [sources: [{Tayori.Sources.Fragments, path: dir}]]
      )

      Inbox.ingest()
      assert [%{args: %{"job" => "digest"}} = job] = enqueued(repo)
      :ok = Tayori.Worker.perform(job)
      assert [%{state: "drafted"}] = Inbox.list()
      last = Digest.status().last_run_at

      # Nothing new the second time.
      Inbox.ingest()
      assert Digest.status().last_run_at == last
    end

    test "the other schedules do not run on ingest", %{config: config, repo: repo} do
      put_config(config, oban: oban_of(repo), digest: [every: {:weekly, :monday}])
      assert :ok = Digest.after_ingest(3)
      assert enqueued(repo) == []
    end

    test "an entry to email waits for the period's email, which lists them", %{config: config} do
      config = subscriptions(config, emails: [every: {:weekly, :monday}])
      ada = subscriber!("ada@example.com")

      :ok = Digest.begin("email_digest", minutes(-60 * 24 * 8))

      first =
        entry!("Exports", %{
          email: true,
          published_at: minutes(-10),
          translations: [
            %{
              locale: "en",
              title: "Exports",
              summary: "In two clicks.",
              body: Kotoba.Content.from_markdown("Zip it.")
            }
          ]
        })

      second = entry!("Timeline", %{email: true, published_at: minutes(-5)})
      _quiet = entry!("Quiet", %{published_at: minutes(-5)})
      _pro = entry!("Pro", %{email: true, segments: ["plan:pro"], published_at: minutes(-5)})

      # Announced: not emailed on its own.
      Scheduler.announce_due(config)
      refute_receive {:email, _}, 100
      assert Tayori.Entries.get!(first.id).emailed_at == nil

      Scheduler.run_due(config)

      assert_receive {:email, email}, 1_000
      assert email.to == [{"", ada.email}]
      assert email.subject == "What's new: Timeline, Exports"
      assert email.text_body =~ ~r/Timeline.*Exports\nIn two clicks\./s
      assert email.text_body =~ "https://atelier.test/changelog/exports?ref=email"
      refute email.text_body =~ "Quiet"
      refute email.text_body =~ "Pro"

      assert %DateTime{} = Tayori.Entries.get!(first.id).emailed_at
      assert %DateTime{} = Tayori.Entries.get!(second.id).emailed_at

      # Sent once.
      Scheduler.run_due(config, DateTime.add(DateTime.utc_now(), 8, :day))
      refute_receive {:email, _}, 100
    end

    test "a period of one entry sends that entry; one of none, nothing", %{config: config} do
      config = subscriptions(config, emails: [every: {:days, 1}])
      subscriber!("ada@example.com")
      :ok = Digest.begin("email_digest", minutes(-60 * 24 * 2))

      Scheduler.run_due(config)
      refute_receive {:email, _}, 100

      entry!("Exports", %{email: true, published_at: minutes(-1)})
      Scheduler.announce_due(config)
      Scheduler.run_due(config, DateTime.add(DateTime.utc_now(), 2, :day))

      assert_receive {:email, %{subject: "Exports"}}, 1_000
    end

    test "with Oban, an email of a period to each subscriber is a job",
         %{config: config, repo: repo} do
      config = subscriptions(config, oban: oban_of(repo), emails: [every: :monthly])
      ada = subscriber!("ada@example.com")
      grace = subscriber!("grace@example.com")
      :ok = Digest.begin("email_digest", minutes(-60 * 24 * 40))

      a = entry!("Exports", %{email: true, published_at: minutes(-10)})
      b = entry!("Timeline", %{email: true, published_at: minutes(-5)})
      Scheduler.announce_due(config)
      Scheduler.run_due(config)

      jobs = enqueued(repo)
      assert length(jobs) == 2
      assert Enum.all?(jobs, &(&1.args["entry_ids"] == [b.id, a.id]))

      assert Enum.sort(Enum.map(jobs, & &1.args["subscriber_id"])) ==
               Enum.sort([ada.id, grace.id])

      :ok = Subscribers.unsubscribe(grace.token)
      for job <- jobs, do: assert(:ok = Tayori.Worker.perform(job))

      assert_received {:email, %{to: [{"", address}]}}
      assert address == ada.email
      refute_received {:email, _}
    end

    test "the email: titles, summaries and links, in the subscriber's language", %{
      config: config
    } do
      config = subscriptions(config)

      entry =
        entry!("Exports", %{
          published_at: minutes(-1),
          translations: [
            %{
              locale: "en",
              title: "Exports",
              summary: "In two clicks.",
              body: Kotoba.Content.from_markdown("Zip it.")
            },
            %{
              locale: "pt-PT",
              title: "Exportações <rápidas>",
              body: Kotoba.Content.from_markdown("Um *zip* do projeto.")
            }
          ]
        })

      other = entry!("Timeline", %{published_at: minutes(-1)})
      subscriber = %Subscribers{email: "ada@example.com", locale: "pt-PT", token: "tok"}
      email = Mail.digest(config, [entry, other], subscriber)

      unsubscribe = "https://atelier.test/changelog/subscription/unsubscribe/tok"
      assert email.from == {"Atelier", "news@atelier.test"}
      assert email.subject == "Novidades: Exportações <rápidas>, Timeline"
      assert email.headers["List-Unsubscribe"] == "<#{unsubscribe}>"
      assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"

      assert email.text_body =~
               "Exportações <rápidas>\nUm zip do projeto.\nLer mais: https://atelier.test/changelog/exports?ref=email"

      assert email.text_body =~ "Cancelar a subscrição: " <> unsubscribe
      assert email.html_body =~ "Exportações &lt;rápidas&gt;"

      assert email.html_body =~
               ~s(href="https://atelier.test/changelog/#{entry.slug}?ref=email")

      assert email.html_body =~ ~s(href="https://atelier.test/changelog?ref=email")
      assert email.html_body =~ ~s(href="#{unsubscribe}")

      long = for n <- 1..12, do: %{other | slug: "t#{n}"}
      assert String.length(Mail.digest(config, long, subscriber).subject) == 110
    end
  end

  test "the next email of a period" do
    config =
      Tayori.Config.new(
        repo: TayoriTest.SQLiteRepo,
        pubsub: TayoriTest.PubSub,
        emails: [every: {:weekly, :friday}, at: ~T[16:00:00]]
      )

    assert Digest.next_run(config.emails, ~U[2026-10-20 12:00:00Z], ~U[2026-10-20 12:00:00Z]) ==
             ~U[2026-10-23 16:00:00Z]
  end

  defp subscriptions(config, opts \\ []) do
    put_config(
      config,
      [
        features: [:subscriptions],
        mailer: TayoriTest.Mailer,
        email_from: {"Atelier", "news@atelier.test"},
        page_url: "https://atelier.test/changelog"
      ] ++ opts
    )
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

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end

  # The emails: not the entries' announcements, nor the schedules' next run.
  defp enqueued(repo), do: Enum.reject(jobs(repo), &(&1.args["job"] in ["announce", "schedules"]))

  defp jobs(TayoriTest.SQLiteRepo = repo) do
    Oban.Testing.all_enqueued(repo: repo, engine: Oban.Engines.Lite, worker: Tayori.Worker)
  end

  defp jobs(repo), do: Oban.Testing.all_enqueued(repo: repo, worker: Tayori.Worker)

  defp oban_of(TayoriTest.SQLiteRepo), do: %{name: TayoriTest.SQLiteOban, queue: :default}
  defp oban_of(TayoriTest.PostgresRepo), do: %{name: TayoriTest.PostgresOban, queue: :default}
end
