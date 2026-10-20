defmodule Tayori.Embed do
  @moduledoc ~S"""
  The news on another origin than the app's: a marketing site, a help
  centre, a page the app does not serve. The `:embed` feature.

      {Tayori,
       repo: MyApp.Repo,
       pubsub: MyApp.PubSub,
       secret_key_base: secret,
       features: [:embed],
       embed: [origins: ["https://www.atelier.app"]]}

  The JSON API (`Tayori.API`) answers the pages of those origins, and no
  others: it gives them CORS headers, without credentials, so that a
  browser never sends the app's cookies along. A reader there is not in
  the app's session; the app's server says who they are with a token it
  signs, `token/1`, which the page gives `<tayori-news>`:

      <tayori-news
        api="https://app.atelier.app/embed/news"
        reader-token="<%= Tayori.Embed.token(@reader) %>"
      ></tayori-news>

  The element sends it in the `authorization` header
  (`Bearer <token>`), and the API reads the reader from it: their id,
  segments, language and the time they joined, as the app's resolver
  gave them when the token was made. A token is valid for a day
  (`:max_age` of the `:embed` option). Without one, or with one that is
  not Tayori's, the API asks the app's resolver, and the reader is
  otherwise a visitor; with one that has expired, it answers 401.

  The token is a `Phoenix.Token`, signed with the app's `:secret_key_base`
  and a salt of Tayori's own: no one can make one, or change the reader
  in it, without the app's secret. Make one for the person the page is
  for, on the server, and never from an id the browser sends.

  The [Any frontend](any_frontend.md) guide has the whole setup.
  """

  import Plug.Conn

  alias Tayori.{Config, Reader}

  @salt "tayori embed reader"

  @doc """
  A signed token of the reader, for `<tayori-news reader-token="...">`
  on another origin. Raises for a visitor (a visitor needs no token) and
  when the `:embed` feature is off.
  """
  @spec token(Reader.t()) :: String.t()
  def token(%Reader{id: nil}) do
    raise ArgumentError, "a visitor has no reader token: give <tayori-news> none"
  end

  def token(%Reader{} = reader) do
    config = Config.get()

    unless Config.feature?(config, :embed) do
      raise ArgumentError, "reader tokens are for the :embed feature, which is off"
    end

    data = %{
      "id" => reader.id,
      "segments" => reader.segments,
      "locale" => reader.locale,
      "since" => reader.since && DateTime.to_unix(reader.since, :microsecond)
    }

    Phoenix.Token.sign(config.secret_key_base, @salt, data)
  end

  @doc """
  The reader of a token of `token/1`: `{:ok, reader}`, or
  `{:error, :expired}` for a token older than `:max_age`, and
  `{:error, :invalid}` for anything else (a token Tayori did not sign, or
  the `:embed` feature off).
  """
  @spec verify(String.t()) :: {:ok, Reader.t()} | {:error, :expired | :invalid}
  def verify(token) when is_binary(token) do
    config = Config.get()

    with true <- Config.feature?(config, :embed),
         {:ok, data} <-
           Phoenix.Token.verify(config.secret_key_base, @salt, token,
             max_age: config.embed.max_age
           ),
         %Reader{} = reader <- reader(data) do
      {:ok, reader}
    else
      {:error, :expired} -> {:error, :expired}
      _ -> {:error, :invalid}
    end
  end

  defp reader(%{"id" => id, "segments" => segments, "locale" => locale, "since" => since})
       when is_binary(id) and is_list(segments) and (is_binary(locale) or is_nil(locale)) and
              (is_integer(since) or is_nil(since)) do
    %Reader{
      id: id,
      segments: segments,
      locale: locale,
      since: since && DateTime.from_unix!(since, :microsecond)
    }
  end

  defp reader(_data), do: nil

  @doc false
  # The token of a request's `authorization: Bearer ...` header, or nil.
  # Read only when the :embed feature is on.
  @spec bearer(Plug.Conn.t()) :: String.t() | nil
  def bearer(conn) do
    if Config.feature?(Config.get(), :embed) do
      with [header | _] <- get_req_header(conn, "authorization"),
           [scheme, token] <- String.split(header, " ", parts: 2),
           "bearer" <- String.downcase(scheme),
           token when token != "" <- String.trim(token) do
        token
      else
        _ -> nil
      end
    end
  end

  @doc false
  # The request's Origin, when it is one of the :embed feature's.
  @spec allowed_origin(Plug.Conn.t()) :: String.t() | nil
  def allowed_origin(conn) do
    config = Config.get()

    with true <- Config.feature?(config, :embed),
         [origin | _] <- get_req_header(conn, "origin"),
         {:ok, origin} <- normalize_origin(origin),
         true <- origin in config.embed.origins do
      origin
    else
      _ -> nil
    end
  end

  @doc false
  # The CORS headers of a response of the API: the Origin allowed back,
  # never credentials, and `vary: origin` for caches, as the answer
  # depends on it.
  @spec cors(Plug.Conn.t()) :: Plug.Conn.t()
  def cors(conn) do
    if Config.feature?(Config.get(), :embed) do
      conn = vary(conn, "origin")

      case allowed_origin(conn) do
        nil -> conn
        origin -> put_resp_header(conn, "access-control-allow-origin", origin)
      end
    else
      conn
    end
  end

  @doc false
  # Adds a header to the response's `vary`.
  @spec vary(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def vary(conn, header) do
    values =
      conn
      |> get_resp_header("vary")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    put_resp_header(conn, "vary", Enum.join(Enum.uniq(values ++ [header]), ", "))
  end

  @doc false
  # An origin as the config keeps it and a browser sends it: the scheme
  # and the host in lowercase, and the port when it is not the scheme's.
  @spec normalize_origin(term()) :: {:ok, String.t()} | :error
  def normalize_origin(origin) when is_binary(origin) do
    case URI.new(origin) do
      {:ok,
       %URI{scheme: scheme, host: host, port: port, path: path, query: nil, fragment: nil} = uri}
      when scheme in ["http", "https"] and is_binary(host) and path in [nil, ""] and
             uri.userinfo == nil ->
        origin(scheme, host(String.downcase(host)), port)

      _ ->
        :error
    end
  end

  defp origin(scheme, {:ok, host}, port) do
    port = if port == URI.default_port(scheme), do: "", else: ":#{port}"
    {:ok, "#{scheme}://#{host}#{port}"}
  end

  defp origin(_scheme, :error, _port), do: :error

  def normalize_origin(_origin), do: :error

  # A name of letters, digits, dots and dashes, or an IPv6 address: no
  # wildcard.
  defp host(host) do
    cond do
      host =~ ~r/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\z/ ->
        {:ok, host}

      host =~ ~r/\A[0-9a-f:.]+\z/ and String.contains?(host, ":") ->
        {:ok, "[#{host}]"}

      true ->
        :error
    end
  end

  # ── The script and the style sheets ─────────────────────────────

  # The files a page on another origin loads from the API: the news
  # bundle (an ES module with no imports) and the style sheets, with
  # Kotoba's for the bodies of the entries. Read when Tayori compiles,
  # like the admin's.
  @assets [
    {"tayori.js", "text/javascript", ["priv/static/tayori.esm.js"]},
    {"tayori.css", "text/css", [{:kotoba, "priv/static/kotoba.css"}, "priv/static/tayori.css"]},
    {"tayori-sumi.css", "text/css",
     [
       {:kotoba, "priv/static/kotoba.css"},
       {:kotoba, "priv/static/kotoba-sumi.css"},
       "priv/static/tayori.css",
       "priv/static/tayori-sumi.css"
     ]}
  ]

  @root Path.expand("../..", __DIR__)

  @doc false
  # The names of the files.
  @spec assets() :: [String.t()]
  def assets, do: Enum.map(@assets, &elem(&1, 0))

  @doc false
  # A file by name: `{content_type, hash, body, gzipped}`, or nil.
  @spec asset(String.t()) :: {String.t(), String.t(), binary(), binary()} | nil
  for {name, content_type, sources} <- @assets do
    files =
      Enum.map(sources, fn
        {app, path} -> Path.join(Application.app_dir(app), path)
        path -> Path.join(@root, path)
      end)

    for file <- files, do: @external_resource(file)
    body = Enum.map_join(files, "\n", &File.read!/1)
    hash = :md5 |> :crypto.hash(body) |> Base.encode16(case: :lower)

    def asset(unquote(name)),
      do: {unquote(content_type), unquote(hash), unquote(body), unquote(:zlib.gzip(body))}
  end

  def asset(_name), do: nil
end
