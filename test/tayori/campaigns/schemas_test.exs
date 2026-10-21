defmodule Tayori.Campaigns.SchemasTest do
  use TayoriTest.DataCase

  alias Tayori.Campaigns.{Campaign, Delivery, Enrollment, Event, Letter, Step, Suppression}

  defp attributes, do: TayoriTest.Audience.attributes()

  defp campaign(attrs), do: Campaign.changeset(%Campaign{}, attrs, attributes())

  for_each_repo do
    setup :campaigns

    test "a campaign: its name, kind, purpose and status" do
      changeset = campaign(%{"name" => " Onboarding ", "kind" => "sequence"})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :name) == "Onboarding"
      assert Ecto.Changeset.get_field(changeset, :purpose) == "product"
      assert Ecto.Changeset.get_field(changeset, :status) == "draft"
      assert Ecto.Changeset.get_field(changeset, :min_gap_hours) == 24
      assert Ecto.Changeset.get_field(changeset, :trigger) == %{"type" => "manual"}

      assert errors_on(campaign(%{})) == %{name: ["can't be blank"], kind: ["can't be blank"]}

      assert errors_on(
               campaign(%{
                 "name" => "X",
                 "kind" => "drip",
                 "purpose" => "spam",
                 "min_gap_hours" => -1,
                 "max_days" => 0,
                 "reply_to" => "nobody"
               })
             ) == %{
               kind: ["is invalid"],
               purpose: ["is invalid"],
               min_gap_hours: ["must be greater than or equal to 0"],
               max_days: ["must be greater than 0"],
               reply_to: ["must be an address"]
             }

      assert campaign(%{"name" => "X", "kind" => "sequence", "max_days" => nil}).valid?
    end

    test "a campaign's statuses are of its kind" do
      for status <- Campaign.statuses("sequence") do
        assert campaign(%{"name" => "X", "kind" => "sequence", "status" => status}).valid?
      end

      for status <- Campaign.statuses("broadcast") do
        assert campaign(%{"name" => "X", "kind" => "broadcast", "status" => status}).valid?
      end

      assert errors_on(campaign(%{"name" => "X", "kind" => "sequence", "status" => "sent"})) ==
               %{status: ["is not a status of a sequence"]}

      assert errors_on(campaign(%{"name" => "X", "kind" => "broadcast", "status" => "active"})) ==
               %{status: ["is not a status of a broadcast"]}
    end

    test "a campaign's trigger: an event or manual, for a sequence only" do
      changeset =
        campaign(%{
          "name" => "X",
          "kind" => "sequence",
          "trigger" => %{type: "event", event: " signed_up "}
        })

      assert Ecto.Changeset.get_field(changeset, :trigger) ==
               %{"type" => "event", "event" => "signed_up"}

      for bad <- [
            %{"type" => "event"},
            %{"type" => "event", "event" => ""},
            %{"type" => "x"}
          ] do
        assert errors_on(campaign(%{"name" => "X", "kind" => "sequence", "trigger" => bad})) ==
                 %{trigger: ["must be an event or manual"]}
      end

      assert errors_on(
               campaign(%{
                 "name" => "X",
                 "kind" => "broadcast",
                 "trigger" => %{"type" => "manual"}
               })
             ) == %{trigger: ["is only for a sequence"]}

      broadcast = campaign(%{"name" => "X", "kind" => "broadcast"})
      assert broadcast.valid?
      assert Ecto.Changeset.get_field(broadcast, :trigger) == nil
    end

    test "a campaign's audience and goal are conditions, checked" do
      changeset =
        campaign(%{
          "name" => "X",
          "kind" => "sequence",
          "audience" => %{attribute: "plan", op: "in", value: "pro"},
          "goal" => %{"attribute" => "nope", "op" => "set"}
        })

      assert errors_on(changeset) == %{goal: [~s(Unknown attribute "nope".)]}

      assert Ecto.Changeset.get_change(changeset, :audience) ==
               %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}
    end

    test "a step: a wait of no less than 0, a skip checked, letters in the app's languages", %{
      repo: repo
    } do
      {:ok, campaign} = repo.insert(campaign(%{"name" => "X", "kind" => "sequence"}))
      locales = Tayori.Config.get().locales

      changeset =
        Step.changeset(
          %Step{campaign_id: campaign.id},
          %{
            "wait" => 2880,
            "skip_if" => %{"attribute" => "has_story", "op" => "true"},
            "letters" => [
              %{
                "locale" => "en",
                "subject" => " Your first story ",
                "body" => Kotoba.Content.from_markdown("Write **it**.")
              }
            ]
          },
          attributes(),
          locales
        )

      assert {:ok, step} = repo.insert(changeset)
      assert [%Letter{subject: "Your first story", text: "Write it."}] = step.letters

      assert errors_on(
               Step.changeset(
                 %Step{},
                 %{"wait" => -1, "skip_if" => %{"x" => 1}},
                 attributes(),
                 locales
               )
             ) ==
               %{
                 wait: ["must be greater than or equal to 0"],
                 skip_if: [~s(Not a condition: %{"x" => 1}.)]
               }

      # One letter for each language.
      assert {:error, changeset} =
               repo.insert(
                 Letter.changeset(
                   %Letter{step_id: step.id},
                   %{"locale" => "en", "subject" => "Again"},
                   locales
                 )
               )

      assert errors_on(changeset) == %{step_id: ["has a letter in this language"]}
    end

    test "a letter: a subject, a language of the app, a button to a whole address" do
      locales = Tayori.Config.get().locales
      letter = &Letter.changeset(%Letter{}, &1, locales)

      assert letter.(%{
               "locale" => "pt-PT",
               "subject" => "Olá",
               "cta_url" => "https://app.test/x"
             }).valid?

      assert letter.(%{"locale" => "en", "subject" => "Hi", "cta_url" => "{{dashboard_url}}"}).valid?

      assert errors_on(letter.(%{})) == %{locale: ["can't be blank"], subject: ["can't be blank"]}

      assert errors_on(
               letter.(%{
                 "locale" => "fr",
                 "subject" => String.duplicate("a", 256),
                 "cta_url" => "javascript:alert(1)",
                 "cta_label" => String.duplicate("a", 81)
               })
             ) == %{
               locale: ["is invalid"],
               subject: ["should be at most 255 character(s)"],
               cta_url: ["must be an http or https address"],
               cta_label: ["should be at most 80 character(s)"]
             }
    end

    test "enrollments, deliveries, events and suppressions", %{repo: repo} do
      {:ok, campaign} = repo.insert(campaign(%{"name" => "X", "kind" => "sequence"}))
      now = DateTime.utc_now()

      enrollment =
        Enrollment.changeset(%Enrollment{}, %{
          campaign_id: campaign.id,
          person: "person:1",
          entered_at: now
        })

      assert {:ok, %{cursor: -1, state: "active"}} = repo.insert(enrollment)
      assert {:error, changeset} = repo.insert(enrollment)
      assert errors_on(changeset) == %{campaign_id: ["has already been taken"]}

      assert errors_on(Enrollment.changeset(%Enrollment{}, %{state: "lost", reason: "bored"})) ==
               %{
                 campaign_id: ["can't be blank"],
                 person: ["can't be blank"],
                 entered_at: ["can't be blank"],
                 state: ["is invalid"],
                 reason: ["is invalid"]
               }

      delivery = Delivery.changeset(%Delivery{}, %{campaign_id: campaign.id, person: "person:1"})
      assert {:ok, %{status: "queued"}} = repo.insert(delivery)

      assert errors_on(Delivery.changeset(%Delivery{}, %{status: "lost"})).status == [
               "is invalid"
             ]

      assert Event.changeset(%Event{}, %{person: "p", name: "x", occurred_at: now}).valid?

      assert errors_on(Event.changeset(%Event{}, %{name: String.duplicate("a", 65)})).name ==
               ["should be at most 64 character(s)"]

      suppression =
        Suppression.changeset(%Suppression{}, %{
          email: " Ada@App.Test ",
          purpose: "marketing",
          reason: "unsubscribed"
        })

      assert {:ok, %{email: "ada@app.test"}} = repo.insert(suppression)
      # One row for an address and a purpose.
      assert_raise Ecto.ConstraintError, fn -> repo.insert(suppression) end

      assert errors_on(
               Suppression.changeset(%Suppression{}, %{email: "x", purpose: "x", reason: "x"})
             ) ==
               %{email: ["must be an address"], purpose: ["is invalid"], reason: ["is invalid"]}
    end
  end
end
