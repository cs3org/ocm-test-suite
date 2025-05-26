/**
 * @fileoverview
 * Cypress test suite for testing invite link federated sharing via ScienceMesh functionality
 * between ownCloud and Opencloud. This suite covers sending and accepting invitation links,
 * sharing files via ScienceMesh, and verifying that the shares are received correctly.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import {
  getUtils
} from '../utils/index.js';

describe('Invite link federated sharing via ScienceMesh functionality between ownCloud and Opencloud', () => {
  // Shared variables to avoid repetition and improve maintainability
  const senderPlatform = Cypress.env('EFSS_PLATFORM_1') ?? 'owncloud';
  const recipientPlatform = Cypress.env('EFSS_PLATFORM_2') ?? 'opencloud';
  const senderVersion = Cypress.env('EFSS_PLATFORM_1_VERSION') ?? 'v10';
  const recipientVersion = Cypress.env('EFSS_PLATFORM_2_VERSION') ?? 'v2';
  const senderUrl = Cypress.env('OWNCLOUD1_URL') || 'https://owncloud1.docker';
  const recipientUrl = Cypress.env('OPENCLOUD1_URL') || 'https://opencloud1.docker';
  const senderUsername = Cypress.env('OWNCLOUD1_USERNAME') || 'marie';
  const senderPassword = Cypress.env('OWNCLOUD1_PASSWORD') || 'radioactivity';
  const recipientUsername = Cypress.env('OPENCLOUD1_USERNAME') || 'alan';
  const recipientPassword = Cypress.env('OPENCLOUD1_PASSWORD') || 'demo';
  const senderDisplayName = Cypress.env('OWNCLOUD1_DISPLAY_NAME') || 'marie';
  const recipientDisplayName = Cypress.env('OPENCLOUD1_DISPLAY_NAME') || 'Alan Turing';
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, '');
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, '');
  const inviteLinkFileName = 'invite-link-oc-opencloud.txt';
  const originalFileName = 'welcome.txt';
  const sharedFileName = inviteLinkFileName;

  // Get the right helper set for each side
  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  /**
   * Test case: Sending an invitation link from ownCloud to Opencloud.
   * Steps:
   * 1. Log in to the sender's ownCloud instance
   * 2. Navigate to the ScienceMesh app
   * 3. Generate the invite link and save it to a file
   */
  it('Send invitation from ownCloud to Opencloud', () => {
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
   * Test case: Accepting the invitation link on Opencloud side.
   * Steps:
   * 1. Load the invite link from the saved file
   * 2. Log in to the recipient's Opencloud instance
   * 3. Accept the invitation
   * 4. Verify the federated contact is established
   */
  it('Accept invitation from ownCloud to Opencloud', () => {
    recipientUtils.acceptInviteLink({
      senderDomain,
      senderUsername,
      senderDisplayName,
      recipientUrl,
      recipientUsername,
      recipientPassword,
      inviteLinkFileName,
    });
  });

  /**
   * Test case: Sharing a file via ScienceMesh from ownCloud to Opencloud.
   * Steps:
   * 1. Log in to the sender's ownCloud instance
   * 2. Ensure the original file exists
   * 3. Rename the file for sharing
   * 4. Create the share for the recipient
   */
  it('Send ScienceMesh share <file> from ownCloud to Opencloud', () => {
    senderUtils.shareViaInviteLink({
      senderUrl,
      senderDomain,
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
   * Test case: Receiving and verifying the ScienceMesh share on Opencloud side.
   * Steps:
   * 1. Log in to the recipient's Opencloud instance
   * 2. Navigate to the Files app
   * 3. Verify the shared file exists
   */
  it('Receive ScienceMesh share <file> from ownCloud to Opencloud', () => {
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
