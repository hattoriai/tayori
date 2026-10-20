import { test, expect } from "@playwright/test";
import { openLive, publish, unique } from "./support";

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
  await publish(adminPage, title, "Share a board with a link.");

  await expect(readerPage.locator(".tayori-badge")).toHaveText("1");
  await readerPage.locator(".tayori-button").click();
  const entry = readerPage.locator(".tayori-entry", { hasText: title });
  await expect(entry).toBeVisible();
  await expect(entry.locator(".tayori-new")).toHaveText("New");
  await expect(readerPage.locator(".tayori-badge")).toHaveCount(0);

  await reader.close();
  await admin.close();
});

test("<tayori-news> shows the news over the JSON API, and marks it seen", async ({ page }) => {
  await page.goto("/plain?as=free");
  const button = page.locator("tayori-news .tayori-button");
  await expect(button).toBeVisible();

  await button.click();
  const panel = page.locator("tayori-news .tayori-panel");
  await expect(panel).toBeVisible();
  await expect(panel.getByRole("heading", { name: "Novidades" })).toBeVisible();
  await expect(panel.locator(".tayori-entry").first()).toBeVisible();
  await expect(page.locator("tayori-news .tayori-badge")).toBeHidden();

  await page.keyboard.press("Escape");
  await expect(panel).toHaveCount(0);
  await expect(button).toBeFocused();
});
