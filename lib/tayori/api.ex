defmodule Tayori.API do
  @moduledoc """
  The news as JSON, for a frontend that Phoenix does not render (React,
  Vue, Svelte, a mobile app), and as HTML for `<tayori-news>`, the
  element of Tayori's script. Mounted with `Tayori.Router.tayori_api/2`:

      scope "/api" do
        pipe_through [:api_session]
        tayori_api "/news", resolver: MyAppWeb.TayoriResolver
      end

  Mount it behind a pipeline that has the app's session (`fetch_session`,
  and the app's own plug that assigns the user): the resolver reads the
  reader from the conn (`c:Tayori.Resolver.resolve_reader/1`). A visitor
  gets the entries for everyone, and nothing is unread. On another
  origin, a reader comes with a signed token instead (the `:embed`
  feature, `Tayori.Embed`).

  ## The routes

    * `GET /` - the newest entries, the pinned ones first:
      `{"entries": [...], "more": bool, "unread": n, "newAfter": time,
      "signedIn": bool, "locale": tag, "page": url, "features": [...],
      "emoji": [...], "messages": {...}}`. An entry published after
      `newAfter` is new to the reader (nil for a visitor). `?before=<id>`
      gives the entries published before that one, with no pinned ones;
      `?limit=` up to 50 (10); `?category=<key>` the entries of a
      category; `?q=` those with every word in their title, summary or
      body.
    * `GET /unread` - `{"unread": n, "signedIn": bool, "locale": tag,
      "features": [...], "emoji": [...], "messages": {...}}`, cheap
      enough to ask often.
    * `POST /seen` - marks the news as seen, now: `{"unread": 0}`.
    * `GET /categories` - `{"categories": [{"key", "name", "color"}]}`,
      in their order, named in the reader's language.
    * `GET /announcement` - the entry announced to the reader now:
      `{"announcement": {...}}`, or `{"announcement": null}`. With the
      `:announcements` feature, else a 404.
    * `POST /announcement/:id/dismiss` - dismisses it for the reader, on
      every device: `{"dismissed": true}`. A visitor's is not kept.
    * `POST /:id/reactions` - turns the reader's reaction on or off, with
      `{"emoji": "🎉"}` as the body: `{"reactions": {"counts": {...},
      "mine": [...]}}`. A 401 for a visitor, a 422 for an emoji that is
      not one of the app's. With the `:reactions` feature, else a 404.
    * `GET /:slug` - one entry: `{"entry": {...}}`, or a 404. It counts a
      view of the entry from `"widget"` (the `:analytics` feature).

  `<tayori-news>` reads the panel as HTML: the components of
  `Tayori.Components`, rendered from the same state as in a LiveView
  (`Tayori.Live.State`), in `{"html": ...}`. The element answers their
  `phx-click`, so the markup is one, wherever the panel is shown:

    * `GET /ui/button` - the button, with the reader's count of unread
      entries: `{"html", "unread"}`. `?label=1` shows its word.
    * `POST /ui/panel` - opens the panel on the list, and marks the news
      seen: `{"html", "since"}`. `since` keeps the New marks of the
      opening in the panel's other views.
    * `GET /ui/panel` - a view of the open panel: `?category=<key>`,
      `?pages=` (the pages of the list shown, up to 20), `?entry=<id>`
      (an entry of the list, or the announcement, opened whole; a view
      from `"widget"`), `?since=`: `{"html", "entry"}`, or a 404 for an
      entry the reader does not see.
    * `GET /ui/announcement` - the announcement of the moment:
      `{"html", "id", "kind"}`, all nil when there is none. With the
      `:announcements` feature, else a 404.

  For machines, not readers, with no session (see the
  [Automation](automation.md) guide):

    * `POST /changes` - changes for the inbox, with the ingest token
      (`Tayori.Ingest`).
    * `POST /hooks/github` - GitHub's webhook, signed with its secret
      (`Tayori.GitHub`).

  With the `:embed` feature, also:

    * `OPTIONS` of each route - the CORS preflight of the sites of the
      feature.
    * `GET /tayori.js` - the script of `<tayori-news>`, an ES module.
    * `GET /tayori.css` and `GET /tayori-sumi.css` - its style sheets, in
      Tayori's theme or Sumi's, with Kotoba's for the bodies.

  An entry is:

      {
        "id": "0193…",
        "slug": "exports-in-two-clicks",
        "title": "Exports in two clicks",
        "summary": "Zip a project, with its files and notes.",
        "cover": {"url": "…", "alt": "…", "width": 1600, "height": 900},
        "categories": [{"key": "new", "name": "New", "color": "green"}],
        "pinned": false,
        "publishedAt": "2026-10-20T09:00:00Z",
        "locale": "en",
        "html": "<p>…</p>",
        "text": "…",
        "url": "https://myapp.com/changelog/exports-in-two-clicks",
        "reactions": {"counts": {"🎉": 3}, "mine": ["🎉"]}
      }

  `cover` is nil when it has none; `html` is the body as Kotoba renders
  it (escaped, with no HTML of its own); `url` the entry on the public
  page, whole, when there is one (the `:page` option, else the
  `tayori_page` of the same router); `reactions` is there with
  the `:reactions` feature. An announcement is an entry with
  `"announce"` (`"popup"`, `"toast"` or `"banner"`), `"until"` and
  `"cta"` (`{"url", "label"}` or nil). `messages` are the words around
  the news in the reader's language (`Tayori.Messages`), and `features`
  the extras a frontend shows (`"reactions"`, `"announcements"`), with
  the `emoji` of the reactions.

  An error is `{"error": code}`: `"not_found"`, `"unauthorized"` (a
  visitor reacts), `"unknown_emoji"`, `"token_expired"` (a reader token
  older than its `:max_age`, a 401).

  Behind the app's `protect_from_forgery`, a `POST` needs the CSRF token
  of the session in the `x-csrf-token` header, as `<tayori-news>` sends
  it.
  """

  @behaviour Plug

  import Plug.Conn

  alias Tayori.{Announcements, Categories, Category, Config, Embed, Entries, Entry}
  alias Tayori.{Messages, Reactions, Reader, Resolver, Views}
  alias Tayori.Panel
  alias Tayori.Router.Page

  @impl Plug
  def init(action), do: action

  # The public page's address, whole, so that its links work from a site
  # on another origin too.
  defp page_url(conn) do
    case Page.path_from(conn.assigns.mount) do
      nil -> nil
      "http" <> _ = url -> url
      path -> endpoint_url(conn) <> path
    end
  end

  defp endpoint_url(conn) do
    case conn.private[:phoenix_endpoint] do
      nil -> ""
      endpoint -> endpoint.url()
    end
  end

  @impl Plug
  def call(conn, :preflight), do: preflight(conn)
  def call(conn, :asset), do: asset(Embed.cors(conn))

  def call(conn, action) do
    opts = Map.put(conn.assigns.mount.options, :page, page_url(conn))
    conn = Embed.cors(conn)

    case reader(conn, opts) do
      {:ok, reader} ->
        handle(action, conn, reader, locale(conn, reader), opts)

      {:error, :expired} ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer error="invalid_token"))
        |> json(401, %{error: "token_expired"})
    end
  end

  # The reader of a token when the request has one of Tayori's, else the
  # resolver's (the token may be the app's own, for its own API).
  defp reader(conn, opts) do
    with token when is_binary(token) <- Embed.bearer(conn),
         {:ok, reader} <- Embed.verify(token) do
      {:ok, reader}
    else
      {:error, :expired} -> {:error, :expired}
      _ -> {:ok, Resolver.reader(opts.resolver, conn)}
    end
  end

  defp handle(:index, conn, reader, locale, opts) do
    conn = fetch_query_params(conn)
    params = conn.query_params
    limit = params |> Map.get("limit", "10") |> parse_int(10) |> min(50) |> max(1)
    as = reader || Reader.visitor(locale)

    entries =
      Tayori.news(as,
        limit: limit + 1,
        before: params["before"] && visible(params["before"], as),
        category: blank(params["category"]),
        search: blank(params["q"])
      )

    pinned = Enum.count(entries, & &1.pinned_at)
    shown = Enum.take(entries, limit + pinned)

    json(
      conn,
      200,
      Map.merge(about(reader, locale), %{
        entries: entries_json(shown, as, opts),
        more: length(entries) > limit + pinned,
        unread: if(reader, do: Tayori.unread_count(reader), else: 0),
        newAfter: reader && Tayori.new_after(reader),
        page: opts[:page]
      })
    )
  end

  defp handle(:unread, conn, reader, locale, _opts) do
    json(
      conn,
      200,
      Map.put(
        about(reader, locale),
        :unread,
        if(reader, do: Tayori.unread_count(reader), else: 0)
      )
    )
  end

  defp handle(:seen, conn, reader, _locale, _opts) do
    if reader, do: Tayori.mark_seen(reader)
    json(conn, 200, %{unread: 0})
  end

  defp handle(:categories, conn, _reader, locale, _opts) do
    locales = Config.get().locales

    json(conn, 200, %{
      categories: Enum.map(Categories.list(), &category_json(&1, locale, locales))
    })
  end

  defp handle(:announcement, conn, reader, locale, opts) do
    if feature?(:announcements) do
      as = reader || Reader.visitor(locale)

      announcement =
        case Announcements.current(as) do
          nil -> nil
          entry -> [entry] |> entries_json(as, opts) |> hd() |> announcement_json(entry)
        end

      json(conn, 200, %{announcement: announcement})
    else
      not_found(conn)
    end
  end

  defp handle(:dismiss, conn, reader, locale, _opts) do
    with true <- feature?(:announcements),
         %Entry{} = entry <- visible(conn.path_params["id"], reader || Reader.visitor(locale)) do
      if reader, do: Announcements.dismiss(reader, entry.id)
      json(conn, 200, %{dismissed: true})
    else
      _ -> not_found(conn)
    end
  end

  defp handle(:react, conn, reader, locale, _opts) do
    with true <- feature?(:reactions),
         %Entry{} = entry <- visible(conn.path_params["id"], reader || Reader.visitor(locale)) do
      {emoji, conn} = emoji(conn)

      case Reactions.toggle(reader || Reader.visitor(locale), entry.id, emoji) do
        {:ok, reactions} -> json(conn, 200, %{reactions: reactions})
        {:error, :visitor} -> json(conn, 401, %{error: "unauthorized"})
        {:error, :unknown_emoji} -> json(conn, 422, %{error: "unknown_emoji"})
      end
    else
      _ -> not_found(conn)
    end
  end

  defp handle(:show, conn, reader, locale, opts) do
    as = reader || Reader.visitor(locale)

    case Tayori.entry(as, conn.path_params["slug"]) do
      %Entry{} = entry ->
        Views.track(reader, entry.id, "widget")
        json(conn, 200, %{entry: [entry] |> entries_json(as, opts) |> hd()})

      nil ->
        not_found(conn)
    end
  end

  # ── The panel as HTML, for <tayori-news> ────────────────────────

  defp handle(:ui_button, conn, reader, locale, opts) do
    conn = fetch_query_params(conn)
    state = Panel.new(reader, page: opts[:page], locale: locale)
    label? = conn.query_params["label"] in ["1", "true"]
    json(conn, 200, %{html: Panel.HTML.button(state, label?), unread: state.unread})
  end

  # Opens the panel: the list, with the news marked seen. `since` is the
  # time what was new until now was published after, for the panel's
  # other views.
  defp handle(:ui_open, conn, reader, locale, opts) do
    state = reader |> Panel.new(page: opts[:page], locale: locale) |> Panel.open()

    json(conn, 200, %{
      html: Panel.HTML.panel(state),
      since: state.seen_before && DateTime.to_iso8601(state.seen_before)
    })
  end

  # The open panel as the element left it: `?category=`, `?pages=` (the
  # pages of the list shown), `?entry=<id>` (an entry of them, or the
  # announcement, opened whole), `?since=` (from the opening).
  defp handle(:ui_panel, conn, reader, locale, opts) do
    conn = fetch_query_params(conn)
    params = conn.query_params
    pages = params |> Map.get("pages", "1") |> parse_int(1) |> min(20) |> max(1)

    state =
      %{
        Panel.new(reader, page: opts[:page], locale: locale)
        | open: true,
          category: blank(params["category"]),
          categories: Categories.by_key(),
          seen_before: since(params["since"])
      }

    state = Panel.load(state, state.limit * pages)

    case blank(params["entry"]) do
      nil ->
        json(conn, 200, %{html: Panel.HTML.panel(state), entry: nil})

      id ->
        case Panel.show(state, id, "widget") do
          {:ok, state} -> json(conn, 200, %{html: Panel.HTML.panel(state), entry: id})
          :error -> not_found(conn)
        end
    end
  end

  defp handle(:ui_announcement, conn, reader, locale, opts) do
    if feature?(:announcements) do
      state = Panel.new(reader, page: opts[:page], locale: locale)

      body =
        case state.announcement do
          nil -> %{html: nil, id: nil, kind: nil}
          entry -> %{html: Panel.HTML.announcement(state), id: entry.id, kind: entry.announce}
        end

      json(conn, 200, body)
    else
      not_found(conn)
    end
  end

  defp since(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _ -> nil
    end
  end

  defp since(_value), do: nil

  # What every answer of the news says of the reader and the app.
  defp about(reader, locale) do
    config = Config.get()
    features = Enum.filter(config.features, &(&1 in [:reactions, :announcements]))

    %{
      signedIn: reader != nil,
      locale: locale,
      features: features,
      emoji: if(:reactions in features, do: config.reactions, else: []),
      messages: Messages.for_locale(locale)
    }
  end

  defp feature?(feature), do: Config.feature?(Config.get(), feature)

  # An entry by its id, if the reader sees it.
  defp visible(id, reader) do
    with true <- is_binary(id),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %Entry{slug: slug} <- safe_get(uuid) do
      Tayori.entry(reader, slug)
    else
      _ -> nil
    end
  end

  defp safe_get(id) do
    Entries.get!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  # The emoji of a reaction, from a JSON or form body, as the app's
  # endpoint parsed it or not.
  defp emoji(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        {:ok, body, conn} = read_body(conn, length: 1_000)

        params = decode(get_req_header(conn, "content-type"), body)
        {text(params["emoji"]), conn}

      params ->
        {text(params["emoji"]), conn}
    end
  end

  defp decode(["application/json" <> _ | _], body) do
    case JSON.decode(body) do
      {:ok, %{} = params} -> params
      _ -> %{}
    end
  end

  defp decode(_content_type, body), do: URI.decode_query(body)

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""

  defp entries_json(entries, reader, opts) do
    config = Config.get()
    categories = Categories.by_key()

    reactions =
      if Config.feature?(config, :reactions),
        do: Reactions.for_entries(reader, Enum.map(entries, & &1.id))

    Enum.map(entries, &entry_json(&1, opts, categories, config.locales, reactions))
  end

  @doc false
  # An entry as the API gives it.
  def entry_json(%Entry{translation: t} = entry, opts, categories, locales, reactions) do
    json = %{
      id: entry.id,
      slug: entry.slug,
      title: t.title,
      summary: t.summary,
      cover: cover_json(entry.cover),
      categories:
        Enum.map(entry.categories, fn key ->
          case Map.get(categories, key) do
            nil -> %{key: key, name: key, color: "gray"}
            category -> category_json(category, t.locale, locales)
          end
        end),
      pinned: entry.pinned_at != nil,
      publishedAt: entry.published_at,
      locale: t.locale,
      html: t.body && t.body.html,
      text: t.body && t.body.text,
      url: opts[:page] && String.trim_trailing(opts.page, "/") <> "/" <> entry.slug
    }

    case reactions do
      {counts, mine} ->
        Map.put(json, :reactions, %{
          counts: Map.get(counts, entry.id, %{}),
          mine: Map.get(mine, entry.id, [])
        })

      nil ->
        json
    end
  end

  defp cover_json(%{"url" => url} = cover) when is_binary(url) do
    %{url: url, alt: cover["alt"] || "", width: cover["width"], height: cover["height"]}
  end

  defp cover_json(_cover), do: nil

  defp category_json(%Category{} = category, locale, locales) do
    %{key: category.key, name: Category.name(category, locale, locales), color: category.color}
  end

  defp announcement_json(json, %Entry{announce: kind, announce_until: until, translation: t}) do
    Map.merge(json, %{
      announce: kind,
      until: until,
      cta: t.cta_url && %{url: t.cta_url, label: t.cta_label}
    })
  end

  # ── CORS, and the files of the embed ────────────────────────────

  # The preflight of a site of the :embed feature: the methods and the
  # headers the element sends, never credentials.
  defp preflight(conn) do
    cond do
      not feature?(:embed) ->
        not_found(conn)

      origin = Embed.allowed_origin(conn) ->
        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("access-control-allow-methods", "GET, POST")
        |> put_resp_header("access-control-allow-headers", "authorization, content-type")
        |> put_resp_header("access-control-max-age", "7200")
        |> Embed.vary("origin")
        |> send_resp(204, "")
        |> halt()

      true ->
        conn
        |> Embed.vary("origin")
        |> send_resp(403, "")
        |> halt()
    end
  end

  defp asset(conn) do
    with true <- feature?(:embed),
         {type, hash, body, gzipped} <- Embed.asset(conn.path_info |> List.last()) do
      etag = ~s("#{hash}")
      gzip? = conn |> get_req_header("accept-encoding") |> Enum.any?(&(&1 =~ "gzip"))

      conn =
        conn
        |> put_resp_header("content-type", type <> "; charset=utf-8")
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> put_resp_header("etag", etag)
        |> Embed.vary("accept-encoding")

      cond do
        etag in get_req_header(conn, "if-none-match") ->
          conn |> send_resp(304, "") |> halt()

        gzip? ->
          conn |> put_resp_header("content-encoding", "gzip") |> send_resp(200, gzipped) |> halt()

        true ->
          conn |> send_resp(200, body) |> halt()
      end
    else
      _ -> not_found(conn)
    end
  end

  # The language of the news: the reader's, else the first of the request's
  # Accept-Language that the entries are written in, else the first.
  @doc false
  def locale(conn, reader) do
    config = Config.get()

    cond do
      reader && reader.locale ->
        reader.locale

      lang = conn |> fetch_query_params() |> Map.get(:query_params) |> Map.get("lang") ->
        best([lang], config)

      true ->
        conn |> get_req_header("accept-language") |> accepted() |> best(config)
    end
  end

  defp accepted([header | _]) do
    header
    |> String.split(",")
    |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim()))
  end

  defp accepted([]), do: []

  defp best(wanted, config) do
    Enum.find_value(wanted, fn tag ->
      language = tag |> String.split("-") |> hd()

      Enum.find(config.locales, &(String.downcase(&1) == String.downcase(tag))) ||
        Enum.find(config.locales, &(&1 |> String.split("-") |> hd() == language))
    end) || Config.default_locale(config)
  end

  defp parse_int(text, default) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value) when is_binary(value), do: value
  defp blank(_value), do: nil

  defp not_found(conn), do: json(conn, 404, %{error: "not_found"})

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(status, JSON.encode!(body))
    |> halt()
  end
end
