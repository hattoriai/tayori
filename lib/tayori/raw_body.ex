defmodule Tayori.RawBody do
  @moduledoc """
  The body of the requests whose signature is of the body as it was sent:
  GitHub's deliveries (`Tayori.GitHub`) and the webhooks of the mail
  providers (`tayori_mail`, the campaigns).

  An endpoint whose `Plug.Parsers` reads JSON (a Phoenix app's does)
  reads the body before the router. Give it PhoenixMountable's reader,
  which keeps the body for the routes that want it, wherever the app puts
  them (`PhoenixMountable.RawBody`; `mix tayori.install` adds it), and is
  shared with the other libraries that need one:

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        body_reader: {PhoenixMountable.RawBody, :read_body, [MyAppWeb.Router]},
        json_decoder: Phoenix.json_library()

  `read_body/2` is Tayori's reader of before, deprecated: it keeps a copy
  of a request with GitHub's `x-hub-signature-256` header, or to a path
  `.../webhooks/<provider>`, and Tayori still reads that copy.
  `{Tayori.GitHub, :read_body, []}` is the same reader.
  """

  @doc """
  Reads the body, as `Plug.Conn.read_body/2`, and keeps a copy of a
  signed one. Deprecated: give `Plug.Parsers` `PhoenixMountable.RawBody`'s.
  """
  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, keep(conn, body)}
      {:more, body, conn} -> {:more, body, keep(conn, body)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp keep(conn, body) do
    if signed?(conn) do
      Plug.Conn.put_private(conn, :tayori_raw_body, [
        Map.get(conn.private, :tayori_raw_body, []),
        body
      ])
    else
      conn
    end
  end

  defp signed?(conn) do
    Plug.Conn.get_req_header(conn, "x-hub-signature-256") != [] or webhook_path?(conn.path_info)
  end

  defp webhook_path?(["webhooks", _provider]), do: true
  defp webhook_path?([_ | rest]), do: webhook_path?(rest)
  defp webhook_path?([]), do: false

  @doc false
  # The body of a request, as it was sent: the copy PhoenixMountable's
  # reader kept, or the body read here when the parsers left it unread, or
  # the copy read_body/2 kept. `:no_raw_body` when the parsers read it
  # without keeping it.
  @spec fetch(Plug.Conn.t(), pos_integer()) ::
          {:ok, binary(), Plug.Conn.t()} | {:error, :too_large | :no_raw_body | term()}
  def fetch(conn, max) do
    case PhoenixMountable.RawBody.fetch(conn, max) do
      {:error, :no_raw_body} -> kept(conn, max)
      result -> result
    end
  end

  defp kept(%{private: %{tayori_raw_body: iodata}} = conn, max) do
    body = IO.iodata_to_binary(iodata)
    if byte_size(body) > max, do: {:error, :too_large}, else: {:ok, body, conn}
  end

  defp kept(_conn, _max), do: {:error, :no_raw_body}
end
