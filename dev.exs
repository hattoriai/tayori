# The Tayori development server: `mix dev`, then http://localhost:4099.
#
# One Phoenix endpoint with a small app ("Atelier", a studio's project
# tool), its news and its campaigns (letters to its people, a table of
# its own in the same database): the admin at /admin/news (Tayori's theme) and
# /sumi/news (the Sumi theme), the news in the app at /, the public page
# at /changelog, and /elsewhere, a site on another origin with the news
# (the :embed feature: localhost and 127.0.0.1 are two origins). The entries are in SQLite (tmp/dev.sqlite3), the
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
Application.put_env(:tayori, TayoriDev.Mailer, adapter: Swoosh.Adapters.Local)
Application.put_env(:swoosh, :local, true)

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

defmodule TayoriDev.CampaignsMigration do
  @moduledoc false
  # The campaigns' tables, and Atelier's people, whom they write to.
  use Ecto.Migration

  def up do
    Tayori.Migrations.up(version: 2)

    create table(:atelier_people) do
      add :name, :string
      add :email, :string
      add :locale, :string
      add :plan, :string
      add :projects, :integer, null: false, default: 0
      add :marketing, :boolean, null: false, default: false
      add :closed_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end
  end

  def down do
    drop table(:atelier_people)
    Tayori.Migrations.down(to: 1)
  end
end

defmodule TayoriDev.Person do
  @moduledoc "A person of Atelier: the campaigns write to them."
  use Ecto.Schema

  schema "atelier_people" do
    field :name, :string
    field :email, :string
    field :locale, :string
    field :plan, :string
    field :projects, :integer, default: 0
    field :marketing, :boolean, default: false
    field :closed_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end

defmodule TayoriDev.Audience do
  @moduledoc "Atelier's people, as the campaigns see them: those whose account is open."
  @behaviour Tayori.Audience

  import Ecto.Query

  alias Tayori.Audience
  alias TayoriDev.Person

  @impl true
  def query, do: from(p in Person, as: :person, where: is_nil(p.closed_at))

  @impl true
  def where_ids(query, ids) do
    ids = for "person:" <> id <- ids, {id, ""} <- [Integer.parse(id)], do: id
    where(query, [person: p], p.id in ^ids)
  end

  @impl true
  def recipient(%Person{} = person) do
    %Tayori.Recipient{
      id: "person:#{person.id}",
      email: person.email,
      name: person.name,
      locale: person.locale,
      since: person.inserted_at,
      data: %{
        "first_name" => person.name |> String.split() |> List.first(),
        "plan" => person.plan,
        "dashboard_url" => "http://localhost:#{System.get_env("PORT", "4099")}/",
        "marketing" => person.marketing
      }
    }
  end

  @impl true
  def person_id, do: dynamic([person: p], fragment("'person:' || CAST(? AS TEXT)", p.id))

  @impl true
  def attributes do
    [
      Audience.attribute(:name, "Name", :string, dynamic([person: p], p.name)),
      Audience.attribute(:email, "Email", :string, dynamic([person: p], p.email)),
      Audience.attribute(
        :plan,
        "Plan",
        {:enum, [{"free", "Free"}, {"pro", "Pro"}, {"studio", "Studio"}]},
        dynamic([person: p], p.plan)
      ),
      Audience.attribute(:projects, "Projects", :integer, dynamic([person: p], p.projects),
        description: "How many projects they made."
      ),
      Audience.attribute(
        :signed_up_at,
        "Signed up",
        :datetime,
        dynamic([person: p], p.inserted_at)
      ),
      Audience.attribute(
        :marketing,
        "Takes news and offers",
        :boolean,
        dynamic([person: p], p.marketing)
      ),
      Audience.attribute(:locale, "Language", :string, dynamic([person: p], p.locale))
    ]
  end

  @impl true
  def events do
    [
      {"signed_up", "Signed up"},
      {"project_created", "Made a project"},
      {"invited_teammate", "Invited a teammate"}
    ]
  end

  @impl true
  def can_email?(%Tayori.Recipient{data: data}, :marketing), do: data["marketing"] == true
  def can_email?(_recipient, :product), do: true
end

# Atelier's news: eight entries with screenshots, in dev/seeds.exs; its
# people, segments and campaigns in dev/campaign_seeds.exs.
Code.require_file("dev/seeds.exs", __DIR__)
Code.require_file("dev/campaign_seeds.exs", __DIR__)

defmodule TayoriDev.Mailer do
  @moduledoc "Atelier's mailer: the emails stay in memory, at /dev/mailbox."
  use Swoosh.Mailer, otp_app: :tayori
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

  # The address prefills the campaigns' test letters.
  @impl true
  def author(user) do
    author = %{"id" => user.id, "name" => user.name}
    if user[:email], do: Map.put(author, "email", user.email), else: author
  end

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

  defp reader(%{plan: plan, team_role: team_role} = user) do
    %Tayori.Reader{
      id: "user:#{user.id}",
      segments: ["plan:#{plan}", "role:#{team_role}"],
      locale: user.locale,
      since: ~U[2026-01-01 00:00:00Z]
    }
  end

  defp reader(_visitor), do: nil
end

defmodule TayoriDev.Who do
  @moduledoc "The person of the request, from `?as=`, kept in the session."
  import Plug.Conn

  @people %{
    "admin" => %{
      id: 1,
      name: "Hattori Hanzo",
      email: "hanzo@atelier.test",
      role: :admin,
      plan: "pro",
      team_role: "owner",
      locale: "en"
    },
    "viewer" => %{
      id: 2,
      name: "Viewer",
      email: "viewer@atelier.test",
      role: :viewer,
      plan: "pro",
      team_role: "member",
      locale: "en"
    },
    "pro" => %{
      id: 3,
      name: "Ada Okafor",
      role: :reader,
      plan: "pro",
      team_role: "owner",
      locale: "en"
    },
    "member" => %{
      id: 5,
      name: "Noah Kim",
      role: :reader,
      plan: "pro",
      team_role: "member",
      locale: "en"
    },
    "free" => %{
      id: 4,
      name: "Grace Moreira",
      role: :reader,
      plan: "free",
      team_role: "owner",
      locale: "pt-PT"
    },
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
  @moduledoc "Atelier: the app whose news this is, in a LiveView."
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <TayoriDev.Layouts.shell dev_user={@dev_user} here="/">
      <:button><Tayori.Components.news_button tayori={@tayori} /></:button>
      <TayoriDev.Layouts.projects />
    </TayoriDev.Layouts.shell>
    <Tayori.Components.news_panel tayori={@tayori} />
    <Tayori.Components.announcement tayori={@tayori} />
    """
  end
end

defmodule TayoriDev.PlainController do
  @moduledoc "A page with no LiveView: the news through <tayori-news> and the JSON API."
  use Phoenix.Controller, formats: [:html]

  alias Phoenix.HTML.Safe

  def show(conn, _params) do
    inner =
      %{dev_user: conn.assigns[:dev_user], here: conn.request_path}
      |> TayoriDev.Layouts.plain_page()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()

    html(
      conn,
      %{conn: conn, inner_content: Phoenix.HTML.raw(inner)}
      |> TayoriDev.Layouts.root()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
    )
  end
end

defmodule TayoriDev.ElsewhereController do
  @moduledoc """
  Atelier's help centre, a site on another origin: the app is on one of
  localhost and 127.0.0.1, the site on the other. It loads the script and
  the style sheet from the app's API, and its server gives the element
  the token of the person of `?as=`, as a site's backend would.
  """
  use Phoenix.Controller, formats: [:html]
  use Phoenix.Component

  alias Phoenix.HTML.Safe

  def show(conn, _params) do
    app_host = if conn.host == "localhost", do: "127.0.0.1", else: "localhost"
    reader = TayoriDev.Resolver.resolve_reader(conn)

    assigns = %{
      api: "http://#{app_host}:#{conn.port}/embed/news",
      token: reader && Tayori.Embed.token(reader),
      dev_user: conn.assigns[:dev_user],
      sumi: conn.query_params["theme"] == "sumi",
      dark: conn.query_params["dark"] != nil
    }

    html(conn, assigns |> page() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  defp page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme={@dark && "dark"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Atelier · Help centre</title>
        <link rel="stylesheet" href={@api <> if(@sumi, do: "/tayori-sumi.css", else: "/tayori.css")} />
        <script type="module" src={@api <> "/tayori.js"}>
        </script>
        <style>
          body { margin: 0; background: #f6f4ef; color: #1f1d1a; font: 15px/1.6 Georgia, serif; }
          [data-theme="dark"] body { background: #17161a; color: #eceae6; }
          header { display: flex; align-items: center; gap: 1rem; padding: 1rem 2rem; border-bottom: 1px solid #e2ddd3; }
          header strong { font-size: 1.125rem; }
          header nav { display: flex; gap: 1.25rem; margin-left: auto; align-items: center; font: 14px system-ui, sans-serif; }
          header a { color: inherit; }
          main { max-width: 40rem; padding: 3rem 2rem; }
          code { font-size: 0.875em; }
        </style>
      </head>
      <body>
        <div id="banner"></div>
        <header>
          <strong>Atelier help centre</strong>
          <nav>
            <a href="#">Guides</a>
            <a href="#">Contact</a>
            <tayori-news api={@api} reader-token={@token} banner="#banner"></tayori-news>
          </nav>
        </header>
        <main>
          <h1>A site on another origin</h1>
          <p>
            This page is on another origin than the app's API (<code>{@api}</code>). It loads
            <code>tayori.js</code> and <code>tayori.css</code> from the API, and the element reads
            the news over CORS, with the token the server signed for {if @dev_user,
              do: @dev_user.name,
              else: "no one: you are a visitor"}.
          </p>
          <p>
            Be <a href="?as=pro">a Pro owner</a>, <a href="?as=free">a Free reader (pt-PT)</a>
            or <a href="?as=visitor">a visitor</a>.
          </p>
        </main>
      </body>
    </html>
    """
  end
end

defmodule TayoriDev.Layouts do
  @moduledoc "Atelier's own layout: a studio's project tool, with its news."
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme={@conn.query_params["dark"] && "dark"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Atelier</title>
        <link
          rel="icon"
          href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%23256d5a'/%3E%3Ctext x='16' y='22' font-family='sans-serif' font-size='17' font-weight='700' fill='white' text-anchor='middle'%3EA%3C/text%3E%3C/svg%3E"
        />
        <link rel="stylesheet" href="/deps/kotoba/kotoba.css" />
        <link :if={sumi?(@conn)} rel="stylesheet" href="/deps/kotoba/kotoba-sumi.css" />
        <link rel="stylesheet" href="/assets/tayori.css" />
        <link :if={sumi?(@conn)} rel="stylesheet" href="/assets/tayori-sumi.css" />
        <style>
          :root { --atelier-accent: #2e6b5c; --atelier-bg: #faf9f7; --atelier-side: #f3f1ed; --atelier-line: #e7e3dc; --atelier-ink: #1f1d1a; --atelier-muted: #79736a; }
          [data-theme="dark"] { --atelier-bg: #17161a; --atelier-side: #1e1d21; --atelier-line: #2c2a30; --atelier-ink: #eceae6; --atelier-muted: #9c968e; --atelier-accent: #6fbfa5; }
          * { box-sizing: border-box; }
          body { margin: 0; background: var(--atelier-bg); color: var(--atelier-ink); font: 15px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; -webkit-font-smoothing: antialiased; }
          a { color: inherit; }
          .app { display: grid; grid-template-columns: 15rem 1fr; min-height: 100vh; }
          .side { display: flex; flex-direction: column; gap: 1.25rem; padding: 1rem 0.75rem; background: var(--atelier-side); border-right: 1px solid var(--atelier-line); }
          .studio { display: flex; align-items: center; gap: 0.5rem; padding: 0.25rem 0.5rem; font-weight: 600; }
          .studio span { display: grid; place-items: center; width: 1.5rem; height: 1.5rem; border-radius: 6px; background: var(--atelier-ink); color: var(--atelier-bg); font-size: 0.75rem; }
          .side nav { display: grid; gap: 1px; }
          .side nav a, .side nav p { display: flex; align-items: center; gap: 0.5rem; margin: 0; padding: 0.375rem 0.5rem; border-radius: 6px; color: var(--atelier-muted); font-size: 0.875rem; text-decoration: none; }
          .side nav a:hover, .side nav a[aria-current] { background: color-mix(in oklab, var(--atelier-ink) 6%, transparent); color: var(--atelier-ink); }
          .side h3 { margin: 0; padding: 0 0.5rem; color: var(--atelier-muted); font-size: 0.6875rem; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; }
          .dot { width: 0.5rem; height: 0.5rem; border-radius: 99px; }
          .main { display: flex; flex-direction: column; min-width: 0; }
          .top { display: flex; align-items: center; gap: 1rem; height: 3.5rem; padding: 0 1.5rem; border-bottom: 1px solid var(--atelier-line); }
          .top h1 { margin: 0; font-size: 0.9375rem; font-weight: 600; }
          .top .actions { display: flex; align-items: center; gap: 0.5rem; margin-left: auto; }
          .avatar { display: grid; place-items: center; width: 1.875rem; height: 1.875rem; border-radius: 99px; background: #b5643c; color: #fff; font-size: 0.6875rem; font-weight: 600; }
          .content { padding: 2rem 1.5rem; max-width: 64rem; }
          .content h2 { margin: 0 0 0.25rem; font-size: 1.5rem; letter-spacing: -0.02em; }
          .content > p { margin: 0 0 1.5rem; color: var(--atelier-muted); }
          .projects { display: grid; grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr)); gap: 1rem; }
          .project { padding: 1rem; border: 1px solid var(--atelier-line); border-radius: 10px; background: var(--atelier-bg); }
          .project strong { display: flex; align-items: center; gap: 0.5rem; font-size: 0.9375rem; }
          .project p { margin: 0.375rem 0 0.75rem; color: var(--atelier-muted); font-size: 0.8125rem; }
          .bar { height: 4px; border-radius: 99px; background: var(--atelier-line); overflow: hidden; }
          .bar span { display: block; height: 100%; background: var(--atelier-accent); }
          .dev { margin-top: auto; padding: 0.75rem; border: 1px dashed var(--atelier-line); border-radius: 8px; font-size: 0.75rem; color: var(--atelier-muted); }
          .dev p { margin: 0 0 0.375rem; }
          .dev a { display: inline-block; margin: 0 0.375rem 0.25rem 0; }
          .dev a[aria-current] { color: var(--atelier-ink); font-weight: 600; text-decoration: none; }
          .dev-main { max-width: 40rem; padding: 2rem 1.5rem; }
          .own-news { position: relative; font: inherit; background: none; border: 1px solid var(--atelier-line); border-radius: 8px; padding: 0.375rem 0.75rem; cursor: pointer; }
          .own-news-dot { position: absolute; top: 0.25rem; right: 0.25rem; width: 0.5rem; height: 0.5rem; border-radius: 99px; background: #c47a35; }
          .own-news-dot[hidden] { display: none; }
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

  defp sumi?(conn), do: conn.query_params["theme"] == "sumi"

  attr :dev_user, :map, default: nil
  attr :here, :string, required: true
  slot :button
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <div class="app">
      <aside class="side">
        <div class="studio"><span>H</span>Hattori Studio</div>
        <nav>
          <a href="/" aria-current={@here == "/" && "page"}>Projects</a>
          <p>Inbox</p>
          <p>My work</p>
          <p>Calendar</p>
          <a href="/plain" aria-current={@here == "/plain" && "page"}>A page without LiveView</a>
          <a href="/plain/own" aria-current={@here == "/plain/own" && "page"}>With a button of its own</a>
          <a href="/elsewhere">A site on another origin</a>
          <a href="/changelog">Changelog</a>
          <a href="/admin/news">Write the news</a>
        </nav>
        <h3>Projects</h3>
        <nav>
          <p :for={{name, color} <- projects()}><span class="dot" style={"background:#{color}"}></span>{name}</p>
        </nav>
        <div class="dev">
          <p>You are {(@dev_user && @dev_user.name) || "a visitor"}. Be:</p>
          <a
            :for={{as, label} <- [{"admin", "Admin"}, {"pro", "Pro owner"}, {"member", "Pro member"}, {"free", "Free (pt-PT)"}, {"visitor", "Visitor"}]}
            href={"#{@here}?as=#{as}"}
          >
            {label}
          </a>
          <p>Theme: <a href={@here}>Tayori</a><a href={"#{@here}?theme=sumi"}>Sumi</a><a href={"#{@here}?dark=1"}>Dark</a></p>
        </div>
      </aside>
      <div class="main">
        <header class="top">
          <h1>Projects</h1>
          <div class="actions">
            {render_slot(@button)}
            <span class="avatar">{initials(@dev_user)}</span>
          </div>
        </header>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  def projects(assigns) do
    ~H"""
    <div class="content">
      <h2>Projects</h2>
      <p>Five projects this month. The news button, top right, has what is new in Atelier.</p>
      <div class="projects">
        <div :for={{{name, color}, done} <- Enum.zip(projects(), [64, 30, 82, 12, 47])} class="project">
          <strong><span class="dot" style={"background:#{color}"}></span>{name}</strong>
          <p>{done}% done · due in {div(100 - done, 4)} days</p>
          <div class="bar"><span style={"width:#{done}%"}></span></div>
        </div>
      </div>
    </div>
    """
  end

  def plain_page(%{here: "/plain/own"} = assigns) do
    ~H"""
    <.shell dev_user={@dev_user} here={@here}>
      <:button>
        <%!-- A classic script, before the element is defined: it hears the first count. --%>
        <script>
          document.addEventListener("tayori:unread", (event) => {
            const own = document.getElementById("own-news")
            own.querySelector(".own-news-dot").hidden = event.detail.count === 0
            own.setAttribute("aria-label", event.detail.count ? "What's new, new updates" : "What's new")
          })
          document.addEventListener("click", (event) => {
            const own = event.target.closest("#own-news")
            if (own) document.querySelector("tayori-news").toggle(own)
          })
        </script>
        <button type="button" id="own-news" class="own-news" aria-label="What's new">
          What's new <span class="own-news-dot" hidden></span>
        </button>
        <tayori-news api="/api/news" button="none"></tayori-news>
      </:button>
      <div class="dev-main">
        <h2>With a button of its own</h2>
        <p>
          <code>&lt;tayori-news button="none"&gt;</code> draws no button: the page's own
          opens the panel with <code>toggle(button)</code>, and shows a dot when
          <code>tayori:unread</code> says something is new.
        </p>
      </div>
    </.shell>
    """
  end

  def plain_page(assigns) do
    ~H"""
    <.shell dev_user={@dev_user} here={@here}>
      <:button><tayori-news api="/api/news"></tayori-news></:button>
      <div class="dev-main">
        <h2>A page without LiveView</h2>
        <p>
          The button at the top is <code>&lt;tayori-news&gt;</code>, a web component that reads
          the JSON API: for a frontend that Phoenix does not render.
        </p>
      </div>
    </.shell>
    """
  end

  defp projects do
    [
      {"Harbour Museum rebrand", "#2e6b5c"},
      {"Kiln & Co. catalogue", "#c47a35"},
      {"Northfield Library signage", "#4a68a8"},
      {"Tamsin Ceramics shop", "#b5485d"},
      {"Orchard Street Bakery", "#7b62a8"}
    ]
  end

  defp initials(nil), do: "?"

  defp initials(%{name: name}),
    do: name |> String.split() |> Enum.map_join(&String.first/1) |> String.slice(0, 2)
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

  # The JSON API for the sites of the :embed feature: no session, no
  # CSRF protection; a reader comes with a token.
  pipeline :embed do
    plug :accepts, ["json"]
  end

  scope "/embed" do
    pipe_through :embed

    tayori_api("/news",
      resolver: TayoriDev.Resolver,
      page: "http://localhost:#{System.get_env("PORT", "4099")}/changelog",
      as: :tayori_embed
    )
  end

  # The JSON API for machines (the Automation guide): no session, no CSRF
  # protection; CI and GitHub prove who they are with a token or a
  # signature.
  pipeline :machines do
    plug :accepts, ["json"]
  end

  scope "/api/machines" do
    pipe_through :machines
    tayori_api("/news", resolver: TayoriDev.Resolver, as: :tayori_machines)
  end

  scope "/admin" do
    pipe_through :browser

    tayori_admin("/news",
      resolver: TayoriDev.Resolver,
      on_mount: [TayoriDev.Who],
      page: "/changelog"
    )
  end

  scope "/sumi" do
    pipe_through :browser

    tayori_admin("/news",
      resolver: TayoriDev.Resolver,
      on_mount: [TayoriDev.Who],
      theme: :sumi,
      page: "/sumi/changelog",
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
    get "/plain/own", TayoriDev.PlainController, :show
    get "/elsewhere", TayoriDev.ElsewhereController, :show

    tayori_page("/changelog",
      title: "What's new in Atelier",
      eyebrow: "Atelier · Changelog",
      description:
        "New features, improvements and fixes, every week, from the studio that makes Atelier.",
      resolver: TayoriDev.Resolver
    )

    tayori_page("/sumi/changelog",
      title: "What's new in Atelier",
      eyebrow: "Atelier · Changelog",
      description:
        "New features, improvements and fixes, every week, from the studio that makes Atelier.",
      resolver: TayoriDev.Resolver,
      theme: :sumi,
      as: :tayori_page_sumi
    )
  end

  # The campaigns' letters: the page to unsubscribe, and the mail
  # providers' webhooks. No session, no CSRF token.
  pipeline :letters do
    plug :accepts, ["html", "json"]
  end

  scope "/" do
    pipe_through :letters
    tayori_mail("/letters")
  end

  scope "/dev" do
    pipe_through :browser
    forward "/mailbox", Plug.Swoosh.MailboxPreview
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
  plug Plug.Static, at: "/dev-seed", from: Path.expand("dev/seed", __DIR__)

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
          fonts = File.read!(Path.expand("assets/css/sumi-fonts.css", File.cwd!()))
          css = source |> File.read!() |> String.replace("/* @tayori-sumi-fonts */", fonts)
          File.mkdir_p!("priv/static")
          File.write!(Path.join("priv/static", file), css)
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

  Ecto.Migrator.run(
    TayoriDev.Repo,
    [{0, TayoriDev.Migration}, {1, TayoriDev.CampaignsMigration}],
    :up,
    all: true,
    log: false
  )

  {:ok, _pid} =
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: TayoriDev.PubSub},
        {Tayori,
         repo: TayoriDev.Repo,
         pubsub: TayoriDev.PubSub,
         secret_key_base: String.duplicate("tayori-development-secret-", 3),
         locales: [{"en", "English"}, {"pt-PT", "Português"}],
         features: [:reactions, :announcements, :analytics, :subscriptions, :webhooks, :embed],
         embed: [origins: ["http://localhost:#{port}", "http://127.0.0.1:#{port}"]],
         mailer: TayoriDev.Mailer,
         email_from: {"Atelier", "news@atelier.test"},
         modules: [:changelog, :campaigns],
         campaigns: [
           audience: TayoriDev.Audience,
           url: "http://localhost:#{port}/letters",
           from: {"Hanzo at Atelier", "hanzo@atelier.test"},
           reply_to: "hanzo@atelier.test",
           providers: [
             resend: [secret: "whsec_" <> Base.encode64("atelier-development-signing-key")]
           ]
         ],
         page_url: "http://localhost:#{port}/changelog",
         inbox: [
           sources: [
             {Tayori.Sources.Changelog, path: Path.expand("dev/CHANGELOG.md")},
             {Tayori.Sources.Fragments, path: Path.expand("dev/news")}
           ],
           kinds: %{
             "added" => "new",
             "feature" => "new",
             "fixed" => "fixed",
             "improved" => "improved"
           }
         ]},
        TayoriDev.Endpoint
      ] ++ if(watch?, do: [TayoriDev.CSSCopier], else: []),
      strategy: :one_for_one
    )

  TayoriDev.Seeds.run()
  TayoriDev.CampaignSeeds.run()

  IO.puts("Tayori development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
