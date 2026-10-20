# Any frontend

The news for a frontend that Phoenix does not render: a React, Vue or
Svelte app served by Phoenix or beside it, a page of plain HTML, a mobile
app. Tayori gives it a JSON API and an element that uses it,
`<tayori-news>`.

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
| `GET /api/news` | the newest entries, `?before=<id>` for the next page, `?limit=` (10, up to 50) |
| `GET /api/news/unread` | the count of unread entries, cheap enough to ask often |
| `POST /api/news/seen` | marks the news seen, now |
| `GET /api/news/:slug` | one entry |

```json
{
  "entries": [
    {
      "id": "0193…",
      "slug": "exports-in-two-clicks",
      "title": "Exports in two clicks",
      "summary": "Zip a project, with its files and notes.",
      "categories": ["New"],
      "publishedAt": "2026-10-20T09:00:00Z",
      "locale": "en",
      "html": "<p>Every project has an <strong>Export</strong> button.</p>",
      "text": "Every project has an Export button.",
      "url": "/changelog/exports-in-two-clicks"
    }
  ],
  "more": false,
  "unread": 1,
  "newAfter": "2026-10-19T17:12:00Z",
  "messages": {"title": "What's new", "...": "..."}
}
```

`html` is the body as Kotoba renders it on the server: every text escaped,
and no HTML of the author's own. `newAfter` is the time after which an
entry is new to the reader (nil for a visitor). `messages` are the words
around the news in the reader's language.

With `protect_from_forgery`, `POST /seen` needs the CSRF token of the
session in the `x-csrf-token` header.

## `<tayori-news>`

The script of the news defines `<tayori-news>`, a button and a panel like
the LiveView ones, over the JSON API:

```html
<tayori-news src="/api/news" page="/changelog"></tayori-news>
```

```js
import "tayori"
```

* `src` - the path of the JSON API.
* `page` - the public page, for the panel's link to all the news.
* `label` - show the word beside the icon.
* `poll` - how often to ask the count again, in seconds (300; 0 never).
  It also asks when the page comes back into view.

It reads the CSRF token from `<meta name="csrf-token">` for `POST /seen`.
It renders into the page, not a shadow root, with the same classes as the
LiveView components, so `tayori.css` (and `kotoba.css`) style it, and
your CSS can too.

It sends `tayori:open` and `tayori:close` events, which bubble.

### In React

```jsx
import "tayori"

export function Header() {
  return (
    <header>
      <tayori-news src="/api/news" page="/changelog" />
    </header>
  )
}
```

### Your own components

The JSON API is the whole contract: a frontend can render the news with
its own components, and call `/unread` and `/seen` itself.

## Another origin

The API reads the reader from your app's session, so it answers the
pages of your app's own origin. A frontend on another origin needs a
signed token and CORS, which Tayori does not give yet (see the backlog).
