defmodule Tayori.AdminInboxTest do
  use TayoriTest.ConnCase

  alias Tayori.{Categories, Change, Inbox}

  defp change!(attrs, source \\ "app") do
    {:ok, change} =
      attrs
      |> Map.put_new(:ref, "ref-#{System.unique_integer([:positive])}")
      |> Inbox.add(source: source)

    change
  end

  defp hours(n), do: DateTime.add(DateTime.utc_now(), n * 3600, :second)

  for {name, repo, tags} <- [
        # ConnCase has checked out SQLite.
        {"SQLite", nil, []},
        {"PostgreSQL", TayoriTest.PostgresRepo, [postgres: true]}
      ] do
    describe "the inbox, on #{name}" do
      @describetag tags
      if repo, do: setup(do: TayoriTest.DataCase.checkout(unquote(repo)))

      test "lists the new changes, the newest first, with what they say", %{conn: conn} do
        {:ok, _} =
          Categories.create(%{"key" => "new", "names" => %{"en" => "New"}, "color" => "blue"})

        change!(
          %{
            title: "Comments on boards",
            body: "Leave a **comment** on a board.",
            kind: "added",
            category: "new",
            version: "2.5.0",
            highlight: true,
            occurred_at: hours(-3)
          },
          "changelog"
        )

        change!(%{title: "Slow search", kind: "fixed", occurred_at: hours(-2)}, "fragments")

        change!(
          %{
            title: "Queue moved",
            audience: "internal",
            url: "https://github.com/atelier/app/pull/2291",
            occurred_at: hours(-1)
          },
          "github"
        )

        {:ok, view, html} = conn |> as_admin() |> live("/admin/news/inbox")

        assert html =~ "Inbox"
        # The bar counts the new changes for the public.
        assert has_element?(view, ".ta-nav .ta-nav-count", "2")

        titles =
          view
          |> render()
          |> LazyHTML.from_fragment()
          |> LazyHTML.query(".ta-change .ta-entry-title")
          |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

        assert titles == ["Queue moved", "Slow search", "Comments on boards"]

        assert html =~ "Leave a comment on a board."
        assert has_element?(view, ".ta-source-pill[data-source=changelog]", "Changelog")
        assert has_element?(view, ".ta-source-pill[data-source=github]", "GitHub")
        assert has_element?(view, ~s(.tayori-category[data-color="blue"]), "New")
        assert has_element?(view, ".ta-tag", "fixed")
        assert has_element?(view, ".ta-internal", "Internal")
        assert has_element?(view, ".ta-version", "2.5.0")
        assert has_element?(view, ".ta-entry-title .ta-star")

        assert has_element?(
                 view,
                 ~s(a.ta-change-link[href="https://github.com/atelier/app/pull/2291"])
               )

        # Only the new changes for the public can be drafted.
        assert has_element?(view, ~s(input[aria-label="Select “Slow search”"]))
        refute has_element?(view, ~s(input[aria-label="Select “Queue moved”"]))
      end

      test "tabs by state with their counts, filters and a search", %{conn: conn} do
        change!(%{title: "Exports in two clicks"}, "api")
        hidden = change!(%{title: "Typo in a tooltip"}, "github")
        {:ok, _} = Inbox.hide(hidden)
        change!(%{title: "Release script", audience: "internal"}, "app")

        {:ok, view, html} = conn |> as_admin() |> live("/admin/news/inbox")
        assert html =~ "Exports in two clicks"
        refute html =~ "Typo in a tooltip"
        assert has_element?(view, ~s(.ta-tabs a[aria-current="page"]), "New")
        assert has_element?(view, ".ta-tabs a", ~r/New\s*2/)
        assert has_element?(view, ".ta-tabs a", ~r/Hidden\s*1/)
        assert has_element?(view, ".ta-tabs a", ~r/All\s*3/)

        html = view |> element(".ta-tabs a", "Hidden") |> render_click()
        assert_patch(view, "/admin/news/inbox?state=hidden")
        assert html =~ "Typo in a tooltip"
        refute html =~ "Exports in two clicks"

        html = view |> element(".ta-tabs a", "All") |> render_click()
        assert html =~ "Typo in a tooltip"
        assert html =~ "Exports in two clicks"

        html = view |> form("#inbox-filters", source: "github") |> render_change()
        assert_patch(view, "/admin/news/inbox?state=all&source=github")
        assert html =~ "Typo in a tooltip"
        refute html =~ "Exports in two clicks"

        html = view |> form("#inbox-filters", source: "", audience: "internal") |> render_change()
        assert_patch(view, "/admin/news/inbox?state=all&audience=internal")
        assert html =~ "Release script"
        refute html =~ "Exports in two clicks"

        html = view |> form("#inbox-filters", audience: "", q: "EXPORT") |> render_change()
        assert_patch(view, "/admin/news/inbox?state=all&q=EXPORT")
        assert html =~ "Exports in two clicks"
        refute html =~ "Release script"

        html = view |> form("#inbox-filters", q: "nothing like it") |> render_change()
        assert html =~ "No change matches"
        assert html =~ "Clear the filters"
      end

      test "drafts an entry from the changes picked, and opens it", %{conn: conn} do
        a =
          change!(%{
            title: "Comments on boards",
            body: "On a whole board.",
            occurred_at: hours(-2)
          })

        b = change!(%{title: "CSV import", body: "Each row a card.", occurred_at: hours(-1)})
        c = change!(%{title: "Not this one"})

        {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/inbox")
        refute has_element?(view, ".ta-selection")

        view |> element(~s(input[phx-value-id="#{a.id}"])) |> render_click()
        view |> element(~s(input[phx-value-id="#{b.id}"])) |> render_click()
        assert has_element?(view, ".ta-selection", "2 selected")
        assert has_element?(view, ~s(#change-#{a.id}.ta-selected))

        {:ok, editor, html} =
          view
          |> element(".ta-selection button", "Draft an entry")
          |> render_click()
          |> follow_redirect(conn |> as_admin())

        assert html =~ "An entry is drafted from 2 changes."
        assert html =~ "Edit entry"
        assert html =~ "Comments on boards"
        assert html =~ "Each row a card."
        assert has_element?(editor, "#from-inbox", "Comments on boards")
        assert has_element?(editor, "#from-inbox", "CSV import")
        refute has_element?(editor, "#from-inbox", "Not this one")

        [entry] = Entries.list()
        assert %Change{state: "drafted", entry_id: id} = Inbox.get(a.id)
        assert id == entry.id
        assert %Change{state: "new"} = Inbox.get(c.id)
      end

      test "selects all, clears, and drafts from all that is new", %{conn: conn} do
        change!(%{title: "One"})
        change!(%{title: "Two"})
        change!(%{title: "Team only", audience: "internal"})

        {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/inbox")
        view |> element("#inbox-select-all") |> render_click()
        assert has_element?(view, ".ta-selection", "2 selected")
        view |> element(".ta-selection button", "Clear") |> render_click()
        refute has_element?(view, ".ta-selection")

        {:ok, _editor, html} =
          view
          |> element("button", "Draft from all new")
          |> render_click()
          |> follow_redirect(conn |> as_admin())

        assert html =~ "An entry is drafted from 2 changes."
        assert Inbox.pending_count() == 0
        assert [%Change{title: "Team only", state: "new"}] = Inbox.list(state: "new")

        # Nothing left: the digest says so.
        {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/inbox")
        refute has_element?(view, "button", "Draft from all new")
        assert render_click(view, "draft_all", %{}) =~ "Nothing to draft"
      end

      test "puts a change aside, and restores it", %{conn: conn} do
        change = change!(%{title: "Typo in a tooltip"})
        {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/inbox")

        html =
          view
          |> element(~s(button[aria-label="Put “Typo in a tooltip” aside"]))
          |> render_click()

        assert html =~ "It is put aside"
        assert %Change{state: "hidden"} = Inbox.get(change.id)
        refute has_element?(view, "#change-#{change.id}")

        {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/inbox?state=hidden")
        view |> element(~s(button[aria-label="Restore “Typo in a tooltip”"])) |> render_click()
        assert %Change{state: "new"} = Inbox.get(change.id)
      end

      test "edits a change in place, and highlights it", %{conn: conn} do
        {:ok, _} =
          Categories.create(%{
            "key" => "fixed",
            "names" => %{"en" => "Fixed"},
            "color" => "orange"
          })

        change = change!(%{title: "fix: search stalls", kind: "chore"})

        {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/inbox")
        view |> element(~s(button[aria-label="Edit “fix: search stalls”"])) |> render_click()
        assert has_element?(view, "#change-form")

        html =
          view
          |> form("#change-form", change: %{title: "", category: "fixed"})
          |> render_submit()

        assert html =~ "can&#39;t be blank"

        html =
          view
          |> form("#change-form",
            change: %{
              title: "Search no longer stalls",
              category: "fixed",
              audience: "internal",
              highlight: "true"
            }
          )
          |> render_submit()

        assert html =~ "Saved."
        refute has_element?(view, "#change-form")

        assert %Change{
                 title: "Search no longer stalls",
                 category: "fixed",
                 audience: "internal",
                 highlight: true
               } = Inbox.get(change.id)

        view
        |> element(~s(button[aria-label="Lead with “Search no longer stalls”"]))
        |> render_click()

        assert %Change{highlight: false} = Inbox.get(change.id)
      end

      test "follows the changes as they come, and the bar's count", %{conn: conn} do
        {:ok, view, html} = conn |> as_admin() |> live("/admin/news/inbox")
        assert html =~ "The inbox is empty"
        refute has_element?(view, ".ta-nav-count")

        change!(%{title: "Sent by the CI"}, "api")
        assert render(view) =~ "Sent by the CI"
        assert has_element?(view, ".ta-nav-count", "1")
      end
    end
  end

  describe "the inbox" do
    test "is empty, and says where changes come from", %{conn: conn} do
      {:ok, view, html} = conn |> as_admin() |> live("/admin/news/inbox")
      assert html =~ "The inbox is empty"

      assert has_element?(
               view,
               ~s(a[href="/admin/news/settings#automation"]),
               "Set up the sources"
             )

      assert has_element?(view, ~s(a[href="https://hexdocs.pm/tayori/automation.html"]))
      refute html =~ "Read the sources now"
    end

    test "a tab with nothing says so", %{conn: conn} do
      {:ok, _} = Inbox.hide(change!(%{title: "Aside"}))
      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news/inbox")
      assert html =~ "Nothing new"
    end

    test "a drafted change whose entry is deleted can be restored", %{conn: conn} do
      change = change!(%{title: "Lonely"})
      {:ok, entry} = Tayori.Digest.run()
      {:ok, _} = Entries.delete(entry)

      {:ok, view, html} = conn |> as_admin() |> live("/admin/news/inbox?state=drafted")
      assert html =~ "Its entry is deleted"
      view |> element(~s(button[aria-label="Restore “Lonely”"])) |> render_click()
      assert %Change{state: "new", entry_id: nil} = Inbox.get(change.id)
    end

    test "a drafted change links to its entry", %{conn: conn} do
      change!(%{title: "Exports"})
      {:ok, entry} = Tayori.Digest.run()

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/inbox?state=drafted")
      assert has_element?(view, ~s(a.ta-change-entry[href="/admin/news/#{entry.id}"]), "Exports")
      refute has_element?(view, ~s(button[aria-label="Restore “Exports”"]))
    end

    test "read only: sees everything, changes nothing", %{conn: conn, config: config} do
      put_config(config, inbox: [sources: [{Tayori.Sources.Changelog, path: "NOPE.md"}]])
      change = change!(%{title: "Visible"})

      {:ok, view, html} = conn |> as_admin("viewer") |> live("/admin/news/inbox")
      assert html =~ "Visible"
      refute has_element?(view, "input[type=checkbox]")
      refute has_element?(view, ".ta-row-actions")
      refute html =~ "Draft from all new"
      refute html =~ "Read the sources now"

      for {event, params} <- [
            {"hide", %{"id" => change.id}},
            {"highlight", %{"id" => change.id}},
            {"edit", %{"id" => change.id}},
            {"toggle", %{"id" => change.id}},
            {"draft_all", %{}},
            {"read", %{}}
          ] do
        render_click(view, event, params)
      end

      assert %Change{state: "new", highlight: false} = Inbox.get(change.id)
      refute has_element?(view, "#change-form")
      assert Entries.list() == []
    end

    test "reads the sources now, and keeps what they gave", %{conn: conn, config: config} do
      dir = Path.join(System.tmp_dir!(), "tayori-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      File.write!(Path.join(dir, "CHANGELOG.md"), """
      # Changelog

      ## [1.4.0] - 2026-10-20

      ### Added

      - Exports in two clicks.
      """)

      put_config(config,
        inbox: [
          sources: [
            {Tayori.Sources.Changelog, path: Path.join(dir, "CHANGELOG.md")},
            {Tayori.Sources.Changelog, path: Path.join(dir, "NOPE.md"), name: "missing"}
          ]
        ]
      )

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/inbox")
      view |> element("button", "Read the sources now") |> render_click()

      html = render_async(view)
      assert html =~ "changelog: 1 new, 0 already in."
      assert html =~ "missing: not read"
      assert html =~ "Exports in two clicks."

      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news/settings")
      assert html =~ "1 new, 0 already in"
      assert html =~ "Last read here"
    end
  end

  describe "settings: automation" do
    test "without sources: how to name them, and the digest", %{conn: conn} do
      {:ok, view, html} = conn |> as_admin() |> live("/admin/news/settings")
      assert has_element?(view, ~s(.ta-settings-nav a[href="#automation"]), "Automation")
      assert has_element?(view, "#automation", "No sources yet")
      assert html =~ "Tayori.Sources.Changelog, path: {:my_app, &quot;priv/CHANGELOG.md&quot;}"
      assert has_element?(view, "#automation .ta-facts", "When you ask")
      assert has_element?(view, "#automation .ta-facts", "A draft, for you to read and publish.")
      assert has_element?(view, "#automation .ta-facts", "Nothing new for the public")
      refute has_element?(view, "#automation button", "Read now")
    end

    test "with sources and a weekly digest", %{conn: conn, config: config} do
      put_config(config,
        inbox: [sources: [{Tayori.Sources.Fragments, path: {:tayori, "priv/news"}}]],
        digest: [every: {:weekly, :monday}, publish: :publish]
      )

      change!(%{title: "Waiting"})

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/settings")
      assert has_element?(view, "#automation .ta-hooks", "fragments")
      assert has_element?(view, "#automation .ta-hooks", "Tayori.Sources.Fragments")
      assert has_element?(view, "#automation .ta-hooks", "priv/news (tayori)")
      assert has_element?(view, "#automation button", "Read now")
      assert has_element?(view, "#automation .ta-facts", "Every Monday at 09:00 UTC")
      assert has_element?(view, "#automation .ta-facts", "The entry is published at once.")
      assert has_element?(view, "#automation .ta-facts", "1 new change for the public")

      {:ok, view, _html} = conn |> as_admin("viewer") |> live("/admin/news/settings")
      refute has_element?(view, "#automation button", "Read now")
    end

    test "the embed's snippet is the embed's mount, not the machines'", %{
      conn: conn,
      config: config
    } do
      put_config(config,
        features: [:embed],
        embed: %{origins: ["https://www.example.com"], max_age: 86_400}
      )

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/settings")
      assert has_element?(view, "#embed-snippet", "/embed/news/tayori.js")
      refute has_element?(view, "#embed-snippet", "/machines/")
    end

    test "the cadence in words" do
      alias Tayori.Admin.Automation

      at = ~T[09:00:00]
      assert Automation.cadence(%{every: :manual, at: at}) == "When you ask"
      assert Automation.cadence(%{every: :ingest, at: at}) == "When changes come"

      assert Automation.cadence(%{every: {:weekly, :friday}, at: ~T[16:30:00]}) ==
               "Every Friday at 16:30 UTC"

      assert Automation.cadence(%{every: :monthly, at: at}) ==
               "On the first of each month at 09:00 UTC"

      assert Automation.cadence(%{every: {:days, 1}, at: at}) == "Every day at 09:00 UTC"
      assert Automation.cadence(%{every: {:days, 3}, at: at}) == "Every 3 days at 09:00 UTC"
    end

    if Code.ensure_loaded?(Tayori.Ingest) do
      test "the ingest token: made, shown once, replaced, revoked", %{conn: conn} do
        {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/settings")
        assert has_element?(view, "#automation", "No token")
        assert has_element?(view, "#automation pre", "/machines/news/changes")

        html = view |> element("#automation button", "Create a token") |> render_click()
        assert html =~ "Copy it now: it is not shown again."
        assert has_element?(view, "#ingest-token-copy[data-copy-text]")
        assert Tayori.Ingest.token?()

        {:ok, view, html} = conn |> as_admin() |> live("/admin/news/settings")
        refute html =~ "it is not shown again"
        assert has_element?(view, "#automation", "A token is set")

        view |> element("#automation button", "Revoke") |> render_click()
        refute Tayori.Ingest.token?()
      end
    end

    if Code.ensure_loaded?(Tayori.GitHub) do
      test "GitHub's secret: made, shown once, removed", %{conn: conn} do
        {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/settings")
        assert has_element?(view, "#automation", "No secret")
        assert has_element?(view, "#automation code", "/machines/news/hooks/github")
        assert has_element?(view, "#automation", "application/json")

        html = view |> element("#automation button", "Create a secret") |> render_click()
        assert html =~ "Copy it now: it is not shown again."
        assert has_element?(view, "#github-secret-copy[data-copy-text]")
        assert Tayori.GitHub.secret?()

        view |> element("#automation button", "Remove") |> render_click()
        refute Tayori.GitHub.secret?()
      end
    end
  end

  describe "the editor" do
    test "shows the changes an entry was drafted from", %{conn: conn} do
      change!(
        %{title: "Comments on boards", url: "https://github.com/atelier/app/pull/7"},
        "github"
      )

      change!(%{title: "CSV import", version: "2.5.0"}, "changelog")
      {:ok, entry} = Tayori.Digest.run()

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/#{entry.id}")
      assert has_element?(view, "#from-inbox", "Comments on boards")
      assert has_element?(view, "#from-inbox", "GitHub")
      assert has_element?(view, "#from-inbox", "2.5.0")
      assert has_element?(view, ~s(#from-inbox a[href="https://github.com/atelier/app/pull/7"]))
      assert has_element?(view, ~s(#from-inbox a[href="/admin/news/inbox?state=drafted"]))
    end

    test "an entry written by hand has none", %{conn: conn} do
      entry = entry!("By hand")
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/#{entry.id}")
      refute has_element?(view, "#from-inbox")

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/new")
      refute has_element?(view, "#from-inbox")
    end
  end
end
