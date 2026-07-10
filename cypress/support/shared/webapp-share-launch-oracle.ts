import type { MitmExpectation } from "./mitm-traffic";

// CERNBox launch traffic is a client-side cross-origin handoff to the remote hub
// (browser -> hub POST /services/ocm/open, POST /hub/ocm-login, redirect to
// /lab). Like Nextcloud, none of these legs traverse the server-to-server OCM
// MITM, so there are no MITM launch expectations; the launch is gated in-browser
// via the cy.origin JupyterLab proof (proveJupyterLabFromLaunchArtifact).
export const CERNBOX_WEBAPP_SHARE_MITM_LAUNCH_EXPECTATIONS: MitmExpectation[] = [];

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
