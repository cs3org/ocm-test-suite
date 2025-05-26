/**
 * @fileoverview
 * Cypress test suite for testing invite link federated sharing via ScienceMesh functionality
 * between Nextcloud and CERNBox. This suite covers sending and accepting invitation links,
 * sharing files via ScienceMesh, and verifying that the shares are received correctly.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import {
  getUtils
} from '../utils/index.js';

describe('Invite link federated sharing via ScienceMesh functionality between Nextcloud and CERNBox', () => {
  // Shared variables to avoid repetition and improve maintainability
  const senderPlatform = Cypress.env('EFSS_PLATFORM_1') ?? 'nextcloud';
  const recipientPlatform = Cypress.env('EFSS_PLATFORM_2') ?? 'cernbox';
  const senderVersion = Cypress.env('EFSS_PLATFORM_1_VERSION') ?? 'v27';
  const recipientVersion = Cypress.env('EFSS_PLATFORM_2_VERSION') ?? 'v1';
  const senderUrl = Cypress.env('NEXTCLOUD1_URL') || 'https://nextcloud1.docker';
  const recipientUrl = Cypress.env('CERNBOX1_URL') || 'https://cernbox1.docker';
  const senderUsername = Cypress.env('NEXTCLOUD1_USERNAME') || 'marie';
  const senderPassword = Cypress.env('NEXTCLOUD1_PASSWORD') || 'radioactivity';
  const recipientUsername = Cypress.env('CERNBOX1_USERNAME') || 'einstein';
  const recipientPassword = Cypress.env('CERNBOX1_PASSWORD') || 'relativity';
  const senderDisplayName = Cypress.env('NEXTCLOUD1_DISPLAY_NAME') || 'marie';
  const recipientDisplayName = Cypress.env('CERNBOX1_DISPLAY_NAME') || 'Albert Einstein';
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, '');
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, '');
  const inviteLinkFileName = 'invite-link-nc-cernbox.txt';
  const originalFileName = 'welcome.txt';
  const sharedFileName = inviteLinkFileName;

  // Get the right helper set for each side
  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  /**
   * Test case: Sending an invitation link from Nextcloud to CERNBox.
   * Steps:
   * 1. Log in to the sender's Nextcloud instance
   * 2. Navigate to the ScienceMesh app
   * 3. Generate the invite link and save it to a file
   */
  it('Send invitation from Nextcloud to CERNBox', () => {
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
   * Test case: Accepting the invitation link on CERNBox side.
   * Steps:
   * 1. Load the invite link from the saved file
   * 2. Log in to the recipient's CERNBox instance
   * 3. Accept the invitation
   * 4. Verify the federated contact is established
   */
  it('Accept invitation from Nextcloud to CERNBox', () => {
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
   * Test case: Sharing a file via ScienceMesh from Nextcloud to CERNBox.
   * Steps:
   * 1. Log in to the sender's Nextcloud instance
   * 2. Ensure the original file exists
   * 3. Rename the file for sharing
   * 4. Create the share for the recipient
   */
  // it('Send ScienceMesh share <file> from Nextcloud to CERNBox', () => {
  //   senderUtils.shareViaInviteLink({
  //     senderUrl,
  //     senderDomain,
  //     senderUsername,
  //     senderPassword,
  //     recipientPlatform,
  //     recipientDomain,
  //     recipientDisplayName,
  //     originalFileName,
  //     sharedFileName,
  //   });
  // });

  /**
   * Test case: Receiving and verifying the ScienceMesh share on CERNBox side.
   * Steps:
   * 1. Log in to the recipient's CERNBox instance
   * 2. Navigate to the Files app
   * 3. Verify the shared file exists
   */
  // it('Receive ScienceMesh share <file> from Nextcloud to CERNBox', () => {
  //   recipientUtils.acceptInviteLinkShare({
  //     senderDisplayName,
  //     recipientUrl,
  //     recipientUsername,
  //     recipientPassword,
  //     recipientDisplayName,
  //     sharedFileName,
  //   });
  // });
});
