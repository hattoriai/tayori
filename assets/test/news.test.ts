import { test } from "node:test";
import assert from "node:assert/strict";
import { isNew, unreadText, type ApiEntry } from "../src/news_element";
import { timeText } from "../src/times";

const entry = (publishedAt: string): ApiEntry => ({
  id: "1",
  slug: "s",
  title: "T",
  summary: null,
  categories: [],
  publishedAt,
  locale: "en",
  html: null,
  url: null,
});

test("unreadText picks the form of the count", () => {
  const messages = { unreadOne: "{n} new update", unreadOther: "{n} new updates" };
  assert.equal(unreadText(messages, 1), "1 new update");
  assert.equal(unreadText(messages, 3), "3 new updates");
});

test("isNew: after newAfter, and never for a visitor", () => {
  assert.equal(isNew(entry("2026-10-20T10:00:00Z"), "2026-10-20T09:00:00Z"), true);
  assert.equal(isNew(entry("2026-10-20T08:00:00Z"), "2026-10-20T09:00:00Z"), false);
  assert.equal(isNew(entry("2026-10-20T10:00:00Z"), null), false);
});

test("timeText shows a day in the reader's zone and language", () => {
  // TZ is America/Los_Angeles in the tests: 03:00 UTC is the day before.
  assert.equal(timeText("2026-10-20T03:00:00Z", "en-GB", false), "19 Oct 2026");
  assert.match(timeText("2026-10-20T15:00:00Z", "pt-PT", false) ?? "", /20/);
  assert.equal(timeText("not a date"), null);
});
