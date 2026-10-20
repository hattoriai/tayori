# The public page

The news on a page of its own, for everyone: your changelog on the web,
with a page for each entry and feeds. `Tayori.Router.tayori_page/2`
mounts it:

```elixir
scope "/" do
  pipe_through :browser
  tayori_page "/changelog", title: "What's new in MyApp"
end
```

| | |
| --- | --- |
| `/changelog` | the newest entries, with "Show more" |
| `/changelog/:slug` | one entry |
| `/changelog/feed.xml` | an Atom feed of the newest 20 |
| `/changelog/feed.json` | a JSON Feed of the same |

## Who sees what

The page shows the entries for everyone: those with no segments. With a
`:resolver`, a reader it gives sees the entries for them too, as in the
app:

```elixir
tayori_page "/changelog", resolver: MyAppWeb.TayoriResolver
```

The feeds follow the same rule; a feed reader has no session, so it gets
the entries for everyone.

## Languages

The page is in the reader's language, when an entry has it: the
resolver's reader, else `?lang=`, else the browser's `Accept-Language`.
With more than one language, it links to the others.

## The look

The page is a document of its own, in Tayori's theme or Sumi's
(`theme: :sumi`), with its style sheet at `/changelog/assets/`. To put it
in your own layout instead:

```elixir
tayori_page "/changelog", layout: {MyAppWeb.Layouts, :root}
```

Your root layout then gets `@inner_content`, `@conn` and `@page_title`,
and your page loads `tayori.css` and `kotoba.css` itself.

## Options

* `:title` - the title of the page and the feeds ("What's new", in the
  reader's language).
* `:limit` - the entries of a page (20).
* `:url` - your app's address (`"https://example.com"`), for the links of
  the feeds, when the conn does not have it (behind a proxy).
* `:csp_nonce_assign_key` - the key of the nonce of your Content Security
  Policy in `conn.assigns`, for the style sheet.

The feeds are cached for five minutes (`cache-control: public,
max-age=300`).
