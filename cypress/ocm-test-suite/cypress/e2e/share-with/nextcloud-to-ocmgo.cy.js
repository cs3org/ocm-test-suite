/**
 * @fileoverview
 * Cypress test suite for testing native federated sharing functionality from Nextcloud to OCM-Go.
 */

import { getUtils } from '../utils/index.js';

describe('Native federated sharing functionality from Nextcloud to OCM-Go', () => {
  const senderPlatform = Cypress.env('EFSS_PLATFORM_1') ?? 'nextcloud';
  const recipientPlatform = Cypress.env('EFSS_PLATFORM_2') ?? 'ocmgo';
  const senderVersion = Cypress.env('EFSS_PLATFORM_1_VERSION') ?? 'v27';
  const recipientVersion = Cypress.env('EFSS_PLATFORM_2_VERSION') ?? 'v1';
  const senderUrl = Cypress.env('NEXTCLOUD1_URL') || 'https://nextcloud1.docker';
  const recipientUrl = Cypress.env('OCMGO1_URL') || 'https://ocm-go1.docker';
  const senderUsername = Cypress.env('NEXTCLOUD1_USERNAME') || 'einstein';
  const senderPassword = Cypress.env('NEXTCLOUD1_PASSWORD') || 'relativity';
  const recipientUsername = Cypress.env('OCMGO1_USERNAME') || 'marie';
  const recipientPassword = Cypress.env('OCMGO1_PASSWORD') || 'radioactivity';
  const originalFileName = 'welcome.txt';
  const sharedFileName = 'nc1-to-og1-share.txt';

  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  it('Send a federated share of a file from Nextcloud to OCM-Go', () => {
    senderUtils.shareViaNativeShareWith({
      senderUrl,
      senderUsername,
      senderPassword,
      originalFileName,
      sharedFileName,
      recipientUsername,
      recipientUrl,
    });
  });

  it('Receive and accept the federated share on OCM-Go from Nextcloud', () => {
    recipientUtils.acceptNativeShareWithShare({
      senderPlatform,
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
      senderUsername,
      senderUrl,
      senderUtils,
    });
  });
});
