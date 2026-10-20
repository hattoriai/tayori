# Automation

The changes that ship come to Tayori's inbox (`Tayori.Inbox`) from the
app's own sources, and from outside it: CI sends them, GitHub tells of
them, the app's code adds them. A digest then makes an entry of them
(`Tayori.Digest`). Each change is the source's and its ref's: one sent
twice is added once.

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
