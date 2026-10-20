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
admin who scheduled it.

## Time zones

The admin picks a time in their browser's time zone when your app has a
time zone database (`tz` or `tzdata`); else in UTC, and the editor says
so.

## The JSON API

It reads the reader from your app's session: it answers the pages of
your app's origin. See [Any frontend](any_frontend.md).

## AI

The model's answer is a suggestion; it can be wrong. Tayori asks it never
to invent a detail, and puts nothing in an entry the admin did not
accept.
