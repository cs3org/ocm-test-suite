// Extract adapter table names and their platform/version keys from a
// registry.ts source file using the TypeScript Compiler API.
//
// Usage:
//   bun run scripts/typescript/extract-registry-keys.ts <path/to/registry.ts>
//
// Output (single-line JSON to stdout):
//   {
//     "tables": ["<tableName>", ...],              // sorted; SSOT for table names
//     "<tableName>": ["<platform>/<version>", ...] // one entry per table (sorted)
//     ...
//   }
//
// "tables" is the authoritative sorted list of all adapter table names
// discovered in the registry source file. The Nushell registry-bound-
// capabilities check (scripts/lib/matrix/check/registry-cross.nu) can compare
// this list against its own REGISTRY_TABLE_CAPABILITY mapping to detect drift
// without maintaining a second hardcoded allowlist.
//
// Per-table fields are unchanged from the original output shape, so existing
// Nushell consumers remain compatible.
//
// Discovery rule: a top-level `const` declaration whose name ends with
// "Adapters" and whose initializer is an object literal. This matches all
// adapter tables in registry.ts without requiring a hardcoded name list.
//
// Exit codes: 0 success, 2 argument or parse error (message written to stderr).

import * as path from "node:path";
import * as ts from "typescript";

function fail(msg: string): never {
  process.stderr.write(`[extract-registry-keys] ERROR: ${msg}\n`);
  process.exit(2);
}

function getPropNameText(name: ts.PropertyName): string | undefined {
  if (
    ts.isIdentifier(name) ||
    ts.isStringLiteral(name) ||
    ts.isNumericLiteral(name) ||
    ts.isNoSubstitutionTemplateLiteral(name)
  ) {
    return name.text;
  }
  return undefined;
}

// Discovers all adapter table names by scanning for top-level `const`
// declarations whose name ends with "Adapters" and whose initializer is an
// object literal. Returns names in sorted order.
function discoverTableNames(sourceFile: ts.SourceFile): string[] {
  const names: string[] = [];
  for (const stmt of sourceFile.statements) {
    if (!ts.isVariableStatement(stmt)) continue;
    if (!(stmt.declarationList.flags & ts.NodeFlags.Const)) continue;
    for (const decl of stmt.declarationList.declarations) {
      if (!ts.isIdentifier(decl.name)) continue;
      const name = decl.name.text;
      if (!name.endsWith("Adapters")) continue;
      if (!decl.initializer || !ts.isObjectLiteralExpression(decl.initializer)) continue;
      names.push(name);
    }
  }
  return names.sort((a, b) => a.localeCompare(b));
}

function extractTable(
  sourceFile: ts.SourceFile,
  tableName: string,
  basename: string,
): string[] {
  for (const stmt of sourceFile.statements) {
    if (!ts.isVariableStatement(stmt)) continue;
    for (const decl of stmt.declarationList.declarations) {
      if (!ts.isIdentifier(decl.name) || decl.name.text !== tableName) continue;
      const init = decl.initializer;
      if (!init || !ts.isObjectLiteralExpression(init)) {
        fail(`${basename}: ${tableName} must be an object literal`);
      }
      const keys: string[] = [];
      for (const outer of init.properties) {
        if (!ts.isPropertyAssignment(outer)) continue;
        const outerName = getPropNameText(outer.name);
        if (!outerName) continue;
        const outerInit = outer.initializer;
        if (!ts.isObjectLiteralExpression(outerInit)) {
          fail(`${basename}: ${tableName}.${outerName} must be an object literal`);
        }
        for (const inner of outerInit.properties) {
          if (!ts.isPropertyAssignment(inner)) continue;
          const innerName = getPropNameText(inner.name);
          if (!innerName) continue;
          keys.push(`${outerName}/${innerName}`);
        }
      }
      keys.sort((a, b) => a.localeCompare(b));
      return keys;
    }
  }
  fail(`${basename}: table not found: ${tableName}`);
}

async function main(): Promise<void> {
  const arg = process.argv[2];
  if (!arg) fail("usage: extract-registry-keys.ts <path/to/registry.ts>");

  const absPath = path.resolve(arg);
  const basename = path.basename(absPath);

  let text: string;
  try {
    text = await Bun.file(absPath).text();
  } catch (e) {
    fail(`${basename}: cannot read file: ${(e as Error).message}`);
  }

  const src = ts.createSourceFile(
    absPath,
    text,
    ts.ScriptTarget.ESNext,
    true,
    ts.ScriptKind.TS,
  );

  const tableNames = discoverTableNames(src);
  if (tableNames.length === 0) {
    fail(
      `${basename}: no adapter tables discovered` +
        ` (expected top-level const declarations ending in "Adapters")`,
    );
  }

  const out: Record<string, string[]> = { tables: tableNames };
  for (const table of tableNames) {
    out[table] = extractTable(src, table, basename);
  }
  process.stdout.write(JSON.stringify(out) + "\n");
}

main();
