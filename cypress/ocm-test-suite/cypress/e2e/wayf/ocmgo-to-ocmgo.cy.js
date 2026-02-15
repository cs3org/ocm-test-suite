/**
 * @fileoverview
 * Cypress WAYF test: OCM-Go sender -> OCM-Go recipient.
 * Covers the full WAYF discovery and invite acceptance flow, followed by
 * sharing a file via the established federated contact.
 */

import { getUtils } from '../utils/index.js';

describe('WAYF federated sharing: OCM-Go to OCM-Go', () => {
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
  const senderDisplayName = Cypress.env('OCMGO1_DISPLAY_NAME') || 'Marie Curie';
  const recipientDisplayName = Cypress.env('OCMGO2_DISPLAY_NAME') || 'Albert Einstein';
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, '');
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, '');
  const inviteLinkFileName = 'wayf-ocmgo-ocmgo.txt';
  const originalFileName = 'test-share.txt';
  const sharedFileName = 'test-share.txt';

  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  it('OCM-Go creates WAYF invite link', () => {
    senderUtils.createWayfInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientUrl,
      inviteLinkFileName,
    });
  });

  it('OCM-Go accepts WAYF invite', () => {
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

  it('OCM-Go sends share via established WAYF contact', () => {
    senderUtils.shareViaInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      originalFileName,
      sharedFileName,
      recipientUsername,
      recipientUrl,
    });
  });

  it('OCM-Go receives and accepts share via WAYF contact', () => {
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
