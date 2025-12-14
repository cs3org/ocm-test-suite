/**
 * @fileoverview
 * Cypress test suite for testing invite link federated sharing via ScienceMesh functionality in ownCloud.
 * This suite covers sending and accepting invitation links, sharing files via ScienceMesh,
 * and verifying that the shares are received correctly.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import { getUtils } from "../utils/index.js";

describe("Invite link federated sharing via ScienceMesh functionality for ownCloud", () => {
  // Shared variables to avoid repetition and improve maintainability
  const senderPlatform = Cypress.env("EFSS_PLATFORM_1") ?? "owncloud";
  const recipientPlatform = Cypress.env("EFSS_PLATFORM_2") ?? "owncloud";
  const senderVersion = Cypress.env("EFSS_PLATFORM_1_VERSION") ?? "v10";
  const recipientVersion = Cypress.env("EFSS_PLATFORM_2_VERSION") ?? "v10";
  const senderUrl = Cypress.env("OWNCLOUD1_URL") || "https://owncloud1.docker";
  const recipientUrl =
    Cypress.env("OWNCLOUD2_URL") || "https://owncloud2.docker";
  const senderUsername = Cypress.env("OWNCLOUD1_USERNAME") || "marie";
  const senderPassword = Cypress.env("OWNCLOUD1_PASSWORD") || "radioactivity";
  const recipientUsername = Cypress.env("OWNCLOUD2_USERNAME") || "mahdi";
  const recipientPassword = Cypress.env("OWNCLOUD2_PASSWORD") || "baghbani";
  const senderDisplayName = Cypress.env("NEXTCLOUD1_DISPLAY_NAME") || "marie";
  const recipientDisplayName =
    Cypress.env("NEXTCLOUD2_DISPLAY_NAME") || "mahdi";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");
  const inviteLinkFileName = "invite-link-oc-oc.txt";
  const originalFileName = "welcome.txt";
  const sharedFileName = "invite-link-oc-oc.txt";

  // Get the right helper set for each side
  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  /**
   * Test case: Sending an invitation link from sender to recipient.
   */
  it("Send invitation from ownCloud to ownCloud", () => {
    senderUtils.createInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientUrl,
      inviteLinkFileName,
    });
  });

  /**
   * Test case: Accepting the invitation link on the recipient's side.
   */
  it("Accept invitation from ownCloud to ownCloud", () => {
    recipientUtils.acceptInviteLink({
      senderPlatform,
      senderDomain,
      senderUsername,
      senderDisplayName,
      recipientUrl,
      recipientDomain,
      recipientUsername,
      recipientPassword,
      inviteLinkFileName,
    });
  });

  /**
   * Test case: Sharing a file via ScienceMesh from sender to recipient.
   */
  it("Send ScienceMesh share of a <file> from ownCloud to ownCloud", () => {
    senderUtils.shareViaInviteLink({
      senderUrl,
      senderDomain,
      senderPlatform,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientUrl,
      recipientDomain,
      recipientUsername,
      originalFileName,
      sharedFileName,
    });
  });

  /**
   * Test Case: Receiving and accepting a ScienceMesh file share on ownCloud 2.
   * This test verifies that the shared file appears in the "Sharing In" section.
   */
  it("Receive ScienceMesh share of a <file> from ownCloud to ownCloud", () => {
    recipientUtils.acceptInviteLinkShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
    });
  });
});
