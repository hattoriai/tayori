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

    test "every entry has the first language, and slugs are unique" do
      assert {:error, changeset} =
               Entries.create(%{translations: [%{locale: "pt-PT", title: "Só em português"}]})

      assert "needs the en version" in errors_on(changeset).translations

      entry!("Same")

      assert {:error, changeset} =
               Entries.create(%{translations: [%{locale: "en", title: "Same"}]})

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
      start_supervised!({Task.Supervisor, name: Tayori.TaskSupervisor})
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
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
