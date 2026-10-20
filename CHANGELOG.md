# Changelog

All notable changes to Tayori are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Tayori follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - unreleased

The first release.

### Added

- Entries in the app's database, on PostgreSQL and SQLite, in versioned
  migrations (`Tayori.Migrations`, `mix tayori.gen.migration`; a
  forgotten version says so at boot): a title, a summary and a Kotoba
  body in each language, an optional cover apart from the body,
  categories, segments, a slug, a pin and a publication time.
- Categories, managed in the admin: names in each language, a colour, an
  order.
- The admin (`tayori_admin`), mounted with
  [PhoenixMountable](https://hexdocs.pm/phoenix_mountable) behind the
  app's own pipeline, with its own layout, script and styles, in Tayori's
  theme or Sumi's, light or dark: the entries, with tabs, counts, a
  search and each entry's views and reactions; the editor, with a
  preview as the page, the panel or the announcement, and the
  publication, cover, details, audience, announcement, email and
  statistics beside it; scheduling in the admin's time zone; the
  categories; the settings. `Tayori.Resolver` says who the admin is and
  what they may do.
- Readers (`Tayori.Reader`) from the app's own users: segments, a
  language, what each has not seen.
- The news in LiveViews: `Tayori.Live` and `Tayori.Components`, a button
  and a panel with category filters, cards, and each entry whole inside
  it, live over PubSub and across tabs.
- The news for any frontend: a JSON API (`tayori_api`) with entries,
  categories, reactions and the announcement, and `<tayori-news>`, the
  LiveView panel as a web component: the API renders the same
  `Tayori.Components` for it (its `/ui` routes), and the element answers
  their clicks and keys as LiveView would.
- The public page (`tayori_page`): filters, a search, pinned entries
  first, each entry's page with the previous and next, Atom and JSON
  feeds (of all or one category), an SEO title and description of each
  entry, Open Graph, Twitter cards, `hreflang`, JSON-LD and a sitemap,
  and preview links of drafts and scheduled entries, signed, for a week.
  The admin and the API find it in the same router by themselves. In
  the app's own layout (`:layout`), which gets the page's language,
  description, canonical address and its tags rendered
  (`Tayori.Page.head/1`); its title, description and eyebrow by locale;
  for a visitor, the app's own choice of language
  (`Tayori.Resolver.resolve_locale/1`) before the browser's.
- Opt-in features (`features: [...]` of `Tayori.Config`), each with no
  route, page or process when it is off:
  - `:reactions`: emoji reactions, one for each reader and emoji;
  - `:announcements`: an entry as a popup, a toast or a banner in the
    app, with a button, until a date, dismissed on every device;
  - `:analytics`: the views of each entry by day and by where it was
    read, with no address, device or cookie kept;
  - `:subscriptions`: readers subscribe by email on the public page,
    with double opt-in and one-click unsubscribing, through the app's
    Swoosh mailer;
  - `:webhooks`: signed webhooks, Slack and Discord, told of each entry,
    their addresses and secrets kept encrypted;
  - `:embed`: the news on another origin, with CORS for the app's sites
    and a reader token the app signs (`Tayori.Embed.token/1`).
- Each entry announced once when it is published, to the open pages,
  the subscribers, the webhooks and the app's `Tayori.Notifier`: as jobs
  of the app's Oban (`:oban`), retried through deploys, or from tasks
  (`Tayori.Jobs`).
- Writing with AI, with the app's own key, kept encrypted by the app's
  Cloak vault (`:vault`) or with its `secret_key_base`: drafts,
  translations, and rewrites of a passage, as Kotoba suggestions.
- Automation: an inbox of what shipped (`Tayori.Inbox`), from a Keep a
  Changelog file and a folder of fragments, Changesets' and towncrier's
  among them (`Tayori.Sources`), read at each deploy; from CI, with a
  token (`POST <api>/changes`, `mix tayori.ingest`); from GitHub's
  webhook, signed, for merged pull requests and published releases
  (`Tayori.GitHub`); and from the app's code. Changes for the team stay
  out of the news. Digests make entries of it, plain or written by the
  model, with translations, as drafts or published, when the admin asks,
  as changes come, or each week, month or n days (`Tayori.Digest`). The
  emails go for each entry, or as one email of a period (`:emails`). The
  admin's inbox, the Automation card of Settings, and the changes behind
  an entry in the editor.
- An MCP server (`Tayori.MCP`), mounted with Sake in the app's own,
  beside its other libraries': the news, the inbox and the categories to
  read; changes to add, entries to draft, write, publish and unpublish,
  under the admin's own access; screenshots from a browser agent,
  uploaded once with a URL that lasts ten minutes, as figures in an
  entry.
- The words around the news in eight languages (`Tayori.Messages`).
- `Tayori.Test`, the installer (`mix igniter.install tayori`, which
  mounts the admin and the public page and starts Tayori, with the app's
  Oban when it has one), and the themes `tayori.css` and
  `tayori-sumi.css`, with icons from Lucide (see `NOTICE`).
