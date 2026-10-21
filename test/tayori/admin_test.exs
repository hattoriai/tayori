defmodule Tayori.AdminTest do
  use TayoriTest.ConnCase

  alias PhoenixMountable.Assets
  alias TayoriTest.Host.Router

  describe "access" do
    test "an admin opens the admin", %{conn: conn} do
      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news")
      assert html =~ "Entries"
      assert html =~ "No entries yet"
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
      assert html =~ ~r{title="plan:pro">\s*<svg.*?</svg>Pro}s

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
      {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => "New"}, "color" => "blue"})
      {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => "Improved"}, "color" => "green"})
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
            "categories" => ["", "new", "improved"],
            "segments" => ["", "plan:pro"]
          }
        })
        |> follow_redirect(conn |> as_admin())

      assert html =~ "Saved."

      [entry] = Entries.list()
      assert entry.slug == "faster-exports"
      assert entry.categories == ["new", "improved"]
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

    test "links to the entry on the public page of the same router, with no :page", %{
      conn: conn
    } do
      entry = entry!("Linked", %{published_at: minutes(-1)})
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/#{entry.id}")

      assert has_element?(view, ~s(a[href="/changelog/linked"]), "View on the page")
      assert has_element?(view, "[data-copy*=\"/changelog/preview/\"]")
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
      html = view |> element(".ta-add-language", "Português") |> render_click()
      assert html =~ ~s|aria-label="Português"|

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
    defp mount, do: Router.__phoenix_mountable_mount__(:tayori_admin)

    test "the script and the style sheet of this build, cached for good", %{conn: conn} do
      conn = get(conn, Assets.url(mount(), :css))
      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/css"

      conn =
        build_conn()
        |> put_req_header("accept-encoding", "gzip")
        |> get(Assets.url(mount(), :js))

      assert conn.status == 200
      assert get_resp_header(conn, "content-encoding") == ["gzip"]
    end

    test "another build's file is a 404", %{conn: conn} do
      conn = get(conn, "/admin/news/js-00000000000000000000000000000000")
      assert conn.status == 404
    end

    test "the page links them, with the meta tags of the socket", %{conn: conn} do
      {:ok, _view, html} = conn |> as_admin() |> live("/admin/news")
      assert html =~ Assets.url(mount(), :css)
      assert html =~ Assets.url(mount(), :js)
      assert html =~ ~s(<meta name="live-path" content="/live")
    end
  end

  # A PNG of one pixel: Kotoba checks the bytes of an image.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
       )

  defp edit(conn, entry), do: conn |> as_admin() |> live("/admin/news/#{entry.id}")

  defp save(view, params \\ %{}) do
    view |> form("#entry-form") |> render_submit(Map.put_new(params, "intent", "save"))
  end

  describe "the entries list" do
    test "the tabs count the entries of each status", %{conn: conn} do
      entry!("Draft 1")
      entry!("Draft 2")
      entry!("Later", %{published_at: minutes(60)})
      entry!("Out", %{published_at: minutes(-1)})

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news")

      counts =
        for label <- ~w(All Drafts Scheduled Published) do
          view
          |> element(".ta-tabs a", label)
          |> render()
          |> LazyHTML.from_fragment()
          |> LazyHTML.query(".ta-count")
          |> LazyHTML.text()
        end

      assert counts == ["4", "2", "1", "1"]

      html = view |> element(".ta-tabs a", "Scheduled") |> render_click()
      assert html =~ "Later"
      refute html =~ "Draft 1"
      assert has_element?(view, ~s(.ta-tabs a[aria-current="page"]), "Scheduled")
    end

    test "a search with no match says so", %{conn: conn} do
      entry!("Exports")
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news?q=boards")
      assert has_element?(view, ".ta-empty", "No entry matches")
      refute has_element?(view, "#entries-search ~ ol")
    end

    test "the views and reactions of each entry, with the features on", %{
      conn: conn,
      config: config
    } do
      entry = entry!("Exports", %{published_at: minutes(-1), announce: "toast"})
      {:ok, _} = Entries.pin(entry)

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news")
      refute has_element?(view, ".ta-entry-stats")
      assert has_element?(view, "#entry-#{entry.id} .ta-pin")
      assert has_element?(view, "#entry-#{entry.id} .ta-tag", "Toast")

      put_config(config, features: [:analytics, :reactions])
      Tayori.Views.track(%Reader{id: "u1"}, entry.id, "page")
      Tayori.Views.track(nil, entry.id, "page")
      {:ok, _} = Tayori.Reactions.toggle(%Reader{id: "u1"}, entry.id, "🚀")

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news")
      assert has_element?(view, ~s(#entry-#{entry.id} [title="Views"]), "2")
      assert has_element?(view, ~s(#entry-#{entry.id} [title="Readers"]), "1")
      assert has_element?(view, ~s(#entry-#{entry.id} [title="Reactions"]), "1")
    end
  end

  describe "the editor's preview" do
    test "shows the entry of the form as the page, the panel and the announcement", %{
      conn: conn,
      config: config
    } do
      entry = entry!("Exports")
      {:ok, view, _html} = edit(conn, entry)

      view
      |> form("#entry-form", %{"entry" => %{"translations" => %{"0" => %{"title" => "Faster"}}}})
      |> render_change()

      view |> element(~s(button[phx-value-mode="preview"])) |> render_click()
      assert has_element?(view, ".ta-preview-stage.tayori-page h1.tayori-entry-title", "Faster")
      refute has_element?(view, ~s(button[phx-value-as="announcement"]))

      view |> element(~s(button[phx-value-as="panel"])) |> render_click()
      assert has_element?(view, ".ta-preview-panel .tayori-card-title", "Faster")
      assert has_element?(view, ".ta-preview-panel .tayori-entry-title", "Faster")

      view |> element(~s(button[phx-value-mode="write"])) |> render_click()
      refute has_element?(view, ".ta-preview")

      put_config(config, features: [:announcements])
      {:ok, view, _html} = edit(conn, entry)
      view |> element(~s(button[phx-value-mode="preview"])) |> render_click()
      view |> element(~s(button[phx-value-as="announcement"])) |> render_click()
      assert has_element?(view, ".ta-preview-announcement .ta-hint")
      refute has_element?(view, ".ta-preview-announcement .tayori-announcement")

      view |> form("#entry-form", %{"entry" => %{"announce" => "toast"}}) |> render_change()

      assert has_element?(
               view,
               ".ta-preview-announcement .tayori-announcement-toast",
               "Exports"
             )
    end
  end

  describe "the editor's cover" do
    setup do
      root = Path.expand("../../tmp/uploads-#{System.unique_integer([:positive])}", __DIR__)
      Application.put_env(:kotoba, Kotoba.Storage.Local, root: root)

      on_exit(fn ->
        Application.delete_env(:kotoba, Kotoba.Storage.Local)
        File.rm_rf!(root)
      end)

      %{root: root}
    end

    test "an image uploaded is the cover, with its description, until removed", %{conn: conn} do
      entry = entry!("Exports")
      {:ok, view, _html} = edit(conn, entry)

      view
      |> file_input("#entry-form", :tayori_cover, [
        %{name: "cover.png", content: @png, type: "image/png"}
      ])
      |> render_upload("cover.png")

      assert has_element?(view, ".ta-cover img")
      assert has_element?(view, "#cover-alt-input")
      assert Entries.get!(entry.id).cover == nil

      save(view, %{"cover_alt" => "A chart of exports"})

      assert %{"url" => "/uploads/kotoba/" <> _, "width" => 1, "height" => 1} =
               cover = Entries.get!(entry.id).cover

      assert cover["alt"] == "A chart of exports"

      view |> element(~s(button[phx-click="remove_cover"])) |> render_click()
      refute has_element?(view, ".ta-cover img")
      save(view)
      assert Entries.get!(entry.id).cover == nil
    end

    test "a file that is not an image is refused", %{conn: conn} do
      entry = entry!("Exports")
      {:ok, view, _html} = edit(conn, entry)

      input =
        file_input(view, "#entry-form", :tayori_cover, [
          %{name: "notes.pdf", content: "%PDF-1.4", type: "application/pdf"}
        ])

      assert {:error, [[_ref, :not_accepted]]} = render_upload(input, "notes.pdf")
      refute has_element?(view, ".ta-cover img")
    end
  end

  describe "the editor's details" do
    test "the categories are checkboxes, and none checked is none", %{conn: conn} do
      {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => "New"}})
      {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => "Fixed"}})
      entry = entry!("Exports", %{categories: ["new"]})
      {:ok, view, _html} = edit(conn, entry)

      assert has_element?(view, ~s(input[name="entry[categories][]"][value="new"][checked]))
      refute has_element?(view, ~s(input[name="entry[categories][]"][value="fixed"][checked]))

      save(view, %{"entry" => %{"categories" => ["", "fixed"]}})
      assert Entries.get!(entry.id).categories == ["fixed"]

      save(view, %{"entry" => %{"categories" => [""]}})
      assert Entries.get!(entry.id).categories == []
    end

    test "the pin is a switch, kept when the entry is saved", %{conn: conn} do
      entry = entry!("Exports", %{published_at: minutes(-1)})
      {:ok, view, _html} = edit(conn, entry)

      assert has_element?(view, ~s(button.ta-switch[aria-checked="false"]))
      view |> element("button.ta-switch") |> render_click()
      assert has_element?(view, ~s(button.ta-switch[aria-checked="true"]))
      assert Entries.get!(entry.id).pinned_at == nil

      save(view)
      assert %DateTime{} = pinned_at = Entries.get!(entry.id).pinned_at

      # Saved again pinned, it keeps its time.
      save(view)
      assert Entries.get!(entry.id).pinned_at == pinned_at

      view |> element("button.ta-switch") |> render_click()
      save(view)
      assert Entries.get!(entry.id).pinned_at == nil
    end

    test "the announcement: a kind, its button and its end", %{conn: conn, config: config} do
      entry = entry!("Exports")
      {:ok, view, _html} = edit(conn, entry)
      refute has_element?(view, "#announcement")

      put_config(config, features: [:announcements])
      {:ok, view, _html} = edit(conn, entry)

      assert has_element?(
               view,
               ~s(#announcement input[name="entry[announce]"][value=""][checked])
             )

      refute has_element?(view, "#announce-until-label")
      refute has_element?(view, ~s(input[name="entry[translations][0][cta_url]"]))

      view |> form("#entry-form", %{"entry" => %{"announce" => "popup"}}) |> render_change()
      assert has_element?(view, "#announce-until-label")
      assert has_element?(view, ~s(input[name="entry[translations][0][cta_url]"]))

      html =
        save(view, %{
          "entry" => %{
            "announce" => "popup",
            "translations" => %{
              "0" => %{"cta_label" => "Export now", "cta_url" => "javascript:alert(1)"}
            }
          }
        })

      assert html =~ "must be a path of the app, or an http or https address"
      assert Entries.get!(entry.id).announce == nil

      save(view, %{
        "entry" => %{
          "announce" => "popup",
          "translations" => %{"0" => %{"cta_label" => "Export now", "cta_url" => "/exports"}}
        }
      })

      saved = Entries.get!(entry.id)
      assert saved.announce == "popup"
      assert [%{cta_label: "Export now", cta_url: "/exports"}] = saved.translations

      save(view, %{"entry" => %{"announce" => ""}})
      assert Entries.get!(entry.id).announce == nil
    end

    test "the email box, with :subscriptions, and once sent it stays", %{
      conn: conn,
      config: config,
      repo: repo
    } do
      entry = entry!("Exports")
      {:ok, view, _html} = edit(conn, entry)
      refute has_element?(view, "#email")

      put_config(config,
        features: [:subscriptions],
        mailer: TayoriTest.Mailer,
        email_from: "news@atelier.test",
        page_url: "https://atelier.test/changelog"
      )

      {:ok, view, _html} = edit(conn, entry)
      refute has_element?(view, ~s(#email input[type="checkbox"][checked]))
      refute has_element?(view, "#email .ta-warning")

      save(view, %{"entry" => %{"email" => "true"}})
      assert Entries.get!(entry.id).email

      save(view, %{"entry" => %{"segments" => ["", "plan:pro"]}})
      assert has_element?(view, "#email .ta-warning")

      repo.update_all(Entry, set: [emailed_at: DateTime.utc_now()])
      {:ok, view, _html} = edit(conn, entry)
      assert has_element?(view, "#email fieldset[disabled]")
      assert has_element?(view, "#email .ta-hint", "Sent")
    end

    test "the stats of the last 30 days, only for a published entry with :analytics", %{
      conn: conn,
      config: config
    } do
      draft = entry!("Draft")
      entry = entry!("Exports", %{published_at: minutes(-1)})

      {:ok, view, _html} = edit(conn, entry)
      refute has_element?(view, "#stats")

      put_config(config, features: [:analytics])
      Tayori.Views.track(%Reader{id: "u1"}, entry.id, "page")
      Tayori.Views.track(%Reader{id: "u1"}, entry.id, "email")
      Tayori.Views.track(nil, entry.id, "page")

      {:ok, view, _html} = edit(conn, draft)
      refute has_element?(view, "#stats")

      {:ok, view, _html} = edit(conn, entry)
      assert has_element?(view, "#stats dd", "3")
      assert has_element?(view, "#stats dd", "1")
      assert has_element?(view, "#stats .ta-sources li", "Public page")
      assert has_element?(view, "#stats .ta-sources li", "Email")
    end
  end

  describe "the categories page" do
    test "adds a category, with its names, colour and key", %{conn: conn} do
      {:ok, view, html} = conn |> as_admin() |> live("/admin/news/categories")
      assert html =~ "No categories yet"

      view |> element(".ta-heading button", "New category") |> render_click()

      html =
        view
        |> form("#category-form", %{
          "category" => %{"names" => %{"en" => "", "pt-PT" => "Novo"}, "color" => "teal"}
        })
        |> render_submit()

      assert html =~ "needs the en name"

      html =
        view
        |> form("#category-form", %{
          "category" => %{"names" => %{"en" => "New", "pt-PT" => "Novo"}, "color" => "teal"}
        })
        |> render_submit()

      assert html =~ "“New” is saved."

      assert %{names: %{"en" => "New", "pt-PT" => "Novo"}, color: "teal"} =
               Tayori.Categories.get("new")

      assert has_element?(view, "#category-new .ta-hint", "Novo")
      refute has_element?(view, "#category-form")
    end

    test "edits, orders and deletes the categories", %{conn: conn} do
      for name <- ~w(New Fixed),
          do: {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => name}})

      entry = entry!("Both", %{categories: ["new", "fixed"]})

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/categories")
      assert has_element?(view, "#category-new .ta-category-count", "1 entry")

      view |> element(~s(button[aria-label="Move fixed up"])) |> render_click()
      assert Enum.map(Tayori.Categories.list(), & &1.key) == ["fixed", "new"]
      assert has_element?(view, ~s(button[aria-label="Move fixed up"][disabled]))

      view |> element(~s(button[aria-label="Edit new"])) |> render_click()
      refute has_element?(view, ~s(#category-form input[name="category[key]"]))

      view
      |> form("#category-form", %{
        "category" => %{"names" => %{"en" => "Shiny"}, "color" => "pink"}
      })
      |> render_submit()

      assert %{names: %{"en" => "Shiny"}, color: "pink"} = Tayori.Categories.get("new")
      assert has_element?(view, "#category-new .tayori-category", "Shiny")

      view |> element(~s(button[aria-label="Edit new"])) |> render_click()
      view |> element("#category-form button", "Delete") |> render_click()
      assert Tayori.Categories.get("new") == nil
      refute has_element?(view, "#category-new")
      assert Entries.get!(entry.id).categories == ["fixed"]
    end

    test "read only: no button to change them", %{conn: conn} do
      {:ok, _} = Tayori.Categories.create(%{"names" => %{"en" => "New"}})
      {:ok, view, html} = conn |> as_admin("viewer") |> live("/admin/news/categories")

      refute html =~ "New category"
      refute has_element?(view, ".ta-row-actions")

      render_click(view, "delete", %{"key" => "new"})
      render_click(view, "move", %{"key" => "new", "by" => "down"})
      render_click(view, "new", %{})
      refute has_element?(view, "#category-form")
      assert Tayori.Categories.get("new")
    end
  end

  describe "the settings" do
    test "the features show which are on", %{conn: conn, config: config} do
      put_config(config, features: [:reactions, :analytics])
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/settings")

      on =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(".ta-features li")
        |> Enum.map(fn li ->
          {li |> LazyHTML.query("strong") |> LazyHTML.text(),
           li |> LazyHTML.query(".ta-badge") |> LazyHTML.text() |> String.trim()}
        end)

      assert {"Reactions", "On"} in on
      assert {"Analytics", "On"} in on
      assert {"Announcements", "Off"} in on
      assert {"Integrations", "Off"} in on
      refute has_element?(view, "#integrations")
      refute has_element?(view, "#email")
    end

    test "the subscribers, with :subscriptions", %{conn: conn, config: config, repo: repo} do
      put_config(config,
        features: [:subscriptions],
        mailer: TayoriTest.Mailer,
        email_from: "news@atelier.test",
        page_url: "https://atelier.test/changelog"
      )

      for email <- ~w(a@x.io b@x.io c@x.io), do: :ok = Tayori.Subscribers.subscribe(email)

      {:ok, _} =
        Tayori.Subscribers.confirm(repo.get_by!(Tayori.Subscribers, email: "a@x.io").token)

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/settings")
      assert has_element?(view, "#email dl div:first-child dd", "1")
      assert has_element?(view, "#email dl div:last-child dd", "2")
    end

    test "the webhooks: added with the secret shown once, tested and removed", %{
      conn: conn,
      config: config
    } do
      put_config(config, features: [:webhooks])
      test = self()

      Req.Test.stub(Tayori.Webhooks, fn conn ->
        send(test, {:request, conn.host})
        Plug.Conn.send_resp(conn, if(conn.host == "down.test", do: 500, else: 204), "")
      end)

      Req.Test.set_req_test_to_shared()
      on_exit(&Req.Test.set_req_test_to_private/0)

      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/settings")
      assert has_element?(view, "#integrations #hook-form")

      html =
        view
        |> form("#hook-form", %{
          "hook" => %{"kind" => "slack", "name" => "Team", "url" => "http://x.test"}
        })
        |> render_submit()

      assert html =~ "The address must start with https://."
      assert Tayori.Webhooks.list() == []

      view
      |> form("#hook-form", %{
        "hook" => %{"kind" => "webhook", "name" => "Ours", "url" => "https://ours.test/hook"}
      })
      |> render_submit()

      [%{"id" => id}] = Tayori.Webhooks.list()
      assert has_element?(view, ".ta-hooks li", "Ours")

      assert [secret] =
               view
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query(".ta-notice pre code")
               |> Enum.map(&LazyHTML.text/1)

      assert byte_size(secret) >= 32

      # Not shown again.
      {:ok, view, _html} = conn |> as_admin() |> live("/admin/news/settings")
      refute render(view) =~ secret

      view
      |> form("#hook-form", %{
        "hook" => %{"kind" => "slack", "name" => "Down", "url" => "https://down.test/x"}
      })
      |> render_submit()

      refute render(view) =~ "x-tayori-signature: sha256=…"

      view |> element(~s(button[phx-click="test_hook"][phx-value-id="#{id}"])) |> render_click()
      assert_receive {:request, "ours.test"}
      assert render_async(view) =~ "Delivered"

      [_ours, %{"id" => down}] = Tayori.Webhooks.list()
      view |> element(~s(button[phx-click="test_hook"][phx-value-id="#{down}"])) |> render_click()
      assert render_async(view) =~ "Failed: {:status, 500}"

      view |> element(~s(button[aria-label="Remove Ours"])) |> render_click()
      assert [%{"name" => "Down"}] = Tayori.Webhooks.list()
      refute has_element?(view, ".ta-hooks li", "Ours")
    end

    test "read only: the webhooks are listed with nothing to change", %{
      conn: conn,
      config: config
    } do
      put_config(config, features: [:webhooks])
      {:ok, _} = Tayori.Webhooks.add("slack", "Team", "https://hooks.slack.test/x")

      {:ok, view, _html} = conn |> as_admin("viewer") |> live("/admin/news/settings")
      assert has_element?(view, ".ta-hooks li", "Team")
      refute has_element?(view, "#hook-form")
      refute has_element?(view, ~s(button[phx-click="test_hook"]))
      refute has_element?(view, ~s(button[phx-click="remove_hook"]))

      [%{"id" => id}] = Tayori.Webhooks.list()
      render_click(view, "remove_hook", %{"id" => id})

      render_submit(view, "add_hook", %{
        "hook" => %{"kind" => "slack", "name" => "B", "url" => "https://b.test"}
      })

      assert [%{"name" => "Team"}] = Tayori.Webhooks.list()
    end
  end

  describe "read only" do
    test "the editor has no write control, whatever the features", %{conn: conn, config: config} do
      put_config(config,
        features: [:announcements, :subscriptions],
        mailer: TayoriTest.Mailer,
        email_from: "news@atelier.test",
        page_url: "https://atelier.test/changelog"
      )

      entry = entry!("Exports", %{published_at: minutes(-1)})
      {:ok, view, _html} = conn |> as_admin("viewer") |> live("/admin/news/#{entry.id}")

      refute has_element?(view, "#publication")
      refute has_element?(view, ".ta-danger-zone")
      refute has_element?(view, ".ta-dropzone")
      assert has_element?(view, "#details fieldset[disabled]")
      assert has_element?(view, "#announcement fieldset[disabled]")
      assert has_element?(view, "#email fieldset[disabled]")

      render_click(view, "pinned", %{})
      render_click(view, "delete", %{})
      save(view, %{"entry" => %{"announce" => "popup"}})
      saved = Entries.get!(entry.id)
      assert saved.pinned_at == nil
      assert saved.announce == nil
    end
  end
end
