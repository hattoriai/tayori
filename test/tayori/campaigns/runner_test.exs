defmodule Tayori.Campaigns.RunnerTest do
  use TayoriTest.DataCase

  import Swoosh.TestAssertions

  alias Tayori.Campaigns
  alias Tayori.Campaigns.{Delivery, Enrollment, Runner}

  @t0 ~U[2026-03-02 09:00:00.000000Z]

  defmodule DownMailer do
    @moduledoc "A mailer that cannot send."
    def deliver(_email), do: {:error, :down}
  end

  defmodule IdMailer do
    @moduledoc "A mailer that gives each email an id, as a provider does."
    def deliver(email) do
      send(self(), {:email, email})
      {:ok, %{id: "msg-" <> elem(hd(email.to), 1)}}
    end
  end

  # What is due at a time, its letters sent here.
  defp run(at, opts \\ []), do: Runner.run_due(Tayori.Config.get(), at, [inline: true] ++ opts)

  defp subjects(campaign) do
    for d <- deliveries(campaign), d.status == "sent", do: d.step_id
  end

  # The emails sent so far, as {subject, address}, in any order.
  defp sent do
    receive do
      {:email, email} -> [{email.subject, elem(hd(email.to), 1)} | sent()]
    after
      0 -> []
    end
  end

  defp statuses(campaign), do: Enum.map(deliveries(campaign), &{&1.status, &1.reason})

  for_each_repo do
    setup :campaigns

    test "an event takes the person into the active sequences it triggers" do
      ada = person!(name: "Ada")
      signed_up = %{"type" => "event", "event" => "signed_up"}

      on = sequence!(%{"name" => "On", "trigger" => signed_up}, [step(0, "Welcome")])

      other =
        sequence!(%{"name" => "Other", "trigger" => %{"type" => "event", "event" => "paid"}}, [
          step(0, "Paid")
        ])

      manual = sequence!(%{"name" => "Manual"}, [step(0, "Manual")])

      {:ok, draft} =
        Campaigns.create(%{"name" => "Draft", "kind" => "sequence", "trigger" => signed_up})

      assert :ok = Tayori.track(person_id(ada), "signed_up", at: @t0)

      assert %Enrollment{entered_at: @t0} = enrollment(on, ada)
      assert enrollment(other, ada) == nil
      assert enrollment(manual, ada) == nil
      assert enrollment(draft, ada) == nil

      # Once.
      assert :ok = Tayori.track(person_id(ada), "signed_up", at: later(@t0, 1))
      assert %Enrollment{entered_at: @t0} = enrollment(on, ada)
    end

    test "a step at its time: sent, once, then the next step's time" do
      ada = person!(name: "Ada Lovelace", email: "ada@app.test")
      campaign = sequence!([step(0, "Welcome"), step(2 * 1440, "Day two")])
      [welcome, day_two] = campaign.steps

      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)
      assert :ok = run(@t0)

      assert_email_sent(subject: "Welcome", to: [{"Ada Lovelace", "ada@app.test"}])

      assert [%Delivery{status: "sent", step_id: step_id, email: "ada@app.test", sent_at: @t0}] =
               deliveries(campaign)

      assert step_id == welcome.id

      assert %{cursor: 0, last_sent_at: @t0, next_at: next_at, state: "active"} =
               enrollment(campaign, ada)

      assert next_at == later(@t0, 2)

      # Nothing before its time, nothing twice.
      run(later(@t0, 1))
      run(@t0)
      refute_email_sent()

      run(later(@t0, 2))
      assert_email_sent(subject: "Day two")
      assert subjects(campaign) == [welcome.id, day_two.id]

      assert %{state: "completed", reason: "finished", cursor: 2880, next_at: nil} =
               enrollment(campaign, ada)

      run(later(@t0, 3))
      refute_email_sent()
    end

    test "two at once advance a person once" do
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, enrollment} = Campaigns.enroll(campaign, person_id(ada), @t0)
      config = Tayori.Config.get()

      [a, b] =
        for _ <- 1..2,
            do: Task.async(fn -> Runner.advance(config, enrollment.id, @t0, inline: true) end)

      assert [:ok, :ok] = Task.await_many([a, b])
      assert [%Delivery{status: "sent"}] = deliveries(campaign)
      assert_received {:email, %{subject: "Welcome"}}
      refute_received {:email, _}
    end

    test "a person held by another node, or ended, is left as they are", %{repo: repo} do
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, enrollment} = Campaigns.enroll(campaign, person_id(ada), @t0)

      repo.update_all(Enrollment, set: [next_at: nil])
      assert :ok = Runner.advance(Tayori.Config.get(), enrollment.id, @t0, inline: true)
      assert deliveries(campaign) == []

      repo.update_all(Enrollment, set: [next_at: @t0, state: "exited"])
      assert :ok = Runner.advance(Tayori.Config.get(), enrollment.id, @t0, inline: true)
      assert deliveries(campaign) == []
      assert :ok = Runner.advance(Tayori.Config.get(), Ecto.UUID.generate(), @t0)
    end

    test "paused, a person waits; resumed, they go on", %{repo: repo} do
      ada = person!(name: "Ada")
      grace = person!(name: "Grace")
      campaign = sequence!([step(0, "Welcome"), step(60, "Later")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)
      {:ok, _} = Campaigns.enroll(campaign, person_id(grace), later(@t0, 0, 30))

      {:ok, paused} = Campaigns.pause(campaign)
      run(later(@t0, 0, 10))
      refute_email_sent()
      assert %{next_at: nil, state: "active"} = enrollment(campaign, ada)
      # Not yet looked at.
      assert %{next_at: %DateTime{}} = enrollment(campaign, grace)

      # Who enters while paused is refused.
      assert {:error, :not_active} = Campaigns.enroll(paused, "person:1", @t0)

      resumed_at = later(@t0, 1)
      {:ok, _} = Campaigns.resume(paused, resumed_at)
      assert %{next_at: ^resumed_at} = enrollment(campaign, ada)

      run(resumed_at)
      # The second step's time passed too, but a letter waits the gap.
      assert Enum.sort(sent()) == [{"Welcome", "ada@app.test"}, {"Welcome", "grace@app.test"}]

      assert repo.aggregate(Delivery, :count) == 2
    end

    test "one who is no longer of the app leaves", %{repo: repo} do
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)

      repo.update!(Ecto.Changeset.change(ada, closed_at: @t0))
      run(@t0)

      refute_email_sent()
      assert %{state: "exited", reason: "left", ended_at: @t0} = enrollment(campaign, ada)
    end

    test "one who reached the goal is done" do
      ada = person!(name: "Ada")
      goal = %{"attribute" => "published", "op" => "true"}
      campaign = sequence!(%{"goal" => goal}, [step(0, "Welcome"), step(60, "Publish")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)

      run(@t0)
      assert_email_sent(subject: "Welcome")
      story!(ada, @t0)

      run(later(@t0, 1))
      refute_email_sent()
      assert %{state: "completed", reason: "goal"} = enrollment(campaign, ada)

      results = Campaigns.results(campaign)
      assert %{entered: 1, active: 0, goal: 1, goal_rate: 1.0, ended: %{"goal" => 1}} = results
      [welcome, publish] = results.steps
      assert %{sent: 1, goal_after: 1} = welcome
      assert %{sent: 0, goal_after: 0} = publish
    end

    test "past the days of the sequence, it ends" do
      ada = person!(name: "Ada")
      campaign = sequence!(%{"max_days" => 14}, [step(0, "Welcome"), step(15 * 1440, "Late")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)

      run(@t0)
      assert_email_sent(subject: "Welcome")
      run(later(@t0, 15))
      refute_email_sent()
      assert %{state: "completed", reason: "expired"} = enrollment(campaign, ada)
    end

    test "unsubscribed, or not to be written to: they leave" do
      ada = person!(name: "Ada")
      grace = person!(name: "Grace", optional_emails: false)
      campaign = sequence!(%{"purpose" => "marketing"}, [step(0, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)
      {:ok, _} = Campaigns.enroll(campaign, person_id(grace), @t0)

      :ok = Campaigns.suppress("ADA@app.test", "marketing", "unsubscribed")
      run(@t0)

      refute_email_sent()
      assert %{state: "exited", reason: "unsubscribed"} = enrollment(campaign, ada)
      assert %{state: "exited", reason: "cannot_email"} = enrollment(campaign, grace)
    end

    test "a step whose skip matches is left out, and the next one goes" do
      ada = person!(name: "Ada")
      photo!(ada)

      campaign =
        sequence!([
          step(0, "Photographs", skip_if: %{"attribute" => "has_photos", "op" => "true"}),
          step(60, "Story", skip_if: %{"attribute" => "has_story", "op" => "true"})
        ])

      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)
      run(@t0)
      refute_email_sent()
      assert statuses(campaign) == [{"skipped", "skip_if"}]
      assert %{cursor: 0, last_sent_at: nil} = enrollment(campaign, ada)

      run(later(@t0, 0, 60))
      assert_email_sent(subject: "Story")
      assert [_, %{skipped: 0, sent: 1}] = Campaigns.results(campaign).steps
    end

    test "a step waits the gap since the last letter; it is not skipped" do
      ada = person!(name: "Ada")
      campaign = sequence!(%{"min_gap_hours" => 40}, [step(0, "Welcome"), step(60, "Soon")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)

      run(@t0)
      assert_email_sent(subject: "Welcome")
      assert %{next_at: next_at} = enrollment(campaign, ada)
      assert next_at == later(@t0, 0, 60)

      run(later(@t0, 0, 60))
      refute_email_sent()
      assert %{next_at: gap} = enrollment(campaign, ada)
      assert gap == later(@t0, 0, 40 * 60)

      run(later(@t0, 0, 40 * 60 - 1))
      refute_email_sent()
      run(gap)
      assert_email_sent(subject: "Soon")
    end

    test "the steps are read live: one added before the cursor is not sent, one after is" do
      ada = person!(name: "Ada")
      campaign = sequence!(%{"min_gap_hours" => 0}, [step(0, "Welcome"), step(120, "Two hours")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)

      run(later(@t0, 0, 120))
      assert_email_sent(subject: "Welcome")
      assert_email_sent(subject: "Two hours")

      {:ok, _} = Campaigns.add_step(Campaigns.get(campaign.id), step(60, "One hour"))
      {:ok, _} = Campaigns.add_step(Campaigns.get(campaign.id), step(180, "Three hours"))
      {:ok, removed} = Campaigns.add_step(Campaigns.get(campaign.id), step(240, "Four hours"))
      {:ok, _} = Campaigns.remove_step(removed)

      # Finished already: the new steps are for those still in it.
      assert %{state: "completed"} = enrollment(campaign, ada)

      grace = person!(name: "Grace")
      {:ok, _} = Campaigns.enroll(campaign, person_id(grace), @t0)
      run(later(@t0, 0, 90))
      assert_email_sent(subject: "Welcome")
      assert_email_sent(subject: "One hour")
      run(later(@t0, 1))
      assert_email_sent(subject: "Two hours")
      assert_email_sent(subject: "Three hours")
      refute_email_sent()
    end

    test "one with no address is skipped, step by step" do
      ada = person!(name: "Ada", email: nil)
      campaign = sequence!([step(0, "Welcome"), step(60, "Next")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)

      run(later(@t0, 1))
      refute_email_sent()
      assert statuses(campaign) == [{"skipped", "no_email"}, {"skipped", "no_email"}]
      assert %{state: "completed", reason: "finished"} = enrollment(campaign, ada)
    end

    test "a letter is checked again when it goes", %{repo: repo, config: config} do
      ada = person!(name: "Ada")
      grace = person!(name: "Grace")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)
      {:ok, _} = Campaigns.enroll(campaign, person_id(grace), @t0)

      # Queued, not sent: the letters go from a task later.
      put_config(config, mailer: DownMailer)
      run(@t0)
      put_config(config, mailer: TayoriTest.Mailer)
      repo.update_all(Delivery, set: [status: "queued", reason: nil])

      :ok = Campaigns.suppress("grace@app.test", "product", "unsubscribed")
      [first, second] = deliveries(campaign)

      for d <- [first, second],
          do: assert(:ok = Runner.deliver_letter(Tayori.Config.get(), d.id, @t0, true))

      assert_email_sent(to: [{"Ada", "ada@app.test"}])
      refute_email_sent()
      assert Enum.sort(statuses(campaign)) == [{"sent", nil}, {"skipped", "unsubscribed"}]

      # A delivery that went is not sent again.
      assert :ok = Runner.deliver_letter(Tayori.Config.get(), first.id, @t0, true)
      refute_email_sent()
    end

    test "a letter that cannot be sent fails on its last attempt", %{config: config} do
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)
      config = put_config(config, mailer: DownMailer)

      # Without Oban, tried once: failed.
      run(@t0)
      assert [%Delivery{status: "failed", reason: ":down"} = d] = deliveries(campaign)

      config.repo.update_all(Delivery, set: [status: "queued", reason: nil])
      assert {:error, :down} = Runner.deliver_letter(config, d.id, @t0, false)
      assert [%Delivery{status: "queued"}] = deliveries(campaign)
      assert {:error, :down} = Runner.deliver_letter(config, d.id, @t0, true)
      assert [%Delivery{status: "failed"}] = deliveries(campaign)
      assert Campaigns.results(Campaigns.get(campaign.id)).steps |> hd() |> Map.get(:failed) == 1
    end

    test "the provider's id of a sent letter is kept", %{config: config} do
      ada = person!(name: "Ada")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)
      put_config(config, mailer: IdMailer)

      run(@t0)
      assert [%Delivery{status: "sent", provider_id: "msg-ada@app.test"}] = deliveries(campaign)
    end

    test "a broadcast goes to its audience, in batches, once each", %{repo: repo} do
      for n <- 1..7, do: person!(name: "Person#{n}", plan: "pro")
      person!(name: "Free", plan: "free")
      person!(name: "Quiet", plan: "pro", optional_emails: false)
      person!(name: "Nobody", plan: "pro", email: nil)
      :ok = Campaigns.suppress("person3@app.test", "all", "bounced")

      broadcast =
        broadcast!(
          %{
            "purpose" => "marketing",
            "audience" => %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}
          },
          "Spring"
        )

      Tayori.subscribe()
      {:ok, _} = Campaigns.schedule_broadcast(broadcast, later(@t0, 1))

      run(@t0, batch_size: 2)
      refute_email_sent()

      run(later(@t0, 1), batch_size: 2)
      id = broadcast.id
      assert_receive {Tayori, :campaign_changed, ^id}

      assert Enum.sort(sent()) ==
               for(n <- [1, 2, 4, 5, 6, 7], do: {"Spring", "person#{n}@app.test"})

      assert %{status: "sent", sent_at: sent_at} = Campaigns.get(broadcast.id)
      assert sent_at == later(@t0, 1)
      assert repo.aggregate(Delivery, :count) == 6

      assert %{recipients: 6, sent: 6, failed: 0, bounced: 0, complained: 0} =
               Campaigns.results(Campaigns.get(broadcast.id))

      # Sent: nothing again, and a walk again (an interrupted one) gives
      # no one two.
      run(later(@t0, 2))
      repo.update_all(Tayori.Campaigns.Campaign, set: [status: "sending"])

      Runner.send_broadcast(Tayori.Config.get(), broadcast.id, later(@t0, 2),
        inline: true,
        resume: true,
        batch_size: 4
      )

      refute_email_sent()
      assert repo.aggregate(Delivery, :count) == 6
      assert {:error, :locked} = Campaigns.update(Campaigns.get(broadcast.id), %{"name" => "X"})
    end

    test "a broadcast cancelled before its time does not go" do
      person!(name: "Ada")
      broadcast = broadcast!("Spring")
      {:ok, scheduled} = Campaigns.schedule_broadcast(broadcast, @t0)
      {:ok, _} = Campaigns.cancel_broadcast(scheduled)

      run(later(@t0, 1))
      refute_email_sent()

      # Nor an archived one.
      {:ok, scheduled} = Campaigns.schedule_broadcast(Campaigns.get(broadcast.id), @t0)
      {:ok, _} = Campaigns.archive(scheduled)
      run(later(@t0, 1))
      refute_email_sent()
    end

    test "the next time of the campaigns, for the scheduler" do
      config = Tayori.Config.get()
      assert Runner.next_due(config) == nil

      ada = person!(name: "Ada")
      campaign = sequence!([step(60, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)
      {:ok, _} = Campaigns.schedule_broadcast(broadcast!("Spring"), later(@t0, 0, 30))

      assert Runner.next_due(config) == later(@t0, 0, 30)
    end
  end
end
