# In the app

The news in your LiveViews: a button with the count of what the reader has
not seen, and the panel it opens.

## The hook

`Tayori.Live` gives each LiveView of a `live_session` the `@tayori`
assign. Put it after your own hooks, so that the resolver finds your user
in the socket's assigns:

```elixir
live_session :app,
  on_mount: [
    {MyAppWeb.UserAuth, :require_authenticated},
    {Tayori.Live, resolver: MyAppWeb.TayoriResolver, page: "/changelog", limit: 10}
  ] do
  ...
end
```

* `:resolver` - your `Tayori.Resolver`.
* `:page` - the path of your public page, for the panel's link to all the
  news and each entry's title.
* `:limit` - the entries of the panel, and of each "Show more" (10).

The hook handles its own events (`tayori:open`, `tayori:close`,
`tayori:more`, `tayori:filter`, `tayori:show`, `tayori:back`, and with the
features on `tayori:react` and `tayori:dismiss`) and the messages of the
PubSub before your LiveView sees them, so your LiveView needs nothing
else.

## The components

```heex
<Tayori.Components.news_button tayori={@tayori} />
<Tayori.Components.news_panel tayori={@tayori} />
```

Put the button where your header has its icons, and the panel once in the
layout: it is fixed to the side of the page. `label` shows the word beside
the icon:

```heex
<Tayori.Components.news_button tayori={@tayori} label class="btn btn-ghost" />
```

The panel has a chip for each of your categories, and each entry as a
card: its cover, its categories, its date, its title and summary. A card
opens its entry in the panel, whole, with a way back to the list; with
the `:reactions` feature, the reader reacts there. Pinned entries come
first.

With the `:announcements` feature, put the announcement once in the
layout too: the newest entry the admin announced, as a popup, a toast or
a banner, until the reader dismisses it (on every device) or opens it.
A popup or a toast waits while the panel is open.

```heex
<Tayori.Components.announcement tayori={@tayori} />
```

Your own button can open the panel too:

```heex
<button phx-click="tayori:open">What's new</button>
```

`Tayori.Components.news/1` is the list alone, for a page of your own:

```heex
<Tayori.Components.news entries={Tayori.news(@reader)} messages={@tayori.messages} />
```

## Live

Each open page follows the news:

* an entry published in the admin, or reaching its scheduled time, adds
  to the count of every reader it is for, at once;
* a change to an entry reaches an open panel;
* opening the news in one tab clears the count in the others, and on the
  reader's other devices.

## The `Tayori` hook

The panel has `phx-hook="Tayori"`, which shows the dates in the reader's
time zone and language. Add it to the hooks of your `LiveSocket` (the
installer does):

```js
import { Tayori } from "tayori"

const liveSocket = new LiveSocket("/live", Socket, {hooks: {...colocatedHooks, Tayori}})
```

Without it, the dates are the day in UTC, in the reader's language.

For a page that LiveView does not render, `<tayori-news>` is the same
button, panel and announcement (see [Any frontend](any_frontend.md)).

## Accessibility

The button's name says the count ("What's new, 2 new updates"), and its
`aria-expanded` whether the panel is open. The panel is a non-modal
dialog, labelled by its heading; Escape and a click outside close it, and
Escape in an entry goes back to the list. An unread entry has a dot, named
"New" for screen readers. A popup announcement is a modal dialog, which
Escape dismisses; a toast or a banner is a status.
