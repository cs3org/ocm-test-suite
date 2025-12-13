/**
 * @fileoverview
 * Cypress test suite for testing invite link federated sharing via ScienceMesh functionality
 * between CERNBox and ownCloud. This suite covers sending and accepting invitation links,
 * sharing files via ScienceMesh, and verifying that the shares are received correctly.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */


import {
  getUtils
} from '../utils/index.js';

describe('Invite link federated sharing via ScienceMesh functionality between CERNBox and ownCloud', () => {
  // Shared variables to avoid repetition and improve maintainability
  const senderPlatform = Cypress.env('EFSS_PLATFORM_1') ?? 'cernbox';
  const recipientPlatform = Cypress.env('EFSS_PLATFORM_2') ?? 'owncloud';
  const senderVersion = Cypress.env('EFSS_PLATFORM_1_VERSION') ?? 'v2';
  const recipientVersion = Cypress.env('EFSS_PLATFORM_2_VERSION') ?? 'v10';
  const senderUrl = Cypress.env('CERNBOX1_URL') || 'https://cernbox1.docker';
  const recipientUrl = Cypress.env('OWNCLOUD1_URL') || 'https://owncloud1.docker';
  const senderUsername = Cypress.env('CERNBOX1_USERNAME') || 'einstein';
  const senderPassword = Cypress.env('CERNBOX1_PASSWORD') || 'relativity';
  const recipientUsername = Cypress.env('OWNCLOUD1_USERNAME') || 'marie';
  const recipientPassword = Cypress.env('OWNCLOUD1_PASSWORD') || 'radioactivity';
  const senderDisplayName = Cypress.env('CERNBOX1_DISPLAY_NAME') || 'Albert Einstein';
  const recipientDisplayName = Cypress.env('OWNCLOUD1_DISPLAY_NAME') || 'marie';
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, '');
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, '');
  const inviteLinkFileName = 'invite-link-cernbox-oc.txt';
  const sharedFileName = inviteLinkFileName;
  const sharedFileContent = 'Hello World!';

  // Get the right helper set for each side
  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  /**
   * Test case: Sending an invitation token from CERNBox to ownCloud.
   * Steps:
   * 1. Log in to the sender's CERNBox instance
   * 2. Navigate to the ScienceMesh app
   * 3. Generate the invite token and save it to a file
   */
  it('Send invitation from CERNBox to ownCloud', () => {
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
   * Test case: Accepting the invitation token on ownCloud side.
   * Steps:
   * 1. Load the invite token from the saved file
   * 2. Log in to the recipient's ownCloud instance
   * 3. Accept the invitation
   * 4. Verify the federated contact is established
   */
  it('Accept invitation from CERNBox to ownCloud', () => {
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
   * Test case: Sharing a file via ScienceMesh from CERNBox to ownCloud.
   * Steps:
   * 1. Log in to the sender's CERNBox instance
   * 2. Create a text file with content
   * 3. Navigate to the Files app
   * 4. Share the file with the recipient
   */
  it('Send ScienceMesh share <file> from CERNBox to ownCloud', () => {
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
   * Test case: Receiving and verifying the ScienceMesh share on ownCloud side.
   * Steps:
   * 1. Log in to the recipient's ownCloud instance
   * 2. Verify the shared file exists and has correct sharing information
   */
  it('Receive ScienceMesh share <file> from CERNBox to ownCloud', () => {
    recipientUtils.acceptInviteLinkShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
    });
  });
})
