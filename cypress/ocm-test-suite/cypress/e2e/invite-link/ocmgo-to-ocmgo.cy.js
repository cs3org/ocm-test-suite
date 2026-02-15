/**
 * @fileoverview
 * Cypress test suite for testing invite link federated sharing between OCM-Go instances.
 * Covers sending and accepting invitation links, sharing files via ScienceMesh,
 * and verifying that the shares are received correctly.
 */

import { getUtils } from '../utils/index.js';

describe('Invite link federated sharing via ScienceMesh functionality for OCM-Go', () => {
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
  const inviteLinkFileName = 'invite-link-ocmgo-ocmgo.txt';
  const originalFileName = 'test-share.txt';
  const sharedFileName = 'test-share.txt';

  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  it('Send invitation from OCM-Go to OCM-Go', () => {
    senderUtils.createInviteLink({
      senderUrl,
      senderDomain,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientDomain,
      inviteLinkFileName,
    });
  });

  it('Accept invitation from OCM-Go to OCM-Go', () => {
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

  it('Send share via invite link from OCM-Go to OCM-Go', () => {
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

  it('Receive and accept share via invite link from OCM-Go to OCM-Go', () => {
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
