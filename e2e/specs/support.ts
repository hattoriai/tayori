// Helpers for the browser tests.

import { expect, type Page } from "@playwright/test";

/** Opens a LiveView page and waits for it to connect. */
export async function openLive(page: Page, path: string): Promise<void> {
  await page.goto(path);
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
}

/** A title no other test has. */
export function unique(title: string): string {
  return `${title} ${Math.random().toString(36).slice(2, 8)}`;
}

/** Writes and publishes an entry in the admin, as the admin. */
export async function publish(page: Page, title: string, body: string): Promise<void> {
  await openLive(page, "/admin/news/new?as=admin");
  await page.getByLabel("Title").fill(title);
  const editor = page.locator('#tayori-body-en [contenteditable="true"]');
  await editor.click();
  await page.keyboard.type(body);
  await page.getByRole("button", { name: "Publish now" }).click();
  await expect(page.getByText("The entry is published.")).toBeVisible();
}
