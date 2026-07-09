/// <reference types="cypress" />

// Generic MITM traffic oracle. The mitmproxy sidecar appends one JSON object
// per intercepted request to traffic.jsonl. This module parses that log and
// asserts that a set of flow-specific expectations appear in it. Flow-specific
// expectations (which requests prove a given handoff) live in the flow that
// owns them, not here.

export const MITM_TRAFFIC_PATH = "/artifacts/mitm/flows/traffic.jsonl";

export type MitmTrafficBody = {
  preview?: string | null;
};

export type MitmTrafficRecord = {
  request: {
    method?: string | null;
    path?: string | null;
    url?: string | null;
    host?: string | null;
  };
  response?: {
    status_code?: number | null;
    headers?: Record<string, string> | null;
    body?: MitmTrafficBody | null;
  };
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parseMitmTrafficJsonl(content: string): MitmTrafficRecord[] {
  const records: MitmTrafficRecord[] = [];

  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.length === 0) {
      continue;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      continue;
    }

    if (!isRecord(parsed) || !isRecord(parsed.request)) {
      continue;
    }

    const request = parsed.request;
    const response = isRecord(parsed.response) ? parsed.response : undefined;

    records.push({
      request: {
        method: typeof request.method === "string" ? request.method : null,
        path: typeof request.path === "string" ? request.path : null,
        url: typeof request.url === "string" ? request.url : null,
        host: typeof request.host === "string" ? request.host : null,
      },
      response:
        response === undefined
          ? undefined
          : {
              status_code:
                typeof response.status_code === "number"
                  ? response.status_code
                  : null,
              headers: isRecord(response.headers)
                ? (response.headers as Record<string, string>)
                : null,
              body: isRecord(response.body)
                ? {
                    preview:
                      typeof response.body.preview === "string"
                        ? response.body.preview
                        : null,
                  }
                : null,
            },
    });
  }

  return records;
}

// Number of records already present before an attempt, so assertions can ignore
// stale entries left in the shared log by earlier retries. Record-count based
// rather than byte-offset based so it never splits a partially written line.
export type MitmTrafficScopeMarker = {
  afterCount: number;
};

export function captureMitmTrafficScopeMarker(): Cypress.Chainable<MitmTrafficScopeMarker> {
  return cy.readFile(MITM_TRAFFIC_PATH, { log: false }).then((content) => ({
    afterCount: parseMitmTrafficJsonl(String(content)).length,
  }));
}

export function recordsAfterMarker(
  content: string,
  marker: MitmTrafficScopeMarker,
): MitmTrafficRecord[] {
  return parseMitmTrafficJsonl(content).slice(marker.afterCount);
}

export type MitmExpectation = {
  label: string;
  predicate: (record: MitmTrafficRecord) => boolean;
};

export function findUnmetExpectations(
  records: MitmTrafficRecord[],
  expectations: MitmExpectation[],
): string[] {
  return expectations
    .filter((expectation) => !records.some(expectation.predicate))
    .map((expectation) => expectation.label);
}

export function summarizeScopedMitmTraffic(
  records: MitmTrafficRecord[],
  options?: { limit?: number },
): string {
  const limit = options?.limit ?? 12;
  if (records.length === 0) {
    return "(no scoped MITM records)";
  }

  const sliceStart = Math.max(0, records.length - limit);
  const lines: string[] = [];
  for (let index = sliceStart; index < records.length; index += 1) {
    const record = records[index];
    const method = record.request.method ?? "?";
    const path = record.request.path ?? record.request.url ?? "?";
    const host = record.request.host ?? "";
    const status =
      record.response?.status_code === undefined ||
      record.response?.status_code === null
        ? "?"
        : String(record.response.status_code);
    const hostPrefix = host.length > 0 ? `${host} ` : "";
    lines.push(`  ${index - sliceStart + 1}. ${method} ${hostPrefix}${path} -> ${status}`);
  }

  const omitted = records.length - lines.length;
  const header =
    omitted > 0
      ? `Scoped MITM records (${records.length} total, showing last ${lines.length}, ${omitted} earlier omitted):`
      : `Scoped MITM records (${records.length} total):`;

  return [header, ...lines].join("\n");
}

function formatMitmExpectationFailure(
  title: string,
  missing: string[],
  records: MitmTrafficRecord[],
): string {
  return [
    `${title}: MITM traffic is missing expected legs: ${missing.join(", ")}`,
    summarizeScopedMitmTraffic(records),
  ].join("\n\n");
}

// Re-reads traffic.jsonl until every expectation is met or the timeout elapses.
// Cypress retries the readFile assertion callback when it throws. Pass a marker
// to scope assertions to records appended after a specific attempt.
export function assertMitmExpectations(options: {
  expectations: MitmExpectation[];
  title: string;
  marker?: MitmTrafficScopeMarker;
  timeoutMs?: number;
}): Cypress.Chainable<void> {
  const { expectations, title, marker } = options;
  const timeoutMs = options.timeoutMs ?? 60000;

  return cy
    .readFile(MITM_TRAFFIC_PATH, { log: false, timeout: timeoutMs })
    .should((content) => {
      const text = String(content);
      const records =
        marker === undefined
          ? parseMitmTrafficJsonl(text)
          : recordsAfterMarker(text, marker);
      const missing = findUnmetExpectations(records, expectations);
      if (missing.length > 0) {
        throw new Error(formatMitmExpectationFailure(title, missing, records));
      }
    })
    .then(() => undefined);
}
