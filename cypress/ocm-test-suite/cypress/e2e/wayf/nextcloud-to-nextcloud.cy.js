/**
 * @fileoverview
 * Cypress test suite for testing WAYF (Where Are You From) federated sharing functionality in Nextcloud.
 * This suite covers creating invites via Contacts app, WAYF provider selection, accepting invitations,
 * sharing files via OCM, and verifying that the shares are received correctly.
 *
 * For Nextcloud v33, this uses the Contacts app and WAYF flow instead of the legacy ScienceMesh app.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import { getUtils } from "../utils/index.js";

describe("WAYF federated sharing functionality for Nextcloud", () => {
  // Shared variables to avoid repetition and improve maintainability
  const senderPlatform = Cypress.env("EFSS_PLATFORM_1") ?? "nextcloud";
  const recipientPlatform = Cypress.env("EFSS_PLATFORM_2") ?? "nextcloud";
  const senderVersion = Cypress.env("EFSS_PLATFORM_1_VERSION") ?? "v33";
  const recipientVersion = Cypress.env("EFSS_PLATFORM_2_VERSION") ?? "v33";
  const senderUrl =
    Cypress.env("NEXTCLOUD1_URL") || "https://nextcloud1.docker";
  const recipientUrl =
    Cypress.env("NEXTCLOUD2_URL") || "https://nextcloud2.docker";
  const senderUsername = Cypress.env("NEXTCLOUD1_USERNAME") || "einstein";
  const senderPassword = Cypress.env("NEXTCLOUD1_PASSWORD") || "relativity";
  const recipientUsername = Cypress.env("NEXTCLOUD2_USERNAME") || "michiel";
  const recipientPassword = Cypress.env("NEXTCLOUD2_PASSWORD") || "dejong";
  const senderDisplayName =
    Cypress.env("NEXTCLOUD1_DISPLAY_NAME") || "einstein";
  const recipientDisplayName =
    Cypress.env("NEXTCLOUD2_DISPLAY_NAME") || "michiel";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");
  const inviteLinkFileName = "wayf-nc-nc.txt";
  const originalFileName = "welcome.txt";
  const sharedFileName = "wayf-nc-nc.txt";

  // Get the right helper set for each side
  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  /**
   * Test case: Creating an invitation via Contacts app and handling WAYF flow.
   * For v33, this creates the invite link, visits the WAYF page, enters the provider,
   * and saves the redirect URL for the recipient-side job.
   */
  it("Create invitation and handle WAYF flow from Nextcloud to Nextcloud", () => {
    senderUtils.createWayfInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientUrl,
      inviteLinkFileName,
    });
  });

  /**
   * Test case: Accepting the invitation on the recipient's side after WAYF redirect.
   * For v33, this reads the redirect URL saved by the sender-side job, logs in,
   * accepts the invite dialog, and verifies the contact was created.
   */
  it("Accept invitation from Nextcloud to Nextcloud", () => {
    recipientUtils.acceptWayfInviteLink({
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
   * Test case: Sharing a file via OCM from sender to recipient.
   * For v33, this uses the Contacts-based federated contact and v33 Sharing sidebar.
   */
  it("Send OCM share of a <file> from Nextcloud to Nextcloud", () => {
    senderUtils.shareViaInviteLink({
      senderUrl,
      senderDomain,
      senderPlatform,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientDomain,
      recipientDisplayName,
      originalFileName,
      sharedFileName,
    });
  });

  /**
   * Test case: Receiving and verifying the OCM share on the recipient's side.
   * For v33, this handles the Remote share dialog and verifies the file using v33 table structure.
   */
  it("Receive OCM share of a <file> from Nextcloud to Nextcloud", () => {
    recipientUtils.acceptInviteLinkShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
    });
  });
});
