import { test, expect, type Page } from "@playwright/test";
import { openLive, unique } from "./support";

/** Writes and publishes an entry in the admin, as the admin: its title field by id, as the SEO title is "Title" too. */
async function publishEntry(page: Page, title: string, body: string): Promise<void> {
  await openLive(page, "/admin/news/new?as=admin");
  await page.locator("#entry_translations_0_title").fill(title);
  await page.locator('#tayori-body-en [contenteditable="true"]').click();
  await page.keyboard.type(body);
  await page.getByRole("button", { name: "Publish now" }).click();
  await expect(page.getByText("The entry is published.")).toBeVisible();
}

/** Opens the panel of <tayori-news> on a page. */
async function openElement(page: Page, path: string) {
  await page.goto(path);
  const button = page.locator("tayori-news .tayori-button");
  await expect(button).toHaveAttribute("aria-label", /.+/);
  await button.click();
  const panel = page.locator("tayori-news .tayori-panel");
  await expect(panel.locator(".tayori-card").first()).toBeVisible();
  return { button, panel };
}

test("a published entry reaches an open page at once, and opening the news clears the count", async ({ browser }) => {
  const reader = await browser.newContext();
  const admin = await browser.newContext();
  const readerPage = await reader.newPage();
  const adminPage = await admin.newPage();

  // The reader opens the news once, so that nothing is unread.
  await openLive(readerPage, "/?as=pro");
  await readerPage.locator(".tayori-button").click();
  await expect(readerPage.locator("#tayori-panel")).toBeVisible();
  await readerPage.keyboard.press("Escape");
  await expect(readerPage.locator("#tayori-panel")).toHaveCount(0);
  await expect(readerPage.locator(".tayori-badge")).toHaveCount(0);

  const title = unique("Shared boards");
  await publishEntry(adminPage, title, "Share a board with a link.");

  await expect(readerPage.locator(".tayori-badge")).toHaveText("1");
  await readerPage.locator(".tayori-button").click();
  const card = readerPage.locator(".tayori-card", { hasText: title });
  await expect(card).toBeVisible();
  await expect(card.locator(".tayori-new")).toHaveText("New");
  await expect(readerPage.locator(".tayori-badge")).toHaveCount(0);

  await reader.close();
  await admin.close();
});

test("<tayori-news> shows the news over the JSON API, and marks it seen", async ({ page }) => {
  const { button, panel } = await openElement(page, "/plain?as=free");
  await expect(panel.getByRole("heading", { name: "Novidades" })).toBeVisible();
  await expect(panel.locator(".tayori-card-title").first()).toBeVisible();
  await expect(page.locator("tayori-news .tayori-badge")).toBeHidden();
  await expect(button).toHaveAttribute("aria-expanded", "true");

  await page.keyboard.press("Escape");
  await expect(panel).toHaveCount(0);
  await expect(button).toBeFocused();
  await expect(button).toHaveAttribute("aria-expanded", "false");
});

test("<tayori-news> has the panel of the LiveView: pinned first, covers, categories", async ({ page }) => {
  const { panel } = await openElement(page, "/plain?as=pro");

  const first = panel.locator(".tayori-card").first();
  await expect(first).toHaveClass(/tayori-card-pinned/);
  await expect(first.locator(".tayori-pinned")).toHaveText("Pinned");
  await expect(panel.locator(".tayori-card .tayori-cover img").first()).toBeVisible();
  await expect(panel.locator(".tayori-card .tayori-category").first()).toBeVisible();
  await expect(panel.locator("time[data-tayori-shown]").first()).toBeVisible();

  // The categories filter the list.
  const filter = panel.getByRole("navigation", { name: "Categories" });
  await expect(filter.getByRole("button", { name: "All" })).toHaveAttribute("aria-pressed", "true");
  await filter.getByRole("button", { name: "Improved" }).click();
  await expect(filter.getByRole("button", { name: "Improved" })).toHaveAttribute("aria-pressed", "true");
  await expect(panel.locator(".tayori-card", { hasText: "Faster search" })).toBeVisible();
  await expect(panel.locator(".tayori-card", { hasText: "Exports in two clicks" })).toHaveCount(0);
  for (const card of await panel.locator(".tayori-card").all()) {
    await expect(card.locator(".tayori-category", { hasText: "Improved" })).toBeVisible();
  }

  await filter.getByRole("button", { name: "All" }).click();
  await expect(panel.locator(".tayori-card", { hasText: "Exports in two clicks" })).toBeVisible();
});

test("<tayori-news> opens an entry in the panel, and Escape goes back, then closes", async ({ page }) => {
  const { button, panel } = await openElement(page, "/plain?as=pro");

  await panel.locator(".tayori-card-title button", { hasText: "Faster search" }).click();
  await expect(panel.locator(".tayori-entry-title")).toHaveText("Faster search");
  await expect(panel.locator(".tayori-entry-body")).toContainText("spreadsheet");
  await expect(panel.getByRole("button", { name: "Back" })).toBeFocused();
  await expect(panel.locator(".tayori-panel-footer .tayori-hint")).toContainText("Back");

  await page.keyboard.press("Escape");
  await expect(panel.locator(".tayori-entry")).toHaveCount(0);
  await expect(panel.locator(".tayori-card-title button", { hasText: "Faster search" })).toBeFocused();

  await panel.locator(".tayori-card-title button", { hasText: "Faster search" }).click();
  await panel.getByRole("button", { name: "Back" }).click();
  await expect(panel.locator(".tayori-cards")).toBeVisible();

  await page.keyboard.press("Escape");
  await expect(panel).toHaveCount(0);
  await expect(button).toBeFocused();
});

test("<tayori-news> reactions: a reader toggles one, a visitor sees the counts", async ({ page, browser }) => {
  const { panel } = await openElement(page, "/plain?as=pro");
  await panel.locator(".tayori-card-title button", { hasText: "Exports in two clicks" }).click();

  const rocket = panel.locator(".tayori-reaction", { hasText: "🚀" });
  await expect(rocket).toBeEnabled();
  const pressed = (await rocket.getAttribute("aria-pressed")) === "true";

  await rocket.click();
  await expect(rocket).toHaveAttribute("aria-pressed", String(!pressed));
  await expect(rocket).toBeFocused();
  await rocket.click();
  await expect(rocket).toHaveAttribute("aria-pressed", String(pressed));

  const visitor = await (await browser.newContext()).newPage();
  const { panel: visitorPanel } = await openElement(visitor, "/plain?as=visitor");
  await visitorPanel.locator(".tayori-card-title button", { hasText: "Faster search" }).click();
  await expect(visitorPanel.locator(".tayori-reaction").first()).toBeDisabled();
  await expect(visitorPanel.locator(".tayori-reaction").first()).toHaveAttribute("title", "Sign in to react");
});

test("<tayori-news> shows the reader's announcement, and dismisses it for good", async ({ page }) => {
  await page.goto("/plain?as=member");
  const toast = page.locator(".tayori-announcement-toast");
  await expect(toast).toBeVisible();
  await expect(toast).toHaveAttribute("role", "status");
  await expect(toast.locator(".tayori-announcement-title")).toHaveText("Timeline view");

  // The open panel has the news: the toast steps aside.
  await page.locator("tayori-news .tayori-button").click();
  await expect(toast).toHaveCount(0);
  await page.keyboard.press("Escape");
  await expect(page.locator(".tayori-announcement-toast")).toBeVisible();

  await page.locator(".tayori-announcement-toast").getByRole("button", { name: "Dismiss" }).click();
  await expect(page.locator(".tayori-announcement")).toHaveCount(0);

  await page.reload();
  await expect(page.locator("tayori-news .tayori-button")).toHaveAttribute("aria-label", /.+/);
  await page.waitForLoadState("networkidle");
  await expect(page.locator(".tayori-announcement")).toHaveCount(0);
});

test("<tayori-news> on another origin: the script and the news over CORS, with a reader token", async ({ page, baseURL }) => {
  // The dev server's site on another origin: the API is on 127.0.0.1, the
  // site on localhost.
  const site = (baseURL ?? "").replace("127.0.0.1", "localhost");
  const { panel } = await openElement(page, `${site}/elsewhere?as=pro`);

  await expect(page.locator("tayori-news")).toHaveAttribute("api", /127\.0\.0\.1/);
  // The entries for Pro readers come with the token: the page has no session there.
  await expect(panel.locator(".tayori-card", { hasText: "Shared boards for Pro studios" })).toBeVisible();

  await panel.locator(".tayori-card-title button", { hasText: "Exports in two clicks" }).click();
  const party = panel.locator(".tayori-reaction", { hasText: "🎉" });
  await expect(party).toBeEnabled();
  const pressed = (await party.getAttribute("aria-pressed")) === "true";
  await party.click();
  await expect(party).toHaveAttribute("aria-pressed", String(!pressed));
  await party.click();
  await expect(party).toHaveAttribute("aria-pressed", String(pressed));

  // A visitor of the site sees the news for everyone, and cannot react.
  await page.goto(`${site}/elsewhere?as=visitor`);
  await page.locator("tayori-news .tayori-button").click();
  const visitorPanel = page.locator("tayori-news .tayori-panel");
  await expect(visitorPanel.locator(".tayori-card").first()).toBeVisible();
  await expect(visitorPanel.locator(".tayori-card", { hasText: "Shared boards for Pro studios" })).toHaveCount(0);
});
