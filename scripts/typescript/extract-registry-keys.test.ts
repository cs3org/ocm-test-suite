// Smoke tests for extract-registry-keys.ts.
//
// Run:
//   bun test scripts/typescript/extract-registry-keys.test.ts
//
// Tests use the actual registry.ts as the canonical fixture. A no-tables
// fixture is written to a temp file for the error-path test.

import { test, expect, describe } from "bun:test";
import * as path from "node:path";
import { unlinkSync, writeFileSync } from "node:fs";

const REGISTRY_PATH = path.resolve(
  import.meta.dir,
  "../../cypress/support/adapters/registry.ts",
);

const SCRIPT_PATH = path.resolve(import.meta.dir, "extract-registry-keys.ts");

// Expected sorted table names as of the current registry.ts.
// Update this list when new adapter tables are added to registry.ts.
const EXPECTED_TABLES = [
  "contactTokenReceiverAdapters",
  "contactTokenSenderAdapters",
  "contactWayfReceiverAdapters",
  "contactWayfSenderAdapters",
  "loginAdapters",
  "providerIdentityAdapters",
  "shareFileReceiverAdapters",
  "shareFileSenderAdapters",
  "shareWithFlowReceiverAdapters",
  "shareWithFlowSenderAdapters",
];

async function runScript(
  args: string[],
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const proc = Bun.spawn(["bun", "run", SCRIPT_PATH, ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;
  return { stdout, stderr, exitCode };
}

describe("extract-registry-keys", () => {
  test("exits 0 and emits valid JSON for real registry.ts", async () => {
    const { stdout, stderr, exitCode } = await runScript([REGISTRY_PATH]);
    expect(exitCode).toBe(0);
    expect(stderr).toBe("");
    const parsed = JSON.parse(stdout);
    expect(typeof parsed).toBe("object");
    expect(Array.isArray(parsed.tables)).toBe(true);
  });

  test("tables field matches expected sorted list", async () => {
    const { stdout, exitCode } = await runScript([REGISTRY_PATH]);
    expect(exitCode).toBe(0);
    const parsed = JSON.parse(stdout);
    expect(parsed.tables).toEqual(EXPECTED_TABLES);
  });

  test("tables field is sorted", async () => {
    const { stdout, exitCode } = await runScript([REGISTRY_PATH]);
    expect(exitCode).toBe(0);
    const parsed = JSON.parse(stdout);
    const sorted = [...parsed.tables].sort((a: string, b: string) =>
      a.localeCompare(b),
    );
    expect(parsed.tables).toEqual(sorted);
  });

  test("output is deterministic across two runs", async () => {
    const [r1, r2] = await Promise.all([
      runScript([REGISTRY_PATH]),
      runScript([REGISTRY_PATH]),
    ]);
    expect(r1.exitCode).toBe(0);
    expect(r2.exitCode).toBe(0);
    expect(r1.stdout).toEqual(r2.stdout);
  });

  test("per-table entries are sorted and present for each table", async () => {
    const { stdout, exitCode } = await runScript([REGISTRY_PATH]);
    expect(exitCode).toBe(0);
    const parsed = JSON.parse(stdout);
    for (const table of parsed.tables as string[]) {
      const entries: unknown = parsed[table];
      expect(Array.isArray(entries)).toBe(true);
      const arr = entries as string[];
      const sorted = [...arr].sort((a, b) => a.localeCompare(b));
      expect(arr).toEqual(sorted);
      for (const e of arr) {
        // Each entry should be "platform/version" with no spaces.
        expect(e).toMatch(/^[^\s/]+\/[^\s/]+$/);
      }
    }
  });

  test("loginAdapters contains all expected platform/version entries", async () => {
    const { stdout, exitCode } = await runScript([REGISTRY_PATH]);
    expect(exitCode).toBe(0);
    const parsed = JSON.parse(stdout);
    expect(parsed.loginAdapters).toEqual([
      "cernbox/v11",
      "nextcloud/v32",
      "nextcloud/v33",
      "nextcloud/v34",
      "ocis/v8",
      "ocmgo/v1",
      "opencloud/v6",
    ]);
  });

  test("exits 2 with error message when no argument given", async () => {
    const { stderr, exitCode } = await runScript([]);
    expect(exitCode).toBe(2);
    expect(stderr).toContain("[extract-registry-keys] ERROR:");
  });

  test("exits 2 with error message for nonexistent file", async () => {
    const { stderr, exitCode } = await runScript(["/nonexistent/registry.ts"]);
    expect(exitCode).toBe(2);
    expect(stderr).toContain("[extract-registry-keys] ERROR:");
  });

  test("exits 2 when registry has no Adapters-named consts", async () => {
    const tmpPath = path.resolve(
      import.meta.dir,
      "__fixture_no_adapters.ts",
    );
    writeFileSync(tmpPath, "export const foo = 1;\n");
    try {
      const { stderr, exitCode } = await runScript([tmpPath]);
      expect(exitCode).toBe(2);
      expect(stderr).toContain("[extract-registry-keys] ERROR:");
      expect(stderr).toContain("no adapter tables discovered");
    } finally {
      unlinkSync(tmpPath);
    }
  });
});
