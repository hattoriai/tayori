defmodule Tayori.Resolver do
  @moduledoc ~S"""
  How Tayori knows the people of the app: who may write the news in the
  admin, and who reads it. The app writes one module, from what it
  already has (its users, their plans and roles, its admin session), and
  gives it to the router macros (`Tayori.Router`) and to `Tayori.Live`:

      defmodule MyAppWeb.TayoriResolver do
        @behaviour Tayori.Resolver

        # The admin.

        @impl true
        def resolve_user(conn), do: conn.assigns[:current_admin]

        @impl true
        def resolve_access(%MyApp.Admin{}), do: :all
        def resolve_access(_nobody), do: {:forbidden, "/admin/login"}

        @impl true
        def author(admin), do: %{"id" => admin.id, "name" => admin.name}

        @impl true
        def segments do
          [
            {"Plan", [{"plan:free", "Free"}, {"plan:pro", "Pro"}]},
            {"Role", [{"role:owner", "Owners"}, {"role:editor", "Editors"}]}
          ]
        end

        # The readers.

        @impl true
        def resolve_reader(%{assigns: %{current_scope: %{user: user}}}) when not is_nil(user) do
          %Tayori.Reader{
            id: "user:#{user.id}",
            segments: ["plan:#{user.plan}", "role:#{user.role}"],
            locale: user.locale,
            since: user.inserted_at
          }
        end

        def resolve_reader(_visitor), do: nil
      end

  ## The admin

  `c:resolve_user/1` reads the admin from the request (the `Plug.Conn` of
  the page, after the app's own pipeline: mount the admin behind it, see
  the [Admin](admin.md) guide). `c:resolve_access/1` says what they may
  do:

    * `:all` - write, publish, delete, and change the settings;
    * `:read_only` - read the entries and the drafts, and change nothing;
    * `:forbidden` - nothing: the admin answers with a 404;
    * `{:forbidden, path}` - nothing: the admin sends them to `path`, such
      as the app's login page.

  Tayori fails closed: there is no default, and a resolver without these
  two functions does not compile.

  ## The readers

  `c:resolve_reader/1` builds a `Tayori.Reader` from a `Plug.Conn` (the
  JSON API and the public page) or from a LiveView socket (`Tayori.Live`,
  after the app's own `on_mount` hooks, so `socket.assigns` has the app's
  user). Nil is a visitor.

  ## The language of a visitor

  The public page and the JSON API speak the reader's language; for a
  visitor, the request's `?lang=`, else the browser's. An app that keeps
  its own choice of language (a cookie, the session, its locale plug)
  says it with `c:resolve_locale/1`, which then comes before the
  browser's:

      @impl true
      def resolve_locale(_conn), do: Gettext.get_locale(MyAppWeb.Gettext)
  """

  @type user :: term()
  @type access :: :all | :read_only | :forbidden | {:forbidden, String.t()}
  @type segment :: {String.t(), String.t()}

  @doc "The admin of the request, or nil."
  @callback resolve_user(Plug.Conn.t()) :: user()

  @doc "What the admin may do."
  @callback resolve_access(user()) :: access()

  @doc """
  Who wrote an entry, kept on it: a map with `"id"` and `"name"`. Without
  this function, entries have no author.
  """
  @callback author(user()) :: map() | nil

  @doc """
  The segments of readers an entry can be for, as the admin offers them:
  a list of `{segment, label}`, or of `{group, [{segment, label}]}`.
  Without this function, every entry is for everyone.
  """
  @callback segments() :: [segment() | {String.t(), [segment()]}]

  @doc "The reader of a request or a LiveView, or nil for a visitor."
  @callback resolve_reader(Plug.Conn.t() | Phoenix.LiveView.Socket.t()) :: Tayori.Reader.t() | nil

  @doc """
  The language the app speaks to the request, or nil: for a visitor of
  the public page and the JSON API, after `?lang=` and before the
  browser's `Accept-Language`. A locale of the app's that the entries are
  not written in takes one of the same language, else the first.
  """
  @callback resolve_locale(Plug.Conn.t()) :: String.t() | nil

  @optional_callbacks author: 1, segments: 0, resolve_reader: 1, resolve_locale: 1

  @doc false
  def author(resolver, user) do
    if exports?(resolver, :author, 1), do: resolver.author(user)
  end

  @doc false
  # The segments as groups, for the admin.
  def segment_groups(resolver) do
    if exports?(resolver, :segments, 0) do
      resolver.segments()
      |> Enum.chunk_by(&match?({_group, list} when is_list(list), &1))
      |> Enum.flat_map(fn
        [{_group, list} | _] = groups when is_list(list) -> groups
        segments -> [{nil, segments}]
      end)
    else
      []
    end
  end

  @doc false
  def reader(resolver, conn_or_socket) do
    if exports?(resolver, :resolve_reader, 1) do
      case resolver.resolve_reader(conn_or_socket) do
        %Tayori.Reader{} = reader -> reader
        nil -> nil
      end
    end
  end

  @doc false
  def locale(resolver, conn) do
    if exports?(resolver, :resolve_locale, 1) do
      case resolver.resolve_locale(conn) do
        locale when is_binary(locale) -> String.replace(locale, "_", "-")
        nil -> nil
      end
    end
  end

  defp exports?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end
end
