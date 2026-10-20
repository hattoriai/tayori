defmodule Tayori.Admin.Assets do
  @moduledoc false
  # Serves the admin's script and style sheet, at
  # <prefix>/assets/admin-<md5>.js and <prefix>/assets/admin-<md5>.css.
  #
  # The admin is a page of its own, so it brings what it needs: the script
  # has Phoenix, LiveView, Kotoba and Koyomi in it (assets/src/admin.ts),
  # and the style sheet has the styles of Kotoba and Koyomi before its
  # own. Both are read and gzipped at compile time. Each URL names the
  # build it came from, so the answer is cached for a year, and a hash of
  # another build is a 404, never the wrong file.

  @behaviour Plug

  import Plug.Conn

  @static Path.expand("../../../priv/static", __DIR__)

  # Kotoba's and Koyomi's styles come from their Hex packages, built.
  @kotoba_css Application.app_dir(:kotoba, ["priv", "static", "kotoba.css"])
  @koyomi_css Application.app_dir(:koyomi, ["priv", "static", "koyomi.css"])

  @external_resource js_path = Path.join(@static, "tayori-admin.js")
  @external_resource css_path = Path.join(@static, "tayori-admin.css")
  @external_resource @kotoba_css
  @external_resource @koyomi_css

  # The files are missing in a checkout until `mix tayori.build`: the
  # admin then has no script and no styles, and everything else works.
  read = fn path ->
    case File.read(path) do
      {:ok, source} -> source
      {:error, _} -> ""
    end
  end

  @js read.(js_path)
  @css Enum.map_join([@kotoba_css, @koyomi_css, css_path], "\n", read)

  @js_gz :zlib.gzip(@js)
  @css_gz :zlib.gzip(@css)

  @hashes %{
    js: Base.encode16(:crypto.hash(:md5, @js), case: :lower),
    css: Base.encode16(:crypto.hash(:md5, @css), case: :lower)
  }

  @doc "The name of an asset of this build: `admin-<md5>.js` or `.css`."
  def name(kind) when kind in [:js, :css], do: "admin-#{@hashes[kind]}.#{kind}"

  @doc """
  Whether a page tracks an asset of another build (after a deploy), from
  the `_track_static` of its connect params.
  """
  def stale?(tracked) when is_list(tracked) do
    Enum.any?(tracked, fn
      url when is_binary(url) ->
        case Regex.run(~r"/assets/(admin-[0-9a-f]{32}\.(?:js|css))\z", URI.parse(url).path || "") do
          [_, file] -> file not in [name(:js), name(:css)]
          nil -> false
        end

      _ ->
        false
    end)
  end

  def stale?(_tracked), do: false

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(%{path_params: %{"asset" => asset}} = conn, :serve) do
    cond do
      asset == name(:js) ->
        # Plug.CSRFProtection refuses a GET answered with JavaScript, as a
        # cross-origin read of a script; this one is public.
        conn
        |> put_private(:plug_skip_csrf_protection, true)
        |> serve("text/javascript", @js, @js_gz)

      asset == name(:css) ->
        serve(conn, "text/css", @css, @css_gz)

      true ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(404, "")
        |> halt()
    end
  end

  defp serve(conn, type, body, gzipped) do
    gzip? =
      conn
      |> get_req_header("accept-encoding")
      |> Enum.any?(&String.contains?(String.downcase(&1), "gzip"))

    conn
    |> put_resp_header("content-type", type)
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_resp_header("vary", "accept-encoding")
    |> then(&if(gzip?, do: put_resp_header(&1, "content-encoding", "gzip"), else: &1))
    |> send_resp(200, if(gzip?, do: gzipped, else: body))
    |> halt()
  end
end
