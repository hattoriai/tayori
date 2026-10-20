defmodule Tayori.Page do
  @moduledoc """
  The public page of the news, its entries one by one, and its feeds
  (Atom and JSON Feed), mounted with `Tayori.Router.tayori_page/2`:

      scope "/" do
        pipe_through :browser
        tayori_page "/changelog", title: "Atelier news"
      end

  It shows the entries for everyone (those with no segments), unless it
  has a resolver and the reader it gives sees more. It is in the reader's
  language when the entry has it: the reader's, `?lang=`, or the
  browser's (`Accept-Language`).

  ## The routes

    * `GET /` - the newest entries, with "Show more" (`?before=<slug>`).
    * `GET /:slug` - one entry.
    * `GET /feed.xml` - an Atom feed of the newest 20 entries.
    * `GET /feed.json` - a JSON Feed of the same.
    * `GET /assets/:file` - its style sheet.

  It renders its own document, in Tayori's theme or Sumi's, unless the
  app gives its own root layout (`layout: {MyAppWeb.Layouts, :root}`),
  which then gets `@inner_content`, `@conn` and `@page_title`, and the app's
  page loads `tayori.css` itself.
  """

  @behaviour Plug

  use Phoenix.Component

  import Plug.Conn

  alias Phoenix.HTML.Safe
  alias Tayori.{API, Assets, Components, Config, Messages, Reader, Resolver}

  @feed_size 20

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(conn, action) do
    opts = conn.private.tayori_page
    conn = fetch_query_params(conn)
    reader = opts.resolver && Resolver.reader(opts.resolver, conn)
    locale = API.locale(conn, reader)
    handle(action, conn, reader || Reader.visitor(locale), locale, opts)
  end

  defp handle(:index, conn, reader, locale, opts) do
    before = conn.query_params["before"] && Tayori.entry(reader, conn.query_params["before"])
    entries = Tayori.news(reader, limit: opts.limit + 1, before: before)

    assigns = %{
      opts: opts,
      locale: locale,
      messages: Messages.for_locale(locale),
      entries: Enum.take(entries, opts.limit),
      more: length(entries) > opts.limit,
      base: base_path(conn, opts)
    }

    render(conn, opts, locale, opts.title || assigns.messages["title"], index_page(assigns))
  end

  defp handle(:show, conn, reader, locale, opts) do
    case Tayori.entry(reader, conn.path_params["slug"]) do
      nil ->
        conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not Found") |> halt()

      entry ->
        assigns = %{
          opts: opts,
          locale: locale,
          messages: Messages.for_locale(locale),
          entry: entry,
          base: base_path(conn, opts)
        }

        render(conn, opts, locale, entry.translation.title, entry_page(assigns))
    end
  end

  defp handle(:atom, conn, reader, locale, opts) do
    entries = Tayori.news(reader, limit: @feed_size)
    base = base_url(conn, opts)
    title = opts.title || Messages.for_locale(locale)["title"]

    updated =
      entries |> Enum.map(& &1.published_at) |> Enum.max(DateTime, fn -> DateTime.utc_now() end)

    xml = [
      ~s(<?xml version="1.0" encoding="utf-8"?>\n),
      ~s(<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="#{escape(locale)}">\n),
      "<title>",
      escape(title),
      "</title>\n",
      ~s(<link href="#{escape(base)}"/>\n),
      ~s(<link rel="self" href="#{escape(base)}/feed.xml"/>\n),
      "<id>",
      escape(base),
      "</id>\n",
      "<updated>",
      DateTime.to_iso8601(updated),
      "</updated>\n",
      Enum.map(entries, &atom_entry(&1, base)),
      "</feed>\n"
    ]

    conn
    |> put_resp_content_type("application/atom+xml")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, xml)
    |> halt()
  end

  defp handle(:json, conn, reader, locale, opts) do
    base = base_url(conn, opts)

    feed = %{
      version: "https://jsonfeed.org/version/1.1",
      title: opts.title || Messages.for_locale(locale)["title"],
      home_page_url: base,
      feed_url: base <> "/feed.json",
      language: locale,
      items:
        for entry <- Tayori.news(reader, limit: @feed_size) do
          %{
            id: entry.id,
            url: base <> "/" <> entry.slug,
            title: entry.translation.title,
            summary: entry.translation.summary,
            content_html: entry.translation.body && entry.translation.body.html,
            date_published: entry.published_at,
            tags: entry.categories,
            language: entry.translation.locale
          }
        end
    }

    conn
    |> put_resp_content_type("application/feed+json")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, JSON.encode!(feed))
    |> halt()
  end

  defp atom_entry(entry, base) do
    t = entry.translation
    url = base <> "/" <> entry.slug

    [
      "<entry>\n",
      "<title>",
      escape(t.title),
      "</title>\n",
      ~s(<link href="#{escape(url)}"/>\n),
      "<id>urn:uuid:",
      entry.id,
      "</id>\n",
      "<published>",
      DateTime.to_iso8601(entry.published_at),
      "</published>\n",
      "<updated>",
      DateTime.to_iso8601(entry.published_at),
      "</updated>\n",
      Enum.map(entry.categories, &[~s(<category term="), escape(&1), ~s("/>\n)]),
      if(t.summary, do: ["<summary>", escape(t.summary), "</summary>\n"], else: []),
      if(t.body, do: [~s(<content type="html">), escape(t.body.html), "</content>\n"], else: []),
      "</entry>\n"
    ]
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp render(conn, opts, locale, title, inner) do
    html =
      case opts.layout do
        {module, function} ->
          apply(module, function, [
            %{inner_content: inner, conn: conn, page_title: title, flash: %{}}
          ])

        nil ->
          document(%{
            inner_content: inner,
            title: title,
            locale: locale,
            css: base_path(conn, opts) <> "/assets/" <> css(opts.theme),
            feed: base_path(conn, opts) <> "/feed.xml",
            nonce: opts.csp_nonce_assign_key && conn.assigns[opts.csp_nonce_assign_key]
          })
      end

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, Safe.to_iodata(html))
    |> halt()
  end

  defp css(:sumi), do: Assets.name(:page_sumi_css)
  defp css(_tayori), do: Assets.name(:page_css)

  defp base_path(conn, opts), do: (conn.script_name |> Enum.map_join(&("/" <> &1))) <> opts.prefix

  defp base_url(conn, opts) do
    case opts.url do
      nil ->
        port =
          if {conn.scheme, conn.port} in [{:http, 80}, {:https, 443}],
            do: "",
            else: ":#{conn.port}"

        "#{conn.scheme}://#{conn.host}#{port}" <> base_path(conn, opts)

      url ->
        String.trim_trailing(url, "/") <> opts.prefix
    end
  end

  defp document(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@locale}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title}</title>
        <link rel="stylesheet" href={@css} nonce={@nonce} />
        <link rel="alternate" type="application/atom+xml" title={@title} href={@feed} />
      </head>
      <body class="tayori-page-body">
        {@inner_content}
      </body>
    </html>
    """
  end

  defp index_page(assigns) do
    ~H"""
    <main class="tayori-page">
      <header class="tayori-page-header">
        <h1>{@opts.title || @messages["title"]}</h1>
        <p class="tayori-page-links">
          <.languages :if={length(Config.get().locales) > 1} base={@base} locale={@locale} />
          <a href={@base <> "/feed.xml"}>{@messages["feed"]}</a>
        </p>
      </header>
      <Components.news entries={@entries} messages={@messages} page={@base} heading="h2" />
      <p :if={@entries == []} class="tayori-empty">{@messages["empty"]}</p>
      <p :if={@more} class="tayori-page-more">
        <a href={@base <> "?" <> URI.encode_query(before: List.last(@entries).slug, lang: @locale)}>
          {@messages["more"]}
        </a>
      </p>
    </main>
    """
  end

  defp entry_page(assigns) do
    ~H"""
    <main class="tayori-page">
      <p class="tayori-page-back"><a href={@base}>← {@opts.title || @messages["allNews"]}</a></p>
      <Components.entry entry={@entry} messages={@messages} heading="h1" />
    </main>
    """
  end

  attr :base, :string, required: true
  attr :locale, :string, required: true

  defp languages(assigns) do
    ~H"""
    <span class="tayori-languages">
      <a
        :for={locale <- Config.get().locales}
        href={@base <> "?lang=" <> URI.encode_www_form(locale)}
        lang={locale}
        aria-current={locale == @locale && "true"}
      >
        {Tayori.Locales.name(locale)}
      </a>
    </span>
    """
  end
end
