/**
 * @fileoverview
 * Cypress test suite for testing invite link federated sharing via ScienceMesh functionality between OCMStub instances.
 * This suite covers sending and accepting invitation links, sharing files via ScienceMesh,
 * and verifying that the shares are received correctly.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import { getUtils } from "../utils/index.js";

describe("Invite link federated sharing via ScienceMesh functionality for OCMStub", () => {
  // Shared variables to avoid repetition and improve maintainability
  const senderPlatform = Cypress.env("EFSS_PLATFORM_1") ?? "ocmstub";
  const recipientPlatform = Cypress.env("EFSS_PLATFORM_2") ?? "ocmstub";
  const senderVersion = Cypress.env("EFSS_PLATFORM_1_VERSION") ?? "v1";
  const recipientVersion = Cypress.env("EFSS_PLATFORM_2_VERSION") ?? "v1";
  const senderUrl = Cypress.env("OCMSTUB1_URL") || "https://ocmstub1.docker";
  const recipientUrl = Cypress.env("OCMSTUB2_URL") || "https://ocmstub2.docker";
  // OCMStub uses hardcoded user 'einstein'
  const senderUsername = Cypress.env("OCMSTUB1_USERNAME") || "einstein";
  const senderPassword = Cypress.env("OCMSTUB1_PASSWORD") || "";
  const recipientUsername = Cypress.env("OCMSTUB2_USERNAME") || "einstein";
  const recipientPassword = Cypress.env("OCMSTUB2_PASSWORD") || "";
  const senderDisplayName = Cypress.env("OCMSTUB1_DISPLAY_NAME") || "Albert Einstein";
  const recipientDisplayName = Cypress.env("OCMSTUB2_DISPLAY_NAME") || "Albert Einstein";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");
  const inviteLinkFileName = "invite-link-ocmstub-ocmstub.txt";
  const sharedFileName = "invite-link-ocmstub-ocmstub";
  const sharedFileContent = "Hello World!";

  // Get the right helper set for each side
  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  /**
   * Test case: Sending an invitation token from sender to recipient.
   * Steps:
   * 1. Log in to the sender's OCMStub instance
   * 2. Generate the invite token and save it to a file
   */
  it("Send invitation from OCMStub to OCMStub", () => {
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
   * Test case: Accepting the invitation token on the recipient's side.
   * Steps:
   * 1. Load the invite token from the saved file
   * 2. Navigate to the accept-invite endpoint
   * 3. Verify the federated contact is established
   */
  it("Accept invitation from OCMStub to OCMStub", () => {
    recipientUtils.acceptInviteLink({
      senderDomain,
      senderPlatform,
      senderUsername,
      senderDisplayName,
      recipientUrl,
      recipientUsername,
      recipientPassword,
      inviteLinkFileName,
    });
  });

  /**
   * Test case: Sharing a file via ScienceMesh from sender to recipient.
   * Steps:
   * 1. Log in to the sender's OCMStub instance
   * 2. Navigate to the shareWith endpoint
   * 3. Verify the share was sent
   */
  it("Send ScienceMesh share <file> from OCMStub to OCMStub", () => {
    senderUtils.shareViaInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      sharedFileName,
      sharedFileContent,
      recipientUsername,
      recipientDisplayName: recipientDomain,
    });
  });

  /**
   * Test case: Receiving and verifying the ScienceMesh share on the recipient's side.
   * Steps:
   * 1. Log in to the recipient's OCMStub instance
   * 2. Accept the shared file
   * 3. Verify the share is received
   */
  it("Receive ScienceMesh share <file> from OCMStub to OCMStub", () => {
    recipientUtils.acceptInviteLinkShare({
      senderDisplayName,
      recipientUrl,
      recipientUsername,
      recipientPassword,
      recipientDisplayName,
      sharedFileName,
    });
  });
});
