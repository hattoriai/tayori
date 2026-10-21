defmodule Tayori.ConditionsTest do
  use TayoriTest.DataCase

  import ExUnit.CaptureLog

  alias Tayori.{Audience, Conditions}
  alias Tayori.Campaigns.{Segment, Segments}

  defp attributes, do: TayoriTest.Audience.attributes()

  defp days_ago(n), do: DateTime.add(DateTime.utc_now(), -n, :day)

  # Ada: Pro, ten visits, two photos and a published story, ten days a
  # person. Bob: Free, an odd address, a draft, two days. Cleo: no email,
  # no plan, just now. Dan closed his account: he is never in.
  defp people(_ctx) do
    ada =
      person!(%{
        name: "Ada Lovelace",
        plan: "pro",
        visits: 10,
        born_on: ~D[1990-05-01],
        inserted_at: days_ago(10)
      })

    bob =
      person!(%{
        name: "Bob Bar",
        email: "B_o%b@app.test",
        plan: "free",
        optional_emails: false,
        inserted_at: days_ago(2)
      })

    cleo = person!(%{name: "Cleo", email: nil, visits: 0, born_on: ~D[2001-01-01]})
    person!(%{name: "Dan Closed", plan: "pro", closed_at: days_ago(1)})

    photo!(ada)
    photo!(ada)
    story!(ada, days_ago(1))
    story!(bob)

    {:ok, ada: ada, bob: bob, cleo: cleo}
  end

  # The names of who matches, checked first.
  defp names(condition) do
    {:ok, condition} = Conditions.validate(condition, attributes())

    condition
    |> Audience.sample(50)
    |> Enum.map(&(&1.name |> String.split() |> hd()))
  end

  defp leaf(attribute, op, value \\ nil) do
    leaf = %{"attribute" => attribute, "op" => op}
    if value == nil, do: leaf, else: Map.put(leaf, "value", value)
  end

  defp errors(condition, opts \\ []) do
    assert {:error, errors} = Conditions.validate(condition, attributes(), opts)
    errors
  end

  for_each_repo do
    setup [:campaigns, :people]

    test "strings: compared without case, the patterns taken as text" do
      assert names(leaf("name", "eq", "ada LOVELACE")) == ["Ada"]
      assert names(leaf("name", "neq", "ADA lovelace")) == ["Bob", "Cleo"]
      assert names(leaf("email", "contains", "_o%")) == ["Bob"]
      assert names(leaf("email", "contains", "O%B")) == ["Bob"]
      assert names(leaf("email", "contains", "%")) == ["Bob"]
      assert names(leaf("email", "contains", "a_a")) == []
      assert names(leaf("email", "contains", "@APP.")) == ["Ada", "Bob"]
      assert names(leaf("name", "starts_with", "c")) == ["Cleo"]
      assert names(leaf("name", "starts_with", "lovelace")) == []
      assert names(leaf("email", "set")) == ["Ada", "Bob"]
      assert names(leaf("email", "not_set")) == ["Cleo"]
      # A person with no value is not equal to any value.
      assert names(leaf("email", "neq", "ada@app.test")) == ["Bob", "Cleo"]
    end

    test "integers, a column and a count" do
      assert names(leaf("visits", "eq", 10)) == ["Ada"]
      assert names(leaf("visits", "neq", 10)) == ["Bob", "Cleo"]
      assert names(leaf("visits", "gt", 0)) == ["Ada"]
      assert names(leaf("visits", "gte", 0)) == ["Ada", "Cleo"]
      assert names(leaf("visits", "lt", 10)) == ["Cleo"]
      assert names(leaf("visits", "lte", 10)) == ["Ada", "Cleo"]
      assert names(leaf("visits", "set")) == ["Ada", "Cleo"]
      assert names(leaf("visits", "not_set")) == ["Bob"]

      # A correlated scalar subquery, on both databases.
      assert names(leaf("photos", "gte", 2)) == ["Ada"]
      assert names(leaf("photos", "eq", 0)) == ["Bob", "Cleo"]
      assert names(leaf("photos", "lt", "2")) == ["Bob", "Cleo"]
    end

    test "booleans: a column and exists" do
      assert names(leaf("has_photos", "true")) == ["Ada"]
      assert names(leaf("has_photos", "false")) == ["Bob", "Cleo"]
      assert names(leaf("has_story", "true")) == ["Ada", "Bob"]
      assert names(leaf("published", "true")) == ["Ada"]
      assert names(leaf("published", "false")) == ["Bob", "Cleo"]
      assert names(leaf("optional_emails", "true")) == ["Ada", "Cleo"]
      assert names(leaf("optional_emails", "false")) == ["Bob"]
    end

    test "times: before and after a date or a time, days ago" do
      today = Date.utc_today()
      assert names(leaf("signed_up_at", "more_than_days_ago", 5)) == ["Ada"]
      assert names(leaf("signed_up_at", "less_than_days_ago", "5")) == ["Bob", "Cleo"]

      assert names(leaf("signed_up_at", "before", Date.to_iso8601(Date.add(today, -5)))) == [
               "Ada"
             ]

      # After a date is after the whole day.
      assert names(leaf("signed_up_at", "after", Date.add(today, -3))) == ["Bob", "Cleo"]
      assert names(leaf("signed_up_at", "after", today)) == []
      assert names(leaf("signed_up_at", "before", Date.add(today, 1))) == ["Ada", "Bob", "Cleo"]

      at = DateTime.to_iso8601(days_ago(1))
      assert names(leaf("signed_up_at", "before", at)) == ["Ada", "Bob"]
      assert names(leaf("signed_up_at", "after", at)) == ["Cleo"]
      assert names(leaf("signed_up_at", "after", "2000-01-01T00:00:00+02:00")) == ~w(Ada Bob Cleo)
      assert names(leaf("signed_up_at", "set")) == ["Ada", "Bob", "Cleo"]
      assert names(leaf("signed_up_at", "not_set")) == []
    end

    test "dates" do
      assert names(leaf("born_on", "before", "2000-01-01")) == ["Ada"]
      assert names(leaf("born_on", "after", "2000-01-01")) == ["Cleo"]
      assert names(leaf("born_on", "after", "2001-01-01")) == []
      assert names(leaf("born_on", "before", "2001-01-01T10:00:00Z")) == ["Ada"]
      assert names(leaf("born_on", "set")) == ["Ada", "Cleo"]
      assert names(leaf("born_on", "not_set")) == ["Bob"]
      assert names(leaf("born_on", "more_than_days_ago", 365)) == ["Ada", "Cleo"]
      assert names(leaf("born_on", "less_than_days_ago", 365)) == []
    end

    test "enums" do
      assert names(leaf("plan", "in", ["pro"])) == ["Ada"]
      assert names(leaf("plan", "in", "pro")) == ["Ada"]
      assert names(leaf("plan", "in", ["pro", "free"])) == ["Ada", "Bob"]
      assert names(leaf("plan", "not_in", ["pro"])) == ["Bob", "Cleo"]
      assert names(leaf("plan", "not_in", ["pro", "free", "team"])) == ["Cleo"]
    end

    test "groups, and not, which is what it says with no value too" do
      assert names(nil) == ["Ada", "Bob", "Cleo"]
      assert names(%{"all" => []}) == ["Ada", "Bob", "Cleo"]
      assert names(%{"any" => []}) == []
      assert names(%{"not" => leaf("plan", "in", ["pro"])}) == ["Bob", "Cleo"]
      assert names(%{"not" => leaf("email", "eq", "ada@app.test")}) == ["Bob", "Cleo"]
      assert names(%{"not" => leaf("visits", "gt", 0)}) == ["Bob", "Cleo"]

      assert names(%{"any" => [leaf("plan", "in", ["pro"]), leaf("has_story", "true")]}) ==
               ~w(Ada Bob)

      assert names(%{
               "all" => [
                 %{"any" => [leaf("plan", "in", ["free"]), leaf("visits", "set")]},
                 %{"not" => leaf("has_photos", "true")}
               ]
             }) == ["Bob", "Cleo"]

      # Atom keys, as Elixir writes them.
      assert names(%{any: [%{attribute: :plan, op: :in, value: ["free"]}]}) == ["Bob"]
    end

    test "events: happened, ever or in the last days", %{ada: ada, bob: bob} do
      Tayori.track(person_id(ada), "signed_up", at: days_ago(1))
      Tayori.track(person_id(bob), "signed_up", at: days_ago(40))
      Tayori.track(person_id(bob), "story_published")

      happened = %{"event" => "signed_up", "op" => "happened"}
      assert names(happened) == ["Ada", "Bob"]
      assert names(Map.put(happened, "within_days", 30)) == ["Ada"]
      assert names(%{"event" => "signed_up", "op" => "not_happened"}) == ["Cleo"]

      assert names(%{"event" => "signed_up", "op" => "not_happened", "within_days" => 30}) ==
               ["Bob", "Cleo"]

      assert names(%{"event" => "story_published", "op" => "happened"}) == ["Bob"]
      assert names(%{"event" => "nothing", "op" => "happened"}) == []
    end

    test "segments, inlined, and segments of segments" do
      {:ok, pro} = Segments.create(%{"name" => "Pro", "condition" => leaf("plan", "in", ["pro"])})

      {:ok, pro_with_photos} =
        Segments.create(%{
          "name" => "Pro with photos",
          "condition" => %{
            "all" => [%{"segment" => pro.id, "op" => "in"}, leaf("has_photos", "true")]
          }
        })

      assert names(%{"segment" => pro.id, "op" => "in"}) == ["Ada"]
      assert names(%{"segment" => pro.id}) == ["Ada"]
      assert names(%{"segment" => pro.id, "op" => "not_in"}) == ["Bob", "Cleo"]
      assert names(%{"segment" => pro_with_photos.id, "op" => "in"}) == ["Ada"]

      # A segment changed is the new condition at once.
      {:ok, _} = Segments.update(pro, %{"condition" => leaf("plan", "in", ["free"])})
      assert names(%{"segment" => pro.id, "op" => "in"}) == ["Bob"]
      assert names(%{"segment" => pro_with_photos.id, "op" => "in"}) == []
    end

    test "a segment that would lead back to itself is refused", %{repo: repo} do
      {:ok, a} = Segments.create(%{"name" => "A", "condition" => leaf("plan", "in", ["pro"])})

      {:ok, b} =
        Segments.create(%{"name" => "B", "condition" => %{"segment" => a.id, "op" => "in"}})

      assert {:error, changeset} =
               Segments.update(a, %{"condition" => %{"not" => %{"segment" => b.id}}})

      assert errors_on(changeset).condition == ["The segment refers back to itself."]

      assert {:error, changeset} = Segments.update(a, %{"condition" => %{"segment" => a.id}})
      assert errors_on(changeset).condition == ["The segment refers back to itself."]

      # Stored with no check, a cycle compiles to false, once each.
      repo.update_all(Segment, set: [condition: %{"segment" => b.id, "op" => "in"}])

      log =
        capture_log(fn ->
          assert Audience.count(%{"segment" => a.id, "op" => "in"}) == 0
        end)

      assert log =~ "compiles a condition to false"
    end

    test "what can no longer run compiles to false, said once" do
      log =
        capture_log(fn ->
          gone = %{"attribute" => "gone_#{System.unique_integer([:positive])}", "op" => "set"}
          assert Audience.count(gone) == 0
          assert Audience.count(%{"not" => gone}) == 3
          assert Audience.count(gone) == 0
        end)

      assert [_once] = Regex.scan(~r/compiles a condition to false/, log)

      capture_log(fn ->
        assert Audience.count(%{"segment" => Ecto.UUID.generate(), "op" => "in"}) == 0
        # A rule whose value is not valid matches no one.
        assert Audience.count(leaf("visits", "gt", "many")) == 0
      end)
    end

    test "validation: the errors, in words" do
      assert errors(leaf("plann", "set")) == [~s(Unknown attribute "plann".)]

      assert errors(leaf("plan", "gt", 3)) == [
               ~s(Plan cannot be "gt": its operators are in, not_in.)
             ]

      assert errors(leaf("visits", "gt", "many")) == ["Visits needs a whole number."]
      assert errors(leaf("visits", "gt")) == ["Visits needs a whole number."]
      assert errors(leaf("name", "contains", "")) == ["Name needs a value."]
      assert errors(leaf("name", "eq", 3)) == ["Name needs a text value."]

      assert errors(leaf("signed_up_at", "before", "yesterday")) ==
               ["Signed up needs a date or a time, in ISO 8601 (2026-01-31)."]

      assert errors(leaf("signed_up_at", "more_than_days_ago", 0)) ==
               ["Signed up needs a positive number of days."]

      assert errors(leaf("plan", "in", [])) == ["Plan needs one or more of free, pro, team."]

      assert errors(leaf("plan", "in", ["gold"])) == [
               ~s(Plan is one of free, pro, team, not ["gold"].)
             ]

      assert errors(%{"event" => "", "op" => "maybe", "within_days" => -1}) == [
               "The name of an event is 1 to 64 characters.",
               ~s(An event "happened" or "not_happened", not "maybe".),
               "The days of an event are a positive number."
             ]

      assert errors(%{"event" => "signed_up", "op" => "happened"}, events: false) == [
               "Conditions on events need the audience's person_id/0."
             ]

      id = Ecto.UUID.generate()
      assert errors(%{"segment" => id}) == [~s(No segment with the id "#{id}".)]
      assert errors(%{"segment" => "nope", "op" => "in"}) == [~s(No segment with the id "nope".)]
      assert errors(%{"plan" => "pro"}) == [~s(Not a condition: %{"plan" => "pro"}.)]
      assert errors(%{"all" => leaf("plan", "set")}) == [~s("all" takes a list of conditions.)]

      # All the errors at once.
      assert length(errors(%{"any" => [leaf("plann", "set"), leaf("visits", "gt", "x")]})) == 2
    end

    test "validation: at most 5 deep and 50 rules" do
      deep = fn n -> Enum.reduce(1..n, leaf("visits", "set"), fn _, c -> %{"not" => c} end) end
      assert {:ok, _} = Conditions.validate(deep.(5), attributes())
      assert errors(deep.(6)) == ["A condition is at most 5 groups deep."]

      many = fn n -> %{"any" => List.duplicate(leaf("visits", "set"), n)} end
      assert {:ok, _} = Conditions.validate(many.(50), attributes())
      assert errors(many.(51)) == ["A condition has at most 50 rules."]
    end

    test "validation normalizes: string keys, values of their type" do
      assert {:ok, normalized} =
               Conditions.validate(
                 %{
                   all: [
                     %{attribute: "visits", op: "gte", value: " 3 "},
                     %{attribute: "plan", op: "in", value: "pro"},
                     %{attribute: "has_story", op: "true", value: "ignored"},
                     %{attribute: "born_on", op: "before", value: ~D[2000-01-01]},
                     %{
                       attribute: "signed_up_at",
                       op: "after",
                       value: "2026-01-01T10:00:00+01:00"
                     },
                     %{event: " signed_up ", op: "happened", within_days: "7"},
                     %{event: "story_published", op: "not_happened"}
                   ]
                 },
                 attributes()
               )

      assert normalized == %{
               "all" => [
                 %{"attribute" => "visits", "op" => "gte", "value" => 3},
                 %{"attribute" => "plan", "op" => "in", "value" => ["pro"]},
                 %{"attribute" => "has_story", "op" => "true"},
                 %{"attribute" => "born_on", "op" => "before", "value" => "2000-01-01"},
                 %{
                   "attribute" => "signed_up_at",
                   "op" => "after",
                   "value" => "2026-01-01T09:00:00Z"
                 },
                 %{"event" => "signed_up", "op" => "happened", "within_days" => 7},
                 %{"event" => "story_published", "op" => "not_happened"}
               ]
             }

      assert Conditions.validate(nil, attributes()) == {:ok, %{"all" => []}}
    end

    test "describe: a sentence for the admin", %{repo: _repo} do
      describe = &Conditions.describe(&1, attributes())

      assert describe.(nil) == "Everyone"
      assert describe.(%{"any" => []}) == "No one"

      assert describe.(%{
               "all" => [
                 leaf("plan", "in", ["pro"]),
                 leaf("signed_up_at", "more_than_days_ago", 7)
               ]
             }) == "Plan is Pro and signed up more than 7 days ago"

      assert describe.(%{
               "any" => [
                 leaf("plan", "in", ["free", "pro", "team"]),
                 %{"all" => [leaf("has_story", "true"), leaf("published", "false")]}
               ]
             }) == "Plan is Free, Pro or Team or (has a story and published a story is false)"

      assert describe.(leaf("plan", "not_in", ["pro"])) == "Plan is not Pro"
      assert describe.(leaf("plan", "not_in", ["pro", "free"])) == "Plan is neither Pro nor Free"

      assert describe.(leaf("plan", "not_in", ~w(pro free team))) ==
               "Plan is none of Pro, Free and Team"

      assert describe.(leaf("name", "eq", "Ada")) == ~s(Name is "Ada")
      assert describe.(leaf("name", "neq", "Ada")) == ~s(Name is not "Ada")
      assert describe.(leaf("email", "contains", "@")) == ~s(Email contains "@")
      assert describe.(leaf("name", "starts_with", "A")) == ~s(Name starts with "A")
      assert describe.(leaf("email", "set")) == "Email is set"
      assert describe.(leaf("email", "not_set")) == "Email is not set"
      assert describe.(leaf("visits", "gt", 3)) == "Visits is more than 3"
      assert describe.(leaf("visits", "gte", 3)) == "Visits is at least 3"
      assert describe.(leaf("visits", "lt", 3)) == "Visits is less than 3"
      assert describe.(leaf("visits", "lte", 3)) == "Visits is at most 3"
      assert describe.(leaf("visits", "eq", 3)) == "Visits is 3"
      assert describe.(leaf("visits", "neq", 3)) == "Visits is not 3"
      assert describe.(leaf("has_photos", "true")) == "Has photos"
      assert describe.(leaf("born_on", "before", "2000-01-01")) == "Born before 2000-01-01"

      assert describe.(leaf("signed_up_at", "after", "2026-01-01T09:30:00Z")) ==
               "Signed up after 2026-01-01 09:30 UTC"

      assert describe.(leaf("signed_up_at", "less_than_days_ago", 1)) ==
               "Signed up less than 1 day ago"

      assert describe.(%{"not" => leaf("has_photos", "true")}) == "Not (has photos)"

      assert describe.(%{"event" => "signed_up", "op" => "happened", "within_days" => 30}) ==
               ~s("Signed up" happened in the last 30 days)

      assert describe.(%{"event" => "custom", "op" => "not_happened"}) ==
               ~s("custom" never happened)

      assert describe.(%{
               "event" => "story_published",
               "op" => "not_happened",
               "within_days" => 1
             }) ==
               ~s("Published a story" did not happen in the last day)

      {:ok, pro} = Segments.create(%{"name" => "Pro", "condition" => leaf("plan", "in", ["pro"])})
      assert describe.(%{"segment" => pro.id, "op" => "in"}) == ~s(In the segment "Pro")
      assert describe.(%{"segment" => pro.id, "op" => "not_in"}) == ~s(Not in the segment "Pro")

      assert describe.(%{"segment" => Ecto.UUID.generate(), "op" => "in"}) ==
               "In a segment that no longer exists"

      assert describe.(leaf("gone", "set")) == ~s(The unknown attribute "gone")
    end
  end

  test "the operators of each type" do
    assert Conditions.operators(:boolean) == ["true", "false"]
    assert Conditions.operators({:enum, [{"a", "A"}]}) == ["in", "not_in"]
    assert "starts_with" in Conditions.operators(:string)
    assert Conditions.event_operators() == ["happened", "not_happened"]
    assert Conditions.limits() == %{depth: 5, leaves: 50}
  end
end
