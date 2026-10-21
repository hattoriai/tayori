defmodule Tayori.AdminCampaignsTest do
  use TayoriTest.LiveCase

  import Swoosh.TestAssertions

  alias Tayori.Campaigns
  alias Tayori.Campaigns.Segments

  @admin "/admin/news"

  # The ids of the builder's rules and groups, in the order of the page.
  defp rules(html, builder),
    do:
      Regex.scan(~r/id="#{builder}-(c\d+)-subject"/, html, capture: :all_but_first)
      |> List.flatten()

  defp groups(html, builder),
    do:
      Regex.scan(
        ~r/id="#{builder}-(c\d+)-op" name="n\[\1\]\[op\]"[^>]*class="ta-input ta-cond-op"/,
        html,
        capture: :all_but_first
      )
      |> Enum.map(&hd/1)

  defp change_builder(view, builder, nodes) do
    view |> element("##{builder}-form") |> render_change(%{"n" => nodes})
  end

  describe "without the campaigns" do
    setup do
      {:ok, ctx} = TayoriTest.DataCase.checkout(TayoriTest.SQLiteRepo)
      {:ok, Keyword.put(ctx, :conn, Phoenix.ConnTest.build_conn())}
    end

    test "their pages are not there", %{conn: conn} do
      for path <- ["/audience", "/audience/new", "/campaigns", "/campaigns/new"] do
        assert_raise Tayori.Admin.NotFound, fn -> conn |> as_admin() |> live(@admin <> path) end
      end
    end

    test "the settings show the changelog's sections and the modules", %{conn: conn} do
      {:ok, _view, html} = conn |> as_admin() |> live(@admin <> "/settings")
      assert html =~ ~s(id="modules")
      assert html =~ ~s(id="ai")
      refute html =~ ~s(id="campaigns")
    end
  end

  campaigns_describe "the audience" do
    test "lists the attributes, the events and the segments with their counts", %{conn: conn} do
      person!(name: "Ada Lovelace", plan: "pro")
      person!(name: "Grace Hopper", plan: "free")

      {:ok, _} =
        Segments.create(%{
          "name" => "Pro",
          "condition" => %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}
        })

      {:ok, view, html} = conn |> as_admin() |> live(@admin <> "/audience")
      assert html =~ "Takes optional emails"
      assert html =~ "One of: Free, Pro, Team"
      assert html =~ "Published a story"
      assert html =~ "story_published"
      assert html =~ "Plan is Pro."
      assert render_async(view) =~ ~r/<svg[^>]*>.*?<\/svg>1\s*<\/span>/s
      assert has_element?(view, "a", "New segment")
    end

    test "a read-only admin sees the segments and changes nothing", %{conn: conn} do
      {:ok, segment} =
        Segments.create(%{"name" => "All", "condition" => %{"all" => []}})

      {:ok, _view, html} = conn |> as_admin("viewer") |> live(@admin <> "/audience")
      refute html =~ "New segment"

      {:ok, view, html} =
        conn |> as_admin("viewer") |> live(@admin <> "/audience/#{segment.id}")

      assert html =~ ~r/<fieldset[^>]*disabled/
      refute html =~ "Add a rule"
      refute html =~ "Delete segment"
      render_submit(view, "save", %{"segment" => %{"name" => "Changed"}})
      render_click(view, "delete", %{})
      assert Segments.get(segment.id).name == "All"
    end
  end

  campaigns_describe "the condition builder" do
    test "rules by type, groups, the sentence, the errors, the count and the people", %{
      conn: conn
    } do
      person!(name: "Ada Lovelace", plan: "pro")
      person!(name: "Grace Hopper", plan: "free")
      {:ok, view, html} = conn |> as_admin() |> live(@admin <> "/audience/new")
      assert html =~ "Everyone."
      assert render_async(view) =~ "2 people"

      # A rule: the first attribute, Name, a text.
      html = view |> element("#segment-condition button", "Add a rule") |> render_click()
      [rule] = rules(html, "segment-condition")
      assert html =~ ~s(name="n[#{rule}][value]")
      assert html =~ "Name needs a value."

      # An enum: a choice of its values.
      html =
        change_builder(view, "segment-condition", %{rule => %{"subject" => "attribute:plan"}})

      assert html =~ ~s(type="checkbox" name="n[#{rule}][value][]" value="team")
      assert html =~ "Plan needs one or more of free, pro, team."

      html =
        change_builder(view, "segment-condition", %{
          rule => %{"subject" => "attribute:plan", "op" => "in", "value" => ["", "pro"]}
        })

      assert html =~ "Plan is Pro."
      html = render_async(view)
      assert html =~ "1 person"
      assert html =~ "ada@app.test"
      refute html =~ "grace@app.test"

      # The other types: a number, a yes or no, a date, an event, a segment.
      html =
        change_builder(view, "segment-condition", %{rule => %{"subject" => "attribute:visits"}})

      assert html =~ ~s(type="number" id="segment-condition-#{rule}-value")

      html =
        change_builder(view, "segment-condition", %{
          rule => %{"subject" => "attribute:has_story"}
        })

      assert html =~ ~s(type="checkbox" name="n[#{rule}][checked]")
      assert html =~ "Has a story."

      html =
        change_builder(view, "segment-condition", %{rule => %{"subject" => "attribute:born_on"}})

      assert html =~ ~s(type="date")

      html = change_builder(view, "segment-condition", %{rule => %{"subject" => "event"}})
      assert html =~ ~s(list="segment-condition-events")
      assert html =~ ~s(<option value="signed_up">Signed up</option>)

      html =
        change_builder(view, "segment-condition", %{
          rule => %{
            "subject" => "event",
            "name" => "signed_up",
            "op" => "not_happened",
            "within_days" => "7"
          }
        })

      assert html =~ "&quot;Signed up&quot; did not happen in the last 7 days."

      # A group, inside, then removed.
      html = view |> element("#segment-condition button", "Add a group") |> render_click()
      assert [_root, _group] = groups(html, "segment-condition")
      assert html =~ "Remove this group"

      html =
        render_click(
          view
          |> element("#segment-condition button[aria-label='Remove this group']")
        )

      assert [_root] = groups(html, "segment-condition")

      # Any of, none of.
      [root] = groups(html, "segment-condition")
      html = change_builder(view, "segment-condition", %{root => %{"op" => "none"}})
      assert html =~ "Not (&quot;Signed up&quot; did not happen in the last 7 days)."

      html =
        view
        |> element("#segment-condition button[aria-label='Remove rule 1']")
        |> render_click()

      assert html =~ "No rule: no one."
      refute rules(html, "segment-condition") != []
    end

    test "groups go three deep at most", %{conn: conn} do
      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/audience/new")
      view |> element("#segment-condition button", "Add a group") |> render_click()
      html = view |> element(".ta-cond-subgroup button", "Add a group") |> render_click()
      assert length(groups(html, "segment-condition")) == 3
      refute has_element?(view, ".ta-cond-subgroup .ta-cond-subgroup button", "Add a group")
    end

    test "a segment rule names the other segments", %{conn: conn} do
      {:ok, pro} =
        Segments.create(%{
          "name" => "Pro",
          "condition" => %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}
        })

      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/audience/new")
      html = view |> element("#segment-condition button", "Add a rule") |> render_click()
      [rule] = rules(html, "segment-condition")

      html =
        change_builder(view, "segment-condition", %{
          rule => %{"subject" => "segment", "segment" => pro.id, "op" => "not_in"}
        })

      assert html =~ ~r/<option value="#{pro.id}" selected[^>]*>\s*Pro\s*<\/option>/
      assert html =~ "Not in the segment &quot;Pro&quot;."
    end
  end

  campaigns_describe "a segment" do
    test "is made, changed and deleted", %{conn: conn} do
      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/audience/new")
      html = view |> element("#segment-condition button", "Add a rule") |> render_click()
      [rule] = rules(html, "segment-condition")

      change_builder(view, "segment-condition", %{
        rule => %{"subject" => "attribute:plan", "op" => "in", "value" => ["pro", "team"]}
      })

      {:ok, view, html} =
        view
        |> form("#segment-form", segment: %{name: "Paying", description: "Pro and Team."})
        |> render_submit()
        |> follow_redirect(conn |> as_admin())

      assert html =~ "“Paying” is saved."
      [segment] = Segments.list()

      assert segment.condition == %{
               "all" => [%{"attribute" => "plan", "op" => "in", "value" => ["pro", "team"]}]
             }

      assert html =~ "Plan is Pro or Team."

      html = view |> form("#segment-form", segment: %{name: "Paid"}) |> render_submit()
      assert html =~ "“Paid” is saved."
      assert Segments.get(segment.id).name == "Paid"

      {:ok, _view, html} =
        view
        |> element("button", "Delete segment")
        |> render_click()
        |> follow_redirect(conn |> as_admin())

      assert html =~ "The segment is deleted."
      assert Segments.list() == []
    end

    test "a name is needed, and the condition must be right", %{conn: conn} do
      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/audience/new")
      view |> element("#segment-condition button", "Add a rule") |> render_click()
      html = view |> form("#segment-form", segment: %{name: "Odd"}) |> render_submit()
      assert html =~ "The segment was not saved"
      assert html =~ "Name needs a value."
      assert Segments.list() == []
    end

    test "is not deleted while a campaign uses it: the page says which", %{conn: conn} do
      {:ok, segment} = Segments.create(%{"name" => "Pro", "condition" => %{"all" => []}})

      {:ok, _} =
        Campaigns.create(%{
          "name" => "Onboarding",
          "kind" => "sequence",
          "audience" => %{"segment" => segment.id, "op" => "in"}
        })

      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/audience/#{segment.id}")
      html = view |> element("button", "Delete segment") |> render_click()
      assert html =~ ~r/The segment is not deleted: Onboarding\s+uses it/
      assert Segments.get(segment.id)
    end
  end

  campaigns_describe "the campaigns" do
    test "the sequences and the broadcasts, with their numbers", %{conn: conn} do
      ada = person!(name: "Ada Lovelace")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada))
      broadcast!(%{"name" => "Spring news"}, "Spring")

      {:ok, view, html} = conn |> as_admin() |> live(@admin <> "/campaigns")
      assert html =~ "Onboarding"
      assert html =~ "Active"
      assert html =~ "Product"
      assert html =~ "Started by hand"
      refute html =~ "Spring news"
      assert [counts] = Map.values(Campaigns.counts([campaign]))
      assert counts.entered == 1

      html = view |> element("a", "Broadcasts") |> render_click()
      assert_patch(view, @admin <> "/campaigns?kind=broadcast")
      assert html =~ "Spring news"
      assert html =~ "Draft"
      refute html =~ "Onboarding"
    end

    test "empty, in the admin's words; read-only, no new ones", %{conn: conn} do
      {:ok, _view, html} = conn |> as_admin() |> live(@admin <> "/campaigns")
      assert html =~ "No sequences yet"
      assert html =~ "New broadcast"

      {:ok, _view, html} =
        conn |> as_admin("viewer") |> live(@admin <> "/campaigns?kind=broadcast")

      assert html =~ "No broadcasts yet"
      refute html =~ "New broadcast"
    end

    test "the archived ones on request", %{conn: conn} do
      campaign = sequence!(%{"name" => "Old one"}, [step(0, "Welcome")])
      {:ok, _} = Campaigns.archive(campaign)

      {:ok, view, html} = conn |> as_admin() |> live(@admin <> "/campaigns")
      refute html =~ "Old one"
      html = view |> element("a", "Show the archived (1)") |> render_click()
      assert html =~ "Old one"
      assert html =~ "Archived"
    end

    test "follow the changes of other admins", %{conn: conn} do
      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/campaigns")
      {:ok, _} = Campaigns.create(%{"name" => "Made elsewhere", "kind" => "sequence"})
      assert render(view) =~ "Made elsewhere"
    end
  end

  campaigns_describe "a sequence" do
    test "is made with its settings, who may enter and its goal", %{conn: conn} do
      {:ok, view, html} = conn |> as_admin() |> live(@admin <> "/campaigns/new?kind=sequence")
      assert html =~ "New sequence"
      assert html =~ "Who may enter"

      html = view |> element("#goal button", "Add a rule") |> render_click()
      [goal] = rules(html, "goal")

      change_builder(view, "goal", %{
        goal => %{"subject" => "attribute:published", "checked" => "true"}
      })

      view |> form("#campaign-form", campaign: %{trigger_type: "event"}) |> render_change()

      {:ok, _view, html} =
        view
        |> form("#campaign-form",
          campaign: %{
            name: "Onboarding",
            purpose: "product",
            trigger_type: "event",
            trigger_event: "signed_up",
            min_gap_hours: "40",
            max_days: "14"
          }
        )
        |> render_submit()
        |> follow_redirect(conn |> as_admin())

      assert html =~ "The sequence is saved."
      [campaign] = Campaigns.list()
      assert campaign.trigger == %{"type" => "event", "event" => "signed_up"}
      assert campaign.goal == %{"all" => [%{"attribute" => "published", "op" => "true"}]}
      assert campaign.audience == nil
      assert campaign.min_gap_hours == 40
      assert campaign.max_days == 14
      assert campaign.author == %{"id" => 7, "name" => "Hanzo"}
    end

    test "its steps: added, edited, in two languages, moved and deleted", %{conn: conn} do
      {:ok, campaign} = Campaigns.create(%{"name" => "Onboarding", "kind" => "sequence"})
      {:ok, view, html} = conn |> as_admin() |> live(@admin <> "/campaigns/#{campaign.id}")
      assert html =~ "No steps yet"

      html = view |> element("button", "Add a step") |> render_click()
      assert html =~ "Step 1 goes after"
      assert html =~ ~s(data-upload=")

      body = Kotoba.Content.from_markdown("Glad you came.")

      html =
        view
        |> form("#step-form")
        |> render_submit(%{
          "step" => %{
            "wait_days" => "0",
            "wait_hours" => "0",
            "letters" => %{
              "0" => %{
                "locale" => "en",
                "subject" => "Welcome",
                "body" => JSON.encode!(body.doc)
              }
            }
          }
        })

      assert html =~ "The step is saved."
      [first] = Campaigns.get(campaign.id).steps
      assert first.wait == 0
      assert [%{subject: "Welcome", text: "Glad you came."}] = first.letters

      # A second step, two days later, skipped for those with a story.
      view |> element("button", "Close") |> render_click()
      view |> element("button", "Add a step") |> render_click()
      html = view |> element("#skip-new button", "Add a rule") |> render_click()
      [skip] = rules(html, "skip-new")

      change_builder(view, "skip-new", %{
        skip => %{"subject" => "attribute:has_story", "checked" => "true"}
      })

      html =
        view
        |> form("#step-form")
        |> render_submit(%{
          "step" => %{
            "wait_days" => "2",
            "wait_hours" => "6",
            "letters" => %{"0" => %{"locale" => "en", "subject" => "Day two"}}
          }
        })

      assert html =~ "The step is saved."
      [_first, second] = Campaigns.get(campaign.id).steps
      assert second.wait == 2 * 1440 + 6 * 60
      assert second.skip_if == %{"all" => [%{"attribute" => "has_story", "op" => "true"}]}

      # The same time as another is refused, in words.
      html =
        view
        |> form("#step-form")
        |> render_submit(%{"step" => %{"wait_days" => "0", "wait_hours" => "0"}})

      assert html =~ "another step goes at this time"

      # Its letter in Portuguese too.
      html = render_click(view, "add_language", %{"locale" => "pt-PT"})
      assert html =~ "Remove the Português letter"

      view
      |> form("#step-form")
      |> render_submit(%{
        "step" => %{
          "wait_days" => "2",
          "wait_hours" => "6",
          "letters" => %{
            "0" => %{"locale" => "en", "subject" => "Day two"},
            "1" => %{"locale" => "pt-PT", "subject" => "Dia dois"}
          }
        }
      })

      second = Campaigns.get_step(second.id)
      assert Enum.map(second.letters, & &1.locale) == ["en", "pt-PT"]

      # Moved up: the letters trade places, the times stay.
      view |> element("button", "Close") |> render_click()
      html = view |> element("button[aria-label='Move step 2 up']") |> render_click()
      assert [a, b] = Campaigns.get(campaign.id).steps
      assert {a.wait, hd(a.letters).subject} == {0, "Day two"}
      assert {b.wait, hd(b.letters).subject} == {2 * 1440 + 6 * 60, "Welcome"}
      assert html =~ "After 2 days 6 hours"

      html = view |> element("button[aria-label='Delete step 2']") |> render_click()
      assert html =~ "The step is deleted."
      assert [_one] = Campaigns.get(campaign.id).steps
    end

    test "starts, pauses, resumes and is archived; refusals in words", %{conn: conn} do
      {:ok, campaign} = Campaigns.create(%{"name" => "Onboarding", "kind" => "sequence"})
      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/campaigns/#{campaign.id}")

      html = view |> element("button", "Start") |> render_click()
      assert html =~ "A sequence needs a step to start: add one."

      {:ok, _} =
        Campaigns.add_step(campaign, %{
          "wait" => 0,
          "letters" => [%{"locale" => "en", "subject" => "Hi"}]
        })

      html = view |> element("button", "Start") |> render_click()

      assert html =~
               "Each step needs a letter in English with a subject and a body: step 1 has not."

      {:ok, _} =
        Campaigns.put_letter(hd(Campaigns.get(campaign.id).steps), "en", %{
          "subject" => "Hi",
          "body" => Kotoba.Content.from_markdown("Hello.")
        })

      html = view |> element("button", "Start") |> render_click()
      assert html =~ "The sequence is started"
      assert Campaigns.get(campaign.id).status == "active"

      html = view |> element("button", "Pause") |> render_click()
      assert html =~ "The sequence is paused"
      assert Campaigns.get(campaign.id).status == "paused"

      html = view |> element("button", "Resume") |> render_click()
      assert html =~ "The sequence goes on"

      html = view |> element("#status button", "Archive") |> render_click()
      assert html =~ "The campaign is archived."

      assert html =~ "An archived campaign does not change." or
               html =~ ~r/<fieldset[^>]*disabled/

      assert Campaigns.get(campaign.id).status == "archived"
      refute has_element?(view, "button", "Add a step")
    end

    test "takes people in, after saying how many", %{conn: conn} do
      person!(name: "Ada Lovelace")
      person!(name: "Grace Hopper")
      campaign = sequence!([step(0, "Welcome")])
      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/campaigns/#{campaign.id}")

      html = view |> form("#enroll-form", segment: "") |> render_submit()
      assert html =~ "2 people may enter now."
      html = view |> element("#confirm button", "Take in 2 people") |> render_click()
      assert html =~ "2 people entered the sequence."
      assert Campaigns.results(campaign).entered == 2
    end

    test "its results, and each step's", %{conn: conn} do
      ada = person!(name: "Ada Lovelace")
      campaign = sequence!([step(0, "Welcome"), step(1440, "Day one")])
      {:ok, _} = Campaigns.enroll(campaign, person_id(ada))
      Tayori.Test.run_campaigns!(DateTime.utc_now())

      {:ok, _view, html} = conn |> as_admin() |> live(@admin <> "/campaigns/#{campaign.id}")
      assert html =~ ~r{<dt>Entered</dt><dd>1</dd>}
      assert html =~ ~r{<dt>In it now</dt><dd>1</dd>}
      assert html =~ "1 sent"
      assert html =~ ~r{<th scope="row">1</th>\s*<td>1</td>}
    end

    test "the preview: a person of the audience, their tags, and a test", %{conn: conn} do
      person!(name: "Ada Lovelace")

      campaign =
        sequence!([
          step(0, "Welcome, {{first_name}}", body: "Hi {{first_name|there}}, {{plan}}.")
        ])

      {:ok, view, _html} =
        conn
        |> with_session(%{"admin" => %{"role" => "admin", "id" => 7, "name" => "Hanzo"}})
        |> live(@admin <> "/campaigns/#{campaign.id}")

      html = view |> element("button", "Preview") |> render_click()
      assert html =~ "Welcome, Ada"
      assert html =~ ~s(sandbox="")
      assert html =~ "srcdoc="
      assert html =~ ~r/has no value for\s+\{\{plan\}\}/

      html = view |> form("#preview-form", person_id: "person:999999") |> render_change()
      assert html =~ "No one in your app has the id “person:999999”."

      view |> form("#preview-form", person_id: "") |> render_change()
      html = view |> form("#test-form", address: "rui@app.test") |> render_submit()
      assert html =~ "A test went to rui@app.test."
      assert_email_sent(subject: "[Test] Welcome, Ada", to: [{"Ada Lovelace", "rui@app.test"}])
      assert Campaigns.results(campaign).steps |> hd() |> Map.get(:sent) == 0
    end

    test "a read-only admin reads it and changes nothing", %{conn: conn} do
      campaign = sequence!([step(0, "Welcome")])

      {:ok, view, html} =
        conn |> as_admin("viewer") |> live(@admin <> "/campaigns/#{campaign.id}")

      assert html =~ ~r/<fieldset[^>]*disabled/
      refute html =~ "Pause"
      refute html =~ "Add a step"
      refute html =~ "Save settings"

      render_click(view, "status", %{"to" => "pause"})
      render_submit(view, "save", %{"campaign" => %{"name" => "Changed"}})
      render_click(view, "new_step", %{})
      assert Campaigns.get(campaign.id).status == "active"
      assert Campaigns.get(campaign.id).name == "Onboarding"

      html = view |> element("button[aria-label='Read step 1']") |> render_click()
      refute html =~ ~s(data-upload=")
      refute html =~ "Save step"
    end

    test "follows the changes of other admins", %{conn: conn} do
      campaign = sequence!([step(0, "Welcome")])
      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/campaigns/#{campaign.id}")
      {:ok, _} = Campaigns.add_step(campaign, step(1440, "Added elsewhere"))
      assert render(view) =~ "Added elsewhere"
      {:ok, _} = Campaigns.pause(campaign)
      assert render(view) =~ "Resume"
    end

    test "an unknown campaign is a 404", %{conn: conn} do
      for id <- ["nope", Ecto.UUID.generate()] do
        assert_raise Tayori.Admin.NotFound, fn ->
          conn |> as_admin() |> live(@admin <> "/campaigns/#{id}")
        end
      end
    end
  end

  campaigns_describe "a broadcast" do
    test "is made with its one letter, then scheduled, cancelled and sent, after the count",
         %{conn: conn} do
      person!(name: "Ada Lovelace", plan: "pro")
      person!(name: "Grace Hopper", plan: "free")
      {:ok, view, html} = conn |> as_admin() |> live(@admin <> "/campaigns/new?kind=broadcast")
      assert html =~ "Who gets it"

      html = view |> element("#audience button", "Add a rule") |> render_click()
      [rule] = rules(html, "audience")

      change_builder(view, "audience", %{
        rule => %{"subject" => "attribute:plan", "op" => "in", "value" => ["pro"]}
      })

      assert render_async(view) =~ "1 person"

      {:ok, view, html} =
        view
        |> form("#campaign-form", campaign: %{name: "Spring", purpose: "marketing"})
        |> render_submit()
        |> follow_redirect(conn |> as_admin())

      assert html =~ "The broadcast is saved."
      [campaign] = Campaigns.list()
      assert campaign.purpose == "marketing"
      assert html =~ "The letter"
      refute html =~ "Add a step"

      # Its letter first.
      html = view |> element("button", "Send now") |> render_click()
      assert html =~ "It goes now to the 1 person of its audience"
      html = view |> element("#confirm button", "Send to 1 person") |> render_click()
      assert html =~ "The letter needs a subject and a body in English first."

      body = Kotoba.Content.from_markdown("The spring is here.")

      html =
        view
        |> form("#step-form")
        |> render_submit(%{
          "step" => %{
            "letters" => %{
              "0" => %{
                "locale" => "en",
                "subject" => "Spring",
                "body" => JSON.encode!(body.doc)
              }
            }
          }
        })

      assert html =~ "The letter is saved."

      at = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

      html =
        view
        |> form("#schedule-form", schedule: %{at: DateTime.to_iso8601(at)})
        |> render_submit()

      assert html =~ "1 person today."
      html = view |> element("#confirm button", "Schedule it") |> render_click()
      assert html =~ "The broadcast is scheduled."
      assert %{status: "scheduled", send_at: send_at} = Campaigns.get(campaign.id)
      assert DateTime.compare(send_at, at) == :eq

      html = view |> element("button", "Cancel the schedule") |> render_click()
      assert html =~ "The broadcast is a draft again"
      assert Campaigns.get(campaign.id).status == "draft"

      view |> element("button", "Send now") |> render_click()
      html = view |> element("button", "Not now") |> render_click()
      refute html =~ ~s(id="confirm")

      view |> element("button", "Send now") |> render_click()
      html = view |> element("#confirm button", "Send to 1 person") |> render_click()
      assert html =~ "The broadcast is on its way."
      assert Campaigns.get(campaign.id).status in ["scheduled", "sending", "sent"]
    end

    test "a time that has passed is refused", %{conn: conn} do
      campaign = broadcast!("Spring")
      {:ok, view, _html} = conn |> as_admin() |> live(@admin <> "/campaigns/#{campaign.id}")
      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_iso8601()
      html = view |> form("#schedule-form", schedule: %{at: past}) |> render_submit()
      assert html =~ "That time has passed"
      assert Campaigns.get(campaign.id).status == "draft"
    end

    test "its results, once sent", %{conn: conn} do
      person!(name: "Ada Lovelace")
      campaign = broadcast!("Spring")
      {:ok, _} = Campaigns.send_broadcast_now(campaign)
      Tayori.Test.run_campaigns!(DateTime.add(DateTime.utc_now(), 1))

      {:ok, _view, html} = conn |> as_admin() |> live(@admin <> "/campaigns/#{campaign.id}")
      assert html =~ ~r{<dt>Recipients</dt><dd>1</dd>}
      assert html =~ ~r{<dt>Sent</dt><dd>1</dd>}
      assert html =~ "Sent"
      refute html =~ "Send now"
    end
  end

  campaigns_describe "the settings" do
    test "the modules on, and the providers' webhook addresses", %{conn: conn, config: config} do
      put_config(config,
        campaigns: [
          audience: TayoriTest.Audience,
          url: "https://app.test/letters",
          from: {"Rui at the app", "rui@app.test"},
          providers: [resend: [secret: TayoriTest.Signing.resend_secret()]]
        ]
      )

      {:ok, _view, html} = conn |> as_admin() |> live(@admin <> "/settings")
      assert html =~ ~s(id="modules")
      assert html =~ ~s(id="campaigns")
      assert html =~ "https://app.test/letters/webhooks/resend"
      assert html =~ "Rui at the app &lt;rui@app.test&gt;"
      assert html =~ ~s(id="ai")
    end

    test "without the changelog, only what the campaigns need", %{conn: conn, config: config} do
      put_config(config, modules: [:campaigns])
      {:ok, _view, html} = conn |> as_admin() |> live(@admin <> "/settings")
      assert html =~ ~s(id="campaigns")
      assert html =~ "No provider yet."

      for id <- ~w(ai automation audiences features email integrations embed) do
        refute html =~ ~s(id="#{id}"), id
      end

      on =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#modules .ta-features li")
        |> Enum.map(fn li ->
          {li |> LazyHTML.query("strong") |> LazyHTML.text(),
           li |> LazyHTML.query(".ta-badge") |> LazyHTML.text() |> String.trim()}
        end)

      assert on == [{"Changelog", "Off"}, {"Campaigns", "On"}]
    end
  end
end
