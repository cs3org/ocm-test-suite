// Cypress config is intentionally JS (not TS) so it loads in minimal container
// environments without requiring a TS runtime.

const runtimeStore = new Map();

function resolveBooleanEnv(value, defaultValue) {
  if (value === undefined || value === null || String(value).trim() === "") {
    return defaultValue;
  }

  switch (String(value).trim().toLowerCase()) {
    case "1":
    case "true":
    case "yes":
    case "y":
    case "on":
      return true;
    case "0":
    case "false":
    case "no":
    case "n":
    case "off":
      return false;
    default:
      return defaultValue;
  }
}

module.exports = {
  video: resolveBooleanEnv(process.env.CYPRESS_video, true),
  allowCypressEnv: false,
  expose: {
    receiver_baseUrl: process.env.CYPRESS_receiver_baseUrl,
  },
  e2e: {
    specPattern: "cypress/e2e/**/*.cy.ts",
    supportFile: "cypress/support/e2e.ts",
    baseUrl: process.env.CYPRESS_BASE_URL || process.env.CYPRESS_baseUrl,
    setupNodeEvents(on, config) {
      on("task", {
        "runtime:clear"() {
          runtimeStore.clear();
          return null;
        },
        "runtime:set"(payload) {
          if (!payload || typeof payload.key !== "string") {
            throw new Error(
              "runtime:set requires a payload object with a string key and any value",
            );
          }
          runtimeStore.set(payload.key, payload.value);
          return null;
        },
        "runtime:get"(payload) {
          if (!payload || typeof payload.key !== "string") {
            throw new Error(
              "runtime:get requires a payload object with a string key",
            );
          }
          const value = runtimeStore.get(payload.key);
          return value === undefined ? null : value;
        },
      });

      return config;
    },
  },
};
