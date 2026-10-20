# Notifications

When an entry is published, your app can tell its readers: an email, a
message in Slack, a push. Tayori sends nothing itself: your app knows its
readers, its mailer and its voice. It tells your notifier.

```elixir
defmodule MyApp.NewsNotifier do
  @behaviour Tayori.Notifier

  @impl true
  def published(entry) do
    %{entry_id: entry.id}
    |> MyApp.Workers.NewsEmail.new()
    |> Oban.insert()
  end
end
```

```elixir
{Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub, notifier: MyApp.NewsNotifier}
```

## When

`c:Tayori.Notifier.published/1` is called once for each publication of an
entry:

* when it is published now, a moment after;
* when it is scheduled, at its time.

In a cluster, one node announces each entry: the announcement is claimed
in the database. An entry unpublished and published again is announced
again; an entry changed after it was published is not.

It runs in a task: a slow mailer holds nothing up, and a crash is logged.
Put the sending in a job (Oban) to retry it.

## The entry

The entry has its translations and its segments:

```elixir
def deliver(entry_id) do
  entry = Tayori.Entries.get!(entry_id)
  config = Tayori.Config.get()

  for user <- MyApp.Accounts.users_for(entry.segments) do
    translation = Tayori.Entry.translation(entry, user.locale, config.locales)
    MyApp.Mailer.deliver(NewsEmail.new(user, entry, translation))
  end
end
```

The body is Kotoba content: `translation.body.html` for the email's HTML,
`translation.body.text` for its text part, and `translation.summary` when
the email gives a summary with a link.

## The PubSub

Every open page hears of an entry on the app's PubSub (see `Tayori`), and
so can your own processes:

```elixir
Tayori.subscribe()

def handle_info({Tayori, :published, id}, state), do: ...
```
