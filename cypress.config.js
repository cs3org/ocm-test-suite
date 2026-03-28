// Cypress config is intentionally JS (not TS) so it loads in minimal container
// environments where Cypress is installed globally and no TS runtime is present.

const runtimeStore = new Map();

module.exports = {
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
            throw new Error("runtime:set requires { key: string, value: any }");
          }
          runtimeStore.set(payload.key, payload.value);
          return null;
        },
        "runtime:get"(payload) {
          if (!payload || typeof payload.key !== "string") {
            throw new Error("runtime:get requires { key: string }");
          }
          const value = runtimeStore.get(payload.key);
          return value === undefined ? null : value;
        },
      });

      return config;
    },
  },
};
