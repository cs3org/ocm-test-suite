import { describe, expect, test } from "bun:test";
import { matchesIncomingWebappShareCardText } from "../adapters/nextcloud/shared/webapp-share-receiver-impl";
import { WEBAPP_SHARE_APP_NAME } from "../contracts/webapp-share";

const shareRef = {
  sharedFolderName: "webapp-share-nc-nc",
  senderFederatedId: "alice@sender.example.test",
  appName: WEBAPP_SHARE_APP_NAME,
};

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

  test("matches when app name and sender federated id are present (no folder name on card)", () => {
    const cardText =
      "Jupyter Shared by alice@sender.example.test read pending Accept Decline";
    expect(matchesIncomingWebappShareCardText(cardText, shareRef)).toBe(true);
  });

  test("rejects sender identity alone without folder name or app name", () => {
    const cardText = "Incoming share from alice@sender.example.test";
    expect(matchesIncomingWebappShareCardText(cardText, shareRef)).toBe(false);
  });

  test("rejects stale same-name card from a different sender", () => {
    const cardText =
      "Shared folder webapp-share-nc-nc from bob@other.example.test Accept";
    expect(matchesIncomingWebappShareCardText(cardText, shareRef)).toBe(false);
  });

  test("rejects empty sender or resource discriminators", () => {
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
        appName: "",
      }),
    ).toBe(false);
  });
});
