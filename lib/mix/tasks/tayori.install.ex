defmodule Mix.Tasks.Tayori.Install do
  @moduledoc """
  Installs Tayori in a Phoenix application.

      $ mix igniter.install tayori

  or, with Tayori already in the deps, `mix tayori.install`.
  [Igniter](https://hexdocs.pm/igniter) shows each change as a diff
  before it writes, and running the task again changes nothing:

    * the router mounts the admin at `/admin/news` and the public page at
      `/changelog` (`tayori_admin/2`, `tayori_page/2`);
    * the migration of Tayori's tables (`mix tayori.gen.migration`);
    * `assets/js/app.js` imports the `Tayori` hook and adds it to the
      `LiveSocket`;
    * `assets/css/app.css` imports kotoba.css and tayori.css, and the Sumi
      theme as a comment;
    * the application starts Tayori after the repo and the PubSub, with
      `oban: Oban` when the app has Oban (`Tayori.Jobs`);
    * `lib/my_app_web/tayori_resolver.ex`, the resolver, which lets no one
      in the admin until you say who your admins are.

  Then put `{Tayori.Live, MyAppWeb.TayoriResolver}` in the `on_mount` of
  your `live_session`, and the news button and panel in your layout: see
  the [Quickstart](quickstart.md).
  """

  use PhoenixMountable.Install,
    otp_app: :tayori,
    mounts: [
      {Tayori.Router, "/news", scope: "/admin", options: "resolver: {web}.TayoriResolver"},
      {Tayori.Router.Page, "/changelog", import: Tayori.Router}
    ],
    migrations: Tayori.Migrations,
    hook: {"Tayori", "tayori"},
    css: ["tayori.css", {"tayori-sumi.css", :comment}],
    manual: "See https://hexdocs.pm/tayori/quickstart.html"

  if Code.ensure_loaded?(Igniter) do
    alias Igniter.Libs.Phoenix, as: Phx
    alias Igniter.Project.Application, as: App
    alias Igniter.Project.Deps
    alias Igniter.Project.Module, as: Mod

    @impl PhoenixMountable.Install
    def install(igniter) do
      app = App.app_name(igniter)
      prefix = Mod.module_name_prefix(igniter)
      web = Phx.web_module(igniter)
      repo = Module.concat(prefix, Repo)
      pubsub = Module.concat(prefix, PubSub)
      endpoint = Module.concat(web, Endpoint)

      options =
        quote do
          [
            repo: unquote(repo),
            pubsub: unquote(pubsub),
            secret_key_base:
              Application.fetch_env!(unquote(app), unquote(endpoint))[:secret_key_base],
            locales: ["en"]
          ]
        end

      # An app with Oban gives it what a publication sends, in its
      # :default queue: see Tayori.Jobs.
      options =
        if Deps.has_dep?(igniter, :oban),
          do: options ++ [oban: Oban],
          else: options

      igniter
      |> PhoenixMountable.Igniter.add_css_imports(:kotoba, ["kotoba.css"])
      |> App.add_new_child({Tayori, {:code, options}},
        after: [repo, pubsub, Phoenix.PubSub, Oban]
      )
      |> resolver(Module.concat(web, TayoriResolver))
    end

    # Written once: the app's own after that.
    defp resolver(igniter, module) do
      case Mod.module_exists(igniter, module) do
        {true, igniter} -> igniter
        {false, igniter} -> Mod.create_module(igniter, module, resolver())
      end
    end

    defp resolver do
      ~S'''
      @moduledoc """
      Who writes the news in the admin, and who reads it. See
      `Tayori.Resolver`.
      """
      @behaviour Tayori.Resolver

      # The admin, from the request: the pipeline of the admin's scope has
      # run. Return nil for nobody.
      @impl true
      def resolve_user(conn), do: conn.assigns[:current_scope] && conn.assigns.current_scope.user

      # What the admin may do: :all, :read_only, :forbidden, or
      # {:forbidden, path} to send them there. Change it to your admins.
      @impl true
      def resolve_access(nil), do: {:forbidden, "/"}
      def resolve_access(_user), do: :forbidden

      # The reader, from a request or a LiveView socket, after your own
      # on_mount hooks. Nil is a visitor.
      @impl true
      def resolve_reader(%{assigns: %{current_scope: %{user: user}}}) when not is_nil(user) do
        %Tayori.Reader{id: "user:#{user.id}", segments: [], since: user.inserted_at}
      end

      def resolve_reader(_visitor), do: nil
      '''
    end
  end
end
