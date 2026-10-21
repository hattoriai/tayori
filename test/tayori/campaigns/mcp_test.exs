if Code.ensure_loaded?(Sake.Server) do
  defmodule Tayori.Campaigns.MCPTest do
    use TayoriTest.DataCase

    import Sake.Test
    import Swoosh.TestAssertions

    alias Tayori.Campaigns
    alias Tayori.Campaigns.Segments

    @news ["tayori:read", "tayori:write"]
    @campaigns ["tayori:campaigns:read", "tayori:campaigns:write", "tayori:campaigns:send"]
    @all @news ++ @campaigns
    @admin %{"role" => "admin", "id" => 7, "name" => "Hanzo"}
    @viewer %{"role" => "viewer", "id" => 8, "name" => "Kiku"}

    @read_tools ~w(list_audience preview_segment list_campaigns get_campaign preview_letter)
    @write_tools ~w(save_segment create_campaign update_campaign add_step update_step
                    remove_step send_test_letter pause_campaign)
    @send_tools ~w(start_campaign enroll_people send_broadcast)
    @campaign_tools @read_tools ++ @write_tools ++ @send_tools

    @pro %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}

    defp mcp(%{config: config}),
      do: {:ok, config: put_config(config, mcp: [resolver: TayoriTest.Resolver])}

    defp client(scopes \\ @all, principal \\ @admin),
      do: connect(Tayori.MCP, scope: principal, scopes: scopes)

    defp names(client) do
      assert {:ok, tools} = list_tools(client)
      Enum.map(tools, & &1.name)
    end

    defp call!(tool, args, client \\ client()) do
      assert {:ok, %{is_error: false, structured: structured}} = call_tool(client, tool, args)
      structured
    end

    defp tool_error(tool, args) do
      assert {:ok, %{is_error: true, text: text}} = call_tool(client(), tool, args)
      text
    end

    test "the scopes, and the instructions of both modules" do
      scopes = Tayori.MCP.__sake__(:scopes) |> Enum.map(&elem(&1, 0))
      assert scopes == @all

      instructions = Tayori.MCP.__sake__(:instructions)
      assert instructions =~ "publish_entry"
      assert instructions =~ "When this app has campaigns"
      assert instructions =~ "list_audience"
      assert instructions =~ "only when\n   the person asks you to"
      assert instructions =~ "how many people it reaches"
    end

    for_each_repo do
      setup [:campaigns, :mcp]

      test "lists the campaigns' tools with the changelog's, each with its hints" do
        assert {:ok, tools} = list_tools(client())
        names = Enum.map(tools, & &1.name)
        assert Enum.take(names, -length(@campaign_tools)) == @campaign_tools
        assert "publish_entry" in names

        hints = Map.new(tools, &{&1.name, &1.annotations})

        for tool <- @read_tools do
          assert hints[tool]["readOnlyHint"] == true
          assert hints[tool]["openWorldHint"] == false
        end

        for tool <- @send_tools do
          assert hints[tool]["readOnlyHint"] == false
          assert hints[tool]["destructiveHint"] == true
          assert hints[tool]["openWorldHint"] == true
        end

        assert hints["send_test_letter"]["openWorldHint"] == true
        assert hints["create_campaign"]["destructiveHint"] == false
        assert hints["update_step"]["idempotentHint"] == true
      end

      test "with the changelog off, only the campaigns' tools", %{config: config} do
        put_config(config, modules: [:campaigns])
        assert names(client()) == @campaign_tools
      end

      test "with the campaigns off, none of theirs, whatever the token", %{config: config} do
        put_config(config, modules: [:changelog])
        names = names(client())
        assert "list_entries" in names
        assert Enum.all?(@campaign_tools, &(&1 not in names))
      end

      test "each scope its tools" do
        assert names(client(["tayori:campaigns:read"])) == @read_tools

        assert names(client(["tayori:campaigns:read", "tayori:campaigns:write"])) ==
                 @read_tools ++ @write_tools

        assert {:error, {:insufficient_scope, %{scope: ["tayori:campaigns:send"]}}} =
                 call_tool(client(["tayori:campaigns:write"]), "start_campaign", %{"id" => "x"})
      end

      test "a principal the resolver gives read only reads, whatever its token holds" do
        names = names(client(@all, @viewer))
        assert Enum.all?(@read_tools, &(&1 in names))
        assert "get_entry" in names
        assert Enum.all?(@write_tools ++ @send_tools, &(&1 not in names))
        assert {:error, _} = call_tool(client(@all, @viewer), "send_broadcast", %{"id" => "x"})
      end

      test "lists the audience: its attributes, events and segments, with counts" do
        person!(plan: "pro")
        person!(name: "Grace Hopper", plan: "free")
        {:ok, _} = Segments.create(%{"name" => "Pro", "condition" => @pro})

        audience = call!("list_audience", %{})

        plan = Enum.find(audience["attributes"], &(&1["key"] == "plan"))
        assert plan["type"] == "enum"
        assert plan["operators"] == ["in", "not_in"]
        assert %{"value" => "pro", "label" => "Pro"} in plan["values"]

        visits = Enum.find(audience["attributes"], &(&1["key"] == "visits"))
        assert "gte" in visits["operators"]
        refute Map.has_key?(visits, "values")

        assert %{"name" => "signed_up", "label" => "Signed up"} in audience["events"]
        assert audience["events_in_conditions"] == true
        assert audience["event_operators"] == ["happened", "not_happened"]

        assert [%{"name" => "Pro", "count" => 1, "sentence" => "Plan is Pro"}] =
                 audience["segments"]

        assert audience["limits"] == %{"depth" => 5, "leaves" => 50}
      end

      test "previews a condition or a segment, and says what is wrong with one" do
        ada = person!(plan: "pro")
        person!(name: "Grace Hopper", plan: "free")

        assert %{"count" => 1, "sentence" => "Plan is Pro", "people" => [person]} =
                 call!("preview_segment", %{"condition" => @pro})

        assert person == %{
                 "id" => person_id(ada),
                 "name" => "Ada Lovelace",
                 "email" => "ada@app.test",
                 "locale" => "en"
               }

        {:ok, segment} = Segments.create(%{"name" => "Pro", "condition" => @pro})

        assert %{"count" => 1, "segment" => %{"name" => "Pro"}} =
                 call!("preview_segment", %{"segment_id" => segment.id})

        assert %{"count" => 2, "sentence" => "Everyone"} =
                 call!("preview_segment", %{"condition" => %{"all" => []}})

        error =
          tool_error("preview_segment", %{
            "condition" => %{
              "all" => [
                %{"attribute" => "plan", "op" => "gt", "value" => 1},
                %{"attribute" => "mood", "op" => "eq", "value" => "x"}
              ]
            }
          })

        assert error =~ "The condition is not a condition Tayori can run"
        assert error =~ ~s(Unknown attribute "mood".)
        assert error =~ "list_audience"

        assert tool_error("preview_segment", %{"condition" => "plan is pro"}) =~
                 "must be a JSON object"

        assert tool_error("preview_segment", %{}) =~ "Give a condition"

        assert tool_error("preview_segment", %{"segment_id" => Ecto.UUID.generate()}) =~
                 "No segment with the id"

        assert tool_error("preview_segment", %{"condition" => @pro, "segment_id" => segment.id}) =~
                 "not both"
      end

      test "saves a segment, and changes it" do
        person!(plan: "pro")

        segment =
          call!("save_segment", %{
            "name" => "Pro",
            "description" => "Who pays",
            "condition" => @pro
          })

        assert %{"id" => id, "name" => "Pro", "count" => 1, "sentence" => "Plan is Pro"} =
                 segment

        changed =
          call!("save_segment", %{
            "id" => id,
            "name" => "Not Pro",
            "condition" => %{"not" => @pro}
          })

        assert %{"id" => ^id, "name" => "Not Pro", "description" => "Who pays", "count" => 0} =
                 changed

        assert Segments.get(id).name == "Not Pro"

        assert tool_error("save_segment", %{"name" => "X"}) =~ "needs a condition"
        assert tool_error("save_segment", %{"condition" => @pro}) =~ "needs a name"
        assert tool_error("save_segment", %{"id" => id}) =~ "Nothing to change"

        assert tool_error("save_segment", %{
                 "name" => "Bad",
                 "condition" => %{"attribute" => "plan", "op" => "in", "value" => ["gold"]}
               }) =~ "The condition is not a condition Tayori can run"

        # A segment that leads back to itself.
        assert tool_error("save_segment", %{
                 "id" => id,
                 "condition" => %{"segment" => id, "op" => "in"}
               }) =~ "condition"
      end

      test "creates a sequence by its writer, and changes its settings" do
        campaign =
          call!("create_campaign", %{
            "name" => "Onboarding",
            "kind" => "sequence",
            "trigger_event" => "signed_up",
            "goal" => %{"attribute" => "published", "op" => "true"},
            "min_gap_hours" => 40,
            "max_days" => 14
          })

        assert %{
                 "id" => id,
                 "kind" => "sequence",
                 "status" => "draft",
                 "purpose" => "product",
                 "trigger" => %{"type" => "event", "event" => "signed_up"},
                 "goal" => %{"sentence" => "Published a story"},
                 "audience" => %{"sentence" => "Everyone", "count" => 0},
                 "min_gap_hours" => 40,
                 "max_days" => 14,
                 "author" => %{"name" => "Hanzo"},
                 "steps" => [],
                 "problems" => ["It has no steps: add one with add_step."]
               } = campaign

        changed =
          call!("update_campaign", %{
            "id" => id,
            "trigger_event" => "",
            "goal" => %{},
            "max_days" => 0,
            "audience" => @pro,
            "purpose" => "marketing"
          })

        assert %{
                 "trigger" => %{"type" => "manual"},
                 "goal" => nil,
                 "max_days" => nil,
                 "purpose" => "marketing",
                 "audience" => %{"sentence" => "Plan is Pro"}
               } = changed

        assert tool_error("update_campaign", %{"id" => id}) =~ "Nothing to change"

        assert tool_error("update_campaign", %{"id" => id, "goal" => %{"attribute" => "x"}}) =~
                 "The goal is not a condition"

        assert tool_error("update_campaign", %{"id" => id, "reply_to" => "nope"}) =~
                 "reply_to must be an address"

        assert tool_error("update_campaign", %{"id" => Ecto.UUID.generate(), "name" => "X"}) =~
                 "No campaign with the id"

        assert tool_error("create_campaign", %{
                 "name" => "News",
                 "kind" => "broadcast",
                 "trigger_event" => "signed_up"
               }) =~ "trigger is only for a sequence"
      end

      test "lists the campaigns, and gets one whole" do
        sequence!([step(0, "Welcome")])
        broadcast!("Autumn news")

        assert %{"campaigns" => [broadcast, sequence]} = call!("list_campaigns", %{})
        assert %{"kind" => "broadcast", "status" => "draft", "steps" => 1} = broadcast
        assert %{"kind" => "sequence", "status" => "active", "steps" => 1} = sequence

        assert %{"campaigns" => [%{"kind" => "sequence"}]} =
                 call!("list_campaigns", %{"kind" => "sequence"})

        {:ok, _} = Campaigns.archive(Campaigns.get(sequence["id"]))
        assert %{"campaigns" => [_]} = call!("list_campaigns", %{})
        assert %{"campaigns" => [_, _]} = call!("list_campaigns", %{"archived" => true})

        detail = call!("get_campaign", %{"id" => broadcast["id"]})

        assert %{
                 "steps" => [%{"after" => "at entry", "letters" => [letter]}],
                 "results" => %{"recipients" => 0},
                 "problems" => []
               } = detail

        assert %{"locale" => "en", "subject" => "Autumn news", "complete" => true} = letter
        assert letter["body"] =~ "About Autumn news."

        assert tool_error("get_campaign", %{"id" => "nope"}) =~ ~s(No campaign with the id "nope")
      end

      test "adds steps with their letters in Markdown, changes and removes them" do
        %{"id" => id} = call!("create_campaign", %{"name" => "Onboarding", "kind" => "sequence"})

        step =
          call!("add_step", %{
            "campaign_id" => id,
            "after_days" => 2,
            "after_hours" => 4,
            "skip_if" => %{"attribute" => "has_photos", "op" => "true"},
            "subject" => "Your photographs, {{first_name|there}}",
            "body" => "## Start\n\n- Open the **library**",
            "cta_label" => "Open it",
            "cta_url" => "https://app.test/library"
          })

        assert %{
                 "id" => step_id,
                 "wait_minutes" => 3120,
                 "after" => "2 days 4 hours after entry",
                 "skip_if" => %{"sentence" => "Has photos"},
                 "letters" => [letter],
                 "missing_locales" => ["pt-PT"]
               } = step

        assert letter["body"] =~ "## Start"
        assert letter["body"] =~ "**library**"
        assert letter["cta_url"] == "https://app.test/library"

        # Stored as Kotoba content.
        [stored] = Campaigns.get_step(step_id).letters
        assert stored.body.html =~ "<strong>library</strong>"

        assert tool_error("add_step", %{"campaign_id" => id, "after_hours" => 52}) =~
                 "another step goes at this time"

        assert tool_error("add_step", %{"campaign_id" => id, "body" => "Hi"}) =~
                 "A letter needs a subject"

        assert tool_error("add_step", %{"campaign_id" => id, "locale" => "fr"}) =~
                 ~s(Unknown language "fr")

        assert tool_error("add_step", %{"campaign_id" => id, "skip_if" => %{"not" => 1}}) =~
                 "The skip_if is not a condition"

        changed =
          call!("update_step", %{
            "step_id" => step_id,
            "after_days" => 3,
            "skip_if" => %{},
            "locale" => "pt-PT",
            "subject" => "As suas fotografias",
            "body" => "Olá."
          })

        assert %{"after" => "3 days after entry", "skip_if" => nil, "missing_locales" => []} =
                 changed

        assert [%{"locale" => "en", "subject" => "Your photographs" <> _}, pt] =
                 changed["letters"]

        assert %{"locale" => "pt-PT", "subject" => "As suas fotografias"} = pt

        changed =
          call!("update_step", %{"step_id" => step_id, "cta_label" => "", "cta_url" => ""})

        assert [%{"cta_label" => nil, "cta_url" => nil}, _] = changed["letters"]

        assert tool_error("update_step", %{"step_id" => step_id}) =~ "Nothing to change"

        assert tool_error("update_step", %{
                 "step_id" => step_id,
                 "locale" => "pt-PT",
                 "body" => "| a |\n|---|\n| b |"
               }) =~ "body"

        assert tool_error("update_step", %{"step_id" => Ecto.UUID.generate(), "subject" => "X"}) =~
                 "No step with the id"

        assert %{"steps" => []} = call!("remove_step", %{"step_id" => step_id})
        assert tool_error("remove_step", %{"step_id" => step_id}) =~ "No step with the id"
      end

      test "a broadcast's one letter is written with update_step, and is not removed" do
        %{"id" => id, "steps" => [%{"id" => step_id, "letters" => []}]} =
          call!("create_campaign", %{"name" => "News", "kind" => "broadcast"})

        assert %{"letters" => [%{"subject" => "Autumn", "complete" => false}]} =
                 call!("update_step", %{"step_id" => step_id, "subject" => "Autumn"})

        assert %{"letters" => [%{"complete" => true}]} =
                 call!("update_step", %{"step_id" => step_id, "body" => "The news."})

        assert tool_error("update_step", %{"step_id" => step_id, "after_days" => 1}) =~
                 "has no time after entry"

        assert tool_error("add_step", %{"campaign_id" => id, "subject" => "X"}) =~
                 "A broadcast has one step"

        assert tool_error("remove_step", %{"step_id" => step_id}) =~ "A broadcast has one step"
      end

      test "previews a letter as a person gets it" do
        ada = person!(plan: "pro")
        nobody = person!(name: "Nemo", email: nil)

        campaign =
          broadcast!(%{"audience" => @pro}, "Hello {{first_name|there}}, {{nickname}}")

        preview = call!("preview_letter", %{"campaign_id" => campaign.id})

        assert %{
                 "person" => %{"id" => person_id, "name" => "Ada Lovelace"},
                 "locale" => "en",
                 "subject" => "Hello Ada, ",
                 "missing_tags" => ["nickname"]
               } = preview

        assert person_id == person_id(ada)
        assert preview["text"] =~ "About Hello"
        assert preview["text"] =~ "https://app.test/letters/unsubscribe/"

        assert tool_error("preview_letter", %{
                 "campaign_id" => campaign.id,
                 "person_id" => person_id(nobody)
               }) =~ "has no email address"

        assert tool_error("preview_letter", %{
                 "campaign_id" => campaign.id,
                 "person_id" => "person:0"
               }) =~ "No person with the id"

        sequence = sequence!([step(0, "One"), step(60, "Two")])

        assert tool_error("preview_letter", %{"campaign_id" => sequence.id}) =~
                 "give the step_id"

        [_, two] = sequence.steps

        assert %{"subject" => "Two"} =
                 call!("preview_letter", %{
                   "campaign_id" => sequence.id,
                   "step_id" => two.id,
                   "person_id" => person_id(ada)
                 })
      end

      test "sends a test letter to an address, and to no one else" do
        ada = person!(plan: "pro")
        campaign = broadcast!("Hello {{first_name|there}}")

        assert %{"sent_to" => "rui@app.test", "subject" => "[Test] Hello {{first_name|there}}"} =
                 call!("send_test_letter", %{
                   "campaign_id" => campaign.id,
                   "to" => "rui@app.test",
                   "person_id" => person_id(ada)
                 })

        assert_email_sent(subject: "[Test] Hello Ada", to: [{"Ada Lovelace", "rui@app.test"}])
        assert deliveries(campaign) == []

        # The writer of the tests has no address.
        assert tool_error("send_test_letter", %{"campaign_id" => campaign.id}) =~
                 "Give the address"

        assert tool_error("send_test_letter", %{"campaign_id" => campaign.id, "to" => "rui"}) =~
                 "is not an email address"

        {:ok, empty} = Campaigns.create(%{"name" => "Empty", "kind" => "broadcast"})

        assert tool_error("send_test_letter", %{"campaign_id" => empty.id, "to" => "a@b.test"}) =~
                 "has no letter yet"

        refute_email_sent()
      end

      test "starts a sequence only when complete, pauses and resumes it" do
        %{"id" => id} = call!("create_campaign", %{"name" => "Onboarding", "kind" => "sequence"})

        assert tool_error("start_campaign", %{"id" => id}) =~ "The sequence has no steps"

        %{"id" => step_id} =
          call!("add_step", %{"campaign_id" => id, "subject" => "Welcome"})

        error = tool_error("start_campaign", %{"id" => id})
        assert error =~ "needs a letter in en with a subject and a body"
        assert error =~ step_id

        assert [problem] = call!("get_campaign", %{"id" => id})["problems"]
        assert problem =~ step_id

        call!("update_step", %{"step_id" => step_id, "body" => "Glad you came."})

        assert %{"status" => "active", "problems" => []} =
                 call!("start_campaign", %{"id" => id})

        assert tool_error("start_campaign", %{"id" => id}) =~ "active already"
        assert %{"status" => "paused"} = call!("pause_campaign", %{"id" => id})
        assert tool_error("pause_campaign", %{"id" => id}) =~ "only an active one pauses"
        assert %{"status" => "active"} = call!("start_campaign", %{"id" => id})

        {:ok, _} = Campaigns.archive(Campaigns.get(id))

        assert tool_error("update_step", %{"step_id" => step_id, "subject" => "X"}) =~
                 "The campaign is locked"

        assert tool_error("update_campaign", %{"id" => id, "name" => "X"}) =~
                 "The campaign is locked"

        assert tool_error("start_campaign", %{"id" => id}) =~ "archived"

        broadcast = broadcast!("News")

        assert tool_error("start_campaign", %{"id" => broadcast.id}) =~
                 "send it with send_broadcast"
      end

      test "takes people into a sequence by their ids, once each" do
        ada = person!(plan: "pro")
        grace = person!(name: "Grace Hopper", plan: "free")

        draft =
          sequence!(%{"name" => "Pro tips", "audience" => @pro}, [step(0, "Hello")])

        {:ok, paused} = Campaigns.pause(draft)

        assert tool_error("enroll_people", %{
                 "campaign_id" => paused.id,
                 "person_ids" => [person_id(ada)]
               }) =~ "The sequence is paused"

        {:ok, campaign} = Campaigns.resume(Campaigns.get(paused.id))

        result =
          call!("enroll_people", %{
            "campaign_id" => campaign.id,
            "person_ids" => [person_id(ada), person_id(grace), "person:0", person_id(ada)]
          })

        assert result["entered"] == 1
        assert result["campaign"]["id"] == campaign.id

        assert [
                 %{"person_id" => grace_id, "reason" => "Not in the sequence's audience."},
                 %{"person_id" => "person:0", "reason" => "No one in the app has this id."}
               ] = result["not_entered"]

        assert grace_id == person_id(grace)
        assert %{state: "active"} = enrollment(campaign, ada)

        assert %{"entered" => 0, "not_entered" => [%{"reason" => reason}]} =
                 call!("enroll_people", %{
                   "campaign_id" => campaign.id,
                   "person_ids" => [person_id(ada)]
                 })

        assert reason =~ "enters once"

        assert tool_error("enroll_people", %{"campaign_id" => campaign.id}) =~
                 "person_ids, a condition or a segment_id"

        assert tool_error("enroll_people", %{
                 "campaign_id" => campaign.id,
                 "person_ids" => [person_id(ada)],
                 "segment_id" => "x"
               }) =~ "one of them"

        assert tool_error("enroll_people", %{
                 "campaign_id" => campaign.id,
                 "person_ids" => Enum.map(1..501, &"person:#{&1}")
               }) =~ "500 at most"

        broadcast = broadcast!("News")

        assert tool_error("enroll_people", %{
                 "campaign_id" => broadcast.id,
                 "person_ids" => [person_id(ada)]
               }) =~ "This is a broadcast"
      end

      test "takes in a condition or a segment only at the count expected" do
        ada = person!(plan: "pro")
        grace = person!(name: "Grace Hopper", plan: "pro")
        person!(name: "Linus Torvalds", plan: "free")
        {:ok, segment} = Segments.create(%{"name" => "Pro", "condition" => @pro})

        # Grace is in the sequence before: of those on Pro, only Ada may enter.
        campaign = sequence!(%{"name" => "Tips"}, [step(0, "Hello")])
        {:ok, _} = Campaigns.enroll(campaign, person_id(grace))

        assert tool_error("enroll_people", %{"campaign_id" => campaign.id, "condition" => @pro}) =~
                 "Give expected_people: 1 person would enter now"

        error =
          tool_error("enroll_people", %{
            "campaign_id" => campaign.id,
            "condition" => @pro,
            "expected_people" => 2
          })

        assert error =~ "1 person would enter now, not 2: no one entered"
        assert enrollment(campaign, ada) == nil

        assert %{"entered" => 1, "not_entered" => []} =
                 call!("enroll_people", %{
                   "campaign_id" => campaign.id,
                   "condition" => @pro,
                   "expected_people" => 1
                 })

        assert %{state: "active"} = enrollment(campaign, ada)

        # A segment: those in it, less those in the sequence, that is no one now.
        assert %{"entered" => 0} =
                 call!("enroll_people", %{
                   "campaign_id" => campaign.id,
                   "segment_id" => segment.id,
                   "expected_people" => 0
                 })

        assert tool_error("enroll_people", %{
                 "campaign_id" => campaign.id,
                 "segment_id" => segment.id,
                 "condition" => @pro,
                 "expected_people" => 0
               }) =~ "not both"

        assert tool_error("enroll_people", %{
                 "campaign_id" => campaign.id,
                 "condition" => %{"attribute" => "nope", "op" => "true"},
                 "expected_people" => 0
               }) =~ "nope"
      end

      test "sends a broadcast only to the count expected, now" do
        person!(plan: "pro")
        person!(name: "Grace Hopper", plan: "pro")
        person!(name: "Linus Torvalds", plan: "free")
        campaign = broadcast!(%{"audience" => @pro}, "Autumn news")

        error =
          tool_error("send_broadcast", %{"id" => campaign.id, "expected_recipients" => 3})

        assert error =~ "The audience has 2 people now, not 3: nothing was sent."
        assert error =~ "expected_recipients 2"
        assert Campaigns.get(campaign.id).status == "draft"

        assert %{"status" => "scheduled", "recipients" => 2} =
                 call!("send_broadcast", %{"id" => campaign.id, "expected_recipients" => 2})

        Tayori.Test.run_campaigns!(DateTime.add(DateTime.utc_now(), 5))
        assert Campaigns.get(campaign.id).status == "sent"
        assert length(deliveries(campaign)) == 2

        assert tool_error("send_broadcast", %{"id" => campaign.id, "expected_recipients" => 2}) =~
                 "The broadcast is sent"

        assert tool_error("update_step", %{
                 "step_id" => hd(campaign.steps).id,
                 "subject" => "X"
               }) =~ "The campaign is locked"

        sequence = sequence!([step(0, "One")])

        assert tool_error("send_broadcast", %{"id" => sequence.id, "expected_recipients" => 0}) =~
                 "start it with start_campaign"
      end

      test "schedules a broadcast at a time, and takes the schedule back" do
        person!(plan: "pro")
        campaign = broadcast!("Autumn news")
        at = minutes(60) |> DateTime.truncate(:second)

        assert %{"status" => "scheduled", "send_at" => send_at, "recipients" => 1} =
                 call!("send_broadcast", %{
                   "id" => campaign.id,
                   "expected_recipients" => 1,
                   "at" => DateTime.to_iso8601(at)
                 })

        {:ok, send_at, 0} = DateTime.from_iso8601(send_at)
        assert DateTime.truncate(send_at, :second) == at

        Tayori.Test.run_campaigns!(DateTime.utc_now())
        assert Campaigns.get(campaign.id).status == "scheduled"

        assert %{"status" => "draft", "send_at" => nil} =
                 call!("pause_campaign", %{"id" => campaign.id})

        assert tool_error("pause_campaign", %{"id" => campaign.id}) =~
                 "only a scheduled one can be stopped"

        assert tool_error("send_broadcast", %{
                 "id" => campaign.id,
                 "expected_recipients" => 1,
                 "at" => "soon"
               }) =~ "is not a time"

        {:ok, empty} = Campaigns.create(%{"name" => "Empty", "kind" => "broadcast"})

        assert tool_error("send_broadcast", %{"id" => empty.id, "expected_recipients" => 1}) =~
                 "needs a letter in en"
      end
    end
  end
end
