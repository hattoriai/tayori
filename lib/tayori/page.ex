defmodule Tayori.Page do
  @moduledoc """
  The public page of the news, its entries one by one, and its feeds
  (Atom and JSON Feed), mounted with `Tayori.Router.tayori_page/2`:

      scope "/" do
        pipe_through :browser
        tayori_page "/changelog", title: "Atelier news", description: "What we ship, every week."
      end

  It shows the entries for everyone (those with no segments), unless it
  has a resolver and the reader it gives sees more. It is in the reader's
  language when the entry has it: the reader's, `?lang=`, or the
  browser's (`Accept-Language`).

  ## The routes

    * `GET /` - the newest entries, whole, the pinned ones first; the
      categories to filter by (`?category=`), a search (`?q=`), and the
      older ones (`?before=<slug>`).
    * `GET /:slug` - one entry, with the entries on either side.
    * `GET /feed.xml` and `GET /feed.json` - Atom and JSON Feed, of the
      newest 20 entries (`?category=` for a category's).
    * `GET /sitemap.xml` - the entries, for search engines.
    * `GET /preview/:token` - an entry before it is published, from the
      admin's preview link: valid a week, never indexed.
    * `POST /:slug/react` - a reaction of the reader (the `:reactions`
      feature), and back to where it was.
    * `POST /subscribe`, `GET /subscription/confirm/:token`,
      `GET` and `POST /subscription/unsubscribe/:token` - the emails (the
      `:subscriptions` feature).

  It renders its own document, in Tayori's theme or Sumi's, light or dark
  as the reader's system is, with the tags of search engines and shared
  links (a description, Open Graph, the cover as its image, the languages
  and a JSON-LD article), unless the app gives its own root layout
  (`layout: {MyAppWeb.Layouts, :root}`), which then gets
  `@inner_content`, `@conn`, `@page_title` and `@meta` (the tags, as a
  list of maps), and the app's page loads `tayori.css` itself.

  The forms (reactions, subscribe) post with the session's CSRF token: the
  page belongs behind the app's `:browser` pipeline.
  """

  @behaviour Plug

  use Phoenix.Component

  import Plug.Conn, except: [assign: 3]
  import Tayori.Icons, only: [icon: 1]

  alias Phoenix.HTML.Safe
  alias Tayori.{API, Categories, Category, Components, Config, Entry, Messages, Reader, Resolver}

  @feed_size 20
  @preview_salt "tayori preview"
  @preview_age 7 * 24 * 3600

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(conn, action) do
    mount = conn.assigns.mount
    opts = Map.put(mount.options, :mount, mount)
    conn = fetch_query_params(conn)
    reader = opts.resolver && Resolver.reader(opts.resolver, conn)
    locale = API.locale(conn, reader)
    handle(action, conn, reader, reader || Reader.visitor(locale), locale, opts)
  end

  @doc """
  The token of a preview link of an entry, signed with the endpoint's
  secret: the admin makes it. `endpoint` is a conn, a socket or an
  endpoint module.
  """
  @spec preview_token(term(), Ecto.UUID.t()) :: String.t()
  def preview_token(endpoint, entry_id), do: Phoenix.Token.sign(endpoint, @preview_salt, entry_id)

  # ── The pages ───────────────────────────────────────────────────

  defp handle(:index, conn, signed_in, reader, locale, opts) do
    config = Config.get()
    params = conn.query_params
    categories = Categories.by_key()
    category = if Map.has_key?(categories, params["category"]), do: params["category"]
    search = blank(params["q"])
    before = params["before"] && Tayori.entry(reader, params["before"])

    entries =
      Tayori.news(reader,
        limit: opts.limit + 1,
        before: before,
        category: category,
        search: search
      )

    pinned = Enum.count(entries, & &1.pinned_at)
    shown = Enum.take(entries, opts.limit + pinned)
    messages = Messages.for_locale(locale)
    base = base_path(conn)

    assigns = %{
      opts: opts,
      config: config,
      locale: locale,
      messages: messages,
      entries: shown,
      more: length(entries) > opts.limit + pinned,
      before: before,
      categories: categories,
      category: category,
      search: search,
      notice: notice_of(params),
      base: base,
      reactions: reactions(config, reader, shown),
      signed_in: signed_in != nil,
      csrf: Plug.CSRFProtection.get_csrf_token()
    }

    title = opts.title || messages["title"]
    url = base_url(conn, opts)

    meta =
      [
        %{name: "description", content: opts.description},
        %{property: "og:type", content: "website"},
        %{property: "og:title", content: title},
        %{property: "og:description", content: opts.description},
        %{property: "og:url", content: url},
        %{property: "og:image", content: opts.image},
        %{
          name: "twitter:card",
          content: if(opts.image, do: "summary_large_image", else: "summary")
        }
      ] ++ languages_meta(config, url) ++ noindex(search || category || before)

    render(conn, opts, locale, title, meta, url, index_page(assigns))
  end

  defp handle(:show, conn, _signed_in, reader, locale, opts) do
    case Tayori.entry(reader, conn.path_params["slug"]) do
      nil ->
        not_found(conn)

      entry ->
        source = if conn.query_params["ref"] == "email", do: "email", else: "page"
        Tayori.Views.track(signed_in_reader(reader), entry.id, source)
        show(conn, reader, locale, opts, entry, preview: false)
    end
  end

  defp handle(:preview, conn, _signed_in, reader, locale, opts) do
    with {:ok, id} <-
           Phoenix.Token.verify(conn, @preview_salt, conn.path_params["token"],
             max_age: @preview_age
           ),
         %Entry{} = entry <- get_entry(id) do
      config = Config.get()
      entry = %{entry | translation: Entry.translation(entry, locale, config.locales)}
      show(conn, reader, locale, opts, entry, preview: true)
    else
      _ -> not_found(conn)
    end
  end

  defp handle(:react, conn, signed_in, reader, _locale, _opts) do
    config = Config.get()
    {:ok, body, conn} = read_form(conn)

    with {:feature, true} <- {:feature, Config.feature?(config, :reactions)},
         %Reader{} <- signed_in,
         %Entry{} = entry <- Tayori.entry(reader, conn.path_params["slug"]) do
      _ = Tayori.Reactions.toggle(signed_in, entry.id, body["emoji"] || "")
      redirect_back(conn, body["return"], base_path(conn) <> "/" <> entry.slug)
    else
      # A feature that is off has no route (Tayori.Config).
      {:feature, false} -> not_found(conn)
      _ -> redirect_back(conn, body["return"], base_path(conn))
    end
  end

  defp handle(:subscribe, conn, _signed_in, _reader, locale, _opts) do
    config = Config.get()
    {:ok, body, conn} = read_form(conn)
    base = base_path(conn)

    if Config.feature?(config, :subscriptions) do
      case Tayori.Subscribers.subscribe(body["email"] || "", locale) do
        :ok -> redirect_to(conn, base <> "?notice=subscribed#subscribe")
        {:error, _} -> redirect_to(conn, base <> "?notice=invalid_email#subscribe")
      end
    else
      not_found(conn)
    end
  end

  defp handle(:confirm, conn, _signed_in, _reader, _locale, _opts) do
    with {:feature, true} <- {:feature, Config.feature?(Config.get(), :subscriptions)},
         {:ok, _subscriber} <- Tayori.Subscribers.confirm(conn.path_params["token"]) do
      redirect_to(conn, base_path(conn) <> "?notice=confirmed")
    else
      {:feature, false} -> not_found(conn)
      _ -> redirect_to(conn, base_path(conn) <> "?notice=invalid")
    end
  end

  defp handle(:unsubscribe, conn, _signed_in, _reader, _locale, _opts) do
    if Config.feature?(Config.get(), :subscriptions) do
      Tayori.Subscribers.unsubscribe(conn.path_params["token"])

      # The one-click unsubscribe of an email client posts, and wants no page.
      if conn.method == "POST",
        do: conn |> send_resp(200, "") |> halt(),
        else: redirect_to(conn, base_path(conn) <> "?notice=unsubscribed")
    else
      not_found(conn)
    end
  end

  defp handle(:sitemap, conn, _signed_in, _reader, locale, opts) do
    base = base_url(conn, opts)
    entries = Tayori.news(Reader.visitor(locale), limit: 1000)

    xml = [
      ~s(<?xml version="1.0" encoding="utf-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      "<url><loc>",
      escape(base),
      "</loc></url>\n",
      for entry <- entries do
        [
          "<url><loc>",
          escape(base <> "/" <> entry.slug),
          "</loc><lastmod>",
          entry.updated_at |> DateTime.to_date() |> Date.to_iso8601(),
          "</lastmod></url>\n"
        ]
      end,
      "</urlset>\n"
    ]

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, xml)
    |> halt()
  end

  defp handle(:atom, conn, _signed_in, reader, locale, opts) do
    entries = Tayori.news(reader, limit: @feed_size, category: conn.query_params["category"])
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
      if(opts.description,
        do: ["<subtitle>", escape(opts.description), "</subtitle>\n"],
        else: []
      ),
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

  defp handle(:json, conn, _signed_in, reader, locale, opts) do
    base = base_url(conn, opts)

    feed = %{
      version: "https://jsonfeed.org/version/1.1",
      title: opts.title || Messages.for_locale(locale)["title"],
      description: opts.description,
      home_page_url: base,
      feed_url: base <> "/feed.json",
      language: locale,
      items:
        for entry <-
              Tayori.news(reader, limit: @feed_size, category: conn.query_params["category"]) do
          %{
            id: entry.id,
            url: base <> "/" <> entry.slug,
            title: entry.translation.title,
            summary: entry.translation.summary,
            content_html: entry.translation.body && entry.translation.body.html,
            image: entry.cover && absolute(entry.cover["url"], base),
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

  defp show(conn, reader, locale, opts, entry, preview: preview?) do
    config = Config.get()
    messages = Messages.for_locale(locale)
    base = base_path(conn)
    url = base_url(conn, opts) <> "/" <> entry.slug
    {newer, older} = if preview?, do: {nil, nil}, else: Tayori.adjacent(reader, entry)
    t = entry.translation

    assigns = %{
      opts: opts,
      config: config,
      locale: locale,
      messages: messages,
      entry: entry,
      newer: newer,
      older: older,
      preview: preview?,
      categories: Categories.by_key(),
      base: base,
      reactions: if(preview?, do: nil, else: reactions(config, reader, [entry])),
      signed_in: reader.id != nil,
      csrf: Plug.CSRFProtection.get_csrf_token()
    }

    meta = entry_meta(conn, config, opts, entry, url, preview?)
    render(conn, opts, locale, t.seo_title || t.title, meta, url, entry_page(assigns))
  end

  # The description, Open Graph, Twitter card and JSON-LD of an entry.
  defp entry_meta(conn, config, opts, entry, url, preview?) do
    t = entry.translation
    description = t.seo_description || t.summary
    image = image(entry, base_url(conn, opts)) || opts.image

    [
      %{name: "description", content: description},
      %{property: "og:type", content: "article"},
      %{property: "og:title", content: t.seo_title || t.title},
      %{property: "og:description", content: description},
      %{property: "og:url", content: url},
      %{property: "og:image", content: image},
      %{property: "og:image:alt", content: entry.cover && entry.cover["alt"]},
      %{
        property: "article:published_time",
        content: entry.published_at && DateTime.to_iso8601(entry.published_at)
      },
      %{name: "twitter:card", content: if(image, do: "summary_large_image", else: "summary")},
      %{json_ld: json_ld(entry, url, image, description)}
    ] ++ languages_meta(config, url) ++ noindex(preview?)
  end

  # ── Markup ──────────────────────────────────────────────────────

  defp index_page(assigns) do
    ~H"""
    <div class="tayori-shell">
      <header class="tayori-masthead">
        <p :if={@opts.eyebrow} class="tayori-eyebrow">{@opts.eyebrow}</p>
        <h1 class="tayori-page-title">{@opts.title || @messages["title"]}</h1>
        <p :if={@opts.description} class="tayori-page-description">{@opts.description}</p>
        <div class="tayori-masthead-actions">
          <.subscribe_form
            :if={Config.feature?(@config, :subscriptions)}
            base={@base}
            csrf={@csrf}
            messages={@messages}
          />
          <nav class="tayori-links" aria-label={@messages["feed"]}>
            <a href={@base <> "/feed.xml"}><.icon name="rss" />{@messages["feed"]}</a>
            <.languages :if={length(@config.locales) > 1} base={@base} locale={@locale} />
          </nav>
        </div>
        <.notice :if={@notice} notice={@notice} messages={@messages} />
      </header>

      <div class="tayori-toolbar">
        <nav
          :if={map_size(@categories) > 0}
          class="tayori-filter"
          aria-label={@messages["categories"]}
        >
          <a
            href={query(@base, @locale, q: @search)}
            class="tayori-chip"
            aria-current={@category == nil && "page"}
          >
            {@messages["all"]}
          </a>
          <a
            :for={category <- Enum.sort_by(Map.values(@categories), & &1.position)}
            href={query(@base, @locale, category: category.key, q: @search)}
            class="tayori-chip"
            data-color={category.color}
            aria-current={@category == category.key && "page"}
          >
            <span class="tayori-dot" aria-hidden="true"></span>
            {Category.name(category, @locale, @config.locales)}
          </a>
        </nav>
        <form class="tayori-search" role="search" action={@base} method="get">
          <input :if={@category} type="hidden" name="category" value={@category} />
          <.icon name="search" />
          <label for="tayori-q" class="tayori-visually-hidden">{@messages["search"]}</label>
          <input
            id="tayori-q"
            class="tayori-input"
            type="search"
            name="q"
            value={@search}
            placeholder={@messages["searchPlaceholder"]}
          />
        </form>
      </div>

      <p :if={@search} class="tayori-results">
        <span :if={@entries == []}>{@messages["noResults"]}</span>
        <a href={query(@base, @locale, category: @category)}>{@messages["clearSearch"]}</a>
      </p>

      <ol :if={@entries != []} class="tayori-timeline">
        <li :for={entry <- @entries} id={"entry-" <> entry.slug}>
          <p class="tayori-timeline-date">
            <time
              datetime={DateTime.to_iso8601(entry.published_at)}
              data-tayori-time="date"
            >
              {Messages.date(@messages, entry.published_at)}
            </time>
          </p>
          <Components.entry
            entry={entry}
            messages={@messages}
            categories={@categories}
            locales={@config.locales}
            href={@base <> "/" <> entry.slug}
            heading="h2"
          >
            <:footer :if={@reactions}>
              <.reaction_form
                entry={entry}
                reactions={@reactions}
                config={@config}
                messages={@messages}
                base={@base}
                csrf={@csrf}
                signed_in={@signed_in}
                return={query(@base, @locale, category: @category, q: @search) <> "#entry-" <> entry.slug}
              />
            </:footer>
          </Components.entry>
        </li>
      </ol>

      <div :if={@entries == [] and !@search} class="tayori-empty">
        <.icon name="inbox" />
        <p>{@messages["empty"]}</p>
      </div>

      <nav :if={@more or @before} class="tayori-pager">
        <a :if={@before} href={query(@base, @locale, category: @category, q: @search)} rel="prev">
          <.icon name="arrow-left" />{@messages["newer"]}
        </a>
        <a
          :if={@more}
          href={
            query(@base, @locale,
              before: @entries |> Enum.reject(& &1.pinned_at) |> List.last() |> Map.get(:slug),
              category: @category,
              q: @search
            )
          }
          rel="next"
        >
          {@messages["older"]}<.icon name="arrow-right" />
        </a>
      </nav>
      <div :if={!@more and !@before} class="tayori-pager"></div>
    </div>
    """
  end

  defp entry_page(assigns) do
    ~H"""
    <p :if={@preview} class="tayori-preview-bar"><.icon name="eye" />{@messages["notPublished"]}</p>
    <div class="tayori-shell">
      <article class="tayori-article">
        <a href={@base} class="tayori-back">
          <.icon name="arrow-left" />{@opts.title || @messages["allNews"]}
        </a>
        <Components.entry
          entry={@entry}
          messages={@messages}
          categories={@categories}
          locales={@config.locales}
          heading="h1"
        >
          <:footer :if={@reactions}>
            <.reaction_form
              entry={@entry}
              reactions={@reactions}
              config={@config}
              messages={@messages}
              base={@base}
              csrf={@csrf}
              signed_in={@signed_in}
              return={@base <> "/" <> @entry.slug}
            />
          </:footer>
        </Components.entry>

        <nav :if={@newer || @older} class="tayori-entry-nav" aria-label={@messages["allNews"]}>
          <a :if={@older} href={@base <> "/" <> @older.slug} rel="prev">
            <span>{@messages["previous"]}</span>
            <strong>{@older.translation.title}</strong>
          </a>
          <a :if={@newer} href={@base <> "/" <> @newer.slug} rel="next">
            <span>{@messages["next"]}</span>
            <strong>{@newer.translation.title}</strong>
          </a>
        </nav>

        <section
          :if={Config.feature?(@config, :subscriptions) and !@preview}
          class="tayori-subscribe-card"
          id="subscribe"
        >
          <h2>{@messages["subscribeTitle"]}</h2>
          <p>{@messages["subscribeText"]}</p>
          <.subscribe_form base={@base} csrf={@csrf} messages={@messages} />
        </section>
      </article>
    </div>
    """
  end

  attr :base, :string, required: true
  attr :csrf, :string, required: true
  attr :messages, :map, required: true

  defp subscribe_form(assigns) do
    ~H"""
    <form class="tayori-subscribe" action={@base <> "/subscribe"} method="post" id="subscribe-form">
      <input type="hidden" name="_csrf_token" value={@csrf} />
      <label for="tayori-email" class="tayori-visually-hidden">{@messages["email"]}</label>
      <input
        id="tayori-email"
        class="tayori-input"
        type="email"
        name="email"
        required
        autocomplete="email"
        placeholder={@messages["emailPlaceholder"]}
      />
      <button type="submit" class="tayori-cta">{@messages["subscribe"]}</button>
    </form>
    """
  end

  attr :entry, Entry, required: true
  attr :reactions, :any, required: true
  attr :config, Config, required: true
  attr :messages, :map, required: true
  attr :base, :string, required: true
  attr :csrf, :string, required: true
  attr :signed_in, :boolean, required: true
  attr :return, :string, required: true

  # Reactions as forms, so that they work without a script.
  defp reaction_form(assigns) do
    {counts, mine} = assigns.reactions

    assigns =
      assigns
      |> assign(:counts, Map.get(counts, assigns.entry.id, %{}))
      |> assign(:mine, Map.get(mine, assigns.entry.id, []))

    ~H"""
    <form
      class="tayori-reactions"
      action={@base <> "/" <> @entry.slug <> "/react"}
      method="post"
      aria-label={@messages["react"]}
    >
      <input type="hidden" name="_csrf_token" value={@csrf} />
      <input type="hidden" name="return" value={@return} />
      <button
        :for={emoji <- @config.reactions}
        type="submit"
        name="emoji"
        value={emoji}
        class="tayori-reaction"
        aria-pressed={to_string(emoji in @mine)}
        disabled={!@signed_in}
        title={!@signed_in && @messages["signInToReact"]}
      >
        <span class="tayori-reaction-emoji" aria-hidden="true">{emoji}</span>
        <span :if={Map.get(@counts, emoji, 0) > 0} class="tayori-reaction-count">
          {Map.get(@counts, emoji)}
        </span>
      </button>
    </form>
    """
  end

  attr :notice, :string, required: true
  attr :messages, :map, required: true

  defp notice(assigns) do
    assigns =
      assign(assigns,
        error: assigns.notice in ["invalid", "invalid_email"],
        text:
          case assigns.notice do
            "subscribed" -> assigns.messages["subscribed"]
            "confirmed" -> assigns.messages["confirmed"]
            "unsubscribed" -> assigns.messages["unsubscribed"]
            "invalid_email" -> assigns.messages["email"] <> "?"
            _ -> assigns.messages["invalidLink"]
          end
      )

    ~H"""
    <p class={["tayori-notice", @error && "tayori-notice-error"]} role="status">
      <.icon name={if @error, do: "circle-x", else: "circle-check"} />{@text}
    </p>
    """
  end

  attr :base, :string, required: true
  attr :locale, :string, required: true

  defp languages(assigns) do
    ~H"""
    <span
      :for={locale <- Config.get().locales}
      class="tayori-language"
    >
      <a
        href={@base <> "?lang=" <> URI.encode_www_form(locale)}
        lang={locale}
        hreflang={locale}
        aria-current={locale == @locale && "page"}
      >
        {Tayori.Locales.name(locale)}
      </a>
    </span>
    """
  end

  # ── The document ────────────────────────────────────────────────

  defp render(conn, opts, locale, title, meta, url, inner) do
    meta = Enum.reject(meta, &(Map.get(&1, :content, true) in [nil, ""]))

    html =
      case opts.layout do
        {module, function} ->
          apply(module, function, [
            %{inner_content: inner, conn: conn, page_title: title, meta: meta, flash: %{}}
          ])

        nil ->
          document(%{
            inner_content: inner,
            title: title,
            locale: locale,
            meta: meta,
            canonical: url,
            theme: opts.theme,
            css: css(opts.mount, opts.theme),
            feed: base_path(conn) <> "/feed.xml",
            nonce: opts.mount.csp_nonces[:style],
            script_nonce: opts.mount.csp_nonces[:script]
          })
      end

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, Safe.to_iodata(html))
    |> halt()
  end

  defp document(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@locale} class="tayori-auto" data-tayori-theme={@theme}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <title>{@title}</title>
        <link rel="canonical" href={@canonical} />
        <.meta_tag :for={tag <- @meta} tag={tag} nonce={@script_nonce} />
        <link rel="stylesheet" href={@css} nonce={@nonce} />
        <link rel="alternate" type="application/atom+xml" title={@title} href={@feed} />
      </head>
      <body class="tayori-page">
        {@inner_content}
      </body>
    </html>
    """
  end

  attr :tag, :map, required: true
  attr :nonce, :string, default: nil

  # HEEx does not interpolate in a script: the tag is built whole. The JSON
  # can hold no "</", so it cannot end the script.
  defp meta_tag(%{tag: %{json_ld: data}, nonce: nonce} = assigns) do
    json = data |> JSON.encode!() |> String.replace("</", "<\\/")
    nonce = if nonce, do: ~s( nonce="#{escape(nonce)}"), else: ""

    assigns =
      assign(
        assigns,
        :script,
        Phoenix.HTML.raw(~s(<script type="application/ld+json"#{nonce}>#{json}</script>))
      )

    ~H"{@script}"
  end

  defp meta_tag(%{tag: %{hreflang: _}} = assigns) do
    ~H"""
    <link rel="alternate" hreflang={@tag.hreflang} href={@tag.href} />
    """
  end

  defp meta_tag(%{tag: %{property: _}} = assigns) do
    ~H"""
    <meta property={@tag.property} content={@tag.content} />
    """
  end

  defp meta_tag(assigns) do
    ~H"""
    <meta name={@tag.name} content={@tag.content} />
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp json_ld(entry, url, image, description) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BlogPosting",
      "headline" => entry.translation.title,
      "description" => description,
      "url" => url,
      "image" => image,
      "datePublished" => entry.published_at && DateTime.to_iso8601(entry.published_at),
      "dateModified" => entry.updated_at && DateTime.to_iso8601(entry.updated_at),
      "inLanguage" => entry.translation.locale,
      "author" =>
        entry.author && entry.author["name"] &&
          %{"@type" => "Person", "name" => entry.author["name"]}
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp languages_meta(%Config{locales: [_one]}, _url), do: []

  defp languages_meta(%Config{locales: locales}, url) do
    for locale <- locales,
        do: %{hreflang: locale, href: url <> "?lang=" <> URI.encode_www_form(locale)}
  end

  defp noindex(falsy) when falsy in [nil, false], do: []
  defp noindex(_), do: [%{name: "robots", content: "noindex"}]

  # The cover, else the first image of the body: the picture of a shared link.
  defp image(%Entry{cover: %{"url" => url}}, base), do: absolute(url, base)

  defp image(%Entry{translation: %{body: %Kotoba.Content{html: html}}}, base)
       when is_binary(html) do
    case Regex.run(~r/<img[^>]+src="([^"]+)"/, html) do
      [_, src] -> absolute(src, base)
      _ -> nil
    end
  end

  defp image(_entry, _base), do: nil

  defp absolute(nil, _base), do: nil

  defp absolute("/" <> _ = path, base) do
    uri = URI.parse(base)
    "#{uri.scheme}://#{uri.authority}" <> path
  end

  defp absolute(url, _base), do: url

  defp reactions(config, reader, entries) do
    if Config.feature?(config, :reactions),
      do: Tayori.Reactions.for_entries(reader, Enum.map(entries, & &1.id))
  end

  defp signed_in_reader(%Reader{id: nil}), do: nil
  defp signed_in_reader(reader), do: reader

  defp get_entry(id) do
    Tayori.Entries.get!(id)
  rescue
    Ecto.NoResultsError -> nil
    Ecto.Query.CastError -> nil
  end

  defp notice_of(%{"notice" => notice})
       when notice in ~w(subscribed confirmed unsubscribed invalid invalid_email),
       do: notice

  defp notice_of(_params), do: nil

  defp read_form(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 8_000)
        {:ok, URI.decode_query(body), conn}

      params ->
        {:ok, params, conn}
    end
  end

  defp redirect_back(conn, return, fallback) do
    base = base_path(conn)

    to =
      if is_binary(return) and String.starts_with?(return, base) and
           not String.starts_with?(return, "//"),
         do: return,
         else: fallback

    redirect_to(conn, to)
  end

  defp redirect_to(conn, to) do
    conn
    |> put_resp_header("location", to)
    |> send_resp(303, "")
    |> halt()
  end

  defp not_found(conn) do
    conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not Found") |> halt()
  end

  # A link of the page, in its language.
  defp query(base, locale, params) do
    case (Keyword.delete(params, :lang) ++ [lang: locale])
         |> Enum.reject(fn {_key, value} -> value in [nil, ""] end) do
      [] -> base
      params -> base <> "?" <> URI.encode_query(params)
    end
  end

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value) when is_binary(value), do: String.trim(value) |> blank_trimmed()

  defp blank_trimmed(""), do: nil
  defp blank_trimmed(value), do: String.slice(value, 0, 100)

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

  # The style sheet of the theme, among the mount's assets.
  defp css(mount, :sumi), do: PhoenixMountable.Assets.url(mount, :sumi)
  defp css(mount, _tayori), do: PhoenixMountable.Assets.url(mount, :css)

  defp base_path(conn), do: PhoenixMountable.Path.path(conn, "/")

  defp base_url(conn, opts) do
    case opts.url do
      nil ->
        port =
          if {conn.scheme, conn.port} in [{:http, 80}, {:https, 443}],
            do: "",
            else: ":#{conn.port}"

        "#{conn.scheme}://#{conn.host}#{port}" <> base_path(conn)

      url ->
        String.trim_trailing(url, "/") <> opts.mount.path
    end
  end
end
