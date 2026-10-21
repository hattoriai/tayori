defmodule Tayori.CampaignsTest do
  use TayoriTest.DataCase

  alias Tayori.Campaigns
  alias Tayori.Campaigns.{Campaign, Segments, Step}

  @t0 ~U[2026-03-02 09:00:00.000000Z]
  @pro %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}

  for_each_repo do
    setup :campaigns

    test "creates a sequence, a draft, and says so" do
      Tayori.subscribe()

      assert {:ok, %Campaign{id: id} = campaign} =
               Campaigns.create(
                 %{name: " Onboarding ", kind: "sequence", status: "active"},
                 author: %{"name" => "Hanzo"}
               )

      assert_receive {Tayori, :campaign_changed, ^id}
      assert campaign.name == "Onboarding"
      assert campaign.status == "draft"
      assert campaign.trigger == %{"type" => "manual"}
      assert campaign.author == %{"name" => "Hanzo"}
      assert campaign.steps == []
      assert Campaigns.get(id).name == "Onboarding"
      assert Campaigns.get("nope") == nil
      assert Campaigns.get(Ecto.UUID.generate()) == nil
      assert [%Campaign{id: ^id}] = Campaigns.list(kind: "sequence")
      assert Campaigns.list(kind: "broadcast") == []

      assert {:error, changeset} = Campaigns.create(%{"kind" => "drip"})
      assert errors_on(changeset) == %{name: ["can't be blank"], kind: ["is invalid"]}
    end

    test "a broadcast is made with its one step" do
      {:ok, broadcast} = Campaigns.create(%{"name" => "News", "kind" => "broadcast"})
      assert [%Step{wait: 0, letters: []} = step] = broadcast.steps

      assert {:error, :one_step} = Campaigns.add_step(broadcast, step(0, "Again"))
      assert {:error, :one_step} = Campaigns.remove_step(step)

      # Its wait stays 0.
      assert {:ok, %Step{wait: 0}} = Campaigns.update_step(step, %{"wait" => 60})
    end

    test "updates the settings, not the kind nor the status" do
      {:ok, campaign} = Campaigns.create(%{"name" => "A", "kind" => "sequence"})

      assert {:ok, campaign} =
               Campaigns.update(campaign, %{
                 "name" => "B",
                 "kind" => "broadcast",
                 "status" => "active",
                 "min_gap_hours" => 40,
                 "goal" => @pro
               })

      assert {campaign.name, campaign.kind, campaign.status} == {"B", "sequence", "draft"}
      assert campaign.min_gap_hours == 40
      assert campaign.goal == @pro

      assert {:error, changeset} = Campaigns.update(campaign, %{"goal" => %{"attribute" => "x"}})
      assert errors_on(changeset).goal != []

      {:ok, archived} = Campaigns.archive(campaign)
      assert archived.status == "archived"
      assert {:error, :locked} = Campaigns.update(archived, %{"name" => "C"})
      assert {:error, :locked} = Campaigns.add_step(archived, step(0, "Hi"))
    end

    test "steps: added at the end, updated, their letters by language, removed" do
      {:ok, campaign} = Campaigns.create(%{"name" => "A", "kind" => "sequence"})

      assert {:ok, first} = Campaigns.add_step(campaign, step(0, "Welcome"))
      assert {:ok, second} = Campaigns.add_step(campaign, step(2880, "Day two"))
      assert {first.position, second.position} == {0, 1}

      # Two steps of a sequence at the same time would be one.
      assert {:error, changeset} = Campaigns.add_step(campaign, step(2880, "Same"))
      assert errors_on(changeset) == %{wait: ["another step goes at this time"]}

      assert {:ok, second} =
               Campaigns.update_step(second, %{
                 "wait" => 1440,
                 "skip_if" => %{"attribute" => "has_story", "op" => "true"}
               })

      assert second.wait == 1440
      assert second.skip_if == %{"attribute" => "has_story", "op" => "true"}

      assert {:ok, letter} =
               Campaigns.put_letter(second, "pt-PT", %{
                 "subject" => "Dia dois",
                 "body" => Kotoba.Content.from_markdown("Olá **{{first_name}}**.")
               })

      assert letter.text == "Olá {{first_name}}."
      assert {:ok, _} = Campaigns.put_letter(second, "en", %{"subject" => "Day 2"})
      assert {:error, changeset} = Campaigns.put_letter(second, "xx", %{"subject" => "X"})
      assert errors_on(changeset).locale == ["is invalid"]

      step = Campaigns.get_step(second.id)

      assert Enum.map(step.letters, &{&1.locale, &1.subject}) == [
               {"en", "Day 2"},
               {"pt-PT", "Dia dois"}
             ]

      assert :ok = Campaigns.delete_letter(step, "pt-PT")
      assert [%{locale: "en"}] = Campaigns.get_step(second.id).letters

      # The letters given are all of them.
      assert {:ok, step} =
               Campaigns.update_step(Campaigns.get_step(first.id), %{
                 "letters" => [%{"locale" => "pt-PT", "subject" => "Bem-vindo"}]
               })

      assert Enum.map(step.letters, & &1.locale) == ["pt-PT"]

      assert {:ok, _} = Campaigns.remove_step(step)
      assert Enum.map(Campaigns.get(campaign.id).steps, & &1.id) == [second.id]
      assert Campaigns.get_step(first.id) == nil
    end

    test "a step moved trades places, and times, with its neighbour" do
      {:ok, campaign} = Campaigns.create(%{"name" => "A", "kind" => "sequence"})

      for {wait, subject} <- [{0, "A"}, {60, "B"}, {120, "C"}],
          do: Campaigns.add_step(campaign, step(wait, subject))

      order = fn ->
        for step <- Campaigns.get(campaign.id).steps,
            do: {step.wait, hd(step.letters).subject}
      end

      [_a, _b, c] = Campaigns.get(campaign.id).steps
      assert {:ok, %Step{wait: 60}} = Campaigns.move_step(c, :up)
      assert order.() == [{0, "A"}, {60, "C"}, {120, "B"}]

      [a | _] = Campaigns.get(campaign.id).steps
      assert {:ok, %Step{wait: 0}} = Campaigns.move_step(a, :up)
      assert {:ok, _} = Campaigns.move_step(a, :down)
      assert order.() == [{0, "C"}, {60, "A"}, {120, "B"}]
    end

    test "a sequence starts with steps whose first letters are whole" do
      {:ok, campaign} = Campaigns.create(%{"name" => "A", "kind" => "sequence"})
      assert {:error, :no_steps} = Campaigns.start(campaign)

      {:ok, empty} = Campaigns.add_step(campaign, step(0, "Welcome", body: ""))
      {:ok, other} = Campaigns.add_step(campaign, %{"wait" => 60, "letters" => []})
      assert {:error, {:incomplete, ids}} = Campaigns.start(campaign)
      assert Enum.sort(ids) == Enum.sort([empty.id, other.id])

      # Another language is not the first.
      {:ok, _} =
        Campaigns.put_letter(other, "pt-PT", %{
          "subject" => "Olá",
          "body" => Kotoba.Content.from_markdown("Olá.")
        })

      assert {:error, {:incomplete, _}} = Campaigns.start(campaign)

      {:ok, _} =
        Campaigns.put_letter(empty, "en", %{"body" => Kotoba.Content.from_markdown("Hello.")})

      {:ok, _} =
        Campaigns.put_letter(other, "en", %{
          "subject" => "Hi",
          "body" => Kotoba.Content.from_markdown("![A photo](/p.png)")
        })

      assert {:ok, campaign} = Campaigns.start(campaign, @t0)
      assert {campaign.status, campaign.started_at} == {"active", @t0}

      assert {:error, {:status, "active"}} = Campaigns.start(campaign)
      assert {:error, {:status, "active"}} = Campaigns.resume(campaign)
      assert {:ok, %{status: "paused"} = paused} = Campaigns.pause(campaign)
      assert {:error, {:status, "paused"}} = Campaigns.pause(paused)
      assert {:ok, %{status: "active"}} = Campaigns.resume(paused)

      assert {:error, {:kind, "broadcast"}} = Campaigns.start(broadcast!("News"))
    end

    test "enroll: an active sequence, a person of the app, in its audience, once" do
      ada = person!(name: "Ada", plan: "pro")
      grace = person!(name: "Grace", plan: "free")

      {:ok, draft} = Campaigns.create(%{"name" => "A", "kind" => "sequence", "audience" => @pro})
      {:ok, _} = Campaigns.add_step(draft, step(60, "Hi"))
      assert {:error, :not_active} = Campaigns.enroll(draft, person_id(ada), @t0)

      {:ok, campaign} = Campaigns.start(draft)
      Tayori.subscribe()

      assert {:ok, enrollment} = Campaigns.enroll(campaign, person_id(ada), @t0)
      assert enrollment.state == "active"
      assert enrollment.cursor == -1
      assert enrollment.entered_at == @t0
      # Its first step's time.
      assert enrollment.next_at == later(@t0, 0, 60)
      id = campaign.id
      assert_receive {Tayori, :campaign_changed, ^id}

      assert {:error, :already} = Campaigns.enroll(campaign, person_id(ada), @t0)
      assert {:error, :not_in_audience} = Campaigns.enroll(campaign, person_id(grace), @t0)
      assert {:error, :not_found} = Campaigns.enroll(campaign, "person:0", @t0)
      assert {:error, :not_found} = Campaigns.enroll(campaign, "nobody", @t0)
    end

    test "enroll_segment: everyone of a condition or a segment in the audience, once" do
      for {name, plan} <- [{"Ada", "pro"}, {"Grace", "pro"}, {"Alan", "free"}, {"Edsger", "team"}],
          do: person!(name: name, plan: plan)

      campaign =
        sequence!(
          %{"audience" => %{"attribute" => "plan", "op" => "in", "value" => ["pro", "free"]}},
          [
            step(0, "Hi")
          ]
        )

      {:ok, segment} = Segments.create(%{"name" => "Pro", "condition" => @pro})

      assert {:ok, 2} = Campaigns.enroll_segment(campaign, segment, @t0)
      assert {:ok, 0} = Campaigns.enroll_segment(campaign, segment.id, @t0)
      # The team plan is not in the audience.
      assert {:ok, 1} = Campaigns.enroll_segment(campaign, nil, @t0)
      assert Campaigns.results(campaign).entered == 3

      assert {:error, :not_found} = Campaigns.enroll_segment(campaign, Ecto.UUID.generate(), @t0)

      assert {:error, [_ | _]} =
               Campaigns.enroll_segment(campaign, %{"attribute" => "nope", "op" => "set"}, @t0)

      {:ok, paused} = Campaigns.pause(campaign)
      assert {:error, :not_active} = Campaigns.enroll_segment(paused, nil, @t0)
    end

    test "archiving a sequence stops its people; only drafts and archives are deleted" do
      ada = person!(name: "Ada")
      campaign = sequence!([step(60, "Hi")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada), @t0)

      assert {:error, :not_draft} = Campaigns.delete(campaign)
      assert {:ok, archived} = Campaigns.archive(campaign, @t0)
      assert {:ok, ^archived} = Campaigns.archive(archived)

      assert %{state: "exited", reason: "stopped", next_at: nil, ended_at: @t0} =
               enrollment(campaign, ada)

      assert Campaigns.list() == []
      assert [_] = Campaigns.list(archived: true)
      assert {:ok, _} = Campaigns.delete(archived)
      assert Campaigns.get(campaign.id) == nil
    end

    test "a broadcast is scheduled with a whole letter, and cancelled before it goes" do
      {:ok, empty} = Campaigns.create(%{"name" => "News", "kind" => "broadcast"})
      assert {:error, {:incomplete, [_]}} = Campaigns.schedule_broadcast(empty, @t0)

      broadcast = broadcast!("Spring")
      at = later(@t0, 1)
      assert {:ok, scheduled} = Campaigns.schedule_broadcast(broadcast, at)
      assert {scheduled.status, scheduled.send_at} == {"scheduled", at}

      assert {:ok, %{status: "draft", send_at: nil} = draft} =
               Campaigns.cancel_broadcast(scheduled)

      assert {:error, {:status, "draft"}} = Campaigns.cancel_broadcast(draft)

      assert {:ok, %{status: "scheduled", send_at: @t0}} =
               Campaigns.send_broadcast_now(draft, @t0)

      assert {:error, {:kind, "sequence"}} =
               Campaigns.schedule_broadcast(sequence!([step(0, "Hi")]), @t0)
    end

    test "suppressions: by address, lowercased, for a purpose or all" do
      refute Campaigns.suppressed?("ada@app.test", "product")
      refute Campaigns.suppressed?(nil, "product")

      assert :ok = Campaigns.suppress(" Ada@App.TEST ", "marketing", "unsubscribed")
      assert :ok = Campaigns.suppress("ada@app.test", "marketing", "manual")
      assert Campaigns.suppressed?("ADA@app.test", "marketing")
      assert Campaigns.suppressed?("ada@app.test", :marketing)
      refute Campaigns.suppressed?("ada@app.test", "product")

      assert :ok = Campaigns.suppress("grace@app.test", "all", "bounced")
      assert Campaigns.suppressed?("grace@app.test", "product")
      assert Campaigns.suppressed?("grace@app.test", "marketing")

      assert :ok = Campaigns.unsuppress("Grace@app.test", "all")
      refute Campaigns.suppressed?("grace@app.test", "product")

      assert {:error, changeset} = Campaigns.suppress("nobody", "spam", "because")
      assert Map.keys(errors_on(changeset)) |> Enum.sort() == [:email, :purpose, :reason]
    end

    test "a segment another segment names is not deleted" do
      {:ok, pro} = Segments.create(%{"name" => "Pro", "condition" => @pro})

      {:ok, inner} =
        Segments.create(%{
          "name" => "Pro with photos",
          "condition" => %{"all" => [%{"segment" => pro.id, "op" => "in"}]}
        })

      assert {:error, {:in_use, ["Pro with photos"]}} = Segments.delete(pro)
      assert {:ok, _} = Segments.delete(inner)
      assert {:ok, _} = Segments.delete(pro)
    end
  end
end
