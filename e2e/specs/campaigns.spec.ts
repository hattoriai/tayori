import { test, expect } from "@playwright/test";
import { openLive, unique } from "./support";

test("the campaigns: the seeded sequence, its steps and its preview", async ({ page }) => {
  await openLive(page, "/admin/news/campaigns?as=admin");
  await page.locator(".ta-campaign-row", { hasText: "Welcome to Atelier" }).click();
  await expect(page.getByRole("heading", { name: "Steps" })).toBeVisible();
  await expect(page.locator(".ta-step")).toHaveCount(3);

  await page.getByRole("tab", { name: "Preview" }).click();
  await expect(page.frameLocator(".ta-letter-frame").getByText("Your studio has a home now.")).toBeVisible();
  // The test goes to the admin's own address, from the app's author/1.
  await expect(page.locator("#test-address")).toHaveValue("hanzo@atelier.test");
});

test("a step with changes not saved asks before another opens", async ({ page }) => {
  await openLive(page, "/admin/news/campaigns?as=admin");
  await page.locator(".ta-campaign-row", { hasText: "Welcome to Atelier" }).click();

  // Opened and left as it was (the letter's editor loaded): no question.
  await page.getByRole("button", { name: "Edit step 1" }).click();
  await expect(page.locator("#step-form")).toBeVisible();
  await page.getByRole("button", { name: "Edit step 2" }).click();
  await expect(page.getByText("Step 2 goes after")).toBeVisible();
  await expect(page.locator("#leaving")).toHaveCount(0);

  // Changed: the card asks, and keeps the change while one writes on.
  const subject = page.locator("#step-form input[name$='[subject]']").first();
  await subject.fill("A changed subject");
  await page.getByRole("button", { name: "Edit step 1" }).click();
  await expect(page.locator("#leaving")).toContainText("changes that are not saved");
  await page.getByRole("button", { name: "Keep writing" }).click();
  await expect(subject).toHaveValue("A changed subject");

  await page.getByRole("button", { name: "Edit step 1" }).click();
  await page.getByRole("button", { name: "Leave the changes" }).click();
  await expect(page.getByText("Step 1 goes after")).toBeVisible();
  await expect(page.locator(".ta-step-subject", { hasText: "A changed subject" })).toHaveCount(0);
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
