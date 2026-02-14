/**
 * @fileoverview
 * Cypress test suite for testing native federated sharing functionality from OCM-Go to Nextcloud.
 */

import { getUtils } from '../utils/index.js';

describe('Native federated sharing functionality from OCM-Go to Nextcloud', () => {
  const senderPlatform = Cypress.env('EFSS_PLATFORM_1') ?? 'ocmgo';
  const recipientPlatform = Cypress.env('EFSS_PLATFORM_2') ?? 'nextcloud';
  const senderVersion = Cypress.env('EFSS_PLATFORM_1_VERSION') ?? 'v1';
  const recipientVersion = Cypress.env('EFSS_PLATFORM_2_VERSION') ?? 'v27';
  const senderUrl = Cypress.env('OCMGO1_URL') || 'https://ocm-go1.docker';
  const recipientUrl = Cypress.env('NEXTCLOUD1_URL') || 'https://nextcloud1.docker';
  const senderUsername = Cypress.env('OCMGO1_USERNAME') || 'marie';
  const senderPassword = Cypress.env('OCMGO1_PASSWORD') || 'radioactivity';
  const recipientUsername = Cypress.env('NEXTCLOUD1_USERNAME') || 'einstein';
  const recipientPassword = Cypress.env('NEXTCLOUD1_PASSWORD') || 'relativity';
  const originalFileName = 'test-share.txt';
  const sharedFileName = 'test-share.txt';

  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  it('Send a federated share of a file from OCM-Go to Nextcloud', () => {
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

  it('Receive and accept the federated share on Nextcloud from OCM-Go', () => {
    recipientUtils.acceptNativeShareWithShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
    });
  });
});
