defmodule TayoriTest.ErrorHTML do
  @moduledoc "Error pages for the test endpoint."
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

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

defmodule TayoriTest.Router do
  @moduledoc "The router of the test endpoint."
  use Phoenix.Router

  import Phoenix.LiveView.Router
  import Tayori.Router

  pipeline :browser do
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
  end

  scope "/admin" do
    pipe_through :browser
    tayori_admin("/news", resolver: TayoriTest.Resolver)
  end
end

defmodule TayoriTest.Endpoint do
  @moduledoc "A Phoenix endpoint for the tests. It runs no server."
  use Phoenix.Endpoint, otp_app: :tayori

  @session [store: :cookie, key: "_tayori_test", signing_salt: "tayori-test"]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]]

  plug Plug.Session, @session
  plug TayoriTest.Router
end
