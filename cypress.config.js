// Cypress config is intentionally JS (not TS) so it loads in minimal container
// environments without requiring a TS runtime.

const runtimeStore = new Map();

const TRUE_TOKENS = new Set(["1", "true", "yes", "y", "on"]);
const FALSE_TOKENS = new Set(["0", "false", "no", "n", "off"]);

function normalizeEnv(value) {
  if (value === undefined || value === null) return null;
  const s = String(value).trim().toLowerCase();
  return s === "" ? null : s;
}

function parseBoolToken(s) {
  if (TRUE_TOKENS.has(s)) return true;
  if (FALSE_TOKENS.has(s)) return false;
  return null;
}

function resolveBooleanEnv(value, defaultValue) {
  const s = normalizeEnv(value);
  if (s === null) return defaultValue;
  const b = parseBoolToken(s);
  return b === null ? defaultValue : b;
}

function resolveVideoCompressionEnv(value, defaultValue) {
  const s = normalizeEnv(value);
  if (s === null) return defaultValue;

  const b = parseBoolToken(s);
  if (b !== null) return b;

  const n = Number(s);
  if (Number.isInteger(n) && n >= 1 && n <= 51) return n;

  return defaultValue;
}

module.exports = {
  video: resolveBooleanEnv(process.env.CYPRESS_video, true),
  videoCompression: resolveVideoCompressionEnv(process.env.CYPRESS_videoCompression, true),
  allowCypressEnv: false,
  expose: {
    receiver_baseUrl: process.env.CYPRESS_receiver_baseUrl,
    proof_cell: process.env.CYPRESS_proof_cell,
    idp_origin: process.env.CYPRESS_idp_origin,
    idp_realm: process.env.CYPRESS_idp_realm,
  },
  e2e: {
    specPattern: "cypress/e2e/**/*.cy.ts",
    supportFile: "cypress/support/e2e.ts",
    baseUrl: process.env.CYPRESS_BASE_URL || process.env.CYPRESS_baseUrl,
    // Keep Cypress default test isolation ON explicitly: it clears cookies in
    // all domains between tests, which is the boundary that drops a shared/external
    // IdP SSO cookie so a later test logs in as the intended user.
    testIsolation: true,
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
