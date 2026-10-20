defmodule Tayori.DigestTest do
  use TayoriTest.DataCase

  import ExUnit.CaptureLog

  alias Tayori.{Digest, Entry, Inbox}
  alias TayoriTest.FakeAI

  doctest Tayori.Digest

  for_each_repo do
    test "nothing waiting, no entry" do
      assert Digest.run() == {:error, :nothing}
      {:ok, _} = Inbox.add(%{ref: "i", title: "Internal", audience: "internal"})
      assert Digest.run() == {:error, :nothing}
    end

    test "one change is an entry of its own, a draft" do
      {:ok, change} =
        Inbox.add(%{
          ref: "a",
          title: "Exports in two clicks",
          body: "Zip a **project**.",
          category: "new"
        })

      assert {:ok, %Entry{} = entry} = Digest.run()
      entry = Tayori.Entries.get!(entry.id)
      [t] = entry.translations

      assert Entry.status(entry) == :draft
      assert t.title == "Exports in two clicks"
      assert t.body.html =~ "<strong>project</strong>"
      assert entry.categories == ["new"]

      assert [%{state: "drafted", entry_id: id}] = Inbox.list()
      assert id == entry.id
      assert Inbox.get(change.id).state == "drafted"
      assert Digest.run() == {:error, :nothing}
    end

    test "several: grouped by category, the highlighted first, published when asked" do
      {:ok, _} =
        Tayori.Categories.create(%{
          "names" => %{"en" => "New"},
          "color" => "blue",
          "key" => "new"
        })

      {:ok, _} = Inbox.add(%{ref: "a", title: "Dates in Auckland", kind: "fixed"})

      {:ok, _} =
        Inbox.add(%{ref: "b", title: "Exports", body: "Exports. Zip it.", category: "new"})

      {:ok, _} = Inbox.add(%{ref: "c", title: "Timeline", category: "new", highlight: true})
      {:ok, _} = Inbox.add(%{ref: "d", title: "Refactor", audience: "internal"})

      assert {:ok, entry} = Digest.run(publish: :publish, now: ~U[2026-10-20 09:00:00Z])
      entry = Tayori.Entries.get!(entry.id)
      [t] = entry.translations

      assert Entry.status(entry) == :published
      assert t.title == "20 October 2026"
      assert t.body.text =~ ~r/New.*Timeline.*Exports: Zip it\..*Dates in Auckland/s
      refute t.body.text =~ "Refactor"
      assert Enum.sort(entry.categories) == ["new"]

      # The internal one is still waiting, for nothing.
      assert [%{ref: "d", state: "new"}] = Inbox.list(state: "new")
    end

    test "two digests of a day: the second's slug takes a number" do
      now = ~U[2026-10-20 09:00:00Z]

      [a, b, _c, _d] =
        for ref <- ~w(a b c d) do
          {:ok, change} = Inbox.add(%{ref: ref, title: "Change #{ref}"})
          change
        end

      assert {:ok, first} = Digest.run(ids: [a.id, b.id], now: now)
      assert {:ok, second} = Digest.run(now: now)
      assert {first.slug, second.slug} == {"20-october-2026", "20-october-2026-2"}

      # A slug given is the entry's, or an error.
      assert {:error, changeset} =
               Tayori.Entries.create(%{
                 slug: "20-october-2026",
                 translations: [%{locale: "en", title: "Again"}]
               })

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "only the changes asked for, and the segments of an entry for some" do
      {:ok, a} = Inbox.add(%{ref: "a", title: "A", segments: ["plan:pro"]})
      {:ok, b} = Inbox.add(%{ref: "b", title: "B", segments: ["plan:team"]})
      {:ok, _c} = Inbox.add(%{ref: "c", title: "C"})

      assert {:ok, entry} = Digest.run(ids: [a.id, b.id])
      assert Enum.sort(entry.segments) == ["plan:pro", "plan:team"]
      assert [%{ref: "c"}] = Inbox.pending()

      assert {:ok, entry} = Digest.run()
      assert entry.segments == []
    end

    test "with AI, the model writes the entry, from the public changes only" do
      configure_ai()
      FakeAI.answer(:writer)

      {:ok, _} =
        Tayori.Categories.create(%{
          "names" => %{"en" => "New", "pt-PT" => "Novo"},
          "color" => "blue",
          "key" => "new"
        })

      {:ok, _} =
        Inbox.add(%{
          ref: "pr-1234",
          title: "Timeline",
          body: "A timeline of the project.",
          category: "new",
          highlight: true,
          url: "https://github.com/acme/app/pull/1234",
          author: "ada"
        })

      {:ok, _} = Inbox.add(%{ref: "b", title: "Dates in Auckland", kind: "fixed"})
      {:ok, _} = Inbox.add(%{ref: "c", title: "Refactor the repo", audience: "internal"})

      assert {:ok, entry} = Digest.run()
      entry = Tayori.Entries.get!(entry.id)
      [t] = entry.translations

      assert t.locale == "en"
      assert t.title == "Timeline"
      assert t.summary == "2 changes, in en."
      assert t.body.text =~ ~r/Timeline.*Dates in Auckland/s
      assert entry.categories == ["new"]
      assert Entry.status(entry) == :draft

      assert_received {:asked, %{system: system, prompt: prompt}}
      assert system =~ "Atelier, a studio's projects."
      assert prompt =~ "- Timeline (highlight; New)\n  A timeline of the project."
      assert prompt =~ "- Dates in Auckland\n"
      refute prompt =~ "Refactor"
      refute prompt =~ "1234"
      refute prompt =~ "ada"
      assert Inbox.pending() == []
    end

    test "with AI, the translations into the other languages when the config says so", %{
      config: config
    } do
      configure_ai()
      put_config(config, locales: ["en", "pt-PT", "fr"], digest: [translate: true])
      FakeAI.answer({:writer, fail: "fr"})

      {:ok, _} = Inbox.add(%{ref: "a", title: "Exports", body: "Zip it."})

      {entry, log} =
        with_log(fn ->
          assert {:ok, entry} = Digest.run()
          entry
        end)

      assert log =~ "did not translate the digest into fr"

      assert [en, pt] = Tayori.Entries.get!(entry.id).translations |> Enum.sort_by(& &1.locale)
      assert {en.locale, en.title} == {"en", "Exports"}
      assert {pt.locale, pt.title} == {"pt-PT", "[pt-PT] Exports"}
      assert pt.summary == "[pt-PT] 1 changes, in en."
      assert pt.body.text =~ "[pt-PT] - Exports"
    end

    test "with ai: false, or without the setting, the digest is plain" do
      {:ok, _} = Inbox.add(%{ref: "a", title: "Exports", body: "Zip it."})
      {:ok, _} = Inbox.add(%{ref: "b", title: "Timeline"})

      configure_ai()
      FakeAI.answer(:writer)

      assert {:ok, entry} = Digest.run(ai: false, now: ~U[2026-10-20 09:00:00Z])

      assert [%{title: "20 October 2026", summary: nil}] =
               Tayori.Entries.get!(entry.id).translations

      refute_received {:asked, _}
    end

    test "when the model fails or answers out of form, the digest is plain, with a warning" do
      configure_ai()

      for {answer, n} <- [{{:error, :unauthorized}, 1}, {["Here is your entry: exports."], 2}] do
        FakeAI.answer(answer)
        {:ok, _} = Inbox.add(%{ref: "a#{n}", title: "Exports #{n}", body: "Zip it."})

        log =
          capture_log(fn ->
            assert {:ok, entry} = Digest.run()

            assert [%{title: title, body: body}] = Tayori.Entries.get!(entry.id).translations
            assert title == "Exports #{n}"
            assert body.text =~ "Zip it."
          end)

        assert log =~ "did not write the digest"
      end
    end

    test "status: the schedule, the next time and what waits", %{config: config} do
      assert %{every: :manual, next_run_at: nil, last_run_at: nil, pending: 0} = Digest.status()

      put_config(config, digest: [every: {:days, 2}, at: ~T[06:00:00]])
      {:ok, _} = Inbox.add(%{ref: "a", title: "A"})
      :ok = Digest.record("digest", ~U[2026-10-19 06:00:10Z])

      assert Digest.status() == %{
               every: {:days, 2},
               next_run_at: ~U[2026-10-21 06:00:00Z],
               last_run_at: ~U[2026-10-19 06:00:10Z],
               pending: 1
             }
    end
  end

  describe "next_run" do
    @tuesday ~U[2026-10-20 12:00:00Z]

    test "weekly: the next such day at the time, after the last run" do
      monday = %{every: {:weekly, :monday}, at: ~T[09:00:00]}
      tuesday = %{monday | every: {:weekly, :tuesday}}

      assert Digest.next_run(monday, nil, @tuesday) == ~U[2026-10-26 09:00:00Z]
      assert Digest.next_run(tuesday, nil, @tuesday) == ~U[2026-10-27 09:00:00Z]
      assert Digest.next_run(tuesday, nil, ~U[2026-10-20 08:59:00Z]) == ~U[2026-10-20 09:00:00Z]

      # Run at the time: the next is a week after.
      assert Digest.next_run(tuesday, ~U[2026-10-20 09:00:00Z], @tuesday) ==
               ~U[2026-10-27 09:00:00Z]

      # A time missed while the app was down is due, once.
      assert Digest.next_run(monday, ~U[2026-10-05 09:00:01Z], @tuesday) ==
               ~U[2026-10-12 09:00:00Z]

      assert Digest.next_run(%{every: {:weekly, :sunday}, at: ~T[23:30:00]}, nil, @tuesday) ==
               ~U[2026-10-25 23:30:00Z]
    end

    test "monthly: the first day of the next month at the time" do
      monthly = %{every: :monthly, at: ~T[09:00:00]}

      assert Digest.next_run(monthly, nil, @tuesday) == ~U[2026-11-01 09:00:00Z]

      assert Digest.next_run(monthly, ~U[2026-12-01 09:00:00Z], @tuesday) ==
               ~U[2027-01-01 09:00:00Z]

      assert Digest.next_run(monthly, ~U[2026-02-01 08:00:00Z], @tuesday) ==
               ~U[2026-02-01 09:00:00Z]

      assert Digest.next_run(monthly, ~U[2026-01-31 23:59:00Z], @tuesday) ==
               ~U[2026-02-01 09:00:00Z]
    end

    test "every n days: n days after the day of the last run, at the time" do
      days = %{every: {:days, 3}, at: ~T[07:15:00]}

      assert Digest.next_run(days, ~U[2026-10-18 07:15:30Z], @tuesday) == ~U[2026-10-21 07:15:00Z]
      assert Digest.next_run(days, ~U[2026-12-30 22:00:00Z], @tuesday) == ~U[2027-01-02 07:15:00Z]
      assert Digest.next_run(days, nil, @tuesday) == ~U[2026-10-23 07:15:00Z]
    end

    test "manual and ingest have no time" do
      for every <- [:manual, :ingest, :each] do
        assert Digest.next_run(%{every: every, at: ~T[09:00:00]}, @tuesday, @tuesday) == nil
      end
    end
  end

  defp configure_ai do
    :ok =
      Tayori.AI.save_settings(
        %{"model" => "anthropic:claude-sonnet-5-5", "about" => "Atelier, a studio's projects."},
        "sk-test"
      )
  end
end
