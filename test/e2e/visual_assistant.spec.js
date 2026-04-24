const { test, expect } = require("@playwright/test");
const fs = require("fs");
const path = require("path");

function kitchenImagePath() {
  const demo = path.resolve("priv/demo/uploads/kitchen.jpg");

  if (fs.existsSync(demo)) {
    return demo;
  }

  const provided = path.resolve("tmp/kitchen.jpg");

  if (fs.existsSync(provided)) {
    return provided;
  }

  const fallback = path.resolve("tmp/e2e-kitchen.jpg");
  fs.mkdirSync(path.dirname(fallback), { recursive: true });

  const onePixelJpeg =
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAEFAqf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/ASP/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/ASP/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/Aqf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/ISf/2gAMAwEAAgADAAAAEP/EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8QH//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8QH//EABQQAQAAAAAAAAAAAAAAAAAAABD/2gAIAQEAAT8QH//Z";

  fs.writeFileSync(fallback, Buffer.from(onePixelJpeg, "base64"));
  return fallback;
}

function bathroomImagePath() {
  const demo = path.resolve("priv/demo/uploads/bathroom.jpg");

  if (fs.existsSync(demo)) {
    return demo;
  }

  const provided = path.resolve("tmp/bathroom.jpg");

  if (fs.existsSync(provided)) {
    return provided;
  }

  const fallback = path.resolve("tmp/e2e-bathroom.jpg");
  fs.mkdirSync(path.dirname(fallback), { recursive: true });
  fs.copyFileSync(kitchenImagePath(), fallback);
  return fallback;
}

async function waitForLiveView(page) {
  await page.waitForFunction(() => window.liveSocket?.isConnected());
  await expect(page.locator("#conversation-frame")).toBeVisible();
}

async function expectFrameHeading(page, name) {
  await expect(page.locator("#conversation-frame").getByRole("heading", { name })).toBeVisible();
}

test("uploads an image, records it as recent, and streams a chat answer", async ({ page }) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });

  await page.goto("/");
  await waitForLiveView(page);
  await page.locator("nav").getByRole("button", { name: "Conversations" }).click();
  await page.getByRole("button", { name: /^New$/ }).click();

  const imagePath = kitchenImagePath();
  const filename = path.basename(imagePath);
  let kitchenConversationId;

  await page.locator("input[type=file]").setInputFiles(imagePath);
  await expect(page.getByTestId("selected-image-preview")).toBeVisible();
  await expect(page.getByText(filename).first()).toBeVisible();
  await page.getByRole("button", { name: /upload image/i }).click();

  await expect(page.getByText(filename).first()).toBeVisible();
  await expect(page.getByText(/mock vision analysis/i)).toBeVisible();
  await expect(page.getByText(/modern farmhouse/i).first()).toBeVisible();
  await expect(page.locator("aside").getByText(filename).first()).toBeVisible();

  kitchenConversationId = await page.evaluate(() => {
    const image = document
      .querySelector("#conversation-frame img[src^='/images/']")
      ?.getAttribute("src");

    return image?.split("/").pop();
  });
  expect(kitchenConversationId).toBeTruthy();

  await page.getByPlaceholder("Ask about this image...").fill("What do you notice?");
  await page.getByPlaceholder("Ask about this image...").press("Enter");

  await expect(page.getByText(/contemporary farmhouse/i)).toBeVisible();
  await expect(page.getByText("No recent conversations.")).toHaveCount(0);
  await expect(page.getByPlaceholder("Ask about this image...")).toBeInViewport();

  await page.getByRole("button", { name: "Memory" }).click();
  await expect(page.getByText("Conversation memory")).toBeVisible();
  await expect(page.getByText("What do you notice?").first()).toBeVisible();

  await page.getByRole("button", { name: "Activity" }).click();
  await expect(page.getByRole("heading", { name: "Activity" })).toBeVisible();
  await expect(page.getByText("/live/chat").first()).toBeVisible();

  await page.locator("nav").getByRole("button", { name: "Uploads" }).click();
  await expectFrameHeading(page, "Uploads");
  await page.getByPlaceholder("Label").fill("Client kitchen concept");
  await page.getByRole("button", { name: "Save" }).click();
  await expect(page.getByText("Client kitchen concept").first()).toBeVisible();

  await page.getByRole("button", { name: "New conversation" }).click();
  await expect(page.getByRole("heading", { name: "New visual analysis" })).toBeVisible();

  const bathroomPath = bathroomImagePath();
  const bathroomFilename = path.basename(bathroomPath);

  await page.locator("input[type=file]").setInputFiles(bathroomPath);
  await expect(page.getByTestId("selected-image-preview")).toBeVisible();
  await expect(page.getByText(bathroomFilename).first()).toBeVisible();
  await expect(page.getByText(/KB|MB|bytes/).first()).toBeVisible();
  await page.getByRole("button", { name: /upload image/i }).click();
  await expect(page.getByText(/spa bath/i).first()).toBeVisible();
  await page.getByPlaceholder("Ask about this image...").fill("What style is this bathroom?");
  await page.getByPlaceholder("Ask about this image...").press("Enter");
  await expect(page.getByText(/contemporary luxury bath/i)).toBeVisible();

  await page.locator("nav").getByRole("button", { name: "Conversations" }).click();
  await expectFrameHeading(page, "Conversations");
  await expect(page.getByText("Client kitchen concept").first()).toBeVisible();
  await expect(page.getByText(bathroomFilename).first()).toBeVisible();

  await page.getByTestId(`recent-conversation-${kitchenConversationId}`).click();
  await expect(page.getByRole("heading", { name: "Client kitchen concept" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Back to conversations" })).toBeVisible();
  await page.getByRole("button", { name: "Back to conversations" }).click();
  await expectFrameHeading(page, "Conversations");
  await page.getByTestId(`recent-conversation-${kitchenConversationId}`).click();
  await expect(page.getByRole("heading", { name: "Client kitchen concept" })).toBeVisible();
  await expect(
    page.getByTestId("conversation-message-user").filter({ hasText: "What do you notice?" }),
  ).toBeVisible();
  await expect(
    page
      .getByTestId("conversation-message-user")
      .filter({ hasText: "What style is this bathroom?" }),
  ).toHaveCount(0);

  await page.locator("nav").getByRole("button", { name: "API Logs" }).click();
  await expectFrameHeading(page, "API Logs");
  await expect(page.getByText("/live/upload").first()).toBeVisible();

  await page.getByRole("button", { name: "Docs" }).click();
  await expectFrameHeading(page, "Docs");
  await expect(page.getByText("What style is this bathroom?")).toBeVisible();

  await page.locator("nav").getByRole("button", { name: "Settings" }).click();
  await expectFrameHeading(page, "Settings");
  page.once("dialog", (dialog) => dialog.accept());
  await page.getByRole("button", { name: /clear images and conversations/i }).click();
  await expect(page.getByText("No recent conversations.")).toBeVisible();

  expect(errors).toEqual([]);
});

test("mobile navigation and upload flow work", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await waitForLiveView(page);

  await page.getByRole("button", { name: "Settings" }).click();
  await expectFrameHeading(page, "Settings");

  await page.locator("nav").getByRole("button", { name: "Conversations" }).click();
  await page.getByRole("button", { name: /^New$/ }).click();

  const imagePath = kitchenImagePath();
  await page.locator("input[type=file]").setInputFiles(imagePath);
  await expect(page.getByTestId("selected-image-preview")).toBeVisible();
  await page.getByRole("button", { name: /upload image/i }).click();

  await expect(page.getByPlaceholder("Ask about this image...")).toBeEnabled();
  await expect(page.getByPlaceholder("Ask about this image...")).toBeInViewport();
});
