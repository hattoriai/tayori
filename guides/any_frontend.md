# Any frontend

The news for a frontend that Phoenix does not render: a React, Vue or
Svelte app served by Phoenix or beside it, a page of plain HTML, a mobile
app, a site on another origin. Tayori gives it a JSON API and an element
that uses it, `<tayori-news>`.

## The JSON API

`Tayori.Router.tayori_api/2` mounts it. Mount it behind a pipeline that
accepts JSON and has your session, so that the resolver finds your user
in the conn's assigns:

```elixir
pipeline :api_session do
  plug :accepts, ["json"]
  plug :fetch_session
  plug :protect_from_forgery
  plug :fetch_current_scope_for_user
end

scope "/api" do
  pipe_through :api_session
  tayori_api "/news", resolver: MyAppWeb.TayoriResolver, page: "/changelog"
end
```

The routes:

| | |
| --- | --- |
| `GET /api/news` | the newest entries, the pinned ones first; `?before=<id>` for the next page, `?limit=` (10, up to 50), `?category=<key>`, `?q=` |
| `GET /api/news/unread` | the count of unread entries, cheap enough to ask often |
| `POST /api/news/seen` | marks the news seen, now |
| `GET /api/news/categories` | the categories, in their order |
| `GET /api/news/:slug` | one entry, counted as a view from `"widget"` (the `:analytics` feature) |
| `POST /api/news/:id/reactions` | turns the reader's reaction on or off (the `:reactions` feature) |
| `GET /api/news/announcement` | the entry announced to the reader now, or null (the `:announcements` feature) |
| `POST /api/news/announcement/:id/dismiss` | dismisses it, on every device |

```json
{
  "entries": [
    {
      "id": "0193…",
      "slug": "exports-in-two-clicks",
      "title": "Exports in two clicks",
      "summary": "Zip a project, with its files and notes.",
      "cover": {"url": "/uploads/export.png", "alt": "The Export button", "width": 1600, "height": 900},
      "categories": [{"key": "new", "name": "New", "color": "green"}],
      "pinned": false,
      "publishedAt": "2026-10-20T09:00:00Z",
      "locale": "en",
      "html": "<p>Every project has an <strong>Export</strong> button.</p>",
      "text": "Every project has an Export button.",
      "url": "/changelog/exports-in-two-clicks",
      "reactions": {"counts": {"🎉": 3}, "mine": ["🎉"]}
    }
  ],
  "more": false,
  "unread": 1,
  "newAfter": "2026-10-19T17:12:00Z",
  "signedIn": true,
  "locale": "en",
  "page": "/changelog",
  "features": ["reactions", "announcements"],
  "emoji": ["👍", "🎉", "❤️", "🚀", "👀"],
  "messages": {"title": "What's new", "...": "..."}
}
```

`html` is the body as Kotoba renders it on the server: every text escaped,
and no HTML of the author's own. The names of the categories are in the
entry's language. `newAfter` is the time after which an entry is new to
the reader (nil for a visitor). `features` are the extras a frontend
shows, `reactions` and `announcements`, with the `emoji` of the
reactions; an entry has `reactions` only with the feature. `messages`
are the words around the news in the reader's language. `/unread` gives
the same, with the count and no entries.

`?category=` and `?q=` are those of `Tayori.news/2`: the entries of a
category, and those with every word of the search in their title,
summary or body, in any language. The pinned entries are on the first
page only, besides `?limit=`: the next page, `?before=` the id of the
last entry that is not pinned, has none.

A reaction is the emoji in the body, as JSON or a form:

```sh
curl -X POST /api/news/0193…/reactions -H 'content-type: application/json' -d '{"emoji": "🎉"}'
```

```json
{"reactions": {"counts": {"🎉": 4}, "mine": ["🎉"]}}
```

A visitor gets a 401 (`{"error": "unauthorized"}`), and an emoji that is
not one of yours a 422 (`{"error": "unknown_emoji"}`).

The announcement is an entry with how it is shown, until when, and its
button:

```json
{
  "announcement": {
    "id": "0193…",
    "title": "Timeline view",
    "...": "...",
    "announce": "toast",
    "until": "2026-10-27T09:00:00Z",
    "cta": {"url": "/timeline", "label": "Try it"}
  }
}
```

`announce` is `popup`, `toast` or `banner`; `cta` is nil when it has no
button, and a nil `label` is the word `tryIt` of the messages. A visitor's
dismissal is not kept: the page hides it until it closes.

A feature that is off has no route: its paths answer 404.

With `protect_from_forgery`, a `POST` needs the CSRF token of the session
in the `x-csrf-token` header.

## `<tayori-news>`

The script of the news defines `<tayori-news>`, the button, the panel and
the announcement of the LiveView components, over the JSON API:

```html
<tayori-news api="/api/news" page="/changelog"></tayori-news>
```

```js
import "tayori"
```

* `api` - the path or the address of the JSON API (`src` is its older
  name).
* `page` - the public page, for the panel's link to all the news (the
  API's `:page` when not given).
* `label` - show the word beside the icon.
* `poll` - how often to ask the count again, in seconds (300; 0 never).
  It also asks when the page comes back into view.
* `reader-token` - the reader's token, on another origin (below).
* `banner` - where an announcement shown as a banner goes, a CSS selector
  (the start of the `<body>` when not given). A popup and a toast are
  fixed to the page.

The panel has the categories to filter by, and the entries as cards: the
cover, the pin, the New mark, the categories, the date, the title, the
summary and the reactions. A card opens its entry in the panel, whole,
with its reactions to press when the reader is signed in. Escape goes
back to the list, then closes, and a click outside closes; the focus
goes to the back button, back to the card, and back to the button. The
announcement steps aside while the panel is open, as in the LiveView.

It reads the CSRF token from `<meta name="csrf-token">` for its `POST`s
on the app's own origin. It renders into the page, not a shadow root,
with the same classes as the LiveView components, so `tayori.css` (and
`kotoba.css`, and `tayori-sumi.css` for Sumi) style it, in light and
dark, and your CSS can too.

It sends `tayori:open` and `tayori:close` events, which bubble, and
`tayori:token-expired` (below).

### In React

```jsx
import "tayori"

export function Header() {
  return (
    <header>
      <tayori-news api="/api/news" page="/changelog" />
    </header>
  )
}
```

### Your own components

The JSON API is the whole contract: a frontend can render the news with
its own components, and call `/unread` and `/seen` itself.

## Another origin

A page on another origin than your app's, a help centre or a marketing
site, has no session of your app: the browser keeps your app's cookies
for your app's origin. The `:embed` feature gives such a page the news,
with a token your server signs for the reader.

### The feature

Name the origins of the sites, each a scheme and a host, with a port if
not the default. Tayori signs the tokens with the app's secret:

```elixir
{Tayori,
 repo: MyApp.Repo,
 pubsub: MyApp.PubSub,
 secret_key_base: Application.fetch_env!(:my_app, MyAppWeb.Endpoint)[:secret_key_base],
 features: [:embed],
 embed: [origins: ["https://www.atelier.app", "https://help.atelier.app"]]}
```

`max_age` sets how long a token is valid, in seconds (a day):
`embed: [origins: [...], max_age: 3600]`.

### The mount

Mount the API again for the sites, behind a pipeline with no session and
no CSRF protection: a request from another origin carries no cookie of
your app, so it has nothing to forge, and its reader comes with the
token. `:as` names the second mount, and `:page` is the address of your
public page, for the links of the entries:

```elixir
pipeline :embed do
  plug :accepts, ["json"]
end

scope "/embed" do
  pipe_through :embed

  tayori_api "/news",
    resolver: MyAppWeb.TayoriResolver,
    page: "https://atelier.app/changelog",
    as: :tayori_embed
end
```

Without a token, the API asks your resolver, with a conn that has no
session: read your user from the assigns, as the installer's resolver
does, and give nil (a visitor) when there is none.

With the feature, the API answers the sites' CORS preflights and gives
their requests their origin back (`access-control-allow-origin`, with
`vary: origin`). It never allows credentials, and it answers no other
origin: a browser on another site cannot read it. Your app's own mount
answers the sites too, but behind `protect_from_forgery` its `POST`s
need your session's CSRF token: give the sites the second mount.

### The page

The API serves the element's script and its style sheets, with Kotoba's
for the bodies:

```html
<link rel="stylesheet" href="https://app.atelier.app/embed/news/tayori.css" />
<script type="module" src="https://app.atelier.app/embed/news/tayori.js"></script>

<tayori-news
  api="https://app.atelier.app/embed/news"
  reader-token="SFMyNTY.g2gDdAAAAAR…"
></tayori-news>
```

`tayori-sumi.css` is the Sumi theme's. The script is an ES module with no
imports, `priv/static/tayori.esm.js` of the Hex package: a site can also
serve its own copy, or bundle `tayori` from npm with its own scripts. The
files are cached for an hour, and change with Tayori.

The Embed card of the admin's settings has the snippet, with the address
of your app's API.

### The reader token

The server that renders the page signs the token of the person it is
for, with the reader your resolver gives:

```heex
<tayori-news api={@news_api} reader-token={Tayori.Embed.token(@reader)}></tayori-news>
```

`Tayori.Embed.token/1` puts the reader's id, segments, language and the
time they joined in a `Phoenix.Token`, signed with your
`secret_key_base` and a salt of Tayori's own. No one can make one, or
change the reader in it, without your secret, and Tayori never takes a
reader's id from the browser any other way. Make it on the server for
the signed-in person, never from an id the page sends. A visitor needs
none: without `reader-token`, the page shows the news for everyone.

When the page is rendered by another server than your app's, that
server asks your app for the token, from its backend, through an
endpoint of your own behind your API's authentication, which answers
`Tayori.Embed.token(reader)`.

The element sends it as `authorization: Bearer <token>`. A token older
than `max_age` is a 401, `{"error": "token_expired"}`: the element
sends `tayori:token-expired`, goes on as a visitor, and takes a new token
when the page sets `reader-token` again:

```js
document.addEventListener("tayori:token-expired", async (event) => {
  const {token} = await (await fetch("/news-token")).json()
  event.target.setAttribute("reader-token", token)
})
```

A bearer token that is not Tayori's (your own API's, say) is left to
your resolver.
