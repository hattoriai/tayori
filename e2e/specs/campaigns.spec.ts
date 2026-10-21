import { test, expect } from "@playwright/test";
import { openLive, unique } from "./support";

test("the campaigns: the seeded sequence, its steps and its preview", async ({ page }) => {
  await openLive(page, "/admin/news/campaigns?as=admin");
  await page.locator(".ta-campaign-row", { hasText: "Welcome to Atelier" }).click();
  await expect(page.getByRole("heading", { name: "Steps" })).toBeVisible();
  await expect(page.locator(".ta-step")).toHaveCount(3);

  await page.getByRole("tab", { name: "Preview" }).click();
  await expect(page.frameLocator(".ta-letter-frame").getByText("Your studio has a home now.")).toBeVisible();
});

test("a segment, written in the condition builder, counts its people as it changes", async ({ page }) => {
  await openLive(page, "/admin/news/audience/new?as=admin");
  await expect(page.locator(".ta-conditions-count")).toContainText("30 people");

  await page.getByRole("button", { name: "Add a rule" }).click();
  await page.getByLabel("What the rule tests").selectOption({ label: "Plan" });
  await page.locator(".ta-rule-pick", { hasText: "Studio" }).click();
  await expect(page.locator(".ta-conditions-sentence")).toHaveText("Plan is Studio.");
  await expect(page.locator(".ta-conditions-count")).toContainText("5 people");

  const name = unique("Studios");
  await page.getByLabel("Name").fill(name);
  await page.getByRole("button", { name: "Save segment" }).click();
  await expect(page.getByText(`“${name}” is saved.`)).toBeVisible();
});

test("a read-only admin sees the campaigns and changes nothing", async ({ page }) => {
  await openLive(page, "/admin/news/campaigns?as=viewer");
  await expect(page.getByRole("link", { name: "New broadcast" })).toHaveCount(0);
  await page.locator(".ta-campaign-row").first().click();
  await expect(page.getByRole("button", { name: "Pause" })).toHaveCount(0);
});
