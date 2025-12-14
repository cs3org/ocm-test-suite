/**
 * @fileoverview
 * Cypress test suite for testing invite link federated sharing via ScienceMesh functionality
 * between oCIS and Nextcloud. This suite covers sending and accepting invitation links,
 * sharing files via ScienceMesh, and verifying that the shares are received correctly.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import { getUtils } from "../utils/index.js";

describe("Invite link federated sharing via ScienceMesh functionality between oCIS and Nextcloud", () => {
  // Shared variables to avoid repetition and improve maintainability
  const senderPlatform = Cypress.env("EFSS_PLATFORM_1") ?? "ocis";
  const recipientPlatform = Cypress.env("EFSS_PLATFORM_2") ?? "nextcloud";
  const senderVersion = Cypress.env("EFSS_PLATFORM_1_VERSION") ?? "v5";
  const recipientVersion = Cypress.env("EFSS_PLATFORM_2_VERSION") ?? "v27";
  const senderUrl = Cypress.env("OCIS1_URL") || "https://ocis1.docker";
  const recipientUrl =
    Cypress.env("NEXTCLOUD1_URL") || "https://nextcloud1.docker";
  const senderUsername = Cypress.env("OCIS1_USERNAME") || "einstein";
  const senderPassword = Cypress.env("OCIS1_PASSWORD") || "relativity";
  const recipientUsername = Cypress.env("NEXTCLOUD1_USERNAME") || "michiel";
  const recipientPassword = Cypress.env("NEXTCLOUD1_PASSWORD") || "dejong";
  const senderDisplayName =
    Cypress.env("OCIS1_DISPLAY_NAME") || "Albert Einstein";
  const recipientDisplayName =
    Cypress.env("NEXTCLOUD1_DISPLAY_NAME") || "michiel";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");
  const inviteLinkFileName = "invite-link-ocis-nc.txt";
  const sharedFileName = inviteLinkFileName;
  const sharedFileContent = "Hello World!";

  // Get the right helper set for each side
  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  /**
   * Test case: Sending an invitation token from oCIS to Nextcloud.
   * Steps:
   * 1. Log in to the sender's oCIS instance
   * 2. Navigate to the ScienceMesh app
   * 3. Generate the invite token and save it to a file
   */
  it("Send invitation from oCIS to Nextcloud", () => {
    senderUtils.createInviteLink({
      senderUrl,
      senderDomain,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientVersion,
      recipientDomain,
      inviteLinkFileName,
    });
  });

  /**
   * Test case: Accepting the invitation token on Nextcloud side.
   * Steps:
   * 1. Load the invite token from the saved file
   * 2. Log in to the recipient's Nextcloud instance
   * 3. Accept the invitation
   * 4. Verify the federated contact is established
   */
  it("Accept invitation from oCIS to Nextcloud", () => {
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
   * Test case: Sharing a file via ScienceMesh from oCIS to Nextcloud.
   * Steps:
   * 1. Log in to the sender's oCIS instance
   * 2. Create a text file with content
   * 3. Navigate to the Files app
   * 4. Share the file with the recipient
   */
  it("Send ScienceMesh share <file> from oCIS to Nextcloud", () => {
    senderUtils.shareViaInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      sharedFileName,
      sharedFileContent,
      recipientUsername,
      recipientDisplayName,
    });
  });

  /**
   * Test case: Receiving and verifying the ScienceMesh share on Nextcloud side.
   * Steps:
   * 1. Log in to the recipient's Nextcloud instance
   * 2. Accept the shared file
   * 3. Navigate to the correct section
   * 4. Verify the shared file exists
   */
  it("Receive ScienceMesh share <file> from oCIS to Nextcloud", () => {
    recipientUtils.acceptInviteLinkShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
    });
  });
});
