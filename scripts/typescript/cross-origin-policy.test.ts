// Static AST enforcement for cy.origin() call sites.
//
// Run:
//   bun test scripts/typescript/cross-origin-policy.test.ts

import { describe, expect, test } from "bun:test";
import * as path from "node:path";
import * as ts from "typescript";
import { CROSS_ORIGIN_ALLOWED_CALL_SITE_FILES } from "../../cypress/support/shared/cross-origin-policy";

const REPO_ROOT = path.resolve(import.meta.dir, "../..");
const CYPRESS_DIR = path.join(REPO_ROOT, "cypress");

function isCyOriginCall(node: ts.Node): boolean {
  if (!ts.isCallExpression(node)) return false;
  const expr = node.expression;
  if (!ts.isPropertyAccessExpression(expr)) return false;
  if (expr.name.text !== "origin") return false;
  const obj = expr.expression;
  if (!ts.isIdentifier(obj)) return false;
  return obj.text === "cy";
}

function fileContainsCyOriginCall(sourceFile: ts.SourceFile): boolean {
  let found = false;
  function visit(node: ts.Node): void {
    if (found) return;
    if (isCyOriginCall(node)) {
      found = true;
      return;
    }
    ts.forEachChild(node, visit);
  }
  visit(sourceFile);
  return found;
}

async function enumerateCypressTsFiles(): Promise<string[]> {
  const glob = new Bun.Glob("**/*.ts");
  const files: string[] = [];
  for await (const rel of glob.scan({ cwd: CYPRESS_DIR, absolute: false })) {
    const normalized = rel.split(path.sep).join("/");
    files.push(`cypress/${normalized}`);
  }
  return files.sort((a, b) => a.localeCompare(b));
}

async function collectCyOriginCallSiteFiles(): Promise<string[]> {
  const files = await enumerateCypressTsFiles();
  const callSites: string[] = [];
  for (const relPath of files) {
    const absPath = path.join(REPO_ROOT, relPath);
    const text = await Bun.file(absPath).text();
    const sourceFile = ts.createSourceFile(
      absPath,
      text,
      ts.ScriptTarget.ESNext,
      true,
      ts.ScriptKind.TS,
    );
    if (fileContainsCyOriginCall(sourceFile)) {
      callSites.push(relPath);
    }
  }
  return callSites.sort((a, b) => a.localeCompare(b));
}

function formatMismatchMessage(
  actual: readonly string[],
  expected: readonly string[],
): string {
  const expectedSet = new Set(expected);
  const actualSet = new Set(actual);
  const extra = actual.filter((f) => !expectedSet.has(f));
  const missing = expected.filter((f) => !actualSet.has(f));
  const lines: string[] = ["cy.origin() call-site allowlist drift detected.", ""];
  if (extra.length > 0) {
    lines.push(
      "EXTRA call-site files (new cy.origin usage - remove it or add to CROSS_ORIGIN_ALLOWED_CALL_SITE_FILES):",
    );
    for (const f of extra) lines.push(`  - ${f}`);
    lines.push("");
  }
  if (missing.length > 0) {
    lines.push(
      "MISSING files (allowed but no cy.origin call - remove from allowlist):",
    );
    for (const f of missing) lines.push(`  - ${f}`);
    lines.push("");
  }
  return lines.join("\n");
}

describe("cross-origin-policy AST enforcement", () => {
  test("cy.origin call sites match CROSS_ORIGIN_ALLOWED_CALL_SITE_FILES", async () => {
    const actual = await collectCyOriginCallSiteFiles();
    const expected = [...CROSS_ORIGIN_ALLOWED_CALL_SITE_FILES].sort((a, b) =>
      a.localeCompare(b),
    );

    if (
      actual.length !== expected.length ||
      actual.some((file, index) => file !== expected[index])
    ) {
      throw new Error(formatMismatchMessage(actual, expected));
    }

    expect(actual).toEqual(expected);
  });
});
