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

## Campaigns, after the first

The campaigns' first version sends letters, step by step. Next:

* **Branches and waits for an event.** A step that waits until a person
  does something (or a time passes), and paths by a condition.
* **Other actions.** An announcement in the app, or a webhook, as a
  step, beside the letters.
* **The app's own actions and triggers.** A step that calls the app's
  code, and triggers the app defines beyond events.
* **A dry run for a person.** What a sequence would send them, and when,
  from where they are.
* **Click tracking.** Links through Tayori, counted per step; opens stay
  out.
* **A cap across campaigns.** At most so many letters a person gets in
  a week, whatever the sequences.
* **Quiet hours and time zones.** A letter waits for a person's
  morning.
* **Entry on joining a segment.** A sequence for those who come to
  match a condition, without an event.
* **Re-entry.** A sequence a person may go through again, after a time.
* **More providers.** Amazon SES, Mailgun, SendGrid built in, beside
  Resend and Postmark.
* **A canvas.** The steps drawn as a flow, once there are branches.
