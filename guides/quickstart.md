# Quickstart

This guide adds Tayori to a Phoenix app, from the dependency to the first
entry your readers see. It shows a Phoenix 1.8 app with `mix phx.gen.auth`;
the [Admin](admin.md) guide covers other ways to know your admins.

## 1. Run the installer

With [Igniter](https://hexdocs.pm/igniter) (`mix archive.install hex igniter_new`
once):

```sh
mix igniter.install tayori
```

It adds `{:tayori, "~> 0.1"}` to your deps and makes these changes,
showing each one as a diff before it writes:

* `lib/my_app_web/router.ex`: the admin at `/admin/news`, in the `/admin`
  scope, and the public page at `/changelog` (step 6);
* the migration of Tayori's tables, in `priv/repo/migrations`;
* `assets/js/app.js`: `import { Tayori } from "tayori"`, and `Tayori` in
  the hooks of the `LiveSocket`;
* `assets/css/app.css`: Kotoba's style sheet and the news', and the Sumi
  theme as a comment;
* `lib/my_app/application.ex`: Tayori, after the repo and the PubSub
  (step 4);
* `lib/my_app_web/tayori_resolver.ex`: your resolver, which lets no one
  into the admin until you say who your admins are (step 5).

Running it again changes nothing. With Tayori already in your deps,
`mix tayori.install` does the same. For writing with AI, with your own
key, add `{:req_llm, "~> 1.6"}` to your deps too.

## 2. Or make the changes by hand

Add the dependency:

```elixir
def deps do
  [
    {:tayori, "~> 0.1"},
    # For writing with AI, with your own key. Optional.
    {:req_llm, "~> 1.6"}
  ]
end
```


In `assets/js/app.js`:

```js
import { Tayori } from "tayori"

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Tayori},
})
```

In `assets/css/app.css`, below the other `@import` lines. The bodies of
the entries are Kotoba content: import Kotoba's style sheet too, unless
your app already does.

```css
@import "../../deps/kotoba/priv/static/kotoba.css";
@import "../../deps/tayori/priv/static/tayori.css";
/* @import "../../deps/tayori/priv/static/tayori-sumi.css"; */
```

And the migration:

```sh
mix tayori.gen.migration
```

## 3. Let esbuild find `tayori` in `deps/`

`import { Tayori } from "tayori"` resolves through the `NODE_PATH` of your
esbuild profile. The Phoenix generators set it; if your profile has no
`NODE_PATH`, add it in `config/config.exs`:

```elixir
env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
```

## 4. Start Tayori

Run the migration:

```sh
mix ecto.migrate
```

The installer added Tayori to the children of `lib/my_app/application.ex`,
after the repo and the PubSub; by hand, add it there:

```elixir
children = [
  MyApp.Repo,
  {Phoenix.PubSub, name: MyApp.PubSub},
  {Tayori,
   repo: MyApp.Repo,
   pubsub: MyApp.PubSub,
   secret_key_base: Application.fetch_env!(:my_app, MyAppWeb.Endpoint)[:secret_key_base],
   locales: ["en"]},
  MyAppWeb.Endpoint
]
```

`locales` are the languages you write the news in, the first the one every
entry has. `secret_key_base` lets the admin keep an AI key, encrypted; see
`Tayori.Config` for the other options.

## 5. Say who your admins and readers are

The installer wrote `lib/my_app_web/tayori_resolver.ex`. Say who may write
the news. Here, the users with an `admin` flag:

```elixir
@impl true
def resolve_user(conn), do: conn.assigns[:current_scope] && conn.assigns.current_scope.user

@impl true
def resolve_access(%MyApp.Accounts.User{admin: true}), do: :all
def resolve_access(nil), do: {:forbidden, "/users/log-in"}
def resolve_access(_user), do: :forbidden
```

And who reads it:

```elixir
@impl true
def resolve_reader(%{assigns: %{current_scope: %{user: %{} = user}}}) do
  %Tayori.Reader{id: "user:#{user.id}", locale: "en", since: user.inserted_at}
end

def resolve_reader(_visitor), do: nil
```

`since` is when the reader joined: what was published before is never
unread to them. The [Readers](readers.md) guide adds segments.

## 6. Mount the admin and the public page

The installer mounted both in `lib/my_app_web/router.ex`. Put the admin
behind the pipeline that signs your users in:

```elixir
import Tayori.Router

scope "/admin" do
  pipe_through [:browser, :require_authenticated_user]
  tayori_admin "/news", resolver: MyAppWeb.TayoriResolver
end

scope "/" do
  pipe_through :browser
  tayori_page "/changelog", title: "What's new in MyApp"
end
```

Open http://localhost:4000/admin/news, write an entry and publish it. The
public page has it at http://localhost:4000/changelog.

## 7. Put the news in your LiveViews

Add `Tayori.Live` to the `on_mount` of the `live_session`, after the hooks
that assign the user:

```elixir
live_session :require_authenticated_user,
  on_mount: [
    {MyAppWeb.UserAuth, :require_authenticated},
    {Tayori.Live, resolver: MyAppWeb.TayoriResolver, page: "/changelog"}
  ] do
  live "/projects", ProjectLive.Index
end
```

And render the button and the panel in `Layouts.app`
(`lib/my_app_web/components/layouts.ex`), with `@tayori` passed on to it
(`<Layouts.app flash={@flash} tayori={@tayori}>`):

```heex
<header class="navbar">
  ...
  <Tayori.Components.news_button :if={assigns[:tayori]} tayori={@tayori} />
</header>
<Tayori.Components.news_panel :if={assigns[:tayori]} tayori={@tayori} />
```

In a Phoenix 1.7 app, put them in `layouts/app.html.heex`, which has the
LiveView's assigns.

Publish another entry: the button of every open page shows it at once.

## Next

* [The admin](admin.md): access, segments, attachments, the CSP.
* [Writing with AI](ai.md): a model and your key, in the admin's Settings.
* [Notifications](notifications.md): an email when an entry is published.
* [Any frontend](any_frontend.md): the news in a React or Vue frontend.
