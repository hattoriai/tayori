defmodule Tayori.Assets do
  @moduledoc false
  # Serves the files of the pages Tayori renders itself, at
  # <prefix>/assets/<name>-<md5>.<ext>: the admin's script and style sheet,
  # and the public page's style sheets.
  #
  # The admin is a page of its own, so it brings what it needs: the script
  # has Phoenix, LiveView, Kotoba and Koyomi in it (assets/src/admin.ts),
  # and the style sheet has the styles of Kotoba and Koyomi before its
  # own. The public page has Kotoba's styles and Tayori's (and Sumi's).
  # All are read and gzipped at compile time. Each URL names the build it
  # came from, so the answer is cached for a year, and a hash of another
  # build is a 404, never the wrong file.

  @behaviour Plug

  import Plug.Conn

  @static Application.app_dir(:tayori, ["priv", "static"])

  # Kotoba's and Koyomi's styles come from their Hex packages, built.
  @kotoba_css Application.app_dir(:kotoba, ["priv", "static", "kotoba.css"])
  @kotoba_sumi_css Application.app_dir(:kotoba, ["priv", "static", "kotoba-sumi.css"])
  @koyomi_css Application.app_dir(:koyomi, ["priv", "static", "koyomi.css"])

  @external_resource js_path = Path.join(@static, "tayori-admin.js")
  @external_resource css_path = Path.join(@static, "tayori-admin.css")
  @external_resource news_css_path = Path.join(@static, "tayori.css")
  @external_resource sumi_css_path = Path.join(@static, "tayori-sumi.css")
  @external_resource @kotoba_css
  @external_resource @kotoba_sumi_css
  @external_resource @koyomi_css

  # The files are missing in a checkout until `mix tayori.build`: the
  # admin then has no script and no styles, and everything else works.
  read = fn path ->
    case File.read(path) do
      {:ok, source} -> source
      {:error, _} -> ""
    end
  end

  @files %{
    admin_js: {"text/javascript", read.(js_path)},
    admin_css: {"text/css", Enum.map_join([@kotoba_css, @koyomi_css, css_path], "\n", read)},
    page_css: {"text/css", Enum.map_join([@kotoba_css, news_css_path], "\n", read)},
    page_sumi_css: {
      "text/css",
      Enum.map_join([@kotoba_css, @kotoba_sumi_css, news_css_path, sumi_css_path], "\n", read)
    }
  }

  @names Map.new(@files, fn {key, {type, body}} ->
           ext = if type == "text/css", do: "css", else: "js"

           base =
             key
             |> Atom.to_string()
             |> String.replace_suffix("_css", "")
             |> String.replace_suffix("_js", "")

           md5 = Base.encode16(:crypto.hash(:md5, body), case: :lower)
           {key, "#{String.replace(base, "_", "-")}-#{md5}.#{ext}"}
         end)

  @by_name Map.new(@names, fn {key, name} -> {name, key} end)

  @doc false
  # The size of a file of this build, for the tests of a build.
  def size(key), do: key |> body() |> byte_size()

  @doc "The name of a file of this build, such as `admin-<md5>.js`."
  def name(key), do: Map.fetch!(@names, key)

  @doc """
  Whether a page tracks a file of another build (after a deploy), from
  the `_track_static` of its connect params.
  """
  def stale?(tracked) when is_list(tracked) do
    Enum.any?(tracked, fn
      url when is_binary(url) ->
        case Regex.run(
               ~r"/assets/([a-z-]+-[0-9a-f]{32}\.(?:js|css))\z",
               URI.parse(url).path || ""
             ) do
          [_, file] -> not Map.has_key?(@by_name, file)
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
    case Map.fetch(@by_name, asset) do
      {:ok, key} ->
        {type, _body} = @files[key]

        # Plug.CSRFProtection refuses a GET answered with JavaScript, as a
        # cross-origin read of a script; this one is public.
        conn
        |> put_private(:plug_skip_csrf_protection, true)
        |> serve(type, body(key), gzipped(key))

      :error ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(404, "")
        |> halt()
    end
  end

  # One function clause for each file, so that each body is in the module
  # once, and gzipped once, at compile time.
  for {key, {_type, body}} <- @files do
    defp body(unquote(key)), do: unquote(body)
    defp gzipped(unquote(key)), do: unquote(:zlib.gzip(body))
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
