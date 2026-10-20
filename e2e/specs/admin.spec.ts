import { test, expect } from "@playwright/test";
import { openLive, publish, unique } from "./support";

test("the admin writes an entry in the editor, publishes it, and the public page has it", async ({ page }) => {
  const title = unique("Board templates");
  await publish(page, title, "Every project has an Export button.");

  await page.getByRole("navigation", { name: "Admin" }).getByRole("link", { name: "Entries" }).click();
  const row = page.locator(".ta-entry-row", { hasText: title });
  await expect(row).toContainText("Published");

  await page.goto("/sumi/changelog");
  await expect(page.getByRole("link", { name: title })).toBeVisible();
  await page.getByRole("link", { name: title }).click();
  await expect(page.locator(".kotoba-content")).toContainText("Every project has an Export button.");
});

test("a read-only admin sees the entries and changes nothing", async ({ page }) => {
  await openLive(page, "/admin/news?as=viewer");
  await expect(page.getByRole("link", { name: "New entry" })).toHaveCount(0);
  await page.locator(".ta-entry-row").first().click();
  await expect(page.getByRole("button", { name: "Save" })).toHaveCount(0);
});
