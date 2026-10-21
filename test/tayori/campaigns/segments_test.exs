defmodule Tayori.Campaigns.SegmentsTest do
  use TayoriTest.DataCase

  alias Tayori.Campaigns.{Campaign, Segment, Segments, Step}

  @pro %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}

  defp campaign!(attrs) do
    config = Tayori.Config.get()

    %Campaign{}
    |> Campaign.changeset(
      Map.merge(%{"kind" => "sequence"}, attrs),
      TayoriTest.Audience.attributes()
    )
    |> config.repo.insert!()
  end

  for_each_repo do
    setup :campaigns

    test "creates, reads, updates and deletes a segment, and says so" do
      Tayori.subscribe()

      assert {:ok, %Segment{id: id} = segment} =
               Segments.create(%{"name" => " Pro ", "description" => " ", "condition" => @pro})

      assert_receive {Tayori, :segment_changed, ^id}
      assert segment.name == "Pro"
      assert segment.description == nil
      assert Segments.get(id).condition == @pro
      assert Segments.get(Ecto.UUID.generate()) == nil
      assert Segments.get("nope") == nil

      assert {:ok, segment} = Segments.update(segment, %{"name" => "Pro people"})
      assert_receive {Tayori, :segment_changed, ^id}
      assert Segments.get(id).name == "Pro people"

      assert {:ok, _} = Segments.delete(segment)
      assert_receive {Tayori, :segment_changed, ^id}
      assert Segments.get(id) == nil
    end

    test "checks the name and the condition" do
      assert {:error, changeset} = Segments.create(%{"condition" => @pro})
      assert errors_on(changeset).name == ["can't be blank"]

      assert {:error, changeset} =
               Segments.create(%{"name" => String.duplicate("a", 161), "condition" => nil})

      assert errors_on(changeset) == %{
               name: ["should be at most 160 character(s)"],
               condition: ["can't be blank"]
             }

      assert {:error, changeset} =
               Segments.create(%{
                 "name" => "X",
                 "condition" => %{"attribute" => "nope", "op" => "set"}
               })

      assert errors_on(changeset).condition == [~s(Unknown attribute "nope".)]

      # Normalized as it is kept.
      assert {:ok, segment} =
               Segments.create(%{
                 name: "Visitors",
                 condition: %{attribute: "visits", op: "gt", value: "3"}
               })

      assert Segments.get(segment.id).condition ==
               %{"attribute" => "visits", "op" => "gt", "value" => 3}
    end

    test "lists the segments by name, with their counts on request" do
      person!(%{name: "Ada A", plan: "pro"})
      person!(%{name: "Bob B", plan: "free"})
      {:ok, _} = Segments.create(%{"name" => "Pro", "condition" => @pro})
      {:ok, _} = Segments.create(%{"name" => "Everyone", "condition" => %{"all" => []}})

      assert [%{name: "Everyone", count: nil}, %{name: "Pro", count: nil}] = Segments.list()

      assert [%{name: "Everyone", count: 2}, %{name: "Pro", count: 1}] =
               Segments.list(counts: true)
    end

    test "a segment a campaign names is not deleted: the campaigns are named" do
      {:ok, pro} = Segments.create(%{"name" => "Pro", "condition" => @pro})
      {:ok, other} = Segments.create(%{"name" => "Other", "condition" => %{"all" => []}})
      in_pro = %{"segment" => pro.id, "op" => "in"}

      campaign!(%{"name" => "Welcome", "audience" => %{"not" => in_pro}})
      campaign!(%{"name" => "Upgrade", "goal" => in_pro})

      skipping = campaign!(%{"name" => "Tips"})
      config = Tayori.Config.get()

      config.repo.insert!(%Step{
        campaign_id: skipping.id,
        wait: 60,
        skip_if: %{"any" => [in_pro]}
      })

      campaign!(%{"name" => "Unrelated", "audience" => %{"segment" => other.id, "op" => "in"}})

      assert Segments.used_by(pro.id) == ["Tips", "Upgrade", "Welcome"]
      assert Segments.delete(pro) == {:error, {:in_use, ["Tips", "Upgrade", "Welcome"]}}
      assert Segments.get(pro.id)

      assert {:error, {:in_use, ["Unrelated"]}} = Segments.delete(other)
    end
  end

  test "without the campaigns, segments cannot be written" do
    {:ok, _ctx} = checkout(TayoriTest.SQLiteRepo)

    assert_raise ArgumentError, ~r/the :campaigns module is off/, fn ->
      Segments.create(%{"name" => "Pro", "condition" => @pro})
    end
  end
end
