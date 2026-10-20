import { test, expect } from "@playwright/test";
import { openLive } from "./support";

test("the admin drafts an entry from two changes of the inbox, and lands in the editor", async ({ page }) => {
  await openLive(page, "/admin/news/inbox?as=admin");

  const changes = page.locator(".ta-change");
  await expect(changes.filter({ hasText: "Import a CSV into a board" })).toBeVisible();
  await expect(changes.filter({ hasText: "Comments on whole boards" })).toBeVisible();
  // A change for the team only is there, and cannot go in an entry.
  const internal = changes.filter({ hasText: "Move the job queue to the new cluster" });
  await expect(internal).toContainText("Internal");
  await expect(internal.locator("input[type=checkbox]")).toHaveCount(0);

  await page.getByLabel("Select “Import a CSV into a board”").check();
  await page.getByLabel("Select “Comments on whole boards”").check();
  await expect(page.locator(".ta-selection")).toContainText("2 selected");
  await page.locator(".ta-selection").getByRole("button", { name: "Draft an entry" }).click();

  await expect(page).toHaveURL(/\/admin\/news\/[0-9a-f-]{36}$/);
  await expect(page.getByText("An entry is drafted from 2 changes.")).toBeVisible();
  const body = page.locator('#tayori-body-en [contenteditable="true"]');
  await expect(body).toContainText("Import a CSV into a board");
  await expect(body).toContainText("Comments on whole boards");
  const fromInbox = page.locator("#from-inbox");
  await expect(fromInbox).toContainText("Import a CSV into a board");
  await expect(fromInbox).toContainText("Comments on whole boards");

  // Back in the inbox, they are drafted, with a link to the entry.
  await fromInbox.getByRole("link", { name: "Open the inbox" }).click();
  await expect(page.locator(".ta-change", { hasText: "Import a CSV into a board" })).toContainText("In “");
});
