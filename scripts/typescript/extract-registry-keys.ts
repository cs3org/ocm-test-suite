// Input: one CLI arg -- path to a registry.ts source file.
// Output: a single-line JSON record mapping each of the 8 adapter table names
// to a sorted array of "platform/version" strings extracted from its AST.
// Exit 0 on success; exit 2 on argument or parse error (message to stderr).

import * as path from "node:path";
import * as ts from "typescript";

const TABLE_NAMES = [
  "loginAdapters",
  "shareWithSenderAdapters",
  "shareWithReceiverAdapters",
  "contactTokenSenderAdapters",
  "contactTokenReceiverAdapters",
  "contactWayfSenderAdapters",
  "contactWayfReceiverAdapters",
  "providerIdentityAdapters",
] as const;

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
  const out: Record<string, string[]> = {};
  for (const table of TABLE_NAMES) {
    out[table] = extractTable(src, table, basename);
  }
  process.stdout.write(JSON.stringify(out) + "\n");
}

main();
