defmodule TayoriTest.Resolver do
  @moduledoc "The resolver of the tests: the admin and the reader are in the session."
  @behaviour Tayori.Resolver

  @impl true
  def resolve_user(conn), do: Plug.Conn.get_session(conn, "admin")

  @impl true
  def resolve_access(%{"role" => "admin"}), do: :all
  def resolve_access(%{"role" => "viewer"}), do: :read_only
  def resolve_access(%{"role" => "banned"}), do: :forbidden
  def resolve_access(_nobody), do: {:forbidden, "/login"}

  @impl true
  def author(admin), do: %{"id" => admin["id"], "name" => admin["name"]}

  @impl true
  def segments do
    [{"Plan", [{"plan:free", "Free"}, {"plan:pro", "Pro"}]}, {"role:owner", "Owners"}]
  end

  @impl true
  def resolve_reader(%Plug.Conn{} = conn), do: reader(Plug.Conn.get_session(conn, "reader"))
  def resolve_reader(%{assigns: assigns}), do: reader(assigns[:current_reader])

  defp reader(%{"id" => id} = reader) do
    %Tayori.Reader{id: id, segments: reader["segments"] || [], locale: reader["locale"]}
  end

  defp reader(_visitor), do: nil
end

defmodule TayoriTest.NewsLive do
  @moduledoc "A page of the app, with the news."
  use Phoenix.LiveView

  def mount(_params, session, socket) do
    {:ok, Phoenix.Component.assign(socket, :current_reader, session["reader"])}
  end

  def render(assigns) do
    ~H"""
    <Tayori.Components.news_button tayori={@tayori} />
    <Tayori.Components.news_panel tayori={@tayori} />
    """
  end
end

defmodule TayoriTest.AssignReader do
  @moduledoc "The app's own on_mount: the reader of the session, in the assigns."
  def on_mount(:default, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :current_reader, session["reader"])}
  end
end

defmodule TayoriTest.Host do
  @moduledoc """
  The app of the tests: the admin mounted with its definition, the API and
  the public page with the macros `import Tayori.Router` gives, as an app
  writes them, and a LiveView of the app's own with the news.
  """

  use PhoenixMountable.TestHost,
    otp_app: :tayori,
    mounts: [{Tayori.Router, "/admin/news", resolver: TayoriTest.Resolver}],
    routes:
      (quote do
         import Tayori.Router

         scope "/" do
           pipe_through :browser

           tayori_api "/api/news", resolver: TayoriTest.Resolver, page: "/changelog"
           tayori_page "/changelog", title: "Test news", limit: 2

           live_session :app,
             on_mount: [
               TayoriTest.AssignReader,
               {Tayori.Live, resolver: TayoriTest.Resolver, limit: 2}
             ] do
             live "/", TayoriTest.NewsLive
           end
         end

         # The API for the :embed feature, as the guide mounts it: no
         # CSRF protection, the readers come with a token.
         pipeline :embed do
           plug :accepts, ["json"]
           plug :fetch_session
         end

         scope "/embed" do
           pipe_through :embed

           tayori_api "/news",
             resolver: TayoriTest.Resolver,
             page: "https://app.test/changelog",
             as: :tayori_embed
         end
       end)
end
