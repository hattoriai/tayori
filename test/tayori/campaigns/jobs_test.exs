defmodule Tayori.Campaigns.JobsTest do
  use TayoriTest.DataCase

  import Ecto.Query, only: [where: 3]
  import Swoosh.TestAssertions

  alias Tayori.Campaigns
  alias Tayori.Campaigns.{Campaign, Delivery, Enrollment, Event, Runner}

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

  # People of a paused sequence, looked at while it was paused: no next
  # time.
  defp waiting(repo, campaign, n) do
    stamp = DateTime.utc_now()

    for chunk <- Enum.chunk_every(1..n, 1000) do
      rows =
        for i <- chunk do
          %{
            id: Ecto.UUID.generate(),
            campaign_id: campaign.id,
            person: "person:#{i}",
            state: "active",
            entered_at: stamp,
            cursor: -1,
            inserted_at: stamp,
            updated_at: stamp
          }
        end

      repo.insert_all(Enrollment, rows)
    end
  end

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

    test "with Oban, boot gives one sweep, which gives a job to what lost its own",
         %{config: config, repo: repo} do
      now = DateTime.utc_now()
      ada = person!(name: "Ada")
      bob = person!(name: "Bob")
      sequence = sequence!([step(60, "Welcome")])

      # Written before Tayori ran with Oban: no job. Ada's time is to come,
      # Bob's passed an hour ago.
      {:ok, _} = Campaigns.enroll(sequence, person_id(ada), now)
      {:ok, late} = Campaigns.enroll(sequence, person_id(bob), DateTime.add(now, -2, :hour))

      {:ok, soon} = Campaigns.schedule_broadcast(broadcast!("Soon"), DateTime.add(now, 600))
      {:ok, missed} = Campaigns.schedule_broadcast(broadcast!("Missed"), DateTime.add(now, -600))
      stopped = broadcast!("Stopped")
      going = broadcast!("Going")
      at = fn minutes -> DateTime.add(now, minutes * 60) end

      repo.update_all(where(Campaign, [c], c.id == ^stopped.id),
        set: [status: "sending", updated_at: at.(-10)]
      )

      repo.update_all(where(Campaign, [c], c.id == ^going.id),
        set: [status: "sending", updated_at: at.(-1)]
      )

      [welcome] = sequence.steps
      paused = sequence!(%{"name" => "Paused"}, [step(0, "Hi")])
      {:ok, _} = Campaigns.pause(paused)

      letter = fn campaign, step, person, minutes ->
        repo.insert!(%Delivery{
          campaign_id: campaign.id,
          step_id: step.id,
          person: person,
          status: "queued",
          updated_at: at.(minutes)
        })
      end

      lost = letter.(sequence, welcome, "person:1", -20)
      letter.(sequence, welcome, "person:2", -1)
      letter.(paused, hd(paused.steps), "person:3", -20)

      assert jobs(repo) == []
      config = put_config(config, oban: oban_of(repo))
      assert :ok = Tayori.Jobs.boot(config)
      assert :ok = Tayori.Jobs.boot(config)

      # One sweep and one cleanup for the cluster, and nothing else.
      assert [sweep] = jobs(repo, "campaigns_sweep")
      assert [_] = jobs(repo, "campaigns_cleanup")
      assert length(jobs(repo)) == 2

      repo.update_all(where(Oban.Job, [j], j.id == ^sweep.id), set: [state: "executing"])
      assert :ok = perform(sweep)

      assert [%{args: %{"id" => id}}] = jobs(repo, "enrollment")
      assert id == late.id

      assert jobs(repo, "broadcast") |> Enum.map(& &1.args["id"]) |> Enum.sort() ==
               Enum.sort([missed.id, stopped.id])

      assert [%{args: %{"delivery_id" => delivery_id}}] = jobs(repo, "letter")
      assert delivery_id == lost.id
      assert soon.id not in Enum.map(jobs(repo, "broadcast"), & &1.args["id"])

      # The next sweep, in an hour.
      assert [next] = jobs(repo, "campaigns_sweep") |> Enum.filter(&(&1.state == "scheduled"))
      assert close?(next.scheduled_at, DateTime.add(now, 3600))
    end

    test "with Oban, a broadcast job that raises half way is tried again, and gives no one two",
         %{config: config, repo: repo} do
      put_config(config, oban: oban_of(repo))
      for name <- ["Ada", "Bob", "Boom", "Cleo"], do: person!(name: name)

      put_config(Tayori.Config.get(),
        campaigns: Keyword.put(campaigns_config()[:campaigns], :audience, TayoriTest.BoomAudience)
      )

      {:ok, _} = Campaigns.send_broadcast_now(broadcast!("Spring"))
      [job] = jobs(repo, "broadcast")

      Process.put(:boom, true)
      assert_raise RuntimeError, fn -> Tayori.Jobs.perform(Tayori.Config.get(), job.args, %{}) end
      assert %{status: "sending"} = Campaigns.get(job.args["id"])

      Process.delete(:boom)
      assert :ok = perform(job, 2)
      assert %{status: "sent"} = Campaigns.get(job.args["id"])
      assert length(jobs(repo, "letter")) == 4
      assert repo.aggregate(Delivery, :count) == 4
    end

    test "with Oban, a paused sequence's letters wait, and resume gives them their jobs",
         %{config: config, repo: repo} do
      put_config(config, oban: oban_of(repo))
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome"), step(1440, "Day two")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), DateTime.add(DateTime.utc_now(), -60))

      [enrollment_job] = jobs(repo, "enrollment")
      :ok = perform(enrollment_job)
      [letter] = jobs(repo, "letter")

      {:ok, paused} = Campaigns.pause(campaign)
      assert :ok = perform(letter)
      refute_email_sent()
      assert [%Delivery{status: "queued"}] = deliveries(campaign)
      repo.update_all(Oban.Job, set: [state: "completed"])

      {:ok, _} = Campaigns.resume(paused)
      assert [again] = jobs(repo, "letter")
      assert again.args == letter.args
      assert :ok = perform(again)
      assert_email_sent(subject: "Welcome")
    end

    # One update for those waiting, then their jobs a batch at a time.
    test "with Oban, resume gives a job to each person waiting, in batches",
         %{config: config, repo: repo} do
      put_config(config, oban: oban_of(repo))
      campaign = sequence!([step(0, "Welcome")])
      {:ok, paused} = Campaigns.pause(campaign)
      waiting(repo, campaign, 1001)

      {:ok, _} = Campaigns.resume(paused)
      assert length(jobs(repo, "enrollment")) == 1001
      assert repo.aggregate(where(Enrollment, [e], is_nil(e.next_at)), :count) == 0
    end

    # More than SQLite takes as parameters of one query.
    test "without Oban, resume takes up any number of people waiting", %{repo: repo} do
      campaign = sequence!([step(0, "Welcome")])
      {:ok, paused} = Campaigns.pause(campaign)
      waiting(repo, campaign, 33_000)

      {:ok, _} = Campaigns.resume(paused)
      assert repo.aggregate(where(Enrollment, [e], is_nil(e.next_at)), :count) == 0
      # Its letters' task, done.
      assert eventually(fn -> Task.Supervisor.children(Tayori.TaskSupervisor) == [] end)
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

    # A wake after each write: those that come while it runs are one run.
    test "without Oban, many wakes of the scheduler are one run", %{config: config} do
      pid = start_supervised!({Tayori.Scheduler, config})
      :sys.get_state(pid)

      :erlang.trace_pattern({Runner, :run_due, 3}, true, [:local])
      :erlang.trace(pid, true, [:call, {:tracer, self()}])
      on_exit(fn -> :erlang.trace_pattern({Runner, :run_due, 3}, false, [:local]) end)

      :sys.suspend(pid)
      for _ <- 1..50, do: Tayori.Scheduler.wake()
      :sys.resume(pid)
      :sys.get_state(pid)

      assert_received {:trace, ^pid, :call, {Runner, :run_due, _}}
      refute_received {:trace, ^pid, :call, {Runner, :run_due, _}}
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
