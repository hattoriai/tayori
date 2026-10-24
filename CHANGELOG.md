# Changelog

All notable changes to Tayori are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Tayori follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## [0.4.0] - 2026-10-24

### Added

- Modules: `:modules` in `Tayori.Config`, `[:changelog]` by default, so
  that an app is as it was. `[:changelog, :campaigns]` runs both,
  `[:campaigns]` only the letters. A module that is off has no admin
  page, no route that answers, no MCP tool, no process and no job. The
  `:features` are the changelog's.
- The campaigns: letters to each person, by what they did, at their own
  time (`Tayori.Campaigns`, and the [Campaigns](guides/campaigns.md)
  guide).
  - The audience (`Tayori.Audience`): the app's people as an Ecto query
    on its own schemas, the facts conditions test as `dynamic`
    expressions, their consent (`can_email?/2`). Nothing is copied.
  - Conditions (`Tayori.Conditions`) on attributes, events and segments,
    compiled to SQL for PostgreSQL and SQLite, checked and said in
    words; segments, saved conditions.
  - Events: `Tayori.track/3`, kept 400 days.
  - Sequences: a trigger event or by hand, who may enter, steps at waits
    after entry with a skip, a goal, a gap between letters, a number of
    days; start, pause, resume, archive. Broadcasts: one letter to a
    segment, now or at a time.
  - Letters in each language with merge tags and fallbacks, a button, a
    preheader, the sender's name and reply-to; a link to unsubscribe
    and one-click unsubscribing; suppressions by purpose.
  - The mount `tayori_mail`: the page to unsubscribe and the mail
    providers' webhooks: Resend, Postmark, or an adapter of
    `Tayori.Campaigns.Provider`.
  - With Oban, a job for each person's next step, each broadcast and
    each letter; without, the scheduler.
  - The admin: Campaigns and Audience, a condition builder with live
    counts, the editor of a sequence's steps, the preview of a letter
    for a person, a test letter, results by step.
  - MCP: the campaigns' tools, in three scopes
    (`tayori:campaigns:read`, `:write`, `:send`): read the audience, try
    and save segments, write campaigns and their letters, preview and
    test, start, take people in (`enroll_people`) and send only when
    asked, at the count expected.
  - `Tayori.Test`: `track!/3`, `run_campaigns!/2`, `post_webhook!/2`.
- `Tayori.Migrations` version 2: the campaigns' tables, made whatever
  the modules. `mix tayori.gen.migration` writes the upgrade.

### Changed

- Requires [Kotoba](https://hexdocs.pm/kotoba) 0.8 and
  [Storehouse](https://hexdocs.pm/storehouse) 0.2: the images of the
  editor, the covers and the agents' uploads are kept with Storehouse, in
  the app's store (`config :storehouse, adapter: ...`). Each file is
  checked by its bytes and stored under a new key, as before.
- `:storage` of `tayori_admin` and of the `:mcp` config is a
  `Storehouse.Adapter` (Storehouse's own config when not given).

### Upgrading

Nothing to change at once. An app that keeps its uploads with Kotoba's
own store (`config :kotoba, Kotoba.Storage.Local, ...` and
`plug Kotoba.Storage.Local.Plug`) works as it did: the same files, the
same URLs, with deprecation warnings. Kotoba 1.0 removes that store, so
move to Storehouse before then:

1. Replace `config :kotoba, Kotoba.Storage.Local, ...` with
   `config :storehouse, Storehouse.Local, ...`, with the same `root`, and
   `url_prefix: "/uploads/kotoba"` (Kotoba's old default, unless you gave
   another), so that the images in your entries stay where they were.
2. Replace `plug Kotoba.Storage.Local.Plug` with
   `plug Storehouse.Local.Plug`.
3. A store of your own, given as `:storage` or in
   `config :kotoba, storage: ...`: `@behaviour Storehouse.Adapter` in
   place of `@behaviour Kotoba.Storage` (the callbacks are the same), and
   `config :storehouse, adapter: MyApp.Store`.

The warnings stop when the steps are done. Kotoba's
[Upgrading](https://hexdocs.pm/kotoba/upgrading.html) guide, "To Kotoba
0.8", has the same steps.

## [0.3.0] - 2026-10-21

### Added

- `<tayori-news button="none">`: no button of the element's own, for a
  page that opens the news from its own control (a menu item, a dot
  instead of a count) with `open(control)` or `toggle(control)`; the
  control gets the focus back when the panel closes. The element sends
  `tayori:unread` with the count whenever it changes, with a button or
  without.

### Changed

- The app names the languages of its entries, in `:locales`:
  `[{"en", "English"}, {"pt-PT", "Português"}]`. Tayori no longer keeps
  names of its own, as an app can write its news in any language: a tag
  without a name shows as its tag in the admin and in the readers'
  language links, where 0.2.0 named some (`pt-PT` was "Português
  (Portugal)", `es-ES` "Español"). Tags alone are still accepted.
  `Tayori.Locales.name/2` takes the config.

## [0.2.0] - 2026-10-21

### Changed

- With Oban (the `:oban` option), nothing looks at the database on a
  timer: each write of an entry gives Oban its announcement, a job at
  its publication time (one for each entry, moved with it), in the
  write's transaction when Oban runs on Tayori's repo, and a
  scheduled digest or period email is a job at its next time, which gives
  Oban the one after. At boot, a task gives Oban the announcements of
  entries that have no job, the schedules and the reading of the
  inbox's sources. Without Oban, the scheduler is as it was. Start
  Tayori after Oban.

## [0.1.0] - 2026-10-20

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
- `scheduler: false`, for an app's tests: no scheduler queries the repo
  outside a test's sandbox, and `Tayori.Test.announce!/0` announces.
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
  (`c:Tayori.Resolver.resolve_locale/1`) before the browser's.
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
