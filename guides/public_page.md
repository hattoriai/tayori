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
| `/changelog` | the newest entries, pinned first, with filters by category, a search and pages |
| `/changelog/:slug` | one entry, with the previous and next |
| `/changelog/feed.xml` | an Atom feed of the newest 20 (`?category=` for one category) |
| `/changelog/feed.json` | a JSON Feed of the same |
| `/changelog/sitemap.xml` | every entry, for search engines |
| `/changelog/preview/:token` | a draft or scheduled entry, from the admin's preview link |

With the `:reactions` and `:subscriptions` features, the page also has the
reactions of each entry and a form to get the news by email (see
[Features](features.md)).

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

Your layout then gets:

* `@inner_content` - the page;
* `@conn` and `@page_title`;
* `@locale` - the page's language, for `<html lang>`;
* `@description` and `@canonical` - the page's description and address;
* `@feed` - the path of the Atom feed;
* `@meta` - the tags of shared links and search engines, as maps;
* `@head` - the same tags rendered, with the canonical link, the
  languages, an entry's JSON-LD and the feed's link
  (`Tayori.Page.head/1`).

So a layout for the page is your own document with `@head` in it, and
the class `tayori-page` on the element that holds the page, which gives
it Tayori's type and colours:

```heex
<!DOCTYPE html>
<html lang={@locale}>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{@page_title} · MyApp</title>
    {@head}
    <link rel="stylesheet" href={~p"/assets/css/app.css"} />
  </head>
  <body>
    <MyAppWeb.Layouts.header />
    <main class="tayori-page">{@inner_content}</main>
    <MyAppWeb.Layouts.footer />
  </body>
</html>
```

Your style sheet then imports `tayori.css` and `kotoba.css`, and sets
the `--tayori-*` properties to your own tokens (see
[Theming](theming.md)):

```css
@import "../../deps/kotoba/priv/static/kotoba.css";
@import "../../deps/tayori/priv/static/tayori.css";

.tayori-page {
  --tayori-font: var(--font-body);
  --tayori-title-font: var(--font-display);
  --tayori-accent: var(--color-accent);
}
```

## Search and filters

The page has a chip for each of your categories, in their order, and a
search of the titles, summaries and text (`?category=new&q=export`, every
word). Pinned entries come first on the first page. A filtered or
searched page is not indexed.

## Shared links and search engines

Each page has its description, its canonical address, the address of each
of its languages (`hreflang`), Open Graph and Twitter cards with the
entry's cover (else the page's `:image`), and JSON-LD of the entry as an
article. An entry's SEO title and description, set in the admin, replace
its title and summary there.

## Previews

The admin's "Copy a preview link" gives an address that shows the last
saved version of a draft or a scheduled entry to whoever has it, for a
week. It is signed with the app's secret, says the entry is not
published, and is not indexed.

## Options

* `:title` - the title of the page and the feeds ("What's new", in the
  reader's language).
* `:description` - a line under the title, and the description of the
  page for search engines and shared links.
* `:eyebrow` - a short line above the title: your app's name, say.

  These three are a string, or a map of a locale to a string, for a page
  in more than one language:

  ```elixir
  tayori_page "/changelog",
    title: %{"en" => "Changelog", "pt-PT" => "Novidades"},
    description: %{"en" => "What we ship.", "pt-PT" => "O que fazemos."}
  ```

  The page takes the reader's locale's, else one of the same language,
  else that of the first of your locales the map has.
* `:image` - the picture of a shared link to the page, and of an entry
  with no cover (an absolute URL).
* `:resolver` - your `Tayori.Resolver`, for the entries of a reader.
* `:theme` - `:tayori` or `:sumi`, for Tayori's own document.
* `:layout` - your root layout, `{module, function}`.
* `:limit` - the entries of a page (20).
* `:url` - your app's address (`"https://example.com"`), for the links of
  the feeds, when the conn does not have it (behind a proxy).
* `:csp_nonce_assign_key` - the key of the nonce of your Content Security
  Policy in `conn.assigns`, for the style sheet.

The feeds are cached for five minutes (`cache-control: public,
max-age=300`).
