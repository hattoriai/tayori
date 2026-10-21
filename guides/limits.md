# Known limits

## Browsers

The browser tests run in Chromium, Firefox and WebKit, in the `en-GB`
locale and the `Europe/Lisbon` time zone. The admin and the news need a
browser with custom elements and `Intl.DateTimeFormat`.

## Databases

Tayori runs on PostgreSQL and SQLite. MySQL is not supported: the
segments are a PostgreSQL array, and a JSON array in SQLite.

## Many entries

Reading the news is a query by publication time, with the segments in
the database; the admin's list of entries loads them all, with a search
and filters. Thousands of entries are fine; the admin has no paging yet.

## Unread

Tayori keeps one time for each reader, not a row for each entry: it
knows what was published since the reader last looked, not which entries
they read. The count stops at 99.

## Scheduling

A scheduled entry is published at its time (it shows to readers from
then on); its announcement (to open pages and the notifier) comes within a
minute on the node that reaches it first, or at once on the node of the
admin who scheduled it. What it sends (emails, webhooks, the notifier)
is retried by Oban when Tayori has it, and is lost with the node that
sends it when it has not: see [Notifications](notifications.md).

## Time zones

The admin picks a time in their browser's time zone when your app has a
time zone database (`tz` or `tzdata`); else in UTC, and the editor says
so.

## The JSON API

It reads the reader from your app's session, on your app's origin. On
another origin (the `:embed` feature), from a token your server signs,
valid for a day: a reader's segments are those of when it was signed.
The element asks the count every few minutes; it has no socket. See
[Any frontend](any_frontend.md).

## AI

The model's answer is a suggestion; it can be wrong. Tayori asks it never
to invent a detail, and puts nothing in an entry the admin did not
accept.

## Search on SQLite

The search ignores case. On SQLite it does so for ASCII letters only:
"ação" finds "ação" and "Ação" only where the accented letters have the
same case. PostgreSQL has no such limit.

## Campaigns

* **One entry per person.** A person enters a sequence once, ever: no
  re-entry, and no entry on joining a segment. Each step's letter goes
  to a person once.
* **Steps are judged when reached.** A person goes from step to step by
  the steps' waits. A step whose moment passed while it was not wanted
  is left out; a step added at or before where a person is does not go
  to them. A sequence has no branches and no waits for an event.
* **Batches.** The runner reads the people whose time came 200 at a
  time, a broadcast its audience 500 at a time (each batch after the
  last key of the one before, `key/0`), and takes a segment into a
  sequence 500 at a time; a broadcast to many people takes a while to
  go. Resuming a sequence takes its people up in one update, then gives
  Oban their jobs 1000 at a time. Without Oban the letters go one after
  the other from a task.
* **Lost jobs.** With Oban, the sweep finds what lost its job once an
  hour (and at each boot): a letter whose job was lost may wait up to
  an hour and a quarter. A letter sent and not marked (a crash between
  the mailer and the database) is not sent again for ten minutes, then
  may be: a letter goes at least once, and twice only then.
* **Steps keep their order** once a person has entered the sequence:
  change their times instead.
* **The admin** reads a campaign again at most once a second while its
  letters go.
* **Events** are kept 400 days (`keep_events_days`), and a condition
  reads them with the audience's `person_id/0`, in one query.
* **No tracking.** No opens and no clicks; a provider's webhook tells of
  bounces and complaints, and a delivery changes nothing.
* **No cap across campaigns.** The gap between letters is a sequence's
  own: two sequences may write to one person the same day. No quiet
  hours, no time zone per person: a letter goes at its time after the
  entry, whatever the hour where the person is.
* **SQLite.** The campaigns' transactions begin immediate on SQLite, so
  that a write waits its turn (the repo's `busy_timeout`, 2000 ms by
  default) instead of failing. A big broadcast holds the write lock for
  a batch at a time; other writes of the app wait behind it. Strings
  are compared without case for ASCII letters only, as the search is.
