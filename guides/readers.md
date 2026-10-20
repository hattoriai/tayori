# Readers

Tayori reads the news for a `Tayori.Reader`, which your resolver builds
from your own user (`c:Tayori.Resolver.resolve_reader/1`):

```elixir
@impl true
def resolve_reader(%{assigns: %{current_scope: %{user: %{} = user}}}) do
  %Tayori.Reader{
    id: "user:#{user.id}",
    segments: ["plan:#{user.plan}", "role:#{user.role}"],
    locale: user.locale,
    since: user.inserted_at
  }
end

def resolve_reader(_visitor), do: nil
```

It gets a `Plug.Conn` (the JSON API, the public page) or a LiveView
socket (`Tayori.Live`, after your own `on_mount` hooks): both have your
`assigns`. Nil is a visitor.

Nothing about your readers leaves your app, and nothing is copied into
Tayori's tables but the time each last saw the news.

## The id

`id` keys what Tayori keeps of a reader: when they last saw the news.
Make it stable, and unique across the kinds of people of your app
(`"user:42"`, `"member:7"`). A visitor has no id: they see the news, and
nothing is unread.

## Segments

Segments are what a reader is, in the words of your app: a plan, a role,
a team, a country, a beta. An entry with no segments is for everyone; an
entry with segments is for the readers in at least one of them.

```elixir
segments: ["plan:pro", "role:owner", "beta"]
```

They are strings, compared as they are. Offer the ones your admins can
choose in `c:Tayori.Resolver.segments/0` (see the [Admin](admin.md)
guide). A visitor has no segments: they see the entries for everyone, and
so does the public page.

Who may see an entry is decided when the news is read: a reader who
moves to the Pro plan sees the Pro entries from then on, the old ones
too.

## Languages

`locale` is the language to show the news in: an entry's translation in
that language, else in the first of Tayori's `:locales`. The words around
the news (the button, the panel) follow it (`Tayori.Messages`).

A visitor has no reader: the public page and the JSON API speak the
request's `?lang=`, else the browser's `Accept-Language`. If your app
keeps its own choice of language (a cookie, the session, a locale plug),
say it with `resolve_locale/1`, which comes before the browser's:

```elixir
@impl true
def resolve_locale(_conn), do: Gettext.get_locale(MyAppWeb.Gettext)
```

## What is unread

Tayori keeps one time for each reader: when they last saw the news. An
entry published after it is unread, and marked New in the panel.
`Tayori.unread_count/2` counts them (up to 99, in one query).

`since` keeps a new account from starting with all the news of the past:
entries published before it are never unread. A reader with no `since`
who never saw the news has everything unread.

Opening the panel (`tayori:open`), or `POST /seen` of the JSON API, marks
the news seen (`Tayori.mark_seen/2`), and tells the reader's other tabs.

## In your code

The functions of `Tayori` read the news for a reader, anywhere:

```elixir
reader = MyAppWeb.TayoriResolver.resolve_reader(conn)

Tayori.news(reader, limit: 5)
Tayori.unread_count(reader)
Tayori.mark_seen(reader)
```
