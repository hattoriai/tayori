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

  `tayori_admin/2` mounts the admin (see the [Admin](admin.md) guide),
  `tayori_api/2` the news as JSON, for a frontend that Phoenix does not
  render (see [Any frontend](any_frontend.md)), and `tayori_page/2` the
  public page and its feeds (see [The public page](public_page.md)).
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

        get "/assets/:asset", Tayori.Assets, :serve, as: :tayori_admin_asset

        live_session session_name, session_opts do
          live "/", Tayori.Admin.EntriesLive, :index, as: :tayori_admin
          live "/new", Tayori.Admin.EntryLive, :new, as: :tayori_admin
          live "/settings", Tayori.Admin.SettingsLive, :index, as: :tayori_admin
          live "/:id", Tayori.Admin.EntryLive, :edit, as: :tayori_admin
        end
      end
    end
  end

  @doc """
  Mounts the news as JSON at `path` (see `Tayori.API` for the routes).
  Mount it behind a pipeline with the app's session.

  Options:

    * `:resolver` - the app's `Tayori.Resolver`, which reads the reader
      from the conn (required).
    * `:page` - the path of the public page, for the `url` of each entry.
  """
  defmacro tayori_api(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      private = %{tayori_api: Tayori.Router.__api__(opts)}

      scope path, alias: false, as: false do
        get "/", Tayori.API, :index, private: private, as: :tayori_api
        get "/unread", Tayori.API, :unread, private: private, as: :tayori_api
        post "/seen", Tayori.API, :seen, private: private, as: :tayori_api
        get "/:slug", Tayori.API, :show, private: private, as: :tayori_api
      end
    end
  end

  @doc """
  Mounts the public page of the news at `path`, with its entries one by
  one and its feeds (see `Tayori.Page`).

  Options:

    * `:title` - the title of the page and the feeds ("What's new", in
      the reader's language).
    * `:resolver` - the app's `Tayori.Resolver`: a reader it gives sees
      the entries for them too. Without it, the page shows the entries for
      everyone.
    * `:layout` - the app's root layout, `{module, function}`, instead of
      Tayori's own document.
    * `:theme` - `:tayori` or `:sumi`, for Tayori's own document (`:tayori`).
    * `:limit` - the entries of a page (20).
    * `:url` - the address of the app (`"https://example.com"`), for the
      links of the feeds, when the conn does not have it (behind a proxy).
    * `:csp_nonce_assign_key` - the key of `conn.assigns` with the nonce of
      the app's Content Security Policy, for the style sheet.
  """
  defmacro tayori_page(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      prefix = Phoenix.Router.scoped_path(__MODULE__, path)
      private = %{tayori_page: Tayori.Router.__page__(prefix, opts)}

      scope path, alias: false, as: false do
        get "/", Tayori.Page, :index, private: private, as: :tayori_page
        get "/feed.xml", Tayori.Page, :atom, private: private, as: :tayori_page
        get "/feed.json", Tayori.Page, :json, private: private, as: :tayori_page
        get "/assets/:asset", Tayori.Assets, :serve, as: :tayori_page_asset
        get "/:slug", Tayori.Page, :show, private: private, as: :tayori_page
      end
    end
  end

  @doc false
  def __api__(opts) do
    check_opts!(:tayori_api, opts, [:resolver, :page])

    %{
      resolver:
        Keyword.get(opts, :resolver) ||
          raise(
            ArgumentError,
            "tayori_api needs a :resolver, a module of the Tayori.Resolver behaviour"
          ),
      page: opts[:page]
    }
  end

  @doc false
  def __page__(prefix, opts) do
    check_opts!(:tayori_page, opts, [
      :title,
      :resolver,
      :layout,
      :theme,
      :limit,
      :url,
      :csp_nonce_assign_key
    ])

    theme = Keyword.get(opts, :theme, :tayori)

    unless theme in @themes do
      raise ArgumentError, ":theme of tayori_page must be one of #{inspect(@themes)}"
    end

    %{
      prefix: prefix,
      title: opts[:title],
      resolver: opts[:resolver],
      layout: opts[:layout],
      theme: theme,
      limit: Keyword.get(opts, :limit, 20),
      url: opts[:url],
      csp_nonce_assign_key: opts[:csp_nonce_assign_key]
    }
  end

  defp check_opts!(macro, opts, known) do
    Enum.each(Keyword.keys(opts), fn key ->
      unless key in known do
        raise ArgumentError,
              "unknown option #{inspect(key)} of #{macro}; the options are: #{inspect(known)}"
      end
    end)
  end

  @doc false
  def __admin__(prefix, opts) do
    check_opts!(:tayori_admin, opts, @admin_opts)

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
