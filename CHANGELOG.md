# Changelog

All notable changes to Tayori are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Tayori follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The `:oban` option: with the app's Oban, the emails, webhooks and
  notifier call of a publication are jobs of `Tayori.Worker`, one each,
  retried with Oban's backoff through deploys and crashes, in the
  `:default` queue or another (`oban: [name: Oban, queue: :news]`).
  Without it, they are sent from tasks, as `Tayori.Jobs` explains.
  `mix tayori.install` sets it when the app has Oban.
- `Tayori.Test.announce!/0` announces the entries whose time has come, in
  the test's process.

### Changed

- Tayori is mounted with [PhoenixMountable](https://hexdocs.pm/phoenix_mountable):
  the admin's script and style sheet are served under the mount as
  `js-<hash>` and `css-<hash>`, and every mount takes PhoenixMountable's
  options (`:as`, `:on_mount`, `:csp_nonce_assign_key`, ...).
- The tables are versioned migrations, `Tayori.Migrations`, in place of
  `Tayori.Migration`: `Tayori.Migrations.up(version: 1)`. A forgotten
  upgrade says so at boot.
- The installer runs on Igniter (`mix igniter.install tayori`): it also
  mounts the admin and the public page, and starts Tayori in the
  application. `--dry-run` is Igniter's own.

## [0.1.0]

The first release: the changelog.

### Added

- Entries in the app's database, on PostgreSQL and SQLite
  (`Tayori.Migration`, `mix tayori.gen.migration`): a title, a summary and
  a Kotoba body in each language, categories, segments, a slug, and a
  publication time.
- The admin (`tayori_admin`), mounted behind the app's own pipeline, with
  its own layout, script and styles, in Tayori's theme or Sumi's: the
  entries, the editor, scheduling in the admin's time zone, and the
  settings. `Tayori.Resolver` says who the admin is and what they may do.
- Readers (`Tayori.Reader`) from the app's own users: segments, a
  language, what each has not seen.
- The news in LiveViews: `Tayori.Live` and `Tayori.Components`, live over
  PubSub and across tabs.
- The news as JSON (`tayori_api`) and `<tayori-news>`, for a frontend that
  Phoenix does not render.
- The public page (`tayori_page`), each entry's page, and Atom and JSON
  feeds.
- Each entry announced once when it is published, to the open pages and
  to the app's `Tayori.Notifier`.
- Writing with AI, with the app's own key, kept encrypted by the app's
  Cloak vault (`:vault`) or with its `secret_key_base`: drafts,
  translations, and rewrites of a passage, as Kotoba suggestions.
- The words around the news in eight languages (`Tayori.Messages`).
- `Tayori.Test`, `mix tayori.install`, and the themes `tayori.css` and
  `tayori-sumi.css`.
