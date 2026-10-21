# MCP

Tayori ships an [MCP](https://modelcontextprotocol.io) server,
`Tayori.MCP`, built on [Sake](https://hexdocs.pm/sake). Connect Claude
Code (or Claude Desktop, or an agent of your own) to your app, and it
writes the news with you: it reads what shipped in the inbox, adds what is
missing, drafts an entry, writes it in each of your languages with its
screenshots, and publishes it when you say so. With the campaigns
(`Tayori.Campaigns`), it writes your letters with you too: it reads your
audience, tries and saves segments, makes sequences and broadcasts,
writes their letters, previews them and sends you a test, and starts or
sends them when you say so. It acts as one of your admins, and your
resolver decides what it may do, as in the admin.

No key of a model is involved: the MCP client is the model, and Tayori
gives it tools. [Writing with AI](ai.md) in the admin is separate.

## What the client can do

| Tool | Scope | What it does |
|---|---|---|
| `list_entries` | `tayori:read` | The entries, by status (`draft`, `scheduled`, `published`, `all`), with a search and a `limit` (50, at most 200) |
| `get_entry` | `tayori:read` | An entry whole, by its id or slug: status, categories, segments, its URL, each language's title, summary and body in Markdown, the languages it is missing |
| `list_changes` | `tayori:read` | The inbox, by `state` (`new`, `drafted`, `hidden`), `source`, `audience` and `limit` |
| `list_categories` | `tayori:read` | The categories, in their order, by key |
| `add_change` | `tayori:write` | A change to the inbox, from `"mcp"`: `title`, and `body`, `kind`, `category`, `audience`, `segments`, `highlight`, `version`, `url`, `ref` |
| `hide_change` | `tayori:write` | Puts a change aside |
| `draft_entry` | `tayori:write` | A draft of the inbox's new public changes, all or `change_ids` (`Tayori.Digest`) |
| `create_entry` | `tayori:write` | A draft: `title`, `summary`, `body` (Markdown), `locale`, `categories`, `segments` |
| `update_entry` | `tayori:write` | Any of those on an entry, in one language (a new one is added); never its status |
| `publish_entry` | `tayori:write` | Publishes an entry, now or `at` a time (ISO 8601), and gives its URL |
| `unpublish_entry` | `tayori:write` | Makes an entry a draft again |
| `request_upload` | `tayori:write` | An address for one image, and the curl command that sends it (below) |
| `upload_image` | `tayori:write` | A small image (1 MB) in the call, as base64 |

With the `:campaigns` module on (`modules: [:changelog, :campaigns]`):

| Tool | Scope | What it does |
|---|---|---|
| `list_audience` | `tayori:campaigns:read` | Your audience's attributes (type, operators, an enum's values), its events, the segments with their counts, and the limits of a condition |
| `preview_segment` | `tayori:campaigns:read` | A `condition` or a `segment_id`: how many people match it now, the first 10, and the sentence; a wrong condition gets its errors |
| `list_campaigns` | `tayori:campaigns:read` | The campaigns, the newest first, by `kind`, with the `archived` ones or not |
| `get_campaign` | `tayori:campaigns:read` | A campaign whole: its settings, its audience's count, its steps with their letters in Markdown, its merge tags, what keeps it from starting (`problems`), its results |
| `preview_letter` | `tayori:campaigns:read` | A step's letter as a person gets it: subject, preheader, text, and the merge tags they lack. Nothing is sent |
| `save_segment` | `tayori:campaigns:write` | A new segment (`name`, `condition`, `description`), or a change of one by its `id` |
| `create_campaign` | `tayori:campaigns:write` | A draft: `name`, `kind`, `purpose`, `trigger_event`, `audience`, `goal`, `min_gap_hours`, `max_days`, `from_name`, `reply_to` |
| `update_campaign` | `tayori:campaigns:write` | Any of those settings but the kind; `{}` takes a goal off, an empty `trigger_event` makes a sequence by hand, `max_days: 0` takes the end off |
| `add_step` | `tayori:campaigns:write` | A step of a sequence, `after_days`, `after_hours`, `after_minutes` from entry, with a `skip_if` and a letter in Markdown |
| `update_step` | `tayori:campaigns:write` | A step's time and `skip_if`, and its letter in one `locale` (a new one is added); a broadcast's letter too |
| `remove_step` | `tayori:campaigns:write` | Removes a step of a sequence and its letters |
| `send_test_letter` | `tayori:campaigns:write` | A step's letter to one address (`to`, else the writer's), "[Test] " before its subject, with a person's merge tags |
| `pause_campaign` | `tayori:campaigns:write` | Pauses an active sequence, or takes a scheduled broadcast back to a draft |
| `start_campaign` | `tayori:campaigns:send` | Starts a sequence, a draft, or resumes a paused one |
| `send_broadcast` | `tayori:campaigns:send` | Sends a broadcast now, or `at` a time; `expected_recipients` must be the audience's count now |

The tools of a module that is off are not listed. A condition is a JSON
object, as `Tayori.Conditions` takes it:
`{"attribute": "plan", "op": "in", "value": ["pro"]}`,
`{"event": "signed_up", "op": "happened", "within_days": 30}`,
`{"segment": "<id>", "op": "in"}`, in `{"all": [...]}`, `{"any": [...]}`
and `{"not": ...}`. Each tool that takes one checks it against your
audience, and answers the errors of `Tayori.Conditions.validate/3` and the
sentence of `Tayori.Conditions.describe/3` ("Plan is Pro"). The letters
are written in Markdown, as the entries are, with their merge tags
(`{{first_name|there}}`).

A tool answers JSON, which the client reads as text and as structured
content. An error is a tool error in words the model can act on: "No
entry with the id or slug "exports".", "Unknown categories: News. The
categories are new, improved, fixed: give their keys (list_categories).",
"slug has already been taken.".

What every tool keeps to:

* **Nothing published but by `publish_entry`.** `draft_entry` makes a
  draft whatever the `:digest` config says, and `update_entry` never
  changes a status. The server's instructions tell the model to publish
  only when you ask it to; `publish_entry` is marked destructive, so your
  client asks you before it runs.
* **Nobody emailed but by `start_campaign` and `send_broadcast`.** And
  a test by `send_test_letter`, to the address given only. The
  instructions tell the model to start or send only when you ask, and to
  say first how many people it reaches; both tools are marked
  destructive and open-world. `send_broadcast` takes
  `expected_recipients`, the count the model told you: when the audience
  has another count now, nothing is sent, and the error gives the count.
* **Nothing deleted.** There is no tool that deletes an entry, a change,
  a category, a segment or a campaign. A change put aside comes back in
  the admin. `remove_step` removes a step of a sequence; the letters it
  sent stay in the results.
* **Your categories and segments.** A category is one of yours, by its
  key; a segment one of your resolver's `segments/0`. A model that
  invents one is told which there are.
* **Your writer.** An entry the client writes has the author your
  resolver's `author/1` gives for the principal, as in the admin; a
  change has its name.

## Setup

### 1. Add Sake

`Tayori.MCP` compiles only when your app depends on Sake:

```elixir
{:sake, "~> 0.4.3"}
```

If Tayori was already compiled without it, compile Tayori again, or
`Tayori.MCP` stays missing (Sake then says `mount needs a Sake.Server,
got Tayori.MCP`):

```sh
mix deps.compile tayori --force
```

### 2. Say who may use it

Your login is not enough: it may be your customers' too. Tayori lets
nobody in until its config names the resolver that decides:

```elixir
{Tayori,
 repo: MyApp.Repo,
 pubsub: MyApp.PubSub,
 page_url: "https://atelier.app/changelog",
 mcp: [resolver: MyAppWeb.TayoriResolver]}
```

On every request, the principal (what your Sake subject module's
`fetch/1` returns) goes to the resolver's `resolve_access/1`, as the
admin of a request does: `:all` may use every tool its token's scopes
allow, `:read_only` only the read ones (`tayori:read` and
`tayori:campaigns:read`), anything else nothing:
the client is shown no tools, and cannot call any. So make the principal
of an admin the value your resolver's `resolve_user/1` gives for them,
and the admin and MCP decide alike.

`:page_url` gives each entry its `url` on the public page.

### 3. Mount it, or serve it on its own

With an MCP server of your own, mount Tayori's in it under a prefix, next
to your other libraries' (its tools become `tayori_list_entries` and so
on):

```elixir
defmodule MyAppWeb.MCP do
  @moduledoc """
  Atelier's MCP server, at /mcp. Sake makes the app the OAuth server for
  it (/oauth); MyAppWeb.MCPSubject gives each role its scopes.
  """

  use Sake.Server, name: "atelier", version: "1.0.0"

  mount Tayori.MCP, prefix: "tayori"
  mount Lotus.MCP, prefix: "lotus"
end
```

`only:` and `except:` mount part of it:
`mount Tayori.MCP, prefix: "tayori", except: [Tayori.MCP.Tools.PublishEntry]`
leaves publishing to the admin.

Or serve it on an endpoint of its own:

```elixir
# router.ex
import Sake.Router

scope "/" do
  sake_endpoint "/news/mcp", server: Tayori.MCP, auth: true
end
```

and list it in the `servers:` of the `Sake` child. Serve it with
`auth: true` on a network: without it there is no token, Sake checks no
scope, and the resolver is the only gate. Sake's quickstart sets up the
rest: the subject module, the `Sake` child, the OAuth routes.

### 4. Give your roles the scopes

* `tayori:read` - "Read the news and the inbox".
* `tayori:write` - "Write, draft and publish the news".
* `tayori:campaigns:read` - "Read the audience and the campaigns".
* `tayori:campaigns:write` - "Write segments, campaigns and their
  letters" (and send a test letter).
* `tayori:campaigns:send` - "Start campaigns and send broadcasts to the
  app's people".

Keep `tayori:campaigns:send` apart: a role may write the letters and
leave the sending to another. Your subject module's `scopes_for/2` maps your roles to them, with the
scopes of the other servers you mount:

```elixir
defmodule MyAppWeb.MCPSubject do
  @behaviour Sake.Auth.Subject

  # from_conn/1, id/1, fetch/1 and display/1 as in Sake's quickstart:
  # fetch/1 returns the admin as MyAppWeb.TayoriResolver.resolve_user/1 does.

  @impl true
  def scopes_for(%{role: :admin}, _resource) do
    ["tayori:read", "tayori:write", "tayori:campaigns:read", "tayori:campaigns:write",
     "tayori:campaigns:send", "lotus:read"]
  end

  def scopes_for(%{role: :marketing}, _resource),
    do: ["tayori:campaigns:read", "tayori:campaigns:write"]

  def scopes_for(%{role: :support}, _resource), do: ["tayori:read", "tayori:campaigns:read"]
  def scopes_for(_user, _resource), do: []
end
```

### 5. Connect Claude Code

```
claude mcp add --transport http atelier https://atelier.app/mcp
```

The first time, your browser opens on your app's login, then the consent
page with the scopes. Allow the read tools once, and keep the write and
send tools on ask.

## A conversation

> **You:** What shipped since the last entry?

Claude reads the inbox (`list_changes`, state `new`): six changes from
GitHub, two of them internal.

> **You:** The logging one is for us. Draft the rest.

`hide_change` for the logging change, then `draft_entry`: a draft with
a section for each category, which Claude reads back (`get_entry`).

> **You:** Lead with the exports, make it warmer, and write it in
> Portuguese too.

`update_entry` with a new body, then `update_entry` with `locale:
"pt-PT"`: `missing_locales` is now empty.

> **You:** Publish it tomorrow at nine.

`publish_entry` with `at: "2026-10-21T09:00:00Z"`: the entry is
scheduled, and Claude gives its URL. Nothing was published before you
said so.

### With the campaigns

> **You:** Write to the Pro people who have no project yet, about
> templates.

Claude reads the audience (`list_audience`): `plan` is an enum with
`pro`, and `has_projects` a boolean. It tries the condition
(`preview_segment`): "Plan is Pro and not (has a project)", 182 people.

> **You:** Good. A broadcast, Thursday at ten.

`create_campaign` (kind `broadcast`, that audience), then `update_step`
with the subject and the letter in Markdown, and `preview_letter` for
one of the 182. `send_test_letter` sends it to you.

> **You:** Looks right. Send it.

Claude says it reaches 182 people, and calls `send_broadcast` with
`expected_recipients: 182` and `at: "2026-10-22T10:00:00Z"`. Had
someone joined in the meantime, nothing would have been sent, and
Claude would have told you the new count.

## Screenshots from a browser agent

An entry about a new screen wants a picture of it. A screenshot is too
big to write as base64 in a call, so the agent asks for an address, and
sends the file there with curl:

1. **The screenshot.** The agent takes it with its browser, Playwright
   say: `await page.screenshot({path: "exports.png"})`, or
   `browser_take_screenshot` of the Playwright MCP server.
2. **`request_upload`**, with the file's name: it answers an address, good
   for one file for ten minutes, and the command:

   ```json
   {
     "url": "https://atelier.app/api/uploads/news/uploads/Zm9v…",
     "curl": "curl -sS -F 'file=@exports.png' https://atelier.app/api/uploads/news/uploads/Zm9v…",
     "expires_at": "2026-10-20T10:10:00Z",
     "max_bytes": 25000000
   }
   ```

3. **curl** sends the file, and answers its URL and its Markdown:

   ```json
   {"url": "/uploads/kotoba/2026/10/…-exports.png", "markdown": "![](/uploads/kotoba/2026/10/…-exports.png)",
    "contentType": "image/png", "width": 1440, "height": 900, "bytes": 182311}
   ```

4. **`create_entry`, `update_entry` or a draft from `draft_entry`** takes
   the Markdown in the body, the alternative text between the brackets,
   alone in its paragraph:

   ```markdown
   Exports are one click from any project.

   ![The Export button, above the project's files](/uploads/kotoba/2026/10/…-exports.png)
   ```

   The image becomes an attachment of the body, as a file dropped in the
   editor does: a figure, with its size, and the alternative text as its
   caption. Several images in one paragraph make a gallery. An image of
   any other address stays an image: Tayori fetches nothing from a URL.

A client that cannot run curl sends a small image in the call with
`upload_image` (`data` in base64, `filename`), up to 1 MB.

### The uploads route

The address is the uploads route of `tayori_api`, `POST /uploads/:token`,
which takes the file in a multipart `file` field or as the body. Give its
whole address in the config:

```elixir
mcp: [
  resolver: MyAppWeb.TayoriResolver,
  upload_url: "https://atelier.app/api/uploads/news/uploads",
  # The storage of the admin's editor, when it is not Kotoba's own config.
  storage: MyApp.KotobaStorage
]
```

The token is the request's only credential: curl has no session and no
CSRF token. A `tayori_api` mounted behind `protect_from_forgery` refuses
it, so mount the API again for the uploads behind a pipeline with no
session, as for the embed (`:as` names the second mount):

```elixir
pipeline :tayori_uploads do
  plug :accepts, ["json"]
end

scope "/api/uploads" do
  pipe_through :tayori_uploads
  tayori_api "/news", resolver: MyAppWeb.TayoriResolver, as: :tayori_uploads
end
```

What the route keeps to:

* **One file, ten minutes.** A token is 32 random bytes; only its
  SHA-256 is kept, in `tayori_settings` (`mcp_upload:<hash>`), so the
  table never holds a token that works. The first file sent uses it up,
  even one refused; an unknown, used or old token is a 404.
* **Images only.** The bytes decide, not the content type: a PNG, JPEG,
  GIF or WebP image (`Kotoba.Attachments`), up to 25 MB, as the editor's
  uploads. Anything else is a 415, and is not stored.
* **The editor's storage.** The file is stored by
  `Kotoba.Attachments.store/2`, with the `:storage` of the config or
  Kotoba's own, under a new key. Tayori remembers each image it stored,
  by its URL (`mcp_file:<hash>` in `tayori_settings`), so that the
  Markdown of an entry finds it.

Your endpoint's `Plug.Parsers` may read a multipart body before Tayori
does, with its own `:length` (8 MB by default): raise it for screenshots
larger than that, or send the file as the body
(`curl -sS --data-binary @exports.png -H 'content-type: image/png' <url>`).

## Locally, over stdio

For your own machine, serve it over stdio:

```
claude mcp add --transport stdio news -- mix sake.stdio Tayori.MCP
```

There is no token over stdio, so every tool is there, and the principal
is `nil`: your resolver decides for `nil`, so let it in only in
development (`def resolve_access(nil), do: if(dev?(), do: :all, else: :forbidden)`).

## Testing

Sake's test client calls the server in memory, with the principal and
the scopes of a role:

```elixir
import Sake.Test

client = connect(MyAppWeb.MCP, scope: admin, scopes: ["tayori:read"])
assert {:ok, %{structured: %{"entries" => _}}} = call_tool(client, "tayori_list_entries", %{})

assert {:error, {:insufficient_scope, _}} =
         call_tool(client, "tayori_publish_entry", %{"id" => "exports"})
```
