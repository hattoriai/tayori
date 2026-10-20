# Notifications

When an entry is published, it is told:

* to every open page, at once, on your PubSub;
* to the subscribers, by email, with the `:subscriptions` feature;
* to webhooks, Slack and Discord, with the `:webhooks` feature;
* to your notifier, for anything else your app does: a push, an email to
  your own users, a post elsewhere. Your app knows its readers, its mailer
  and its voice.

```elixir
defmodule MyApp.NewsNotifier do
  @behaviour Tayori.Notifier

  @impl true
  def published(entry) do
    MyApp.Push.news(entry)
  end
end
```

```elixir
{Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub, notifier: MyApp.NewsNotifier}
```

## When

Each publication of an entry is announced once:

* when it is published now, a moment after;
* when it is scheduled, at its time.

In a cluster, one node announces each entry: the announcement is claimed
in the database. An entry unpublished and published again is announced
again; an entry changed after it was published is not.

Readers see a scheduled entry at its time whatever happens to the
announcement: what is announced is only what it sends.

## With Oban, or without

With [Oban](https://hexdocs.pm/oban), give it to Tayori, and each email,
each webhook and the call to your notifier is a job of `Tayori.Worker`,
retried with Oban's backoff, through deploys and crashes:

```elixir
{Tayori, repo: MyApp.Repo, pubsub: MyApp.PubSub, oban: Oban}
```

The jobs go to the `:default` queue, or the one you give
(`oban: [name: Oban, queue: :news]`), which must be one your Oban runs.
`mix tayori.install` sets `oban: Oban` when your app has Oban.

Without Oban, Tayori sends them from tasks in the node that announced the
entry: a webhook is tried three times, an email once, and a failure is
logged. A node stopped while it sends (a deploy, a crash) loses what it
had not sent: no one gets an entry twice, but some may not get it. For
subscribers or webhooks that matter, run Oban. `Tayori.Jobs` has the
details.

With Oban, your notifier already runs in a job, so it can send directly
and raise to be retried. Without it, put your sending in a job of your
own when it should be retried.

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
