defmodule Tayori.AudienceTest do
  use TayoriTest.DataCase

  import Ecto.Query

  alias Tayori.{Audience, Recipient}

  defp people(_ctx) do
    people =
      for {name, plan} <- [{"Ada A", "pro"}, {"Bob B", "free"}, {"Cleo C", "pro"}],
          do: person!(%{name: name, plan: plan})

    person!(%{name: "Dan D", plan: "pro", closed_at: DateTime.utc_now()})
    {:ok, people: people}
  end

  @pro %{"attribute" => "plan", "op" => "in", "value" => ["pro"]}

  test "attribute/5 builds an attribute, and checks it" do
    expr = dynamic([person: p], p.plan)

    assert %Audience.Attribute{key: "plan", label: "Plan", type: :string, expr: ^expr} =
             Audience.attribute(:plan, "Plan", :string, expr)

    assert %{description: "Their plan"} =
             Audience.attribute("plan", "Plan", :string, expr, description: "Their plan")

    assert_raise ArgumentError, ~r/lowercase letters/, fn ->
      Audience.attribute("Plan!", "Plan", :string, expr)
    end

    assert_raise ArgumentError, ~r/label/, fn -> Audience.attribute(:plan, "", :string, expr) end

    assert_raise ArgumentError, ~r/the type of the attribute plan/, fn ->
      Audience.attribute(:plan, "Plan", :float, expr)
    end

    assert_raise ArgumentError, ~r/the type of the attribute plan/, fn ->
      Audience.attribute(:plan, "Plan", {:enum, []}, expr)
    end

    assert_raise ArgumentError, ~r/must be a dynamic/, fn ->
      Audience.attribute(:plan, "Plan", :string, :plan)
    end

    assert_raise ArgumentError, ~r/takes :description/, fn ->
      Audience.attribute(:plan, "Plan", :string, expr, hint: "x")
    end
  end

  test "the optional callbacks, and their defaults" do
    defmodule Bare do
      @behaviour Tayori.Audience
      def query, do: from(p in TayoriTest.Person, as: :person)
      def where_ids(query, _ids), do: query
      def recipient(person), do: %Recipient{id: "person:#{person.id}"}
    end

    assert Audience.attributes(Bare) == []
    assert Audience.events(Bare) == []
    assert Audience.person_id(Bare) == nil
    assert Audience.can_email?(Bare, %Recipient{id: "x"}, :marketing)

    audience = TayoriTest.Audience
    assert length(Audience.attributes(audience)) > 5
    assert {"signed_up", "Signed up"} in Audience.events(audience)
    assert %Ecto.Query.DynamicExpr{} = Audience.person_id(audience)

    refute Audience.can_email?(audience, %Recipient{id: "x", data: %{}}, :marketing)

    assert Audience.can_email?(
             audience,
             %Recipient{id: "x", data: %{"optional_emails" => true}},
             :marketing
           )

    assert Audience.can_email?(audience, %Recipient{id: "x"}, :product)
  end

  test "without the campaigns, the audience is not there" do
    {:ok, _ctx} = checkout(TayoriTest.SQLiteRepo)
    assert Audience.current() == nil
    assert_raise ArgumentError, ~r/the :campaigns module is off/, fn -> Audience.count(nil) end

    assert_raise ArgumentError, ~r/the :campaigns module is off/, fn ->
      Audience.get("person:1")
    end
  end

  for_each_repo do
    setup [:campaigns, :people]

    test "count/2 and sample/3, of who is in the base query" do
      assert Audience.count(nil) == 3
      assert Audience.count(@pro) == 2
      assert Audience.count(%{"any" => []}) == 0

      assert [%Recipient{name: "Ada A"}, %Recipient{name: "Cleo C"}] = Audience.sample(@pro)
      assert [%Recipient{name: "Ada A"}] = Audience.sample(@pro, 1)
      assert Audience.sample(nil) |> length() == 3
    end

    test "each_batch/4 walks every person, in batches, in order", %{people: people} do
      test = self()

      assert :ok =
               Audience.each_batch(nil, 2, &send(test, {:batch, Enum.map(&1, fn r -> r.id end)}))

      ids = Enum.map(people, &person_id/1)
      assert_received {:batch, first}
      assert_received {:batch, second}
      assert first ++ second == ids
      assert length(first) == 2
      refute_received {:batch, _}

      # A last batch that is whole ends with an empty look, no call.
      assert :ok = Audience.each_batch(nil, 3, &send(test, {:batch, length(&1)}))
      assert_received {:batch, 3}
      refute_received {:batch, _}

      assert :ok = Audience.each_batch(%{"any" => []}, 3, &send(test, {:batch, &1}))
      refute_received {:batch, _}
    end

    test "get/1: a recipient, or nil", %{people: [ada | _]} do
      assert %Recipient{
               id: id,
               email: "ada@app.test",
               name: "Ada A",
               locale: "en",
               data: %{"first_name" => "Ada"}
             } = Audience.get(person_id(ada))

      assert id == person_id(ada)
      assert Audience.get("person:0") == nil
      assert Audience.get("someone") == nil

      dan = Tayori.Config.get().repo.get_by!(TayoriTest.Person, name: "Dan D")
      assert Audience.get(person_id(dan)) == nil
    end

    test "match?/3, in one query", %{people: [ada, bob | _]} do
      assert Audience.match?(person_id(ada), @pro)
      refute Audience.match?(person_id(bob), @pro)
      assert Audience.match?(person_id(bob), nil)
      refute Audience.match?("person:0", nil)
    end

    test "the person's id as SQL is the recipient's", %{people: people} do
      audience = TayoriTest.Audience
      person_id = Audience.person_id(audience)

      ids =
        audience.query()
        |> audience.order()
        |> select(^%{id: person_id})
        |> Tayori.Config.get().repo.all()
        |> Enum.map(& &1.id)

      assert ids == Enum.map(people, &person_id/1)
    end
  end
end
