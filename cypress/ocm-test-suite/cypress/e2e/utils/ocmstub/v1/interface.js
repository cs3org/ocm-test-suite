/**
 * @fileoverview
 * Utility functions for Cypress tests interacting with OcmStub version 1.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import * as implementation from './implementation.js';

export const platform = 'ocmstub';
export const version = 'v1';
export const versionAliases = ['v1.0.0'];

export function login({ url }) {
  cy.visit(`${url}/?`);

  // Ensure the login button is visible
  cy.get('input[value="Log in"]', { timeout: 10000 }).should('be.visible');

  // Perform login by clicking the button
  cy.get('input[value="Log in"]').click();

  // Verify session activation
  cy.url({ timeout: 10000 }).should('match', /\/?session=active/);
};

/**
 * Create an invite link from OCMStub (as inviter).
 * Calls the /ocm/generate-invite-token endpoint to retrieve the token.
 */
export function createInviteLink({
  senderUrl,
  senderDomain,
  senderUsername,
  senderPassword,
  recipientPlatform,
  recipientDomain,
  inviteLinkFileName,
}) {
  // Log in to OCMStub first
  login({ url: senderUrl });

  // Call the token generation endpoint and extract the token
  cy.request({
    method: 'GET',
    url: `${senderUrl}/ocm/generate-invite-token`,
    failOnStatusCode: true,
  }).then((response) => {
    expect(response.status).to.eq(200);
    expect(response.body).to.have.property('token');
    
    const inviteToken = response.body.token;
    cy.log(`Generated invite token: ${inviteToken}`);
    
    // Write the token to the file for the receiver to use
    cy.writeFile(inviteLinkFileName, inviteToken);
  });
}

/**
 * Accept an invite link on OCMStub (as receiver).
 * Navigates to /accept-invite with the token and providerDomain.
 */
export function acceptInviteLink({
  senderDomain,
  senderPlatform,
  senderUsername,
  senderDisplayName,
  recipientUrl,
  recipientUsername,
  recipientPassword,
  inviteLinkFileName,
}) {
  // Read the token from file
  cy.readFile(inviteLinkFileName).then((rawToken) => {
    const token = String(rawToken).trim();

    // Navigate to OCMStub's accept-invite endpoint
    const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, '');
    const acceptUrl = `${recipientUrl}/accept-invite?token=${token}&providerDomain=${senderDomain}`;

    cy.visit(acceptUrl);

    // Verify successful acceptance
    cy.contains('Invite Accepted', { timeout: 15000 }).should('be.visible');
    cy.contains(senderDomain, { timeout: 10000 }).should('be.visible');
  });
}

/**
 * Share a file via the established invite-link contact.
 * Uses the existing shareViaNativeShareWith mechanism.
 */
export function shareViaInviteLink({
  senderUrl,
  senderUsername,
  senderPassword,
  sharedFileName,
  sharedFileContent,
  recipientUsername,
  recipientDisplayName,
}) {
  // OCMStub share-with is done via URL navigation
  const recipientDomain = recipientDisplayName || recipientUsername;
  // Build the share URL - OCMStub uses einstein as the hardcoded user
  cy.visit(`${senderUrl}/shareWith?${recipientUsername}@${recipientDomain}`);

  // Verify the confirmation message is displayed
  cy.contains('yes shareWith', { timeout: 10000 }).should('be.visible');
}

/**
 * Accept a share received via invite-link contact.
 */
export function acceptInviteLinkShare({
  senderDisplayName,
  recipientUrl,
  recipientUsername,
  recipientPassword,
  recipientDisplayName,
  sharedFileName,
}) {
  // Log in to OCMStub
  login({ url: recipientUrl });

  // Navigate to accept the share
  cy.visit(`${recipientUrl}/acceptShare`);

  // Verify share acceptance
  cy.contains('yes acceptShare', { timeout: 10000 }).should('be.visible');
}

export function shareViaNativeShareWith({
  senderUrl,
  recipientUsername,
  recipientUrl,
}) {
  // Step 1: Navigate to the federated share link on OcmStub 1.0
  // Remove trailing slash and leading https or http from recipientUrl
  cy.visit(`${senderUrl}/shareWith?${recipientUsername}@${recipientUrl.replace(/^https?:\/\/|\/$/g, '')}`);

  // Step 2: Verify the confirmation message is displayed
  cy.contains('yes shareWith', { timeout: 10000 })
    .should('be.visible')
}

export function acceptNativeShareWithShare({
  senderPlatform,
  recipientUrl,
  recipientUsername,
  sharedFileName,
  senderUsername,
  senderUrl,
  senderUtils,
}) {
  // Step 1: Log in to the recipient's instance
  login({ url: recipientUrl });

  // Step 2: Handle share acceptance
  implementation.acceptShare({
    senderPlatform,
    recipientUrl,
    recipientUsername,
    sharedFileName,
    senderUsername,
    senderUrl,
    senderUtils,
  });
}

export function acceptFederatedLinkShare({
  senderPlatform,
  recipientUrl,
  recipientUsername,
  sharedFileName,
  senderUsername,
  senderUrl,
  senderUtils,
}) {
  // Step 1: Log in to the recipient's instance
  login({ url: recipientUrl });

  // Step 2: Handle share acceptance
  implementation.acceptShare({
    senderPlatform,
    recipientUrl,
    recipientUsername,
    sharedFileName,
    senderUsername,
    senderUrl,
    senderUtils,
  });
}

/**
 * Build the federated share details object.
 *
 * @param {string} recipientUsername - Username of the recipient (e.g. "alice")
 * @param {string} recipientUrl - Hostname or URL of the recipient (e.g. "remote.example.com")
 * @param {string} sharedFileName - The name of the file being shared
 * @param {string} senderUsername - Username of the sender (e.g. "bob")
 * @param {string} senderUrl - Full URL of the sender (e.g. "https://my.example.com/")
 * @returns {Object} The federated share details
 */
export function buildFederatedShareDetails({
  recipientUsername,
  recipientUrl,
  sharedFileName,
  senderUsername,
  senderUrl
}) {
  return {
    shareWith: `${recipientUsername}@${recipientUrl.replace(/^https?:\/\/|\/$/g, '')}`,
    fileName: sharedFileName,
    owner: `${senderUsername}@${senderUrl.replace(/^https?:\/\/|\/$/g, '')}`,
    sender: `${senderUsername}@${senderUrl.replace(/^https?:\/\/|\/$/g, '')}`,
    shareType: 'user',
    resourceType: 'file',
    protocol: 'webdav'
  };
}
