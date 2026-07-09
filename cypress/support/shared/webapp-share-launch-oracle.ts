import type { MitmExpectation, MitmTrafficRecord } from "./mitm-traffic";

// Launch-leg proof for the CERNBox -> JupyterHub Layer 2 handoff. Cross-origin
// navigation makes in-browser assertions unreliable, so the MITM capture is the
// authoritative oracle: the remote open reaches the hub and redirects toward the
// notebook workspace.
export function mentionsLab(record: MitmTrafficRecord): boolean {
  return [
    record.response?.headers?.Location,
    record.response?.headers?.location,
    record.response?.body?.preview,
    record.request.url,
  ].some((value) => typeof value === "string" && value.includes("/lab"));
}

export const CERNBOX_WEBAPP_SHARE_LAUNCH_EXPECTATIONS: MitmExpectation[] = [
  {
    label: "POST /services/ocm/open",
    predicate: (record) =>
      record.request.method === "POST" &&
      (record.request.path ?? "").includes("/services/ocm/open"),
  },
  {
    // The OCM service launcher submits a cross-origin form POST to the hub's
    // OCMLoginHandler (hub/.../handlers.py: OCMLoginHandler implements post()
    // only); asserting GET here never matches real launch traffic.
    label: "POST /hub/ocm-login",
    predicate: (record) =>
      record.request.method === "POST" &&
      (record.request.path ?? "").includes("/hub/ocm-login"),
  },
  {
    label: "redirect toward /lab handoff boundary",
    predicate: mentionsLab,
  },
];

// Nextcloud receiver launch is debug-first on the first NC -> NC smoke: prove the
// receiver launcher and an outbound OCM handoff without reusing the CERNBox hub
// oracle.
export function isNextcloudOutboundOcmHandoff(record: MitmTrafficRecord): boolean {
  if (record.request.method !== "POST") {
    return false;
  }

  const path = record.request.path ?? "";
  if (path.includes("/hub/ocm-login") || path.includes("/services/ocm/open")) {
    return true;
  }

  const preview = record.response?.body?.preview ?? "";
  if (!preview.includes("access_token")) {
    return false;
  }

  // Debug NC->NC: token evidence must come from an OCM-scoped POST, not any
  // unrelated OAuth/token endpoint seen during the launch window.
  const url = record.request.url ?? "";
  return path.includes("/ocm") || url.includes("/ocm");
}

export const NEXTCLOUD_WEBAPP_SHARE_LAUNCH_EXPECTATIONS: MitmExpectation[] = [
  {
    label: "GET /apps/ocmremotewebapp/ocm/open (redirect target)",
    predicate: (record) =>
      record.request.method === "GET" &&
      (record.request.path ?? "").includes("/apps/ocmremotewebapp/ocm/open") &&
      (record.request.url ?? "").includes("target=redirect"),
  },
  {
    label: "POST outbound OCM handoff (hub/services path or OCM-scoped access_token)",
    predicate: isNextcloudOutboundOcmHandoff,
  },
];

export function resolveWebappShareLaunchExpectations(
  receiverAdapterKey: string,
): MitmExpectation[] {
  if (receiverAdapterKey.startsWith("cernbox/")) {
    return CERNBOX_WEBAPP_SHARE_LAUNCH_EXPECTATIONS;
  }
  if (receiverAdapterKey.startsWith("nextcloud/")) {
    return NEXTCLOUD_WEBAPP_SHARE_LAUNCH_EXPECTATIONS;
  }

  throw new Error(
    [
      `[webapp-share] No launch MITM expectations for receiver adapter "${receiverAdapterKey}".`,
      "Add a receiver-specific launch oracle before running this pair.",
    ].join(" "),
  );
}
