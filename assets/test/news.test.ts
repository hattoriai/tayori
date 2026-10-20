import { test } from "node:test";
import assert from "node:assert/strict";
import { isNew, summaryText, topReactions, unreadText, type ApiEntry } from "../src/news_element";
import { timeText } from "../src/times";

const entry = (publishedAt: string): ApiEntry => ({
  id: "1",
  slug: "s",
  title: "T",
  summary: null,
  cover: null,
  categories: [],
  pinned: false,
  publishedAt,
  locale: "en",
  html: null,
  text: null,
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

test("summaryText: the summary, else the start of the body", () => {
  assert.equal(summaryText({ summary: "Short.", text: "Long body." }), "Short.");
  assert.equal(summaryText({ summary: null, text: "  Two\n\nlines " }), "Two lines");
  assert.equal(summaryText({ summary: null, text: "" }), null);
  const long = summaryText({ summary: null, text: "é".repeat(200) }) ?? "";
  assert.equal([...long].length, 178);
  assert.ok(long.endsWith("…"));
});

test("topReactions: the three most given, none for no reactions", () => {
  assert.deepEqual(topReactions({ counts: { "👍": 1, "🎉": 5, "❤️": 3, "👀": 0, "🚀": 2 }, mine: [] }), [
    ["🎉", 5],
    ["❤️", 3],
    ["🚀", 2],
  ]);
  assert.deepEqual(topReactions(undefined), []);
});

test("timeText shows a day in the reader's zone and language", () => {
  // TZ is America/Los_Angeles in the tests: 03:00 UTC is the day before.
  assert.equal(timeText("2026-10-20T03:00:00Z", "en-GB", false), "19 Oct 2026");
  assert.match(timeText("2026-10-20T15:00:00Z", "pt-PT", false) ?? "", /20/);
  assert.equal(timeText("not a date"), null);
});
