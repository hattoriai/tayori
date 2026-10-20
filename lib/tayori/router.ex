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

  See the [Admin](admin.md) guide.
  """

  @admin_opts [:resolver, :on_mount, :csp_nonce_assign_key, :socket_path, :theme, :storage, :as]
  @themes [:tayori, :sumi]

  @doc """
  Mounts the admin at `path`: the entries, the editor, and the settings.
  It is a page of its own, with its own layout, styles and scripts, so it
  looks the same in any app. Mount it in a scope whose pipeline lets in
  only the app's admins: the resolver then says what each may do.

  Options:

    * `:resolver` - the app's `Tayori.Resolver` (required).
    * `:on_mount` - the app's own `on_mount` hooks, run before Tayori's,
      on every mount and reconnect: check the admin's session there.
    * `:csp_nonce_assign_key` - the key of `conn.assigns` with the nonce
      of the app's Content Security Policy, or a map
      `%{style: key, script: key}`.
    * `:socket_path` - the path of the app's LiveView socket (`"/live"`).
    * `:theme` - `:tayori` or `:sumi` (`:tayori`).
    * `:storage` - the `Kotoba.Storage` of the attachments of the editor
      (Kotoba's own config when not given).
    * `:as` - the name of the live session (`:tayori_admin`).
  """
  defmacro tayori_admin(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      prefix = Phoenix.Router.scoped_path(__MODULE__, path)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        {session_name, session_opts} = Tayori.Router.__admin__(prefix, opts)

        get "/assets/:asset", Tayori.Admin.Assets, :serve, as: :tayori_admin_asset

        live_session session_name, session_opts do
          live "/", Tayori.Admin.EntriesLive, :index, as: :tayori_admin
          live "/new", Tayori.Admin.EntryLive, :new, as: :tayori_admin
          live "/settings", Tayori.Admin.SettingsLive, :index, as: :tayori_admin
          live "/:id", Tayori.Admin.EntryLive, :edit, as: :tayori_admin
        end
      end
    end
  end

  @doc false
  def __admin__(prefix, opts) do
    Enum.each(Keyword.keys(opts), fn key ->
      unless key in @admin_opts do
        raise ArgumentError,
              "unknown option #{inspect(key)} of tayori_admin; the options are: #{inspect(@admin_opts)}"
      end
    end)

    resolver =
      Keyword.get(opts, :resolver) ||
        raise ArgumentError,
              "tayori_admin needs a :resolver, a module of the Tayori.Resolver behaviour"

    theme = Keyword.get(opts, :theme, :tayori)

    unless theme in @themes do
      raise ArgumentError, ":theme of tayori_admin must be one of #{inspect(@themes)}"
    end

    csp = csp_keys(Keyword.get(opts, :csp_nonce_assign_key))
    socket_path = Keyword.get(opts, :socket_path, "/live")
    on_mount = List.wrap(Keyword.get(opts, :on_mount, [])) ++ [Tayori.Admin.Auth]

    session_opts = [
      on_mount: on_mount,
      session:
        {__MODULE__, :__admin_session__,
         [prefix, resolver, csp, socket_path, theme, opts[:storage]]},
      root_layout: {Tayori.Admin.Layouts, :root}
    ]

    {Keyword.get(opts, :as, :tayori_admin), session_opts}
  end

  defp csp_keys(nil), do: %{style: nil, script: nil}
  defp csp_keys(key) when is_atom(key), do: %{style: key, script: key}
  defp csp_keys(%{} = keys), do: %{style: keys[:style], script: keys[:script]}

  @doc false
  # Runs on the request of the page: the admin is read from the conn,
  # after the app's own pipeline.
  def __admin_session__(conn, prefix, resolver, csp, socket_path, theme, storage) do
    user = resolver.resolve_user(conn)

    %{
      "prefix" => prefix,
      "resolver" => resolver,
      "user" => user,
      "access" => resolver.resolve_access(user),
      "socket_path" => socket_path,
      "theme" => theme,
      "storage" => storage,
      "csp_nonces" => %{
        style: csp.style && conn.assigns[csp.style],
        script: csp.script && conn.assigns[csp.script]
      }
    }
  end
end
