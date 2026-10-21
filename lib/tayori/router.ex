defmodule Tayori.Router do
  @moduledoc """
  Mounts Tayori in the app's router.

      import Tayori.Router

      scope "/admin" do
        pipe_through [:browser, :require_admin]

        tayori_admin "/news",
          resolver: MyAppWeb.TayoriResolver,
          on_mount: [{MyAppWeb.AdminAuth, :require_admin}]
      end

      scope "/api" do
        pipe_through :api_session
        tayori_api "/news", resolver: MyAppWeb.TayoriResolver
      end

      scope "/" do
        pipe_through :browser
        tayori_page "/changelog", title: "What's new in MyApp"
      end

      # The campaigns' letters: no session, no CSRF token.
      pipeline :letters do
        plug :accepts, ["html", "json"]
      end

      scope "/" do
        pipe_through :letters
        tayori_mail "/letters"
      end

  `tayori_admin/2` mounts the admin (see the [Admin](admin.md) guide),
  `tayori_api/2` the news as JSON, for a frontend that Phoenix does not
  render (see [Any frontend](any_frontend.md)), and `tayori_page/2` the
  public page and its feeds (see [The public page](public_page.md)), and
  `tayori_mail/2` the addresses of the campaigns' letters, to unsubscribe
  and for the mail providers' webhooks (see `Tayori.Campaigns.Mount`). Each
  is a library mounted with [PhoenixMountable](https://hexdocs.pm/phoenix_mountable):
  ordinary routes in the app's router (`mix phx.routes` lists them),
  behind the app's own scopes and pipelines. Every mount also takes the
  options of PhoenixMountable: `:as` (to mount one twice), `:on_mount`,
  `:socket_path`, `:transport`, `:csp_nonce_assign_key`, `:asset_host`
  and `:pubsub`.

  The admin is a page of its own, as Lotus's dashboard is: its own
  document, script and style sheet, served under the mount with the hash
  of the build in their names, so it looks the same in any app.
  """

  alias Tayori.Router.{API, Mail, Page}

  use PhoenixMountable,
    otp_app: :tayori,
    macro: :tayori_admin,
    title: "Tayori",
    layout: {Tayori.Admin.Layouts, :root},
    on_mount: [Tayori.Admin.Auth],
    schema: Tayori.Migrations,
    assets:
      {PhoenixMountable.Assets.Embedded,
       css: [
         {:kotoba, "priv/static/kotoba.css"},
         {:koyomi, "priv/static/koyomi.css"},
         "priv/static/tayori.css",
         "priv/static/tayori-admin.css"
       ],
       sumi: [
         {:kotoba, "priv/static/kotoba.css"},
         {:kotoba, "priv/static/kotoba-sumi.css"},
         {:koyomi, "priv/static/koyomi.css"},
         {:koyomi, "priv/static/koyomi-sumi.css"},
         "priv/static/tayori.css",
         "priv/static/tayori-sumi.css",
         "priv/static/tayori-admin.css"
       ],
       js: "priv/static/tayori-admin.js"}

  options(
    resolver: [
      type: :atom,
      required: true,
      verify: {:behaviour, Tayori.Resolver},
      doc: "The app's `Tayori.Resolver`: who the admin is, and what they may do."
    ],
    theme: [
      type: {:in, [:tayori, :sumi]},
      default: :tayori,
      doc: "The admin's theme: Tayori's own, or Sumi's."
    ],
    page: [
      type: :string,
      doc:
        "The path of the public page, for the admin's links to the entries and their previews. By default, the `tayori_page` of the same router."
    ],
    storage: [
      type: :atom,
      doc:
        "The `Kotoba.Storage` of the attachments of the editor (Kotoba's own config when not given)."
    ]
  )

  routes do
    live "/", Tayori.Admin.EntriesLive, :index
    live "/new", Tayori.Admin.EntryLive, :new
    live "/inbox", Tayori.Admin.InboxLive, :index
    live "/categories", Tayori.Admin.CategoriesLive, :index
    live "/settings", Tayori.Admin.SettingsLive, :index
    live "/:id", Tayori.Admin.EntryLive, :edit
  end

  # The admin, read from the request of the page, after the app's own
  # pipeline: it goes into the LiveView's session.
  @impl PhoenixMountable
  def session(conn, mount, _session) do
    resolver = mount.options.resolver
    user = resolver.resolve_user(conn)
    %{"user" => user, "access" => resolver.resolve_access(user)}
  end

  @impl PhoenixMountable
  def repo(_mount) do
    Tayori.Config.get().repo
  rescue
    RuntimeError -> nil
  end

  @doc """
  Mounts the news as JSON at `path`: see `Tayori.Router.API` for the
  options, and `Tayori.API` for the routes.
  """
  defmacro tayori_api(path, opts \\ []) do
    quote do
      require unquote(API)
      unquote(API).tayori_api(unquote(path), unquote(opts))
    end
  end

  @doc """
  Mounts the public page of the news, its entries and its feeds at
  `path`: see `Tayori.Router.Page` for the options, and `Tayori.Page`
  for the routes.
  """
  defmacro tayori_page(path, opts \\ []) do
    quote do
      require unquote(Page)
      unquote(Page).tayori_page(unquote(path), unquote(opts))
    end
  end

  @doc """
  Mounts the addresses of the campaigns' letters at `path`, the `:url` of
  `:campaigns`: the page to unsubscribe and the mail providers' webhooks.
  See `Tayori.Campaigns.Mount` for the routes, and why its pipeline has no
  CSRF protection.
  """
  defmacro tayori_mail(path, opts \\ []) do
    quote do
      require unquote(Mail)
      unquote(Mail).tayori_mail(unquote(path), unquote(opts))
    end
  end
end
