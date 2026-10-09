import { afterEach, describe, expect, test } from "bun:test";
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const require = createRequire(import.meta.url);
const filename = require.resolve("../../cypress.config.js");
const keys = [
  "OCMTS_WEBAPP_BROWSER_EXPERIMENT",
  "OCMTS_WEBAPP_LAUNCH_DIAGNOSTICS",
  "OCMTS_WEBAPP_REQUEST_REPLAY",
];
const originals = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
const dirs: string[] = [];
afterEach(() => {
  for (const key of keys) {
    if (originals[key] === undefined) delete process.env[key];
    else process.env[key] = originals[key];
  }
  delete require.cache[filename];
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function setup(experiment = "0") {
  process.env.OCMTS_WEBAPP_BROWSER_EXPERIMENT = experiment;
  process.env.OCMTS_WEBAPP_LAUNCH_DIAGNOSTICS = "0";
  delete require.cache[filename];
  const config = require(filename);
  const events: Record<string, any> = {};
  config.e2e.setupNodeEvents((name: string, handler: any) => {
    events[name] = handler;
  }, { downloadsFolder: tmpdir() });
  return { config, events };
}

describe("launch experiment", () => {
  test("default keeps browser security and does not disable cache", () => {
    const { config, events } = setup();
    expect(config.e2e.chromeWebSecurity).toBeUndefined();
    const options = { args: ["--remote-debugging-port=1234"] };
    expect(events["before:browser:launch"]({ family: "chromium", name: "chrome" }, options)).toBe(options);
    expect(options.args).not.toContain("--disable-http-cache");
  });
  test("experiment applies Chrome cache flag once and global e2e setting", () => {
    const { config, events } = setup("1");
    expect(config.e2e.chromeWebSecurity).toBe(false);
    const options = { args: ["--remote-debugging-port=1234"] };
    events["before:browser:launch"]({ family: "chromium", name: "chrome" }, options);
    events["before:browser:launch"]({ family: "chromium", name: "chrome" }, options);
    expect(options.args.filter((arg) => arg === "--disable-http-cache")).toHaveLength(1);
    expect(options.args[0]).toBe("--remote-debugging-port=1234");
  });
  test("cache flag is not inserted for Firefox", () => {
    const { events } = setup("1");
    const options = { args: [] };
    events["before:browser:launch"]({ family: "firefox", name: "firefox" }, options);
    expect(options.args).toEqual([]);
  });
});

describe("retry evidence", () => {
  test("attempt 2 then 3 replace canonical bytes and return existing path", () => {
    const { events } = setup();
    const dir = mkdtempSync(join(tmpdir(), "ocmts-screenshot-"));
    dirs.push(dir);
    const canonical = join(dir, "cell--09--receiver--authenticated.png");
    writeFileSync(canonical, "attempt-1");
    for (const attempt of [2, 3]) {
      const retry = join(dir, "cell--09--receiver--authenticated (attempt " + attempt + ").png");
      writeFileSync(retry, "attempt-" + attempt);
      expect(events["after:screenshot"]({ path: retry })).toEqual({ path: canonical });
      expect(readFileSync(canonical, "utf8")).toBe("attempt-" + attempt);
      expect(existsSync(retry)).toBe(false);
    }
  });
  test("missing canonical succeeds; failed marker remains; unsuffixed is unchanged", () => {
    const { events } = setup();
    const dir = mkdtempSync(join(tmpdir(), "ocmts-screenshot-"));
    dirs.push(dir);
    const retry = join(dir, "launch (failed) (attempt 2).png");
    const canonical = join(dir, "launch (failed).png");
    writeFileSync(retry, "failure");
    expect(events["after:screenshot"]({ path: retry })).toEqual({ path: canonical });
    expect(readFileSync(canonical, "utf8")).toBe("failure");
    expect(events["after:screenshot"]({ path: canonical })).toBeUndefined();
    expect(readFileSync(canonical, "utf8")).toBe("failure");
  });
  test("missing retry bytes fail instead of returning a nonexistent path", () => {
    const { events } = setup();
    const dir = mkdtempSync(join(tmpdir(), "ocmts-screenshot-"));
    dirs.push(dir);
    expect(() => events["after:screenshot"]({ path: join(dir, "missing (attempt 2).png") })).toThrow();
  });
});
