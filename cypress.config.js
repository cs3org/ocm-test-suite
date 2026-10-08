// Cypress config is intentionally JS (not TS) so it loads in minimal container
// environments without requiring a TS runtime.

const path = require("node:path");
const fs = require("node:fs");

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

const { createLaunchProbe } = require("./cypress.config.launch-probe.cjs");
const launchDiagnostics = resolveBooleanEnv(process.env.OCMTS_WEBAPP_LAUNCH_DIAGNOSTICS, false);
const browserExperiment = resolveBooleanEnv(process.env.OCMTS_WEBAPP_BROWSER_EXPERIMENT, false);
const requestReplay = resolveBooleanEnv(process.env.OCMTS_WEBAPP_REQUEST_REPLAY, true);

module.exports = {
  video: resolveBooleanEnv(process.env.CYPRESS_video, true),
  videoCompression: resolveVideoCompressionEnv(process.env.CYPRESS_videoCompression, true),
  allowCypressEnv: false,
  expose: {
    receiver_baseUrl: process.env.CYPRESS_receiver_baseUrl,
    proof_cell: process.env.CYPRESS_proof_cell,
    sender_idp_origin: process.env.CYPRESS_sender_idp_origin,
    sender_idp_realm: process.env.CYPRESS_sender_idp_realm,
    receiver_idp_origin: process.env.CYPRESS_receiver_idp_origin,
    receiver_idp_realm: process.env.CYPRESS_receiver_idp_realm,
    webapp_launch_diagnostics: launchDiagnostics,
    webapp_request_replay: requestReplay,
  },
  e2e: {
    ...(browserExperiment ? { chromeWebSecurity: false } : {}),
    specPattern: "cypress/e2e/**/*.cy.ts",
    supportFile: "cypress/support/e2e.ts",
    baseUrl: process.env.CYPRESS_BASE_URL || process.env.CYPRESS_baseUrl,
    // Keep Cypress default test isolation ON explicitly: it clears cookies in
    // all domains between tests, which is the boundary that drops a shared/external
    // IdP SSO cookie so a later test logs in as the intended user.
    testIsolation: true,
    setupNodeEvents(on, config) {
      const probe = createLaunchProbe(config);
      on("before:browser:launch", (browser, launchOptions) => {
        const chrome = browser.family === "chromium" && browser.name !== "electron";
        if (launchDiagnostics && !chrome) {
          throw new Error("Launch diagnostics require Chrome");
        }
        if (chrome) {
          if (browserExperiment && !launchOptions.args.includes("--disable-http-cache")) {
            launchOptions.args.push("--disable-http-cache");
          }
          if (launchDiagnostics) probe.capturePort(launchOptions.args);
        }
        return launchOptions;
      });
      on("after:run", () => probe.stop());
      on("task", {
        "launch-probe:start"(payload) {
          return launchDiagnostics ? probe.start(payload?.attempt) : null;
        },
        "launch-probe:stop"() {
          return probe.finish();
        },
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

      // Retries suffix screenshots with ' (attempt n)'; strip it so explicit evidence
      // screenshots keep deterministic names per the evidence standard; ' (failed)' markers are preserved.
      on("after:screenshot", (details) => {
        const dir = path.dirname(details.path);
        const base = path.basename(details.path);
        const cleanedBase = base.replace(/\s*\(attempt\s+\d+\)\s*/g, "");
        if (cleanedBase === base) {
          return undefined;
        }
        const cleanPath = path.join(dir, cleanedBase);
        try {
          fs.unlinkSync(cleanPath);
        } catch (error) {
          if (error.code !== "ENOENT") throw error;
        }
        fs.renameSync(details.path, cleanPath);
        return { path: cleanPath };
      });

      return config;
    },
  },
};
