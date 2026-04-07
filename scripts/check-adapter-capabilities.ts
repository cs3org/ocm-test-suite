import * as fs from "node:fs/promises";
import * as path from "node:path";
import * as ts from "typescript";

type Capability = "login" | "share-with.sender" | "share-with.receiver";

type AdapterCapabilitiesJsonV1 = {
  schema_version: 1;
  adapters: Record<string, Capability[]>;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseAdapterCapabilitiesJsonV1(raw: string): AdapterCapabilitiesJsonV1 {
  const parsed: unknown = JSON.parse(raw);
  if (!isRecord(parsed)) {
    throw new Error("Top-level JSON value must be an object.");
  }

  const schemaVersion = parsed["schema_version"];
  if (schemaVersion !== 1) {
    throw new Error(
      `Unsupported schema_version: ${JSON.stringify(schemaVersion)} (expected 1).`,
    );
  }

  const adapters = parsed["adapters"];
  if (!isRecord(adapters)) {
    throw new Error('"adapters" must be an object.');
  }

  const out: Record<string, Capability[]> = {};
  for (const [key, value] of Object.entries(adapters)) {
    if (!Array.isArray(value) || !value.every((v) => typeof v === "string")) {
      throw new Error(`"adapters.${key}" must be an array of strings.`);
    }

    const caps: Capability[] = [];
    for (const cap of value) {
      if (cap !== "login" && cap !== "share-with.sender" && cap !== "share-with.receiver") {
        throw new Error(
          `"adapters.${key}" has unknown capability: ${JSON.stringify(cap)}.`,
        );
      }
      caps.push(cap);
    }
    out[key] = caps;
  }

  return { schema_version: 1, adapters: out };
}

function getPropNameText(name: ts.PropertyName): string | undefined {
  if (ts.isIdentifier(name)) return name.text;
  if (ts.isStringLiteral(name) || ts.isNumericLiteral(name)) return name.text;
  if (ts.isNoSubstitutionTemplateLiteral(name)) return name.text;
  return undefined;
}

function extractAdapterKeysFromTable(
  sourceFile: ts.SourceFile,
  tableName: string,
): Set<string> {
  const keys = new Set<string>();

  for (const stmt of sourceFile.statements) {
    if (!ts.isVariableStatement(stmt)) continue;

    for (const decl of stmt.declarationList.declarations) {
      if (!ts.isIdentifier(decl.name) || decl.name.text !== tableName) continue;
      const init = decl.initializer;
      if (!init || !ts.isObjectLiteralExpression(init)) {
        throw new Error(`[registry] ${tableName} must be an object literal.`);
      }

      for (const outerProp of init.properties) {
        if (!ts.isPropertyAssignment(outerProp)) continue;
        const outerName = getPropNameText(outerProp.name);
        if (!outerName) continue;
        const outerInit = outerProp.initializer;
        if (!ts.isObjectLiteralExpression(outerInit)) {
          throw new Error(`[registry] ${tableName}.${outerName} must be an object literal.`);
        }

        for (const innerProp of outerInit.properties) {
          if (!ts.isPropertyAssignment(innerProp)) continue;
          const innerName = getPropNameText(innerProp.name);
          if (!innerName) continue;
          keys.add(`${outerName}/${innerName}`);
        }
      }

      return keys;
    }
  }

  throw new Error(`[registry] Missing expected table: ${tableName}`);
}

function toSortedUnique(xs: readonly string[]): string[] {
  return Array.from(new Set(xs)).sort((a, b) => a.localeCompare(b));
}

function setDiff(a: ReadonlySet<string>, b: ReadonlySet<string>): string[] {
  const out: string[] = [];
  a.forEach((x) => {
    if (!b.has(x)) out.push(x);
  });
  out.sort((l, r) => l.localeCompare(r));
  return out;
}

async function main(): Promise<number> {
  const scriptPath = process.argv[1];
  if (!scriptPath) {
    throw new Error("Missing script path in argv[1].");
  }
  const scriptDir = path.dirname(path.resolve(scriptPath));
  const repoRoot = path.resolve(scriptDir, "..");

  const jsonPath = path.join(
    repoRoot,
    "cypress",
    "support",
    "adapters",
    "adapter-capabilities.v1.json",
  );
  const registryPath = path.join(repoRoot, "cypress", "support", "adapters", "registry.ts");

  const [jsonRaw, registryRaw] = await Promise.all([
    fs.readFile(jsonPath, "utf8"),
    fs.readFile(registryPath, "utf8"),
  ]);

  const capabilitiesJson = parseAdapterCapabilitiesJsonV1(jsonRaw);

  const sourceFile = ts.createSourceFile(
    registryPath,
    registryRaw,
    ts.ScriptTarget.ESNext,
    true,
    ts.ScriptKind.TS,
  );

  const loginKeys = extractAdapterKeysFromTable(sourceFile, "loginAdapters");
  const senderKeys = extractAdapterKeysFromTable(sourceFile, "shareWithSenderAdapters");
  const receiverKeys = extractAdapterKeysFromTable(sourceFile, "shareWithReceiverAdapters");

  const expected = new Map<string, Set<Capability>>();
  const addCap = (key: string, cap: Capability) => {
    const set = expected.get(key) ?? new Set<Capability>();
    set.add(cap);
    expected.set(key, set);
  };

  Array.from(loginKeys).forEach((key) => addCap(key, "login"));
  Array.from(senderKeys).forEach((key) => addCap(key, "share-with.sender"));
  Array.from(receiverKeys).forEach((key) => addCap(key, "share-with.receiver"));

  const expectedKeys = new Set(expected.keys());
  const jsonKeys = new Set(Object.keys(capabilitiesJson.adapters));

  const missingKeys = setDiff(expectedKeys, jsonKeys);
  const extraKeys = setDiff(jsonKeys, expectedKeys);

  const mismatches: Array<{
    key: string;
    expected: string[];
    actual: string[];
    notes?: string[];
  }> = [];

  for (const key of Array.from(expectedKeys).sort((a, b) => a.localeCompare(b))) {
    const expectedCaps = toSortedUnique(Array.from(expected.get(key) ?? []));
    const actualRaw = capabilitiesJson.adapters[key];
    if (!actualRaw) continue; // missing handled above
    const actualCaps = toSortedUnique(actualRaw);

    const notes: string[] = [];
    if (actualRaw.length !== actualCaps.length) {
      notes.push("JSON contains duplicate capability entries.");
    }

    const expectedJoined = expectedCaps.join(",");
    const actualJoined = actualCaps.join(",");
    if (expectedJoined !== actualJoined) {
      mismatches.push({ key, expected: expectedCaps, actual: actualCaps, notes });
    } else if (notes.length > 0) {
      // Even if the normalized sets match, treat duplicates as drift.
      mismatches.push({ key, expected: expectedCaps, actual: actualCaps, notes });
    }
  }

  if (missingKeys.length === 0 && extraKeys.length === 0 && mismatches.length === 0) {
    process.stdout.write("[check-adapter-capabilities] OK\n");
    return 0;
  }

  process.stderr.write("[check-adapter-capabilities] Adapter capabilities drift detected.\n");

  if (missingKeys.length > 0) {
    process.stderr.write(`- Missing adapter keys in JSON (${missingKeys.length}):\n`);
    for (const k of missingKeys) process.stderr.write(`  - ${k}\n`);
  }

  if (extraKeys.length > 0) {
    process.stderr.write(`- Extra adapter keys in JSON (${extraKeys.length}):\n`);
    for (const k of extraKeys) process.stderr.write(`  - ${k}\n`);
  }

  if (mismatches.length > 0) {
    process.stderr.write(`- Capability mismatches (${mismatches.length}):\n`);
    for (const m of mismatches) {
      process.stderr.write(`  - ${m.key}\n`);
      if (m.notes && m.notes.length > 0) {
        for (const note of m.notes) process.stderr.write(`    note: ${note}\n`);
      }
      process.stderr.write(`    expected: [${m.expected.join(", ")}]\n`);
      process.stderr.write(`    actual:   [${m.actual.join(", ")}]\n`);
    }
  }

  return 1;
}

main()
  .then((code) => {
    process.exitCode = code;
  })
  .catch((err: unknown) => {
    const msg = err instanceof Error ? err.stack ?? err.message : String(err);
    process.stderr.write(`[check-adapter-capabilities] ERROR: ${msg}\n`);
    process.exitCode = 2;
  });
