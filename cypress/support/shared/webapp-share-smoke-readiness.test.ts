import { describe, expect, test } from "bun:test";
import { matchesIncomingWebappShareCardText } from "../adapters/nextcloud/shared/webapp-share-receiver-impl";
import type { MitmTrafficRecord } from "./mitm-traffic";
import {
  CERNBOX_WEBAPP_SHARE_LAUNCH_EXPECTATIONS,
  isNextcloudOutboundOcmHandoff,
  NEXTCLOUD_WEBAPP_SHARE_LAUNCH_EXPECTATIONS,
  resolveWebappShareLaunchExpectations,
} from "./webapp-share-launch-oracle";

const shareRef = {
  sharedFolderName: "webapp-share-nc-nc",
  senderFederatedId: "alice@sender.example.test",
};

function mitmRecord(
  overrides: Partial<MitmTrafficRecord> & { request: MitmTrafficRecord["request"] },
): MitmTrafficRecord {
  return {
    response: overrides.response,
    request: overrides.request,
  };
}

describe("matchesIncomingWebappShareCardText", () => {
  test("matches when both folder name and sender federated id are present", () => {
    const cardText =
      "Shared folder webapp-share-nc-nc from alice@sender.example.test Accept";
    expect(matchesIncomingWebappShareCardText(cardText, shareRef)).toBe(true);
  });

  test("normalizes whitespace before matching", () => {
    const cardText =
      "Shared   folder\nwebapp-share-nc-nc\nfrom\nalice@sender.example.test";
    expect(matchesIncomingWebappShareCardText(cardText, shareRef)).toBe(true);
  });

  test("rejects folder name alone without sender identity", () => {
    const cardText = "Shared folder webapp-share-nc-nc from someone else Accept";
    expect(matchesIncomingWebappShareCardText(cardText, shareRef)).toBe(false);
  });

  test("rejects sender identity alone without folder name", () => {
    const cardText = "Incoming share from alice@sender.example.test";
    expect(matchesIncomingWebappShareCardText(cardText, shareRef)).toBe(false);
  });

  test("rejects stale same-name card from a different sender", () => {
    const cardText =
      "Shared folder webapp-share-nc-nc from bob@other.example.test Accept";
    expect(matchesIncomingWebappShareCardText(cardText, shareRef)).toBe(false);
  });

  test("rejects empty sender or folder discriminators", () => {
    const cardText =
      "Shared folder webapp-share-nc-nc from alice@sender.example.test";
    expect(
      matchesIncomingWebappShareCardText(cardText, {
        ...shareRef,
        senderFederatedId: "   ",
      }),
    ).toBe(false);
    expect(
      matchesIncomingWebappShareCardText(cardText, {
        ...shareRef,
        sharedFolderName: "",
      }),
    ).toBe(false);
  });
});

describe("isNextcloudOutboundOcmHandoff", () => {
  test("accepts POST /services/ocm/open handoff", () => {
    const record = mitmRecord({
      request: {
        method: "POST",
        path: "/services/ocm/open",
        url: "https://receiver.example.test/services/ocm/open",
      },
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(true);
  });

  test("accepts POST /hub/ocm-login handoff", () => {
    const record = mitmRecord({
      request: {
        method: "POST",
        path: "/hub/ocm-login",
        url: "https://hub.example.test/hub/ocm-login",
      },
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(true);
  });

  test("accepts OCM-scoped POST whose body preview mentions access_token", () => {
    const record = mitmRecord({
      request: {
        method: "POST",
        path: "/apps/ocm/api/v1/token",
        url: "https://receiver.example.test/apps/ocm/api/v1/token",
      },
      response: {
        body: { preview: '{"access_token":"opaque-token"}' },
      },
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(true);
  });

  test("rejects non-POST traffic", () => {
    const record = mitmRecord({
      request: {
        method: "GET",
        path: "/services/ocm/open",
        url: "https://receiver.example.test/services/ocm/open",
      },
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(false);
  });

  test("rejects unrelated OAuth token POST without OCM scope", () => {
    const record = mitmRecord({
      request: {
        method: "POST",
        path: "/index.php/apps/oauth2/api/v1/token",
        url: "https://receiver.example.test/index.php/apps/oauth2/api/v1/token",
      },
      response: {
        body: { preview: '{"access_token":"oauth-noise"}' },
      },
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(false);
  });

  test("rejects unrelated POST without hub/services path or token evidence", () => {
    const record = mitmRecord({
      request: {
        method: "POST",
        path: "/index.php/login",
        url: "https://receiver.example.test/index.php/login",
      },
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(false);
  });
});

describe("resolveWebappShareLaunchExpectations", () => {
  test("returns unchanged CERNBox launch expectations", () => {
    const expectations = resolveWebappShareLaunchExpectations("cernbox/v2");
    expect(expectations).toBe(CERNBOX_WEBAPP_SHARE_LAUNCH_EXPECTATIONS);
    expect(expectations.map((item) => item.label)).toEqual([
      "POST /services/ocm/open",
      "POST /hub/ocm-login",
      "redirect toward /lab handoff boundary",
    ]);
  });

  test("returns tightened Nextcloud launch expectations", () => {
    const expectations = resolveWebappShareLaunchExpectations("nextcloud/v35");
    expect(expectations).toBe(NEXTCLOUD_WEBAPP_SHARE_LAUNCH_EXPECTATIONS);
    expect(expectations.map((item) => item.label)).toEqual([
      "GET /apps/ocmremotewebapp/ocm/open (redirect target)",
      "POST outbound OCM handoff (hub/services path or OCM-scoped access_token)",
    ]);
  });

  test("throws for unsupported receiver adapters", () => {
    expect(() => resolveWebappShareLaunchExpectations("owncloud/v10")).toThrow(
      /No launch MITM expectations/,
    );
  });
});
