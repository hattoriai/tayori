defmodule Tayori.EntriesTest do
  use TayoriTest.DataCase

  defmodule Notifier do
    @behaviour Tayori.Notifier
    @impl true
    def published(entry) do
      send(:persistent_term.get(:tayori_test_notified), {:notified, entry.id})
    end
  end

  for_each_repo do
    test "the slug comes from the title of the first language" do
      entry = entry!("Ação rápida: exports")
      assert entry.slug == "acao-rapida-exports"
      assert Entry.status(entry) == :draft
    end

    test "every entry has the first language, and slugs are unique, numbered when made" do
      assert {:error, changeset} =
               Entries.create(%{translations: [%{locale: "pt-PT", title: "Só em português"}]})

      assert "needs the en version" in errors_on(changeset).translations

      entry!("Same")

      assert {:ok, %{slug: "same-2"}} =
               Entries.create(%{translations: [%{locale: "en", title: "Same"}]})

      assert {:ok, %{slug: "same-3"}} =
               Entries.create(%{"slug" => "", "translations" => [%{locale: "en", title: "Same"}]})

      assert {:error, changeset} =
               Entries.create(%{slug: "same", translations: [%{locale: "en", title: "Other"}]})

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "a language outside the locales is refused" do
      assert {:error, changeset} =
               Entries.create(%{
                 translations: [%{locale: "en", title: "A"}, %{locale: "fr", title: "B"}]
               })

      assert [%{locale: ["is invalid"]} | _] =
               Enum.reject(errors_on(changeset).translations, &(&1 == %{}))
    end

    test "categories and segments are trimmed and unique" do
      entry =
        entry!("Lists", %{categories: [" New ", "New", ""], segments: ["plan:pro", " plan:pro"]})

      assert entry.categories == ["New"]
      assert entry.segments == ["plan:pro"]
    end

    test "list: drafts and scheduled first, a search, a status" do
      entry!("Old news", %{published_at: minutes(-60)})
      entry!("Draft about exports")
      entry!("Scheduled", %{published_at: minutes(60)})

      assert Enum.map(Entries.list(), &Entry.status/1) == [:draft, :scheduled, :published]
      assert [%Entry{slug: "draft-about-exports"}] = Entries.list(search: "EXPORT")
      assert [%Entry{slug: "old-news"}] = Entries.list(status: :published)
    end

    test "list: a search for % or _ finds them, not every entry" do
      entry!("100% faster")
      entry!("snake_case")
      entry!("Plain")

      assert [%Entry{slug: "100-faster"}] = Entries.list(search: "100%")
      assert [%Entry{slug: "snake-case"}] = Entries.list(search: "e_c")
      assert [%Entry{slug: "plain"}] = Entries.list(search: "PLAIN")
    end

    test "publish, schedule, unpublish and delete are told on the PubSub" do
      :ok = Tayori.subscribe()
      entry = entry!("Live")
      assert_receive {Tayori, :changed, id} when id == entry.id

      {:ok, entry} = Entries.publish(entry, minutes(10))
      assert Entry.status(entry) == :scheduled

      {:ok, entry} = Entries.unpublish(entry)
      assert Entry.status(entry) == :draft

      {:ok, _} = Entries.delete(entry)
      assert_raise Ecto.NoResultsError, fn -> Entries.get!(entry.id) end
    end

    test "an entry is announced once, when its time comes", %{config: config} do
      :persistent_term.put(:tayori_test_notified, self())
      config = %{config | notifier: Notifier}
      Tayori.Config.put(config)
      :ok = Tayori.subscribe()

      now = entry!("Now", %{published_at: minutes(-1)})
      later = entry!("Later", %{published_at: minutes(5)})

      Tayori.Scheduler.announce_due(config)
      Tayori.Scheduler.announce_due(config)
      assert_receive {Tayori, :published, id} when id == now.id
      assert_receive {:notified, id} when id == now.id
      refute_receive {Tayori, :published, _}, 50

      Tayori.Scheduler.announce_due(config, minutes(6))
      assert_receive {Tayori, :published, id} when id == later.id
      assert_receive {:notified, id} when id == later.id
    end

    test "pin and unpin keep when the entry was pinned, and are told on the PubSub" do
      entry = entry!("Pinned")
      :ok = Tayori.subscribe()

      {:ok, pinned} = Entries.pin(entry)
      assert %DateTime{} = pinned.pinned_at
      assert_receive {Tayori, :changed, id} when id == entry.id

      {:ok, unpinned} = Entries.unpin(pinned)
      assert unpinned.pinned_at == nil
      assert Entries.get!(entry.id).pinned_at == nil
    end

    test "a cover is an image, with its alternative text, changed and removed" do
      entry = entry!("Covered")

      image = %Kotoba.Nodes.Attachment{
        key: "covers/a.png",
        url: "/uploads/covers/a.png",
        name: "a.png",
        content_type: "image/png",
        bytes: 1200,
        width: 1600,
        height: 900
      }

      assert {:error, :not_an_image} =
               Entries.put_cover(entry, %{image | content_type: "application/pdf"})

      {:ok, entry} = Entries.put_cover(entry, image)

      assert Entries.get!(entry.id).cover == %{
               "url" => "/uploads/covers/a.png",
               "key" => "covers/a.png",
               "width" => 1600,
               "height" => 900,
               "alt" => ""
             }

      {:ok, entry} = Entries.put_cover_alt(entry, "  A chart of exports  ")
      assert Entries.get!(entry.id).cover["alt"] == "A chart of exports"

      {:ok, entry} = Entries.put_cover_alt(entry, String.duplicate("a", 400))
      assert String.length(Entries.get!(entry.id).cover["alt"]) == 300

      {:ok, entry} = Entries.put_cover(entry, image, "Given at once")
      assert entry.cover["alt"] == "Given at once"

      {:ok, _entry} = Entries.remove_cover(entry)
      assert Entries.get!(entry.id).cover == nil
    end

    test "an entry is announced as a popup, a toast or a banner, or not at all" do
      assert {:error, changeset} = Entries.create(attrs("Shout", %{announce: "siren"}))
      assert "is invalid" in errors_on(changeset).announce

      until = minutes(60)

      for kind <- Entry.announce_kinds() do
        {:ok, entry} =
          Entries.create(attrs("As #{kind}", %{announce: kind, announce_until: until}))

        assert entry.announce == kind
        assert DateTime.compare(entry.announce_until, until) == :eq
      end
    end

    test "an entry announced as nothing is announced until no time" do
      {:ok, entry} =
        Entries.create(attrs("Banner", %{announce: "banner", announce_until: minutes(60)}))

      {:ok, entry} = Entries.update(entry, %{announce: "  ", announce_until: minutes(30)})
      assert entry.announce == nil
      assert entry.announce_until == nil
      assert Entries.get!(entry.id).announce_until == nil
    end

    test "counts: every status, for the admin's tabs" do
      assert Entries.counts() == %{all: 0, draft: 0, scheduled: 0, published: 0}

      entry!("Draft 1")
      entry!("Draft 2")
      entry!("Later", %{published_at: minutes(60)})
      entry!("Out", %{published_at: minutes(-1)})

      assert Entries.counts() == %{all: 4, draft: 2, scheduled: 1, published: 1}
    end

    test "the button of an announcement goes to a path of the app or an http(s) address" do
      for url <- [
            "/projects/new",
            "https://atelier.test/x",
            "http://atelier.test",
            "  /trimmed  "
          ] do
        assert {:ok, entry} = Entries.create(attrs("CTA #{url}", %{}, cta_url: url))
        assert hd(entry.translations).cta_url == String.trim(url)
      end

      for url <- [
            "javascript:alert(1)",
            "JavaScript:alert(1)",
            "//evil.test/x",
            "data:text/html,hi",
            "ftp://files.test",
            "https://",
            "relative/path"
          ] do
        assert {:error, changeset} = Entries.create(attrs("Bad #{url}", %{}, cta_url: url)),
               "#{url} was accepted"

        assert [%{cta_url: ["must be a path of the app, or an http or https address"]}] =
                 errors_on(changeset).translations
      end

      {:ok, entry} = Entries.create(attrs("No CTA", %{}, cta_url: "  ", cta_label: " "))
      assert %{cta_url: nil, cta_label: nil} = hd(entry.translations)
    end
  end

  defp attrs(title, attrs, translation \\ []) do
    Map.put(attrs, :translations, [Map.new([locale: "en", title: title] ++ translation)])
  end
end
