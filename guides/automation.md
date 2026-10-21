# Automation

What ships is already written down somewhere: a `CHANGELOG.md`, a folder
of fragments, the pull requests merged, the releases published. Tayori
reads it, keeps it in an inbox, and makes entries of it, plain or
written by the model, as often as you like. The readers hear of them as
often as they like.

```
sources ──► inbox ──► digest ──► entry ──► page, panel, feeds
CI, GitHub,  the changes  plain or   a draft, or   emails, each one
your code    waiting      by the AI  published     or by period
```

Each step is yours to set, and each can be done by hand instead:

* **The inbox** (`Tayori.Inbox`) takes the changes: from the sources of
  the `:inbox` config when the app starts, from CI, from GitHub's
  webhook, from your code, and from an agent over MCP.
* **A digest** (`Tayori.Digest`) makes an entry of the changes waiting:
  when you ask, each time changes come, or on a schedule.
* **The entry** is a draft for you to read, unless you say to publish
  it.
* **The emails** go for each entry, or once a week or a month.

Nothing of it runs until you set it up. Without the options below, the
inbox is empty and the news is written by hand, as before.

## The inbox

A change is what shipped, in a line or a paragraph: a title, a body in
Markdown, and what it is (`Tayori.Change`). It has a source (`"changelog"`,
`"github"`, `"api"`...) and a ref, its name in that source; the same
source and ref is the same change, so reading a source again adds only
what is new.

A change is for the public, or for the team (`audience: "internal"`).
The team's never go into an entry: they are in the inbox so that you see
everything that shipped, and decide.

### The app's sources

```elixir
{Tayori,
 repo: MyApp.Repo,
 pubsub: MyApp.PubSub,
 inbox: [
   sources: [
     {Tayori.Sources.Changelog, path: {:my_app, "priv/CHANGELOG.md"}},
     {Tayori.Sources.Fragments, path: {:my_app, "priv/news"}}
   ],
   kinds: %{"added" => "new", "changed" => "improved", "fixed" => "fixed"}
 ]}
```

The sources are read when the app starts, which is when a deploy brings
new code (`ingest_on_start: false` to read them only when asked). A
`{otp_app, path}` is in the app's `priv`, so it is in the release.

`Tayori.Sources.Changelog` reads a [Keep a
Changelog](https://keepachangelog.com) file: each item of each release
is a change, with the release's version and date and the section's kind
(`added`, `fixed`...). `[Unreleased]` is left until it is released
(`sections: :all` to take it). An item can say more about itself in a
comment at its end:

```markdown
### Added

- Exports in two clicks: zip a project with its files. <!-- highlight; category: new -->
- The job queue runs on the new cluster. <!-- audience: internal -->
```

`Tayori.Sources.Fragments` reads a folder of Markdown files, one change
each, as [Changesets](https://github.com/changesets/changesets) and
[towncrier](https://towncrier.readthedocs.io) write them. The
frontmatter says what the change is; the rest is its body, and its first
heading or sentence its title when the frontmatter has none:

```markdown
---
title: Exports in two clicks
kind: added
highlight: true
segments: [plan:pro]
---

Zip a whole project, with its files, and get a link by email.
```

`towncrier`'s `1234.feature.md` has the kind `feature`. A key Tayori
does not know is kept in the change's `meta`. A `README.md` in the
folder is not a change.

A source of your own is a module of `Tayori.Source`, with `changes/1`.

### Kinds and categories

A source names kinds (`added`, `fix`, `feature`); your entries have
categories. `:kinds` maps one to the other. A change with no category
of its own takes its kind's, or the category whose key is its kind, or
none.

`:audience` is the audience of a change that does not say: `"public"`,
or `"internal"` for an app whose sources say everything, where the
admin picks what the public hears.

### In the admin

The inbox has its page in the admin, with a count of the new changes in
the bar. The changes are there by state (new, drafted, put aside), by
source and audience. Pick some, and **Draft an entry** makes a digest of
them and opens it in the editor; **Draft from all new** takes every new
public change. A change can be edited before (its title, category,
audience, whether to lead with it), put aside, or brought back.

Settings → Automation shows the sources, the digest's schedule, and
makes the token for CI and the secret for GitHub. The editor shows the
changes an entry was made from.

## From CI

### Mount the API for machines

CI and GitHub have no session of your app. Mount the JSON API a second
time, behind a pipeline with no session and no CSRF protection, as the
`:embed` feature does:

```elixir
pipeline :machines do
  plug :accepts, ["json"]
end

scope "/api/machines" do
  pipe_through :machines
  tayori_api "/news", resolver: MyAppWeb.TayoriResolver, as: :tayori_machines
end
```

Two of its routes are for machines, and read no session:

| | |
| --- | --- |
| `POST /api/machines/news/changes` | changes, with the ingest token |
| `POST /api/machines/news/hooks/github` | GitHub's webhook, signed with its secret |

The mount with your session has them too, but there a `POST` needs the
CSRF token of the session, as every `POST` behind
`protect_from_forgery` does: CI has none. They do not need the `:embed`
feature, and answer no CORS: a browser has no business with them.

### The ingest token

The admin makes the token in Settings, and sees it once. Tayori keeps
only its SHA-256. Making another revokes the one before. Keep it in your
CI's secrets, as `TAYORI_INGEST_TOKEN`. While no token was made, the
route answers 404.

### `mix tayori.ingest`

In CI, `mix tayori.ingest` reads your changelog and your fragments, and
sends their changes to the app. It does not start the app, and needs no
database. It needs the `:req` dependency.

```sh
mix tayori.ingest \
  --url https://myapp.com/api/machines/news \
  --changelog CHANGELOG.md \
  --fragments priv/news
```

The token is `--token`, or the `TAYORI_INGEST_TOKEN` environment
variable. `--source` names the source of every change (`changelog` and
`fragments` by default, as the sources of the `:inbox` config name
theirs, so a change read by both is one). It sends 500 changes a request
at most, prints how many were new, and fails when the app refuses a
request or a change.

A step of GitHub Actions, after the deploy:

```yaml
- name: Send the changes to Tayori
  run: mix tayori.ingest --url https://myapp.com/api/machines/news --changelog CHANGELOG.md
  env:
    TAYORI_INGEST_TOKEN: ${{ secrets.TAYORI_INGEST_TOKEN }}
```

### Any other client

The route takes JSON, with the token in the `authorization` header:

```sh
curl -X POST https://myapp.com/api/machines/news/changes \
  -H "authorization: Bearer $TAYORI_INGEST_TOKEN" \
  -H "content-type: application/json" \
  -d '{"changes": [{"ref": "pr-1234", "title": "Exports in two clicks", "kind": "added"}]}'
```

A change is the attributes of `Tayori.Change`: `ref` and `title` are
needed; `body` (Markdown), `kind`, `category`, `audience`, `segments`,
`highlight`, `version`, `url`, `author`, `occurred_at` and `meta` are
not. Its `source` is `"api"` unless it says. `{"change": {...}}` sends
one.

```json
{"added": 1, "existing": 0, "errors": [{"index": 2, "errors": {"title": ["can't be blank"]}}]}
```

| Status | |
| --- | --- |
| 201 | at least one change was new |
| 200 | none was new |
| 422 | none could be added |
| 400 | the body is not JSON, or has no `changes` |
| 401 | no token, or another |
| 404 | no token was ever made, or it was revoked |
| 413 | more than 500 changes, or a body over a megabyte |

`errors` gives the index of each change that could not be added, with
what was wrong, by field.

## From GitHub

A webhook of your repository tells Tayori of each pull request merged
and each release published.

### The secret

The admin makes the webhook's secret in Settings, and sees it once, to
paste into GitHub. Tayori keeps it encrypted, as the AI key: it needs the
`:vault` or the `:secret_key_base` option. While there is none, the
route answers 404.

### The raw body

GitHub signs the body as it sent it, and Tayori checks the signature
against it. A Phoenix endpoint parses JSON before the router, so the body
is gone when the route is reached. Give your endpoint's `Plug.Parsers`
Tayori's body reader, which keeps a copy of the bodies GitHub signs, and
only those:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  body_reader: {Tayori.GitHub, :read_body, []},
  json_decoder: Phoenix.json_library()
```

Without it, each delivery is answered with a 500, and the log says why.

### Add the webhook

In the repository on GitHub, Settings → Webhooks → Add webhook:

* **Payload URL** - the route of the API for machines:
  `https://myapp.com/api/machines/news/hooks/github`.
* **Content type** - `application/json`.
* **Secret** - the secret made in Tayori's Settings.
* **Which events** - Let me select individual events: **Pull requests**
  and **Releases**, and nothing else.

GitHub sends a `ping` first, which Tayori answers with a 200. Each
delivery is in the webhook's Recent Deliveries, with Tayori's answer: a
200 with the counts, a 202 for an event Tayori does not read, a 401 for
a wrong signature.

### What becomes a change

A pull request merged into the default branch is one change: the pull
request's title, and the section of its description headed
`## Changelog` or `## Release notes`, when there is one. Tayori never
takes the rest of the description: it is often for the team. A template
helps:

```markdown
## Changelog

<!-- What changes for the people who use the app, in their words. Leave empty if nothing. -->
```

A pull request closed without a merge is nothing; so is one merged into
another branch.

Its labels say more, with a prefix (`changelog:` by default):

| Label | |
| --- | --- |
| `changelog:skip` | no change |
| `changelog:internal` | for the team only, never in an entry |
| `changelog:public` | for everyone |
| `changelog:highlight` | worth leading with |
| `changelog:category:<key>` | its category |
| `changelog:segment:<segment>` | the readers it is for |
| `changelog:<kind>` | its kind, such as `changelog:added` |

```elixir
inbox: [github: [label_prefix: "news:", only_labeled: true]]
```

With `only_labeled: true`, a pull request with none of these labels is
nothing.

A release published is a change for each item of its notes, read as a
changelog's: an item under `### Added` has the kind `added`, an item
with no section has none. GitHub's own notes work too: the credits after
each item and the list of new contributors are left out. Notes with no
item are one change, titled with the release's name. A prerelease is
nothing until it is released.

Pull requests and releases are both changes of the source `"github"`.
If you take both, label the pull requests `changelog:skip`, or take one.

## From your code

`Tayori.Inbox.add/2` adds a change from anywhere in the app: a job that
finishes a migration, a feature flag turned on for everyone.

```elixir
Tayori.Inbox.add(
  %{ref: "flag:timeline", title: "Timeline view", kind: "added", highlight: true},
  source: "flags"
)
```

`Tayori.Inbox.add_many/2` adds several, and counts them as the route
does. A change added again, with the same source and ref, changes
nothing.

`Tayori.Inbox.ingest/0` reads the sources of the `:inbox` config again;
the app reads them when it starts. In a deploy with Mix, `mix
tayori.ingest` does it and prints each source's count. In a release, ask
the running app:

```sh
bin/my_app rpc "IO.inspect(Tayori.Inbox.ingest())"
```

Not `bin/my_app eval`: it runs in a new node that does not start the
app, so Tayori has no repo there.

## Digests

A digest makes an entry of the changes waiting in the inbox: the new
ones, for the public. A change for the team (`audience: "internal"`), or
one you put aside, never goes into one. The changes it takes are then
`"drafted"`, with the entry's id, and no digest takes them again.

```elixir
{:ok, entry} = Tayori.Digest.run()
{:ok, entry} = Tayori.Digest.run(ids: ["0193…", "0194…"])
{:error, :nothing} = Tayori.Digest.run()
```

The admin's inbox and the MCP tools call the same function.

### Plain, or written by the model

Without AI, the digest is plain. One change makes an entry of its own:
its title and its body. Several make an entry titled with the day, with
a section for each category, the highlighted changes first.

With AI set up in the admin's Settings (see [Writing with AI](ai.md)),
the model writes the entry: a title, a summary and a body in Markdown,
in your first language and in the voice of "About your product". It is
told to:

* put together the changes that belong together;
* lead with the highlights;
* write for the people who use the product, not its developers: what
  they can do now, without the names in the code or the numbers of
  tickets and pull requests;
* say only what the changes say.

The model gets each change's title, body, category and whether it is a
highlight. It never gets a change's ref, link or author, nor a change
for the team. The entry's categories and segments are the changes', not
the model's.

To have the other languages too, translated by the model:

```elixir
digest: [translate: true]
```

A language the model fails to translate is left for you to write.

When the model fails, or answers in another form, the digest is plain,
and a warning is logged: a digest never waits on the model. To make a
plain one with AI set up, `Tayori.Digest.run(ai: false)`.

### Review

A digest is a draft. Read it in the admin, change what it says, and
publish it.

When you trust what comes out, publish at once:

```elixir
digest: [publish: :publish]
```

The entry is then published as it is written, and announced as any
other: on the page, in the app, to webhooks and subscribers when it says
so. Keep `:draft` while you try the model on your changes.

## Cadence

When a digest runs is the `:every` of the `:digest` config:

* `:manual` - when you ask, in the admin or with `Tayori.Digest.run/1`.
  The default.
* `:ingest` - each time changes come: after a deploy reads the sources,
  and after the ingest endpoint or GitHub adds some.
* `{:weekly, day}` - each week, on a day (`:monday` ... `:sunday`;
  `:weekly` alone is Monday).
* `:monthly` - on the first day of each month.
* `{:days, n}` - n days after the day of the last scheduled digest.

A scheduled digest runs at `:at`, a time of day in UTC (`~T[09:00:00]`).
With fewer changes waiting than `:minimum` (`1`), it makes nothing, and
the changes wait for the next time. The time is kept all the same, so a
weekly digest with too little to say waits a week, not a minute.

With the `:oban` option, the schedule is a job at its next time, which
gives Oban the one after; without, Tayori's scheduler looks every
minute, on one node of the cluster. A schedule begins when Tayori first
starts with it: a weekly digest added on a Wednesday first runs the next
Monday, not at once. A time missed while the app was down runs once,
when it starts again.

With the `:oban` option, the digest is a job of `Tayori.Worker`. Asked
for again while one waits, it is the same job, which takes the changes
that came meanwhile. Without Oban, it runs in a task.

`Tayori.Digest.status/0` says where it stands: the schedule, the next
time, the last, and how many changes wait.

### An app that deploys on each merge

Each deploy reads the sources, and each merge brings a change or two.
An entry for each would be too many: gather them for a week, and read
the draft before it goes out.

```elixir
digest: [every: {:weekly, :tuesday}, at: ~T[14:00:00], minimum: 3]
```

A quiet week with fewer than three changes waits for the next.

### Release notes with each version

An app that ships versions makes an entry of each one, as it ships:

```elixir
digest: [every: :ingest]
```

Code that adds changes in batches tells the digest how many were new:

```elixir
%{added: added} = Tayori.Inbox.add_many(changes, source: "release")
Tayori.Digest.after_ingest(added)
```

### A weekly changelog

```elixir
digest: [every: {:weekly, :friday}, at: ~T[10:00:00], publish: :publish]
```

Published each Friday as the model writes it, when you trust it with
your changes.

### A monthly changelog for customers

Customers read a month at a time. The model groups the month's changes
and leads with what matters:

```elixir
digest: [every: :monthly, at: ~T[08:00:00], minimum: 5, translate: true]
```

The draft waits for you on the first of the month, in every language.

### By hand

```elixir
digest: [every: :manual]
```

The inbox fills; you choose the changes and make the entry in the admin,
when there is something to say.

## Emails

With the `:subscriptions` feature, an entry you choose to email goes to
the subscribers. When it goes is the `:emails` config.

### Each entry

```elixir
emails: [every: :each]
```

The default: an email for each entry, when it is published, with the
whole entry.

### A digest email

```elixir
emails: [every: {:weekly, :monday}, at: ~T[08:00:00]]
```

The entries to email wait. On the day, at the time (UTC), one email
lists those published since the last: each one's title, its summary (or
the first words of its body) and a link to the public page, the newest
first. A period of one entry sends that entry, as it would
alone. A period with none sends nothing.

`:every` is `{:weekly, day}` (`:weekly` is Monday), `:monthly` (the first
day of the month), or `{:days, n}`. Each entry is sent once: it is
marked `emailed_at` when the email of its period goes out. An entry for
some readers (with segments) is never emailed, as with each entry.

The email comes in the subscriber's language, with the same look as an
entry's, and a link and a `List-Unsubscribe` header to leave. With Oban,
each subscriber's email is a job; without, they are sent from a task,
one after the other.

### Fewer emails

Publishing and emailing are now apart. You can publish as often as
things ship, and the page, the panel and the feeds keep up, while the
subscribers hear once a week or once a month. Choose what to email
entry by entry: the emails carry what readers would miss, not each fix.

For an app that publishes a digest each week, `emails: [every: :each]`
is already one email a week. For one that publishes each day, or on each
deploy, a weekly or monthly email keeps the inbox of your readers quiet.

Say so on the page: the words of the subscribe form ("The news, by
email") are yours to change, as `subscribeText` (see `Tayori.Messages`):
"Once a month, what changed".

## From an agent

The MCP server (`Tayori.MCP`) gives an agent the same steps: it adds
changes, drafts an entry from the inbox, writes and edits it, puts
screenshots in it, and publishes it when asked. See [MCP](mcp.md).
