defmodule Tayori.AnnouncementsTest do
  use TayoriTest.DataCase

  alias Tayori.Announcements

  for_each_repo do
    setup %{config: config} do
      put_config(config, features: [:announcements])
      :ok
    end

    test "nothing is announced when the :announcements feature is off", %{config: config} do
      entry!("Popup", %{published_at: minutes(-1), announce: "popup"})
      assert %Entry{} = Announcements.current(Reader.visitor())

      put_config(config, features: [])
      assert Announcements.current(Reader.visitor()) == nil
    end

    test "the newest entry announced, with its translation in the reader's language" do
      entry!("Not announced", %{published_at: minutes(-1)})
      entry!("Older toast", %{published_at: minutes(-20), announce: "toast"})

      entry!("Banner", %{
        published_at: minutes(-10),
        announce: "banner",
        translations: [%{locale: "en", title: "Banner"}, %{locale: "pt-PT", title: "Faixa"}]
      })

      entry!("A draft", %{announce: "popup"})
      entry!("Scheduled", %{published_at: minutes(10), announce: "popup"})

      assert %Entry{announce: "banner", translation: %{title: "Faixa"}} =
               Announcements.current(Reader.visitor("pt-PT"))
    end

    test "an announcement is for the readers its entry is for" do
      entry!("For all", %{published_at: minutes(-10), announce: "toast"})
      entry!("For pro", %{published_at: minutes(-1), announce: "popup", segments: ["plan:pro"]})

      assert %Entry{slug: "for-all"} = Announcements.current(Reader.visitor())
      assert %Entry{slug: "for-all"} = Announcements.current(%Reader{id: "u", segments: ["x"]})

      assert %Entry{slug: "for-pro"} =
               Announcements.current(%Reader{id: "u", segments: ["plan:pro"]})
    end

    test "an announcement ends at its date" do
      entry!("Over", %{published_at: minutes(-30), announce: "popup", announce_until: minutes(-1)})

      assert Announcements.current(Reader.visitor()) == nil

      entry!("On", %{published_at: minutes(-60), announce: "toast", announce_until: minutes(5)})
      assert %Entry{slug: "on"} = Announcements.current(Reader.visitor())
      assert Announcements.current(Reader.visitor(), now: minutes(6)) == nil
    end

    test "a reader who dismissed it sees the one before, on every device" do
      older = entry!("Older", %{published_at: minutes(-10), announce: "banner"})
      newer = entry!("Newer", %{published_at: minutes(-1), announce: "popup"})
      ada = %Reader{id: "ada"}

      :ok = Tayori.subscribe(ada)
      assert :ok = Announcements.dismiss(ada, newer.id)
      assert_receive {Tayori, :dismissed, id} when id == newer.id

      assert %Entry{id: id} = Announcements.current(ada)
      assert id == older.id

      # Another reader still sees it; dismissing twice is the same.
      assert %Entry{id: id} = Announcements.current(%Reader{id: "grace"})
      assert id == newer.id
      assert :ok = Announcements.dismiss(ada, newer.id)
      :ok = Announcements.dismiss(ada, older.id)
      assert Announcements.current(ada) == nil
    end

    test "a visitor's dismissal is not kept" do
      entry = entry!("Popup", %{published_at: minutes(-1), announce: "popup"})
      :ok = Tayori.subscribe()

      assert :ok = Announcements.dismiss(Reader.visitor(), entry.id)
      assert %Entry{} = Announcements.current(Reader.visitor())
      refute_receive {Tayori, :dismissed, _}, 50
    end
  end

  test "an entry is announcing until its date" do
    now = DateTime.utc_now()
    refute Entry.announcing?(%Entry{announce: nil}, now)
    assert Entry.announcing?(%Entry{announce: "toast"}, now)
    assert Entry.announcing?(%Entry{announce: "toast", announce_until: minutes(1)}, now)
    refute Entry.announcing?(%Entry{announce: "toast", announce_until: minutes(-1)}, now)
  end
end
