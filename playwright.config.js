const { defineConfig } = require("@playwright/test");
const path = require("path");

const port = Number(process.env.E2E_PORT || 4003);
const e2eEnv = {
  ...process.env,
  PORT: String(port),
  DATABASE_PATH: path.resolve("tmp/e2e/inkit_e2e.db"),
  UPLOAD_DIR: path.resolve("tmp/e2e/uploads"),
};

module.exports = defineConfig({
  testDir: "./test/e2e",
  timeout: 30_000,
  expect: {
    timeout: 5_000,
  },
  use: {
    baseURL: `http://localhost:${port}`,
    viewport: { width: 1440, height: 1000 },
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  webServer: {
    command: "mix ecto.setup && mix phx.server",
    env: e2eEnv,
    url: `http://localhost:${port}`,
    reuseExistingServer: false,
    timeout: 120_000,
  },
});
