defmodule Tayori.API do
  @moduledoc """
  The news as JSON, for a frontend that Phoenix does not render (React,
  Vue, Svelte, a mobile app) and for `<tayori-news>`, the element of
  Tayori's script. Mounted with `Tayori.Router.tayori_api/2`:

      scope "/api" do
        pipe_through [:browser]
        tayori_api "/news", resolver: MyAppWeb.TayoriResolver, page: "/changelog"
      end

  Mount it behind a pipeline that has the app's session (`fetch_session`,
  and the app's own plug that assigns the user): the resolver reads the
  reader from the conn (`c:Tayori.Resolver.resolve_reader/1`). A visitor
  gets the entries for everyone, and nothing is unread.

  ## The routes

    * `GET /` - the newest entries: `{"entries": [...], "more": bool,
      "unread": n, "newAfter": time, "messages": {...}}`; an entry
      published after `newAfter` is new to the reader (nil for a visitor). `?before=<id>` gives
      the entries published before that one; `?limit=` up to 50 (10).
    * `GET /unread` - `{"unread": n, "messages": {...}}`, the count alone,
      cheap enough to ask often.
    * `POST /seen` - marks the news as seen, now: `{"unread": 0}`. Behind
      the app's `protect_from_forgery`, send the CSRF token in the
      `x-csrf-token` header, as `<tayori-news>` does.
    * `GET /:slug` - one entry: `{"entry": {...}}`, or a 404.

  An entry is `{"id", "slug", "title", "summary", "categories",
  "publishedAt", "locale", "html", "text", "url"}`: `html` is the body as
  Kotoba renders it (escaped, with no HTML of its own), `url` the entry on
  the public page when the API knows its path (`:page`). `messages` are
  the words around the news in the reader's language (`Tayori.Messages`).
  """

  @behaviour Plug

  import Plug.Conn

  alias Tayori.{Config, Entries, Entry, Messages, Reader, Resolver}

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(conn, action) do
    opts = conn.assigns.mount.options
    reader = Resolver.reader(opts.resolver, conn)
    locale = locale(conn, reader)
    handle(action, conn, reader, locale, opts)
  end

  defp handle(:index, conn, reader, locale, opts) do
    conn = fetch_query_params(conn)
    limit = conn.query_params |> Map.get("limit", "10") |> parse_int(10) |> min(50) |> max(1)
    as = reader || Reader.visitor(locale)

    entries =
      Tayori.news(as, limit: limit + 1, before: before(conn.query_params["before"], as))

    json(conn, 200, %{
      entries: entries |> Enum.take(limit) |> Enum.map(&entry_json(&1, opts)),
      more: length(entries) > limit,
      unread: if(reader, do: Tayori.unread_count(reader), else: 0),
      newAfter: reader && Tayori.new_after(reader),
      messages: Messages.for_locale(locale)
    })
  end

  defp handle(:unread, conn, reader, locale, _opts) do
    json(conn, 200, %{
      unread: if(reader, do: Tayori.unread_count(reader), else: 0),
      messages: Messages.for_locale(locale)
    })
  end

  defp handle(:seen, conn, reader, _locale, _opts) do
    if reader, do: Tayori.mark_seen(reader)
    json(conn, 200, %{unread: 0})
  end

  defp handle(:show, conn, reader, locale, opts) do
    case Tayori.entry(reader || Reader.visitor(locale), conn.path_params["slug"]) do
      %Entry{} = entry -> json(conn, 200, %{entry: entry_json(entry, opts)})
      nil -> json(conn, 404, %{error: "not_found"})
    end
  end

  # The entry to page before, if the reader sees it.
  defp before(nil, _reader), do: nil

  defp before(id, reader) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
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

  @doc false
  # An entry as the API and the JSON Feed give it.
  def entry_json(%Entry{translation: t} = entry, opts) do
    %{
      id: entry.id,
      slug: entry.slug,
      title: t.title,
      summary: t.summary,
      categories: entry.categories,
      publishedAt: entry.published_at,
      locale: t.locale,
      html: t.body && t.body.html,
      text: t.body && t.body.text,
      url: opts[:page] && String.trim_trailing(opts.page, "/") <> "/" <> entry.slug
    }
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

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(status, JSON.encode!(body))
    |> halt()
  end
end
