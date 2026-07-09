import type { MitmExpectation, MitmTrafficRecord } from "./mitm-traffic";

// MITM launch-leg expectations for receivers where hub traffic is proxied.
export function mentionsLab(record: MitmTrafficRecord): boolean {
  return [
    record.response?.headers?.Location,
    record.response?.headers?.location,
    record.response?.body?.preview,
    record.request.url,
  ].some((value) => typeof value === "string" && value.includes("/lab"));
}

export const CERNBOX_WEBAPP_SHARE_MITM_LAUNCH_EXPECTATIONS: MitmExpectation[] = [
  {
    label: "POST /services/ocm/open",
    predicate: (record) =>
      record.request.method === "POST" &&
      (record.request.path ?? "").includes("/services/ocm/open"),
  },
  {
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

// Nextcloud launch traffic stays on browser-to-hub paths the MITM does not proxy.
export const NEXTCLOUD_WEBAPP_SHARE_MITM_LAUNCH_EXPECTATIONS: MitmExpectation[] = [];

export function resolveWebappShareMitmLaunchExpectations(
  receiverAdapterKey: string,
): MitmExpectation[] {
  if (receiverAdapterKey.startsWith("cernbox/")) {
    return CERNBOX_WEBAPP_SHARE_MITM_LAUNCH_EXPECTATIONS;
  }
  if (receiverAdapterKey.startsWith("nextcloud/")) {
    return NEXTCLOUD_WEBAPP_SHARE_MITM_LAUNCH_EXPECTATIONS;
  }

  throw new Error(
    [
      `[webapp-share] No MITM launch expectations for receiver adapter "${receiverAdapterKey}".`,
      "Add a receiver-specific launch oracle before running this pair.",
    ].join(" "),
  );
}
