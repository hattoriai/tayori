# Features

A changelog is always there: entries in your languages, categories,
covers, pinned entries, a search, the admin, the news in your app and the
public page. The rest is yours to turn on, in the `:features` of
`Tayori.Config`, so that an app that wants a changelog gets only that:

```elixir
{Tayori,
 repo: MyApp.Repo,
 pubsub: MyApp.PubSub,
 features: [:reactions, :announcements, :analytics]}
```

A feature that is off has no admin page, no route, no form, no element
and no process. Settings → Features in the admin lists what is on.

## Always there

* **Categories**, managed in the admin (Categories): a name in each of your
  languages, a colour, an order. An entry has any number of them; the
  panel and the public page filter by them.
* **A cover**, optional: a picture of its own at the top of the entry, on
  its card and on shared links, apart from the screenshots in its body.
* **Pinned entries**, first in the panel and on the public page.
* **A search** of the titles, summaries and text, in the admin and on the
  public page.
* **Previous and next** on each entry's page.
* **Shared links**: an SEO title and description of each entry, Open
  Graph, Twitter cards, `hreflang`, JSON-LD and a sitemap.
* **Preview links** for drafts and scheduled entries, valid a week.

## Reactions

`:reactions`. Readers react to an entry with an emoji, in the panel and on
the public page, and see how many did. A reaction is a reader's: a visitor
cannot react, and each reader counts once for each emoji. The admin sees
the reactions of each entry.

The emoji are yours to choose:

```elixir
features: [:reactions], reactions: ["👍", "🎉", "❤️", "🚀", "👀"]
```

## Announcements

`:announcements`. The admin announces an entry as a popup, a toast or a
banner, until a date, with a button of its own (a label and a path of
your app, or an `https` address). A reader sees the newest announcement
they have not dismissed; dismissing it, or opening the entry, is
remembered for them on every device. A visitor sees it until the page
closes it. Put `Tayori.Components.announcement/1` in your layout (see
[In the app](in_app.md)).

## Analytics

`:analytics`. The views of each entry, by day and by where it was read:
opened in the panel or in `<tayori-news>`, on the public page, or from an
email's link. A feed is not counted: a feed reader fetches it whether or
not anyone reads it. The admin
shows each entry's views and readers on its list, and the last 30 days of
a published entry beside the editor.

Nothing about a reader is kept but their id, for a reader your resolver
gives; a visitor is counted with the other visitors of the day. No
address, no device, no cookie.

## Subscriptions

`:subscriptions`. Readers subscribe by email on the public page; the
admin chooses, for each entry, whether it is emailed when it is
published. Every address is confirmed first (double opt-in), every email
has a one-click unsubscribe link (`List-Unsubscribe`), and an entry for
some readers (with segments) is never emailed: subscribers are
addresses, not readers.

Tayori sends the emails with your Swoosh mailer:

```elixir
{:swoosh, "~> 1.17"}
```

```elixir
features: [:subscriptions],
mailer: MyApp.Mailer,
email_from: {"MyApp", "news@myapp.com"},
page_url: "https://myapp.com/changelog"
```

`:page_url` is the address of the public page, for the links of the
emails. Settings → Email shows the subscribers, confirmed and waiting.

## Webhooks

`:webhooks`. The admin adds places told of each entry when it is
published, in Settings → Integrations:

* a webhook: a POST of the entry as JSON, signed with its secret
  (`x-tayori-signature: sha256=<hex HMAC-SHA256 of the body>`), shown
  once when it is added;
* Slack: a message to an incoming webhook;
* Discord: a message to a channel webhook.

Their addresses and secrets are kept encrypted, as the AI key is. A
webhook gets every entry; Slack and Discord get the entries for
everyone, which are public. Each place can be sent a test.

Tayori posts them with Req:

```elixir
{:req, "~> 0.5"}
```

## Embed

`:embed`. The news on another domain than your app's: see
[Any frontend](any_frontend.md).

## Sending, with Oban or not

The emails, the webhooks and the call to your notifier are sent when an
entry is published. With Oban they are jobs, retried through deploys;
without, they are sent from a task. See [Notifications](notifications.md).
