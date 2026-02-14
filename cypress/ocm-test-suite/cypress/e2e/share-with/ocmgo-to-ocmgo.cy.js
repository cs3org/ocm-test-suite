/**
 * @fileoverview
 * Cypress test suite for testing native federated sharing functionality between OCM-Go instances.
 */

import { getUtils } from '../utils/index.js';

describe('Native federated sharing functionality for OCM-Go', () => {
  const senderPlatform = Cypress.env('EFSS_PLATFORM_1') ?? 'ocmgo';
  const recipientPlatform = Cypress.env('EFSS_PLATFORM_2') ?? 'ocmgo';
  const senderVersion = Cypress.env('EFSS_PLATFORM_1_VERSION') ?? 'v1';
  const recipientVersion = Cypress.env('EFSS_PLATFORM_2_VERSION') ?? 'v1';
  const senderUrl = Cypress.env('OCMGO1_URL') || 'https://ocm-go1.docker';
  const recipientUrl = Cypress.env('OCMGO2_URL') || 'https://ocm-go2.docker';
  const senderUsername = Cypress.env('OCMGO1_USERNAME') || 'marie';
  const senderPassword = Cypress.env('OCMGO1_PASSWORD') || 'radioactivity';
  const recipientUsername = Cypress.env('OCMGO2_USERNAME') || 'einstein';
  const recipientPassword = Cypress.env('OCMGO2_PASSWORD') || 'relativity';
  const originalFileName = 'test-share.txt';
  const sharedFileName = 'test-share.txt';

  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  it('should successfully send a federated share from OCM-Go to OCM-Go', () => {
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

  it('should successfully receive and accept the federated share on OCM-Go', () => {
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
