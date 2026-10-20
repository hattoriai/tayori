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

Tayori's scheduler looks every minute, on one node of the cluster. A
schedule begins the first time it looks: a weekly digest added on a
Wednesday first runs the next Monday, not at once. A time missed while
the app was down runs once, at the next look.

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

Say so on the page: the words of the subscribe form ("One email when
something new ships") are yours to change, as `subscribeText` (see
`Tayori.Messages`).
