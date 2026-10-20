# The admin

The admin is where the news is written: the entries, the editor, and the
settings. `Tayori.Router.tayori_admin/2` mounts it in your router.

```elixir
import Tayori.Router

scope "/admin" do
  pipe_through [:browser, :require_admin]

  tayori_admin "/news",
    resolver: MyAppWeb.TayoriResolver,
    on_mount: [{MyAppWeb.AdminAuth, :require_admin}],
    csp_nonce_assign_key: :csp_nonce
end
```

It is a page of its own, as Lotus's dashboard and Oban Web are: its own
document, script and style sheet, served at `/admin/news/assets/` with the
hash of the build in their names. Your app's layout, CSS and JavaScript
never reach it, and it never reaches them. It joins your app's LiveView
socket (`/live`, or `:socket_path`).

## Behind your authentication

Mount the admin in a scope whose pipeline lets in only your admins. Three
things keep it closed, as in Lotus:

1. **Your pipeline** runs on the request of the page, and on the requests
   of its script and style sheet.
2. **Your resolver** reads the admin from that request
   (`c:Tayori.Resolver.resolve_user/1`) and says what they may do
   (`c:Tayori.Resolver.resolve_access/1`):
   * `:all` - write, publish, delete, and change the settings;
   * `:read_only` - read the entries and the drafts, change nothing;
   * `:forbidden` - nothing: the admin answers with a 404;
   * `{:forbidden, path}` - nothing: the admin sends them to `path`.
3. **Your `on_mount` hooks** (`:on_mount`) run on every mount and
   reconnect of the admin's LiveViews, before Tayori's: check the admin's
   session there, so that a session that ended stops the admin at once.

There is no default: a resolver without `resolve_user/1` and
`resolve_access/1` does not compile, and the resolver the installer
writes lets no one in.

The admin goes into the LiveView's session as `resolve_user/1` returns
it: return a small map or struct, not a user with all its associations.

### An admin of its own

An app with admins apart from its users (their own table, as in
indie.camera) reads them from its own assigns:

```elixir
def resolve_user(conn), do: conn.assigns[:current_admin_user]

def resolve_access(%MyApp.Admin.User{}), do: :all
def resolve_access(nil), do: {:forbidden, "/admin/login"}
```

## Who wrote it

`c:Tayori.Resolver.author/1` gives the author kept on each new entry:

```elixir
def author(admin), do: %{"id" => admin.id, "name" => admin.name}
```

## Segments

`c:Tayori.Resolver.segments/0` gives the segments the editor offers, alone
or in groups:

```elixir
def segments do
  [
    {"Plan", [{"plan:free", "Free"}, {"plan:pro", "Pro"}]},
    {"Role", [{"role:owner", "Owners"}, {"role:editor", "Editors"}]}
  ]
end
```

An entry with no segments is for everyone; an entry with segments is for
the readers in at least one of them. See [Readers](readers.md).

## Languages

The editor has a tab for each language of the entry, and adds the others
of `:locales`. The first language is required; the others are optional,
and readers of a language an entry lacks read the first.

## Attachments

The editor is Kotoba's, with its attachments: images, PDFs and videos,
dropped or pasted into the body. Kotoba keeps them in its storage, which
your app configures (`config :kotoba, storage: ...`, see Kotoba's Uploads
guide), or in another for the admin alone:

```elixir
tayori_admin "/news", resolver: MyAppWeb.TayoriResolver, storage: MyApp.NewsStorage
```

## Writing

The editor has the entry's title, summary and body in each language, and
beside them its cards:

* **Publication**: publish now or at a time, save a draft, copy a preview
  link (see below), and see the entry on the public page.
* **Cover**: an optional picture of the entry's own, dropped or picked,
  with its description for screen readers.
* **Details**: the end of its address, its categories (Categories, in the
  admin's bar, has the list), and pinning it.
* **Audience**: the segments it is for (see [Readers](readers.md)).
* **Announcement**, **Email** and **Last 30 days**, with those features
  on (see [Features](features.md)).

Preview shows the entry as your readers will see it: on the public page,
in the panel, or as its announcement, in the language of the tab.

## Publishing

An entry is a draft until it is published: now, or at a time picked in
the admin's own time zone (their browser's, when your app has a time zone
database such as `tz` or `tzdata`, else UTC). A scheduled entry is
published at its time, by the node that reaches it first; each entry is
announced once, to every open page, and sends what it sends (emails,
webhooks, your notifier; see [Notifications](notifications.md)).
Unpublishing makes it a draft again; publishing it again announces it
again.

A preview link shows the last saved version of a draft or a scheduled
entry on the public page, to whoever has it, for a week. It needs
`tayori_admin`'s `:page` option, the path of your public page:

```elixir
tayori_admin "/news", resolver: MyAppWeb.TayoriResolver, page: "/changelog"
```

## The theme

`theme: :sumi` gives the admin the Sumi theme of Hattori AI. Both themes
follow the system's light and dark, or the admin's choice in the bar's
appearance menu (light, dark or the system's), kept in their browser.

## Content Security Policy

With `:csp_nonce_assign_key`, the admin's `<link>` and `<script>` carry
the nonce of your policy, read from `conn.assigns` (one key, or
`%{style: key, script: key}`). The admin needs:

* `script-src 'self' 'nonce-…'`;
* `style-src 'self' 'nonce-…'` and `style-src-attr 'unsafe-inline'`
  (the editor and the date picker place their popovers with inline
  styles);
* `connect-src 'self' wss:` for the LiveView socket;
* `img-src` and `media-src` with the origin of Kotoba's storage, for
  attachments.

## Reconnects after a deploy

The names of the admin's script and style sheet carry the hash of the
build, and are cached for a year. A page of an older build asks for
files the new build does not have, and gets a 404: reload it.
