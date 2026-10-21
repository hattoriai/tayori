defmodule Tayori.Campaigns.JobsTest do
  use TayoriTest.DataCase

  import Ecto.Query, only: [where: 3]
  import Swoosh.TestAssertions

  alias Tayori.Campaigns
  alias Tayori.Campaigns.{Delivery, Event, Runner}

  defmodule DownMailer do
    @moduledoc "A mailer that cannot send."
    def deliver(_email), do: {:error, :down}
  end

  defp jobs(TayoriTest.SQLiteRepo = repo) do
    Oban.Testing.all_enqueued(repo: repo, engine: Oban.Engines.Lite, worker: Tayori.Worker)
  end

  defp jobs(repo), do: Oban.Testing.all_enqueued(repo: repo, worker: Tayori.Worker)

  defp jobs(repo, job), do: Enum.filter(jobs(repo), &(&1.args["job"] == job))

  defp oban_of(TayoriTest.SQLiteRepo), do: TayoriTest.SQLiteOban
  defp oban_of(TayoriTest.PostgresRepo), do: TayoriTest.PostgresOban

  defp perform(job, attempt \\ 1),
    do: Tayori.Worker.perform(%{job | attempt: attempt, max_attempts: job.max_attempts})

  defp close?(a, b), do: abs(DateTime.diff(a, b)) <= 1

  for_each_repo do
    setup :campaigns

    test "with Oban, a person of a sequence is a job at their next time, and each letter a job",
         %{config: config, repo: repo} do
      put_config(config, oban: [name: oban_of(repo), queue: :news])
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome"), step(2 * 1440, "Day two")])
      entered = DateTime.add(DateTime.utc_now(), -60)

      {:ok, enrollment} = Campaigns.enroll(campaign, person_id(ada), entered)
      assert [job] = jobs(repo, "enrollment")
      assert job.args == %{"job" => "enrollment", "id" => enrollment.id}
      assert job.queue == "news"
      assert close?(job.scheduled_at, entered)

      # Its time came: the letter is a job, and the person's job moves to
      # their next time.
      assert :ok = perform(job)
      refute_email_sent()

      assert [letter] = jobs(repo, "letter")
      assert letter.max_attempts == 5
      assert [%Delivery{id: id, status: "queued"}] = deliveries(campaign)
      assert letter.args == %{"job" => "letter", "delivery_id" => id}

      assert [moved] = jobs(repo, "enrollment")
      assert close?(moved.scheduled_at, DateTime.add(entered, 2, :day))

      assert :ok = perform(letter)
      assert_email_sent(subject: "Welcome")
      assert [%Delivery{status: "sent"}] = deliveries(campaign)

      # Its job before its time does nothing, and keeps one job.
      assert :ok = perform(moved)
      assert [_] = jobs(repo, "enrollment")
      assert length(jobs(repo, "letter")) == 1
    end

    test "with Oban, an event that enrolls gives the job in its transaction",
         %{config: config, repo: repo} do
      put_config(config, oban: oban_of(repo))
      ada = person!(name: "Ada")

      sequence!(%{"trigger" => %{"type" => "event", "event" => "signed_up"}}, [step(0, "Welcome")])

      :ok = Tayori.track(person_id(ada), "signed_up")
      assert [_] = jobs(repo, "enrollment")
    end

    test "with Oban, a broadcast is a job at its time, moved with it, then a job each letter",
         %{config: config, repo: repo} do
      put_config(config, oban: oban_of(repo))
      for name <- ["Ada", "Grace"], do: person!(name: name)
      broadcast = broadcast!("Spring")
      at = DateTime.add(DateTime.utc_now(), 3600)

      {:ok, scheduled} = Campaigns.schedule_broadcast(broadcast, at)
      assert [job] = jobs(repo, "broadcast")
      assert job.args == %{"job" => "broadcast", "id" => broadcast.id}
      assert close?(job.scheduled_at, at)

      # Before its time, nothing.
      assert :ok = perform(job)
      assert %{status: "scheduled"} = Campaigns.get(broadcast.id)

      {:ok, _} = Campaigns.send_broadcast_now(scheduled)
      assert [job] = jobs(repo, "broadcast")
      assert close?(job.scheduled_at, DateTime.utc_now())

      assert :ok = perform(job)
      assert %{status: "sent"} = Campaigns.get(broadcast.id)
      letters = jobs(repo, "letter")
      assert length(letters) == 2

      for letter <- letters, do: assert(:ok = perform(letter))
      assert_email_sent(subject: "Spring")
      assert_email_sent(subject: "Spring")

      # The job again (a retry after a crash): no one gets two.
      repo.update_all(Tayori.Campaigns.Campaign, set: [status: "sending"])
      assert :ok = perform(job, 2)
      assert length(jobs(repo, "letter")) == 2
      assert %{status: "sent"} = Campaigns.get(broadcast.id)
    end

    test "with Oban, a letter that fails is tried again, and failed on its last attempt",
         %{config: config, repo: repo} do
      put_config(config, oban: oban_of(repo), mailer: DownMailer)
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), DateTime.add(DateTime.utc_now(), -60))

      [job] = jobs(repo, "enrollment")
      :ok = perform(job)
      [letter] = jobs(repo, "letter")

      assert {:error, :down} = perform(letter, 1)
      assert [%Delivery{status: "queued"}] = deliveries(campaign)
      assert {:error, :down} = perform(letter, 4)
      assert [%Delivery{status: "queued"}] = deliveries(campaign)
      assert {:error, :down} = perform(letter, 5)
      assert [%Delivery{status: "failed", reason: ":down"}] = deliveries(campaign)
    end

    test "with Oban, boot gives Oban the campaigns' work that may have no job",
         %{config: config, repo: repo} do
      # Written before Tayori ran with Oban: no job.
      ada = person!(name: "Ada")
      campaign = sequence!([step(60, "Welcome")])
      {:ok, enrollment} = Campaigns.enroll(campaign, person_id(ada))
      broadcast = broadcast!("Spring")
      {:ok, _} = Campaigns.schedule_broadcast(broadcast, DateTime.add(DateTime.utc_now(), 600))
      sending = broadcast!("Half sent")

      repo.update_all(where(Tayori.Campaigns.Campaign, [c], c.id == ^sending.id),
        set: [status: "sending"]
      )

      assert jobs(repo) == []

      config = put_config(config, oban: oban_of(repo))
      assert :ok = Tayori.Jobs.boot(config)
      assert :ok = Tayori.Jobs.boot(config)

      assert [%{args: %{"id" => id}}] = jobs(repo, "enrollment")
      assert id == enrollment.id

      assert jobs(repo, "broadcast") |> Enum.map(& &1.args["id"]) |> Enum.sort() ==
               Enum.sort([broadcast.id, sending.id])

      assert [_] = jobs(repo, "campaigns_cleanup")
    end

    test "with Oban, the events' cleanup is a job each day", %{config: config, repo: repo} do
      config = put_config(config, oban: oban_of(repo))
      now = DateTime.utc_now()
      Tayori.track("person:1", "old", at: DateTime.add(now, -401, :day))
      Tayori.track("person:1", "new", at: now)

      Tayori.Jobs.boot(config)
      [job] = jobs(repo, "campaigns_cleanup")
      # Running, as Oban has it while it performs it.
      repo.update_all(where(Oban.Job, [j], j.id == ^job.id), set: [state: "executing"])
      assert :ok = perform(job)

      assert repo.all(Event) |> Enum.map(& &1.name) == ["new"]
      assert [next] = jobs(repo, "campaigns_cleanup")
      assert close?(next.scheduled_at, DateTime.add(now, 1, :day))
    end

    test "without Oban, the letters go from a task after the write", %{repo: repo} do
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), DateTime.add(DateTime.utc_now(), -60))

      assert :ok = Runner.run_due(Tayori.Config.get(), DateTime.utc_now())
      assert_receive {:email, %{subject: "Welcome"}}, 1_000
      assert eventually(fn -> repo.one(Delivery).status == "sent" end)
    end

    test "without Oban, the scheduler's tick advances the campaigns", %{
      config: config,
      repo: repo
    } do
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), DateTime.add(DateTime.utc_now(), -60))

      start_supervised!({Tayori.Scheduler, config})
      assert eventually(fn -> match?(%{status: "sent"}, repo.one(Delivery)) end)
      assert %{state: "completed", reason: "finished"} = enrollment(campaign, ada)
    end

    test "without Oban, the events' cleanup is once a day", %{config: config, repo: repo} do
      :persistent_term.erase({Runner, :cleaned, repo, nil})
      day = ~U[2030-01-10 09:00:00Z]
      Tayori.track("person:1", "old", at: DateTime.add(day, -401, :day))

      assert :ok = Runner.daily_cleanup(config, day)
      assert repo.aggregate(Event, :count) == 0

      Tayori.track("person:1", "old", at: DateTime.add(day, -401, :day))
      assert :ok = Runner.daily_cleanup(config, DateTime.add(day, 3600))
      assert repo.aggregate(Event, :count) == 1

      assert :ok = Runner.daily_cleanup(config, DateTime.add(day, 1, :day))
      assert repo.aggregate(Event, :count) == 0
    end

    test "with the campaigns off, their jobs do nothing", %{config: config} do
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome")])

      {:ok, enrollment} =
        Campaigns.enroll(campaign, person_id(ada), DateTime.add(DateTime.utc_now(), -60))

      config = put_config(config, modules: [:changelog])

      assert :ok = Tayori.Jobs.perform(config, %{"job" => "enrollment", "id" => enrollment.id})
      assert :ok = Tayori.Jobs.perform(config, %{"job" => "broadcast", "id" => campaign.id})
      assert :ok = Runner.run_due(config, DateTime.utc_now())
      assert deliveries(campaign) == []
    end
  end

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end
end
