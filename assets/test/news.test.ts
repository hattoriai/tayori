import { test } from "node:test";
import assert from "node:assert/strict";
import { panelQuery } from "../src/news_element";
import { timeText } from "../src/times";

test("panelQuery: only what differs from the first view", () => {
  assert.equal(panelQuery({ category: null, pages: 1, entry: null, since: null }), "");
  assert.equal(
    panelQuery({ category: "api", pages: 2, entry: "0193", since: "2026-10-20T09:00:00Z" }),
    "?category=api&pages=2&entry=0193&since=2026-10-20T09%3A00%3A00Z",
  );
});

test("timeText shows a day in the reader's zone and language", () => {
  // TZ is America/Los_Angeles in the tests: 03:00 UTC is the day before.
  assert.equal(timeText("2026-10-20T03:00:00Z", "en-GB", false), "19 Oct 2026");
  assert.match(timeText("2026-10-20T15:00:00Z", "pt-PT", false) ?? "", /20/);
  assert.equal(timeText("not a date"), null);
});
