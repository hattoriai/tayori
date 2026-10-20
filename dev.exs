# The Tayori development server: `mix dev`, then http://localhost:4099.
#
# One Phoenix endpoint with a small app ("Atelier", a studio's project
# tool) and its news: the admin at /admin/news (Tayori's theme) and
# /sumi/news (the Sumi theme), the news in the app at /, the public page
# at /changelog. The entries are in SQLite (tmp/dev.sqlite3), the
# attachments of the editor in tmp/uploads. The browser tests in e2e/ run
# against it.
#
# The bundles are built first when any is missing, then rebuild and the
# page reloads on a change.
#
# Query params: `as` - who you are: `admin` (the default), `viewer` (the
# admin read only), `pro`, `free` or `visitor` (a reader of the app).
#
# Environment:
#
#   * PORT - the HTTP port (4099).
#   * TAYORI_DEV_WATCH - "false" starts no esbuild watcher and no live
#     reload, for the browser tests; the bundles must be built first.
#   * TAYORI_DEV_DATABASE - the SQLite file (tmp/dev.sqlite3).

port = "PORT" |> System.get_env("4099") |> String.to_integer()
watch? = System.get_env("TAYORI_DEV_WATCH") != "false"
database = System.get_env("TAYORI_DEV_DATABASE", Path.expand("tmp/dev.sqlite3", __DIR__))
uploads = Path.expand("tmp/uploads", __DIR__)

Application.put_env(:phoenix, :json_library, JSON)
Application.put_env(:elixir, :time_zone_database, Tz.TimeZoneDatabase)
Logger.configure(level: :info)

Application.put_env(:tayori, TayoriDev.Repo, database: database, pool_size: 5)
Application.put_env(:kotoba, Kotoba.Storage.Local, root: uploads, url_prefix: "/uploads")

Application.put_env(:tayori, TayoriDev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  code_reloader: watch?,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: port],
  live_view: [signing_salt: "tayori-dev-live-view-salt"],
  pubsub_server: TayoriDev.PubSub,
  render_errors: [formats: [html: TayoriDev.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("tayori-development-secret-", 3),
  server: true,
  url: [host: "localhost"],
  watchers:
    if(watch?,
      do: [
        tayori_esm: {Esbuild, :install_and_run, [:tayori_esm, ~w(--watch)]},
        tayori_admin: {Esbuild, :install_and_run, [:tayori_admin, ~w(--watch)]}
      ],
      else: []
    ),
  live_reload: [
    patterns: [
      ~r"priv/static/.*\.(js|css)$",
      ~r"lib/tayori/.*\.ex$"
    ]
  ]
)

defmodule TayoriDev.Repo do
  @moduledoc "The entries of the development server, in SQLite."
  use Ecto.Repo, otp_app: :tayori, adapter: Ecto.Adapters.SQLite3
end

defmodule TayoriDev.Migration do
  @moduledoc false
  use Ecto.Migration
  def up, do: Tayori.Migrations.up(version: 1)
  def down, do: Tayori.Migrations.down(to: 0)
end

defmodule TayoriDev.Seeds do
  @moduledoc "A few entries of Atelier's news, the first time."

  def run do
    if Tayori.Entries.list() == [] do
      entry(
        "Exports in two clicks",
        ["Feature"],
        [],
        -2,
        """
        Every project now has an **Export** button. It makes a zip of the
        project's files and its notes, and emails you a link when it is ready.

        - Files keep their folders.
        - Notes come as Markdown.
        """,
        pt: {"Exportações em dois cliques", "Cada projeto tem agora um botão **Exportar**."}
      )

      entry(
        "Shared boards for Pro studios",
        ["Feature"],
        ["plan:pro"],
        -1,
        "Pro studios can share a board with a client, read only, with a link.",
        []
      )

      entry(
        "Faster search",
        ["Improved"],
        [],
        -26,
        "Search answers as you type, and forgives a typo.",
        []
      )

      entry(
        "Calendar view",
        ["Feature"],
        [],
        nil,
        "A draft: the calendar of a project's due dates.",
        []
      )
    end
  end

  defp entry(title, categories, segments, hours, body, translations) do
    pt =
      case translations[:pt] do
        {title, body} ->
          [%{locale: "pt-PT", title: title, body: Kotoba.Content.from_markdown(body)}]

        nil ->
          []
      end

    {:ok, entry} =
      Tayori.Entries.create(
        %{
          categories: categories,
          segments: segments,
          translations: [
            %{locale: "en", title: title, body: Kotoba.Content.from_markdown(body)} | pt
          ]
        },
        author: %{"id" => 1, "name" => "Hattori Hanzo"}
      )

    if hours, do: Tayori.Entries.publish(entry, DateTime.add(DateTime.utc_now(), hours * 3600))
  end
end

defmodule TayoriDev.Resolver do
  @moduledoc "Who you are, from `?as=` (kept in the session)."
  @behaviour Tayori.Resolver

  @impl true
  def resolve_user(conn), do: conn.assigns[:dev_user]

  @impl true
  def resolve_access(%{role: :admin}), do: :all
  def resolve_access(%{role: :viewer}), do: :read_only
  def resolve_access(_reader), do: {:forbidden, "/"}

  @impl true
  def author(user), do: %{"id" => user.id, "name" => user.name}

  @impl true
  def segments do
    [
      {"Plan", [{"plan:free", "Free"}, {"plan:pro", "Pro"}]},
      {"Role", [{"role:owner", "Owners"}, {"role:member", "Members"}]}
    ]
  end

  @impl true
  def resolve_reader(%Plug.Conn{} = conn), do: reader(conn.assigns[:dev_user])
  def resolve_reader(%{assigns: assigns}), do: reader(assigns[:dev_user])

  defp reader(%{role: role} = user) when role in [:pro, :free, :admin, :viewer] do
    plan = if role == :free, do: "free", else: "pro"

    %Tayori.Reader{
      id: "user:#{user.id}",
      segments: ["plan:#{plan}", "role:owner"],
      locale: user.locale
    }
  end

  defp reader(_visitor), do: nil
end

defmodule TayoriDev.Who do
  @moduledoc "The person of the request, from `?as=`, kept in the session."
  import Plug.Conn

  @people %{
    "admin" => %{id: 1, name: "Hattori Hanzo", role: :admin, locale: "en"},
    "viewer" => %{id: 2, name: "Viewer", role: :viewer, locale: "en"},
    "pro" => %{id: 3, name: "Ada (Pro)", role: :pro, locale: "en"},
    "free" => %{id: 4, name: "Grace (Free)", role: :free, locale: "pt-PT"},
    "visitor" => nil
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    as =
      case conn.query_params["as"] do
        as when is_map_key(@people, as) -> as
        _ -> get_session(conn, "as") || "admin"
      end

    conn |> put_session("as", as) |> assign(:dev_user, @people[as])
  end

  def on_mount(:default, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :dev_user, @people[session["as"] || "admin"])}
  end
end

defmodule TayoriDev.HomeLive do
  @moduledoc "Atelier: the app whose news this is."
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <header class="dev-header">
      <strong>Atelier</strong>
      <nav>
        <a href="/plain">Plain page</a>
        <a href="/changelog">Changelog</a>
        <Tayori.Components.news_button tayori={@tayori} />
      </nav>
    </header>
    <Tayori.Components.news_panel tayori={@tayori} />
    <main class="dev-main">
      <h1>Atelier</h1>
      <p>A studio's projects. Its news is written at <a href="/admin/news">/admin/news</a>.</p>
      <p>
        You are <strong>{(@dev_user && @dev_user.name) || "a visitor"}</strong>. Be
        <a href="/?as=admin">the admin</a>, <a href="/?as=viewer">a viewer</a>,
        <a href="/?as=pro">a Pro reader</a>, <a href="/?as=free">a Free reader</a>
        or <a href="/?as=visitor">a visitor</a>.
      </p>
      <p>
        The envelope above is the news of this LiveView, <code>Tayori.Components</code>. The
        <a href="/plain">plain page</a> has <code>&lt;tayori-news&gt;</code>, over the JSON API.
      </p>
    </main>
    """
  end
end

defmodule TayoriDev.PlainController do
  @moduledoc "A page with no LiveView: the news through <tayori-news> and the JSON API."
  use Phoenix.Controller, formats: [:html]

  alias Phoenix.HTML.Safe

  def show(conn, _params) do
    page(conn, """
    <header class="dev-header">
      <strong>Atelier</strong>
      <nav>
        <a href="/">LiveView page</a>
        <a href="/changelog">Changelog</a>
        <tayori-news src="/api/news" page="/changelog"></tayori-news>
      </nav>
    </header>
    <main class="dev-main">
      <h1>A plain page</h1>
      <p>This page is not a LiveView: the envelope is &lt;tayori-news&gt;, which reads the JSON API.</p>
    </main>
    """)
  end

  # The page in the root layout of the app, as a template would be.
  defp page(conn, body) do
    html(
      conn,
      %{conn: conn, inner_content: Phoenix.HTML.raw(body)}
      |> TayoriDev.Layouts.root()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
    )
  end
end

defmodule TayoriDev.Layouts do
  @moduledoc "The root layout of Atelier's own pages."
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Atelier</title>
        <link rel="stylesheet" href="/deps/kotoba/kotoba.css" />
        <link rel="stylesheet" href="/assets/tayori.css" />
        <link :if={@conn.query_params["theme"] == "sumi"} rel="stylesheet" href="/assets/tayori-sumi.css" />
        <style>
          body { margin: 0; font-family: system-ui; }
          .dev-header { display: flex; justify-content: space-between; align-items: center; padding: 0.75rem 1.5rem; border-bottom: 1px solid #ddd; }
          .dev-header nav { display: flex; gap: 1rem; align-items: center; }
          .dev-main { max-width: 40rem; margin: 3rem auto; line-height: 1.5; padding: 0 1rem; }
        </style>
        <script type="importmap">
          {"imports": {
            "phoenix": "/vendor/phoenix/phoenix.mjs",
            "phoenix_live_view": "/vendor/phoenix_live_view/phoenix_live_view.esm.js",
            "tayori": "/assets/tayori.esm.js"
          }}
        </script>
        <script type="module">
          import {Socket} from "phoenix"
          import {LiveSocket} from "phoenix_live_view"
          import * as Tayori from "tayori"
          const csrf = document.querySelector("meta[name='csrf-token']").content
          const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrf}, hooks: {...Tayori.hooks}})
          liveSocket.connect()
          window.liveSocket = liveSocket
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end

defmodule TayoriDev.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router
  import Tayori.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TayoriDev.Layouts, :root}
    plug :protect_from_forgery
    plug TayoriDev.Who
  end

  # The JSON API with the app's session: the reader is the person of the
  # session, and POST /seen is checked against the CSRF token.
  pipeline :api_session do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug TayoriDev.Who
  end

  scope "/api" do
    pipe_through :api_session
    tayori_api("/news", resolver: TayoriDev.Resolver, page: "/changelog")
  end

  scope "/admin" do
    pipe_through :browser
    tayori_admin("/news", resolver: TayoriDev.Resolver, on_mount: [TayoriDev.Who])
  end

  scope "/sumi" do
    pipe_through :browser

    tayori_admin("/news",
      resolver: TayoriDev.Resolver,
      on_mount: [TayoriDev.Who],
      theme: :sumi,
      as: :tayori_admin_sumi
    )
  end

  scope "/" do
    pipe_through :browser

    live_session :app,
      on_mount: [TayoriDev.Who, {Tayori.Live, resolver: TayoriDev.Resolver, page: "/changelog"}] do
      live "/", TayoriDev.HomeLive
    end

    get "/plain", TayoriDev.PlainController, :show
    tayori_page("/changelog", title: "Atelier news", resolver: TayoriDev.Resolver)
    tayori_page("/sumi/changelog", title: "Atelier news", theme: :sumi, as: :tayori_page_sumi)
  end
end

defmodule TayoriDev.ErrorHTML do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule TayoriDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :tayori

  @session [store: :cookie, key: "_tayori_dev", signing_salt: "tayori-dev"]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]]

  if Application.compile_env(:tayori, [__MODULE__, :code_reloader], false) do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.Static, at: "/assets", from: Path.expand("priv/static", __DIR__)
  plug Plug.Static, at: "/vendor/phoenix", from: {:phoenix, "priv/static"}
  plug Plug.Static, at: "/vendor/phoenix_live_view", from: {:phoenix_live_view, "priv/static"}
  plug Plug.Static, at: "/deps/kotoba", from: {:kotoba, "priv/static"}
  plug Kotoba.Storage.Local.Plug, at: "/uploads"

  plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: JSON
  plug Plug.MethodOverride
  plug Plug.Session, @session
  plug TayoriDev.Router
end

defmodule TayoriDev.CSSCopier do
  @moduledoc """
  Copies the style sheets of assets/css to priv/static as they change,
  so that the page reloads with them (esbuild watches the scripts).
  """
  use GenServer

  @files ~w(tayori.css tayori-sumi.css tayori-admin.css)

  def start_link(_), do: GenServer.start_link(__MODULE__, %{})

  def init(state) do
    send(self(), :copy)
    {:ok, state}
  end

  def handle_info(:copy, state) do
    state =
      Map.new(@files, fn file ->
        source = Path.expand("assets/css/#{file}", File.cwd!())
        mtime = File.stat!(source).mtime

        if state[file] != mtime do
          File.mkdir_p!("priv/static")
          File.cp!(source, Path.join("priv/static", file))
        end

        {file, mtime}
      end)

    Process.send_after(self(), :copy, 500)
    {:noreply, state}
  end
end

# The script's process ends after this file, so the server runs in a task
# that stays alive; `mix run --no-halt` keeps the VM up.
Task.async(fn ->
  if watch?, do: {:ok, _apps} = Application.ensure_all_started(:esbuild)

  File.mkdir_p!(Path.dirname(database))
  File.mkdir_p!(uploads)
  _ = Ecto.Adapters.SQLite3.storage_up(TayoriDev.Repo.config())

  # The tables first, then Tayori, whose scheduler reads them at once.
  {:ok, _pid} = TayoriDev.Repo.start_link()
  Ecto.Migrator.run(TayoriDev.Repo, [{0, TayoriDev.Migration}], :up, all: true, log: false)

  {:ok, _pid} =
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: TayoriDev.PubSub},
        {Tayori,
         repo: TayoriDev.Repo,
         pubsub: TayoriDev.PubSub,
         secret_key_base: String.duplicate("tayori-development-secret-", 3),
         locales: ["en", "pt-PT"]},
        TayoriDev.Endpoint
      ] ++ if(watch?, do: [TayoriDev.CSSCopier], else: []),
      strategy: :one_for_one
    )

  TayoriDev.Seeds.run()

  IO.puts("Tayori development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
