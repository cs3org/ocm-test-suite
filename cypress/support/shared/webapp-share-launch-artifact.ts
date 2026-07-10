/// <reference types="cypress" />

export type NextcloudWebappShareLaunchArtifact = {
  receiverKind: "nextcloud";
  launchGate: "cross-origin-open";
  /** Absolute origin of the remote hub, extracted from the ocm/open launch HTML. */
  hubOrigin: string;
  /** The ocm/open request URL (target=redirect) that fired the launch, for reference. */
  openRequestUrl: string;
};

export type CernboxWebappShareLaunchArtifact = {
  receiverKind: "cernbox";
  launchGate: "cross-origin-open";
  /** Absolute origin of the remote hub, extracted from the open-in-app app_url. */
  hubOrigin: string;
};

export type WebappShareLaunchArtifact =
  | NextcloudWebappShareLaunchArtifact
  | CernboxWebappShareLaunchArtifact;

function decodeMinimalHtmlEntities(raw: string): string {
  return raw
    .replace(/&amp;/g, "&")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"');
}

export function extractHubLaunchOriginFromRedirectHtml(body: string): string | null {
  try {
    let raw: string | null = null;

    const formActionMatch = body.match(/action="([^"]+)"/);
    if (formActionMatch?.[1]) {
      raw = formActionMatch[1];
    } else {
      const locationReplaceMatch = body.match(
        /location\.replace\(\s*(["'])(.*?)\1\s*\)/,
      );
      if (locationReplaceMatch?.[2]) {
        raw = locationReplaceMatch[2];
      }
    }

    if (!raw) {
      return null;
    }

    const decoded = decodeMinimalHtmlEntities(raw);
    const parsed = new URL(decoded);
    if (!/^https?:$/i.test(parsed.protocol)) {
      return null;
    }
    return parsed.origin;
  } catch {
    return null;
  }
}

// CERNBox launches via a JSON open-in-app response ({ app_url, access_token }),
// not the redirect HTML Nextcloud returns. Pull the remote hub origin from the
// app_url the browser then form-POSTs into.
export function extractHubLaunchOriginFromOpenInApp(body: unknown): string | null {
  try {
    let payload: unknown = body;
    if (typeof body === "string") {
      payload = JSON.parse(body);
    }
    const appUrl = (payload as { app_url?: unknown } | null | undefined)?.app_url;
    if (typeof appUrl !== "string" || appUrl.trim().length === 0) {
      return null;
    }
    const parsed = new URL(appUrl);
    if (!/^https?:$/i.test(parsed.protocol)) {
      return null;
    }
    return parsed.origin;
  } catch {
    return null;
  }
}

export function assertHubLaunchOrigin(
  hubOrigin: string | null,
  receiverOrigin?: string,
): void {
  if (!hubOrigin || hubOrigin.trim().length === 0) {
    throw new Error(
      [
        "Expected an absolute hub origin extracted from the ocm/open launch HTML,",
        `but got ${JSON.stringify(hubOrigin)}.`,
      ].join(" "),
    );
  }

  let parsed: URL;
  try {
    parsed = new URL(hubOrigin);
  } catch {
    throw new Error(
      [
        "Expected an absolute http(s) hub origin extracted from the ocm/open launch HTML,",
        `but got ${JSON.stringify(hubOrigin)}.`,
      ].join(" "),
    );
  }

  if (!/^https?:$/i.test(parsed.protocol)) {
    throw new Error(
      [
        "Expected an absolute http(s) hub origin extracted from the ocm/open launch HTML,",
        `but got ${JSON.stringify(hubOrigin)}.`,
      ].join(" "),
    );
  }

  if (receiverOrigin && parsed.origin === receiverOrigin) {
    throw new Error(
      [
        "Expected a distinct remote hub origin extracted from the ocm/open launch HTML,",
        `but hub origin ${JSON.stringify(hubOrigin)} matches receiver origin`,
        `${JSON.stringify(receiverOrigin)}.`,
      ].join(" "),
    );
  }
}
