defmodule Tayori.RawBody do
  @moduledoc """
  A body reader for `Plug.Parsers`, for the requests whose signature is of
  the body as it was sent: GitHub's deliveries (`Tayori.GitHub`) and the
  webhooks of the mail providers (`tayori_mail`, the campaigns).

  An endpoint whose `Plug.Parsers` reads JSON (a Phoenix app's does)
  reads the body before the router. This reader reads it as
  `Plug.Conn.read_body/2` does, and keeps a copy of it for those requests
  only: a request with GitHub's `x-hub-signature-256` header, or to a
  path `.../webhooks/<provider>`.

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        body_reader: {Tayori.RawBody, :read_body, []},
        json_decoder: Phoenix.json_library()

  `{Tayori.GitHub, :read_body, []}` is the same reader.
  """

  @doc "Reads the body, as `Plug.Conn.read_body/2`, and keeps a copy of a signed one."
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
  # The body of a request, as it was sent: read here, or kept by
  # read_body/2 when the endpoint's parsers read it first. `:error` when
  # the parsers read it without keeping it.
  @spec fetch(Plug.Conn.t(), pos_integer()) ::
          {:ok, binary(), Plug.Conn.t()} | {:error, :too_large | :no_raw_body | term()}
  def fetch(%{body_params: %Plug.Conn.Unfetched{}} = conn, max) do
    case Plug.Conn.read_body(conn, length: max) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _body, _conn} -> {:error, :too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch(%{private: %{tayori_raw_body: iodata}} = conn, _max),
    do: {:ok, IO.iodata_to_binary(iodata), conn}

  def fetch(_conn, _max), do: {:error, :no_raw_body}
end
