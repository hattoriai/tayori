defmodule Tayori.ReactionsTest do
  use TayoriTest.DataCase

  alias Tayori.Reactions

  for_each_repo do
    setup %{config: config} do
      put_config(config, features: [:reactions])
      %{entry: entry!("Reacted", %{published_at: minutes(-1)})}
    end

    test "a reaction is turned on, then off", %{entry: entry} do
      ada = %Reader{id: "ada"}

      assert {:ok, %{counts: %{"🎉" => 1}, mine: ["🎉"]}} = Reactions.toggle(ada, entry.id, "🎉")
      assert {:ok, %{counts: counts, mine: []}} = Reactions.toggle(ada, entry.id, "🎉")
      assert counts == %{}
    end

    test "each reaction counts once per reader", %{entry: entry} do
      {:ok, _} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "👍")
      {:ok, _} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "🚀")
      {:ok, _} = Reactions.toggle(%Reader{id: "grace"}, entry.id, "👍")

      assert {:ok, %{counts: %{"👍" => 3, "🚀" => 1}, mine: ["👍"]}} =
               Reactions.toggle(%Reader{id: "linus"}, entry.id, "👍")
    end

    test "a visitor cannot react, nor with an emoji that is not the app's", %{entry: entry} do
      assert {:error, :visitor} = Reactions.toggle(Reader.visitor(), entry.id, "👍")
      assert {:error, :unknown_emoji} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "💩")
      assert Reactions.for_entries(%Reader{id: "ada"}, [entry.id]) == {%{}, %{}}
    end

    test "the emoji are the app's own", %{config: config, entry: entry} do
      put_config(config, reactions: ["💯"])

      assert {:error, :unknown_emoji} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "👍")
      assert {:ok, %{mine: ["💯"]}} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "💯")
    end

    test "a reaction is told on the PubSub", %{entry: entry} do
      :ok = Tayori.subscribe()
      {:ok, _} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "👀")
      assert_receive {Tayori, :reacted, id} when id == entry.id
    end

    test "the counts of entries, and the reader's own, in the order they reacted", %{
      entry: entry
    } do
      other = entry!("Other", %{published_at: minutes(-2)})
      quiet = entry!("Quiet", %{published_at: minutes(-3)})

      {:ok, _} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "🚀")
      {:ok, _} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "👍")
      {:ok, _} = Reactions.toggle(%Reader{id: "grace"}, entry.id, "👍")
      {:ok, _} = Reactions.toggle(%Reader{id: "grace"}, other.id, "❤️")

      {counts, mine} = Reactions.for_entries(%Reader{id: "ada"}, [entry.id, other.id, quiet.id])

      assert counts == %{
               entry.id => %{"🚀" => 1, "👍" => 2},
               other.id => %{"❤️" => 1}
             }

      assert mine == %{entry.id => ["🚀", "👍"]}

      # A visitor gets the counts, and nothing of their own.
      assert Reactions.for_entries(Reader.visitor(), [entry.id, other.id]) == {counts, %{}}
      assert Reactions.for_entries(%Reader{id: "ada"}, []) == {%{}, %{}}
    end

    test "totals: the reactions of each entry, for the admin", %{entry: entry} do
      other = entry!("Other", %{published_at: minutes(-2)})
      {:ok, _} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "🚀")
      {:ok, _} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "👍")
      {:ok, _} = Reactions.toggle(%Reader{id: "grace"}, entry.id, "👍")

      assert Reactions.totals([entry.id, other.id]) == %{entry.id => 3}
      assert Reactions.totals([]) == %{}
    end

    test "the reactions of a deleted entry go with it", %{entry: entry} do
      {:ok, _} = Reactions.toggle(%Reader{id: "ada"}, entry.id, "🚀")
      {:ok, _} = Entries.delete(entry)
      assert Reactions.totals([entry.id]) == %{}
    end
  end
end
