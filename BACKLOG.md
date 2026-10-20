# Backlog

Known gaps in Tayori, each to become an issue.

## Roadmaps and announcements

The name holds more than a changelog: a roadmap (what is coming, from
planned to shipped), announcements that are not entries of the changelog
(a banner, a popup once), and newsletters. The entries would need a kind,
and the public page a section for each.

## Reactions and views

Featurebase-like counts of who saw an entry, and reactions to it. Tayori
keeps one "seen" time per reader, not a row per entry and reader; views
would need one, and a retention.

## Search on the public page

The public page pages by date; it has no search, and no filter of
categories.

## A connector for <tayori-news> outside the app's origin

The JSON API reads the reader from the app's session, so `<tayori-news>`
works on the app's own origin. A frontend on another origin needs a
signed token (`Phoenix.Token`) and CORS.

## Import from another changelog

Markdown imports through `Kotoba.Content.from_markdown/2` work in a
script; there is no import of HTML (Kotoba has no `from_html`), nor of
another tool's export.

## The AI and the notes of what shipped

The drafts start from notes the admin pastes. A source of what shipped
(merged pull requests, a release's notes, Linear or Jira issues) would
fill them.

## mix tayori.build tests

Jumon and Kotoba test their build task (`test/mix/*_build_test.exs`,
tagged :build); Tayori's build task has no tests of its own yet.
