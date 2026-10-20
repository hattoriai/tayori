defmodule Tayori.AdminTest do
  use TayoriTest.ConnCase

  alias Tayori.Assets

  describe "access" do
    test "an admin opens the admin", %{conn: conn} do
      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news")
      assert html =~ "Entries"
      assert html =~ "Nothing has been written yet"
    end

    test "nobody is sent where the resolver says", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/admin/news")
    end

    test "forbidden is a 404", %{conn: conn} do
      assert_raise Tayori.Admin.NotFound, fn ->
        conn |> as_admin("banned") |> live("/admin/news")
      end
    end

    test "read only: no new entry, no buttons, the fields disabled", %{conn: conn} do
      entry = entry!("Visible")
      {:ok, _view, html} = conn |> as_admin("viewer") |> live("/admin/news")
      refute html =~ "New entry"

      {:ok, view, html} = conn |> as_admin("viewer") |> live("/admin/news/#{entry.id}")
      refute html =~ "Save draft"
      assert html =~ ~r/<fieldset[^>]*disabled/
      render_submit(view, "save", %{"entry" => %{"slug" => "changed"}, "intent" => "save"})
      assert Entries.get!(entry.id).slug == "visible"

      # No uploads for a reader of the admin; an admin who writes has them.
      refute html =~ ~s(data-upload=")
      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news/#{entry.id}")
      assert html =~ ~s(data-upload=")
    end
  end

  describe "entries" do
    test "lists entries with their status, and filters them", %{conn: conn} do
      entry!("A draft")
      entry!("Out now", %{published_at: minutes(-5), categories: ["New"], segments: ["plan:pro"]})

      {:ok, view, html} = conn |> as_admin() |> live("/admin/news")
      assert html =~ "A draft"
      assert html =~ "Out now"
      assert html =~ "For plan:pro"

      html = view |> form("#entries-search", q: "out") |> render_change()
      assert_patch(view, "/admin/news?q=out")
      assert html =~ "Out now"
      refute html =~ "A draft"

      html = view |> element("a", "Drafts") |> render_click()
      assert_patch(view, "/admin/news?status=draft&q=out")
      refute html =~ "Out now"

      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news?status=draft")
      assert html =~ "A draft"
      refute html =~ "Out now"
    end

    test "follows the changes of other admins", %{conn: conn} do
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news")
      entry!("Written elsewhere")
      assert render(view) =~ "Written elsewhere"
    end
  end

  describe "editor" do
    test "writes a draft, with categories and segments", %{conn: conn} do
      {:ok, view, html} = conn |> as_admin() |> live("/admin/news/new")
      assert html =~ "New entry"
      assert html =~ "Pro"

      body = Kotoba.Content.from_markdown("Exports in **two** clicks.")

      {:ok, _view, html} =
        view
        |> form("#entry-form")
        |> render_submit(%{
          "intent" => "save",
          "entry" => %{
            "translations" => %{
              "0" => %{
                "locale" => "en",
                "title" => "Faster exports",
                "body" => JSON.encode!(body.doc)
              }
            },
            "categories" => "New, Improved",
            "segments" => ["", "plan:pro"]
          }
        })
        |> follow_redirect(conn |> as_admin())

      assert html =~ "Saved."

      [entry] = Entries.list()
      assert entry.slug == "faster-exports"
      assert entry.categories == ["New", "Improved"]
      assert entry.segments == ["plan:pro"]
      assert entry.author == %{"id" => 7, "name" => "Hanzo"}

      assert [%{title: "Faster exports", body: %Kotoba.Content{text: "Exports in two clicks."}}] =
               entry.translations

      assert Entry.status(entry) == :draft
    end

    test "publishes now, then unpublishes", %{conn: conn} do
      :ok = Tayori.subscribe()
      entry = entry!("Ready")
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/#{entry.id}")

      html = view |> form("#entry-form") |> render_submit(%{"intent" => "publish"})
      assert html =~ "The entry is published."
      assert Entry.status(Entries.get!(entry.id)) == :published
      refute html =~ "Publish now"

      html = view |> form("#entry-form") |> render_submit(%{"intent" => "unpublish"})
      assert html =~ "The entry is a draft again."
      assert Entry.status(Entries.get!(entry.id)) == :draft
    end

    test "schedules at a time with an offset", %{conn: conn} do
      entry = entry!("Later")
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/#{entry.id}")
      at = minutes(120) |> DateTime.truncate(:second)

      html =
        view
        |> form("#entry-form")
        |> render_submit(%{
          "intent" => "publish",
          "schedule" => %{"at" => DateTime.to_iso8601(at)}
        })

      assert html =~ "The entry is scheduled."
      saved = Entries.get!(entry.id)
      assert Entry.status(saved) == :scheduled
      assert DateTime.compare(saved.published_at, at) == :eq
    end

    test "adds a language, and shows errors", %{conn: conn} do
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/new")
      html = view |> element("button", "+ Português (Portugal)") |> render_click()
      assert html =~ ~s|aria-label="Português (Portugal)"|

      html =
        view
        |> form("#entry-form", %{"entry" => %{"translations" => %{"0" => %{"title" => ""}}}})
        |> render_submit(%{"intent" => "save"})

      assert html =~ "The entry was not saved"
      assert Entries.list() == []
    end

    test "deletes an entry", %{conn: conn} do
      entry = entry!("Gone soon")
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/#{entry.id}")

      assert {:error, {:live_redirect, %{to: "/admin/news"}}} =
               view |> element("button", "Delete entry") |> render_click()

      assert Entries.list() == []
    end

    test "an unknown entry is a 404", %{conn: conn} do
      assert_raise Tayori.Admin.NotFound, fn -> conn |> as_admin() |> live("/admin/news/nope") end
    end
  end

  describe "assets" do
    test "the script and the style sheet of this build, cached for good", %{conn: conn} do
      conn = get(conn, "/admin/news/assets/" <> Assets.name(:admin_css))
      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/css"

      conn =
        build_conn()
        |> put_req_header("accept-encoding", "gzip")
        |> get("/admin/news/assets/" <> Assets.name(:admin_js))

      assert conn.status == 200
      assert get_resp_header(conn, "content-encoding") == ["gzip"]
    end

    test "another build's file is a 404", %{conn: conn} do
      conn = get(conn, "/admin/news/assets/admin-00000000000000000000000000000000.js")
      assert conn.status == 404

      assert Assets.stale?([
               "https://x/admin/news/assets/admin-00000000000000000000000000000000.js"
             ])

      refute Assets.stale?(["https://x/admin/news/assets/" <> Assets.name(:admin_js), "/app.js"])
    end
  end
end
