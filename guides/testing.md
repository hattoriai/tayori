# Testing

`Tayori.Test` publishes entries in your test database (each a little
after the one before, so the newest is first), and reads the news
button and panel of a LiveView, in `Phoenix.LiveViewTest`, with no
browser.

```elixir
import Tayori.Test

test "a Pro customer sees the news for Pro", %{conn: conn} do
  publish!("Faster search", categories: ["Improved"])
  publish!("For free plans", segments: ["plan:free"])
  publish!("Shared boards", segments: ["plan:pro"])

  {:ok, view, _html} = conn |> log_in_user(pro_user()) |> live(~p"/projects")

  assert unread(view) == 2

  assert [%{title: "Shared boards", new: true}, %{title: "Faster search", categories: ["Improved"]}] =
           open_news(view)

  assert unread(view) == 0
end
```

* `publish!/2` - writes and publishes an entry: `:body` (Markdown),
  `:categories`, `:segments`, `:at`, `:translations`.
* `unread/1` - the count the button shows.
* `open_news/1` - opens the panel, as a click on the button does, and
  returns its entries; the news is then seen.
* `entries/1` - the entries the open panel shows.
* `close_news/1` - closes the panel.

Tayori is in your app's supervision tree in the tests too, with your test
repo; the entries are in the sandbox of each test.

## Your notifier

Call your notifier with an entry, as Tayori does:

```elixir
entry = publish!("Exports")
MyApp.NewsNotifier.published(entry)
```

With the `:oban` option, what a publication sends is a job of
`Tayori.Worker`, which your Oban's testing mode keeps:

```elixir
use Oban.Testing, repo: MyApp.Repo

entry = publish!("Exports")
announce!()
assert_enqueued worker: Tayori.Worker, args: %{"job" => "notify", "entry_id" => entry.id}
```

## The JSON API

`Phoenix.ConnTest` reads it as any route of your app:

```elixir
publish!("Exports")
assert %{"entries" => [%{"title" => "Exports"}]} = conn |> get(~p"/api/news") |> json_response(200)
```

## What these tests do not cover

The script of the news: the dates in the reader's time zone, and
`<tayori-news>` in a page. Test those in a browser.
