defmodule Tayori.ViewsTest do
  use TayoriTest.DataCase

  alias Tayori.{View, Views}

  for_each_repo do
    setup do
      %{entry: entry!("Viewed", %{published_at: minutes(-1)})}
    end

    test "nothing is counted when the :analytics feature is off", %{entry: entry} do
      assert :ok = Views.track(%Reader{id: "ada"}, entry.id, "page")
      assert Views.totals([entry.id]) == %{}
    end

    test "every view is counted, and the readers once", %{config: config, entry: entry} do
      put_config(config, features: [:analytics])

      :ok = Views.track(%Reader{id: "ada"}, entry.id, "page")
      :ok = Views.track(%Reader{id: "ada"}, entry.id, "page")
      :ok = Views.track(%Reader{id: "ada"}, entry.id, "panel")
      :ok = Views.track(%Reader{id: "grace"}, entry.id, "email")

      assert Views.totals([entry.id]) == %{entry.id => %{views: 4, readers: 2}}
    end

    test "the visitors are counted together, under no one", %{
      config: config,
      entry: entry,
      repo: repo
    } do
      put_config(config, features: [:analytics])

      :ok = Views.track(nil, entry.id, "page")
      :ok = Views.track(Reader.visitor(), entry.id, "page")
      :ok = Views.track(Reader.visitor("pt-PT"), entry.id, "widget")

      assert Views.totals([entry.id]) == %{entry.id => %{views: 3, readers: 0}}

      assert [%View{reader: "", source: "page", count: 2}, %View{reader: "", source: "widget"}] =
               repo.all(View) |> Enum.sort_by(& &1.source)
    end

    test "a source is one of the places an entry is read", %{entry: entry} do
      assert Views.sources() == ~w(panel page widget email)

      assert_raise FunctionClauseError, fn ->
        Views.track(%Reader{id: "ada"}, entry.id, "billboard")
      end
    end

    test "totals of several entries, and of none", %{config: config, entry: entry} do
      put_config(config, features: [:analytics])
      other = entry!("Other", %{published_at: minutes(-1)})
      unseen = entry!("Unseen", %{published_at: minutes(-1)})

      :ok = Views.track(%Reader{id: "ada"}, entry.id, "page")
      :ok = Views.track(nil, other.id, "page")

      assert Views.totals([entry.id, other.id, unseen.id]) == %{
               entry.id => %{views: 1, readers: 1},
               other.id => %{views: 1, readers: 0}
             }

      assert Views.totals([]) == %{}
    end

    test "by day: every day since, the oldest first, by source", %{
      config: config,
      entry: entry,
      repo: repo
    } do
      put_config(config, features: [:analytics])
      today = Date.utc_today()

      repo.insert_all(View, [
        %{entry_id: entry.id, reader: "ada", source: "page", day: Date.add(today, -3), count: 2},
        %{entry_id: entry.id, reader: "", source: "page", day: Date.add(today, -3), count: 5},
        %{entry_id: entry.id, reader: "ada", source: "email", day: Date.add(today, -3), count: 1},
        %{entry_id: entry.id, reader: "ada", source: "page", day: Date.add(today, -9), count: 4}
      ])

      :ok = Views.track(%Reader{id: "grace"}, entry.id, "panel")

      assert Views.by_day(entry.id, Date.add(today, -4)) == [
               {Date.add(today, -4), %{}},
               {Date.add(today, -3), %{"page" => 7, "email" => 1}},
               {Date.add(today, -2), %{}},
               {Date.add(today, -1), %{}},
               {today, %{"panel" => 1}}
             ]

      assert Views.by_day(entry.id, today) == [{today, %{"panel" => 1}}]
    end
  end
end
