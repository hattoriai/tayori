# Sake is not a dependency of the oldest Phoenix's job (TAYORI_OLDEST).
if Code.ensure_loaded?(Sake.Server) do
  defmodule TayoriTest.AppMCP do
    @moduledoc "The app's own MCP server, with Tayori's mounted in it."
    use Sake.Server, name: "app", version: "1.0.0"
    mount Tayori.MCP, prefix: "tayori"
  end

  defmodule Tayori.MCPTest do
    use TayoriTest.DataCase

    import Phoenix.ConnTest, except: [connect: 2, connect: 3]
    import Plug.Conn, only: [put_req_header: 3]
    import Sake.Test

    alias Tayori.{Categories, Inbox, Uploads}

    @endpoint TayoriTest.Host.Endpoint
    @all ["tayori:read", "tayori:write"]
    @admin %{"role" => "admin", "id" => 7, "name" => "Hanzo"}
    @viewer %{"role" => "viewer", "id" => 8, "name" => "Kiku"}
    # The API mounted with no CSRF protection, as the guide mounts it for
    # the uploads.
    @uploads "http://www.example.com/embed/news/uploads"

    defp mcp(%{config: config}) do
      root = Path.expand("../../tmp/mcp_uploads", __DIR__)
      previous = Application.get_env(:kotoba, Kotoba.Storage.Local)
      Application.put_env(:kotoba, Kotoba.Storage.Local, root: root)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:kotoba, Kotoba.Storage.Local, previous),
          else: Application.delete_env(:kotoba, Kotoba.Storage.Local)
      end)

      config =
        put_config(config,
          page_url: "https://app.test/changelog",
          mcp: [resolver: TayoriTest.Resolver, upload_url: @uploads]
        )

      {:ok, _} = Categories.create(%{"key" => "new", "names" => %{"en" => "New"}})
      {:ok, _} = Categories.create(%{"key" => "fixed", "names" => %{"en" => "Fixed"}})
      {:ok, config: config}
    end

    defp client(scopes \\ @all, principal \\ @admin),
      do: connect(Tayori.MCP, scope: principal, scopes: scopes)

    defp call!(client, tool, args) do
      assert {:ok, %{is_error: false, structured: structured}} = call_tool(client, tool, args)
      structured
    end

    defp tool_error(client, tool, args) do
      assert {:ok, %{is_error: true, text: text}} = call_tool(client, tool, args)
      text
    end

    # A PNG of a width and a height, whole: its signature, header, pixels.
    defp png(width, height) do
      row = <<0>> <> :binary.copy(<<200, 120, 40>>, width)
      pixels = :zlib.compress(:binary.copy(row, height))

      <<137, 80, 78, 71, 13, 10, 26, 10>> <>
        chunk("IHDR", <<width::32, height::32, 8, 2, 0, 0, 0>>) <>
        chunk("IDAT", pixels) <> chunk("IEND", "")
    end

    defp chunk(type, data) do
      <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
    end

    defp png_file(width, height) do
      path = Plug.Upload.random_file!("tayori-test")
      File.write!(path, png(width, height))
      path
    end

    defp upload_path(client) do
      %{"url" => "http://www.example.com" <> path} = call!(client, "request_upload", %{})
      path
    end

    test "the :mcp option is checked" do
      new = &Tayori.Config.new(repo: TayoriTest.SQLiteRepo, pubsub: TayoriTest.PubSub, mcp: &1)

      assert %{resolver: TayoriTest.Resolver, upload_url: "https://app.test/api/news/uploads"} =
               new.(
                 resolver: TayoriTest.Resolver,
                 upload_url: "https://app.test/api/news/uploads/"
               ).mcp

      assert_raise ArgumentError, ~r/:mcp takes/, fn -> new.(author: {Kernel, :self}) end
      assert_raise ArgumentError, ~r/a Tayori.Resolver/, fn -> new.(resolver: Kernel) end
      assert_raise ArgumentError, ~r/http\(s\) address/, fn -> new.(upload_url: "/uploads") end
    end

    for_each_repo do
      setup :mcp

      test "lists its tools, each with its hints" do
        assert {:ok, tools} = list_tools(client())

        assert Enum.map(tools, & &1.name) == ~w(
               list_entries get_entry list_changes list_categories add_change hide_change
               draft_entry create_entry update_entry publish_entry unpublish_entry
               request_upload upload_image
             )

        hints = Map.new(tools, &{&1.name, &1.annotations})
        assert hints["list_entries"]["readOnlyHint"] == true
        assert hints["publish_entry"]["destructiveHint"] == true
        assert hints["create_entry"]["readOnlyHint"] == false
      end

      test "mounted in the app's server, under its prefix, and decided the same" do
        assert {:ok, tools} = list_tools(connect(TayoriTest.AppMCP, scope: @admin, scopes: @all))
        assert "tayori_create_entry" in Enum.map(tools, & &1.name)

        viewer = connect(TayoriTest.AppMCP, scope: @viewer, scopes: @all)
        assert {:ok, tools} = list_tools(viewer)
        names = Enum.map(tools, & &1.name)
        assert "tayori_get_entry" in names
        refute "tayori_create_entry" in names

        entry!("Exports")

        assert {:ok, %{structured: %{"slug" => "exports"}}} =
                 call_tool(viewer, "tayori_get_entry", %{"id" => "exports"})
      end

      test "a read-only token sees the read tools only, and is refused the others" do
        client = client(["tayori:read"])
        assert {:ok, tools} = list_tools(client)
        names = Enum.map(tools, & &1.name)
        assert "get_entry" in names
        refute "publish_entry" in names

        assert {:error, {:insufficient_scope, %{scope: ["tayori:write"]}}} =
                 call_tool(client, "create_entry", %{"title" => "Exports"})
      end

      test "a principal the resolver gives read only reads, whatever its token holds" do
        client = client(@all, @viewer)
        assert {:ok, tools} = list_tools(client)
        names = Enum.map(tools, & &1.name)
        assert "list_entries" in names
        refute "create_entry" in names
        assert {:error, _} = call_tool(client, "create_entry", %{"title" => "Exports"})
      end

      test "nobody the resolver forbids, nobody without a resolver", %{config: config} do
        assert {:ok, []} = list_tools(client(@all, %{"role" => "banned"}))
        put_config(config, mcp: [])

        log =
          ExUnit.CaptureLog.capture_log(fn ->
            assert {:ok, []} = list_tools(client())
            assert {:error, _} = call_tool(client(), "list_entries", %{})
          end)

        assert log =~ "give the :mcp option of Tayori a :resolver"
      end

      test "lists the entries by status, and searches them" do
        entry!("Exports in two clicks")
        entry!("Dark mode", %{published_at: minutes(-5)})
        entry!("Calendar sync", %{published_at: minutes(60)})

        %{"entries" => entries, "more" => false} = call!(client(), "list_entries", %{})

        assert Enum.map(entries, & &1["title"]) == [
                 "Exports in two clicks",
                 "Calendar sync",
                 "Dark mode"
               ]

        assert %{"entries" => [%{"title" => "Dark mode", "status" => "published"} = dark]} =
                 call!(client(), "list_entries", %{"status" => "published"})

        assert dark["url"] == "https://app.test/changelog/dark-mode"

        assert %{"entries" => [%{"status" => "draft"}]} =
                 call!(client(), "list_entries", %{"search" => "export"})

        assert %{"entries" => [_], "more" => true} =
                 call!(client(), "list_entries", %{"limit" => 1})
      end

      test "gets an entry by its id or its slug, its body in Markdown" do
        entry = entry!("Exports", %{categories: ["new"]})

        assert %{
                 "id" => id,
                 "status" => "draft",
                 "categories" => ["new"],
                 "translations" => [%{"locale" => "en", "title" => "Exports", "body" => body}],
                 "missing_locales" => ["pt-PT"]
               } = call!(client(), "get_entry", %{"id" => "exports"})

        assert id == entry.id
        assert body =~ "About Exports."
        assert %{"slug" => "exports"} = call!(client(), "get_entry", %{"id" => entry.id})

        assert tool_error(client(), "get_entry", %{"id" => "nope"}) ==
                 ~s(No entry with the id or slug "nope".)
      end

      test "lists the changes and the categories" do
        {:ok, _} = Inbox.add(%{ref: "pr-1", title: "Exports", kind: "added"}, source: "github")
        {:ok, _} = Inbox.add(%{ref: "pr-2", title: "Logs", audience: "internal"}, source: "app")

        assert %{"changes" => [_, _]} = call!(client(), "list_changes", %{})

        assert %{"changes" => [%{"title" => "Exports", "source" => "github", "state" => "new"}]} =
                 call!(client(), "list_changes", %{"audience" => "public", "state" => "new"})

        assert %{"categories" => [%{"key" => "new", "name" => "New"}, %{"key" => "fixed"}]} =
                 call!(client(), "list_categories", %{})
      end

      test "checks the arguments" do
        assert tool_error(client(), "list_entries", %{"status" => "gone"}) =~ "Invalid arguments"
        assert tool_error(client(), "list_entries", %{"limit" => 0}) =~ "Invalid arguments"
        assert tool_error(client(), "create_entry", %{}) =~ "Invalid arguments"
      end

      test "adds a change from MCP, by its writer, and puts one aside" do
        change =
          call!(client(), "add_change", %{
            "title" => "Exports in two clicks",
            "body" => "Zip a project.",
            "category" => "new",
            "highlight" => true
          })

        assert %{"source" => "mcp", "ref" => "mcp-" <> _, "author" => "Hanzo", "state" => "new"} =
                 change

        same = call!(client(), "add_change", %{"title" => "Other", "ref" => "pr-9"})
        again = call!(client(), "add_change", %{"title" => "Again", "ref" => "pr-9"})
        assert again["id"] == same["id"]

        assert %{"state" => "hidden"} = call!(client(), "hide_change", %{"id" => change["id"]})

        assert tool_error(client(), "hide_change", %{"id" => "x"}) ==
                 ~s(No change with the id "x".)
      end

      test "refuses a category or a segment the app does not have" do
        assert tool_error(client(), "add_change", %{"title" => "X", "category" => "News"}) =~
                 "Unknown categories: News. The categories are new, fixed"

        assert tool_error(client(), "add_change", %{"title" => "X", "segments" => ["plan:gold"]}) =~
                 "Unknown segments: plan:gold. The segments are plan:free, plan:pro, role:owner"

        assert tool_error(client(), "add_change", %{"title" => "X", "url" => "ftp://x"}) ==
                 "url must be an http(s) address."
      end

      test "drafts an entry of the new public changes, and never publishes it", %{config: config} do
        put_config(config, digest: [publish: :publish])
        {:ok, a} = Inbox.add(%{ref: "1", title: "Exports", category: "new"})
        {:ok, _} = Inbox.add(%{ref: "2", title: "Fixed the dates", category: "fixed"})

        draft = call!(client(), "draft_entry", %{"change_ids" => [a.id]})

        assert %{"status" => "draft", "translations" => [%{"title" => "Exports"}]} = draft
        assert draft["change_ids"] == [a.id]
        assert Inbox.get(a.id).state == "drafted"

        all = call!(client(), "draft_entry", %{})
        assert %{"status" => "draft", "translations" => [%{"title" => "Fixed the dates"}]} = all

        assert tool_error(client(), "draft_entry", %{}) =~ "No change waits for an entry"

        assert tool_error(client(), "draft_entry", %{"change_ids" => ["x"]}) =~
                 "Not ids of changes: x"
      end

      test "creates a draft by its writer, and changes it in each language" do
        entry =
          call!(client(), "create_entry", %{
            "title" => "Exports",
            "summary" => "Zip a project.",
            "body" => "## How\n\n- Open a project\n- **Export**",
            "categories" => ["new"]
          })

        assert %{"status" => "draft", "author" => %{"id" => 7, "name" => "Hanzo"}} = entry
        assert [%{"body" => body}] = entry["translations"]
        assert body =~ "## How"
        assert body =~ "**Export**"

        changed =
          call!(client(), "update_entry", %{
            "id" => entry["id"],
            "locale" => "pt-PT",
            "title" => "Exportações",
            "body" => "Num clique."
          })

        assert [%{"locale" => "en", "title" => "Exports"}, %{"locale" => "pt-PT"} = pt] =
                 changed["translations"]

        assert pt["title"] == "Exportações"
        assert changed["missing_locales"] == []

        changed =
          call!(client(), "update_entry", %{
            "id" => "exports",
            "summary" => "",
            "segments" => ["plan:pro"]
          })

        assert [%{"summary" => nil}, %{"title" => "Exportações"}] = changed["translations"]
        assert changed["segments"] == ["plan:pro"]
        assert changed["url"] == nil
        assert changed["status"] == "draft"
      end

      test "flattens the errors of an entry" do
        assert tool_error(client(), "create_entry", %{"title" => "X", "locale" => "pt-PT"}) =~
                 "translations needs the en version"

        assert tool_error(client(), "create_entry", %{"title" => "X", "locale" => "fr"}) =~
                 ~s(Unknown language "fr")

        entry!("Exports")

        assert tool_error(client(), "create_entry", %{"title" => "Exports"}) ==
                 "slug has already been taken."

        assert tool_error(client(), "update_entry", %{"id" => "exports", "title" => ""}) ==
                 "A title cannot be empty."

        assert tool_error(client(), "update_entry", %{"id" => "exports"}) =~ "Nothing to change"
      end

      test "publishes when asked, now or at a time, and unpublishes" do
        entry!("Exports")

        assert %{"status" => "published", "url" => "https://app.test/changelog/exports"} =
                 call!(client(), "publish_entry", %{"id" => "exports"})

        assert tool_error(client(), "publish_entry", %{"id" => "exports"}) =~ "already published"
        assert %{"status" => "draft"} = call!(client(), "unpublish_entry", %{"id" => "exports"})

        at = minutes(60) |> DateTime.truncate(:second)

        assert %{"status" => "scheduled", "published_at" => published_at} =
                 call!(client(), "publish_entry", %{
                   "id" => "exports",
                   "at" => DateTime.to_iso8601(at)
                 })

        assert {:ok, ^at, 0} = DateTime.from_iso8601(published_at) |> truncate()

        assert tool_error(client(), "publish_entry", %{"id" => "exports", "at" => "soon"}) =~
                 "is not a time"
      end

      test "an upload: a token, the file, an entry with its figure, in the panel" do
        assert %{"url" => url, "curl" => curl, "expires_at" => _} =
                 call!(client(), "request_upload", %{"filename" => "shot.png"})

        assert curl == "curl -sS -F 'file=@shot.png' #{url}"
        assert "http://www.example.com" <> path = url

        upload = %Plug.Upload{
          path: png_file(4, 3),
          filename: "shot.png",
          content_type: "text/html"
        }

        conn = post(build_conn(), path, %{"file" => upload})

        assert %{"url" => image_url, "markdown" => markdown, "contentType" => "image/png"} =
                 json_response(conn, 201)

        assert %{"width" => 4, "height" => 3, "name" => "shot.png"} = json_response(conn, 201)
        assert markdown == "![](#{image_url})"

        # One file for each token.
        assert json_response(post(build_conn(), path, %{"file" => upload}), 404)

        body = "The timeline, at last.\n\n" <> String.replace(markdown, "![]", "![The timeline]")
        entry = call!(client(), "create_entry", %{"title" => "Timeline", "body" => body})
        assert [%{"body" => markdown_back}] = entry["translations"]
        assert markdown_back =~ "![The timeline](#{image_url})"

        stored = Tayori.Entries.get!(entry["id"])
        [translation] = stored.translations
        assert translation.body.html =~ "kotoba-attachment"
        assert translation.body.html =~ "The timeline</figcaption>"

        {:ok, _} = Tayori.Entries.publish(stored)
        html = json_response(get(build_conn(), "/embed/news/timeline"), 200)["entry"]["html"]
        assert html =~ image_url
        assert html =~ "kotoba-attachment"
      end

      test "an upload as the body, and what is refused" do
        path = upload_path(client())

        conn =
          build_conn()
          |> put_req_header("content-type", "image/png")
          |> post(path, "<html><script>alert(1)</script></html>")

        assert json_response(conn, 415) == %{"error" => "not_an_image"}

        # A token is used up by the file sent, even one refused.
        conn =
          build_conn()
          |> put_req_header("content-type", "image/png")
          |> post(path, png(2, 2))

        assert json_response(conn, 404) == %{"error" => "not_found"}

        conn =
          build_conn()
          |> put_req_header("content-type", "image/png")
          |> post(upload_path(client()), png(2, 2))

        assert %{"width" => 2, "name" => "image"} = json_response(conn, 201)

        conn =
          build_conn()
          |> put_req_header("content-type", "image/png")
          |> post("/embed/news/uploads/forged", png(2, 2))

        assert json_response(conn, 404)
      end

      test "an upload in a multipart body, as curl sends it" do
        boundary = "tayori-boundary"

        body =
          "--#{boundary}\r\n" <>
            ~s(Content-Disposition: form-data; name="file"; filename="shot.png"\r\n) <>
            "Content-Type: image/png\r\n\r\n" <>
            png(5, 5) <> "\r\n--#{boundary}--\r\n"

        conn =
          build_conn()
          |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
          |> post(upload_path(client()), body)

        assert %{"width" => 5, "name" => "shot.png"} = json_response(conn, 201)

        conn =
          build_conn()
          |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
          |> post(upload_path(client()), "--#{boundary}--\r\n")

        assert json_response(conn, 400) == %{"error" => "no_file"}
      end

      test "a token past its time is not good", %{config: config} do
        %{"url" => "http://www.example.com/embed/news/uploads/" <> token} =
          call!(client(), "request_upload", %{})

        assert {:ok, nil} = Uploads.check(token)
        config.repo.update_all(Tayori.Settings.Setting, set: [inserted_at: minutes(-11)])
        assert Uploads.check(token) == :error
        assert Uploads.consume(token) == :error
      end

      test "without an upload_url, request_upload says to send the image in the call",
           %{config: config} do
        put_config(config, mcp: [resolver: TayoriTest.Resolver])
        assert tool_error(client(), "request_upload", %{}) =~ "upload_image"
      end

      test "a small image in the call" do
        data = Base.encode64(png(3, 3))

        assert %{"url" => url, "markdown" => _, "width" => 3} =
                 call!(client(), "upload_image", %{"data" => data, "filename" => "logo.png"})

        assert Uploads.attachment(url).width == 3

        assert tool_error(client(), "upload_image", %{
                 "data" => Base.encode64("not a picture"),
                 "filename" => "x.png"
               }) =~ "not a PNG"

        assert tool_error(client(), "upload_image", %{"data" => "%%%", "filename" => "x.png"}) ==
                 "The data is not base64."
      end

      test "an image Tayori did not store stays an image, never fetched" do
        entry =
          call!(client(), "create_entry", %{
            "title" => "Elsewhere",
            "body" => "![A cat](https://cdn.test/cat.png)"
          })

        [translation] = Tayori.Entries.get!(entry["id"]).translations
        refute translation.body.html =~ "kotoba-attachment"
        assert translation.body.html =~ "https://cdn.test/cat.png"
      end
    end

    defp truncate({:ok, at, offset}), do: {:ok, DateTime.truncate(at, :second), offset}
  end
end
