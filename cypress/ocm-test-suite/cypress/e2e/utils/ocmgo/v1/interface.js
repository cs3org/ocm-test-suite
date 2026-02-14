/**
 * @fileoverview
 * Cypress adapter for OCM-Go v1.
 * Exports platform metadata and the standard helper set consumed by spec files.
 */

import * as implementation from './implementation.js';

export const platform = 'ocmgo';
export const version = 'v1';
export const versionAliases = ['v1.0.0'];

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

export function login({ url, username, password }) {
  implementation.doLogin(url, username, password);
}

// ---------------------------------------------------------------------------
// Native share-with (no prior invite needed)
// ---------------------------------------------------------------------------

export function shareViaNativeShareWith({
  senderUrl,
  senderUsername,
  senderPassword,
  originalFileName,
  sharedFileName,
  recipientUsername,
  recipientUrl,
}) {
  login({ url: senderUrl, username: senderUsername, password: senderPassword });

  const fileName = originalFileName || sharedFileName;
  const localPath = `/data/${senderUsername}/${fileName}`;
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, '');
  const shareWith = `${recipientUsername}@${recipientDomain}`;

  implementation.fillOutgoingShareForm(senderUrl, shareWith, localPath);
}

export function acceptNativeShareWithShare({
  recipientUrl,
  recipientUsername,
  recipientPassword,
  sharedFileName,
}) {
  login({ url: recipientUrl, username: recipientUsername, password: recipientPassword });
  implementation.acceptShareInInbox(recipientUrl, sharedFileName);
}

// ---------------------------------------------------------------------------
// Invite link
// ---------------------------------------------------------------------------

/**
 * Create an invite token via the outgoing UI and write the base64 invite
 * string to a file for the recipient to import.
 */
export function createInviteLink({
  senderUrl,
  senderUsername,
  senderPassword,
  inviteLinkFileName,
}) {
  login({ url: senderUrl, username: senderUsername, password: senderPassword });

  implementation.createInvite(senderUrl).then((inviteString) => {
    cy.writeFile(inviteLinkFileName, inviteString);
  });
}

/**
 * Read the invite string from file, import it via the API, and accept.
 */
export function acceptInviteLink({
  recipientUrl,
  recipientUsername,
  recipientPassword,
  inviteLinkFileName,
}) {
  // Login first so the session cookie is available for API calls
  implementation.doLogin(recipientUrl, recipientUsername, recipientPassword);

  cy.readFile(inviteLinkFileName).then((raw) => {
    const inviteString = String(raw).trim();
    implementation.importAndAcceptInvite(recipientUrl, inviteString);
  });
}

/**
 * Share a file with a federated contact established via invite link.
 * Uses the same outgoing share form as native share-with.
 */
export function shareViaInviteLink({
  senderUrl,
  senderUsername,
  senderPassword,
  sharedFileName,
  recipientUsername,
  recipientUrl,
  recipientDisplayName,
  originalFileName,
}) {
  login({ url: senderUrl, username: senderUsername, password: senderPassword });

  const fileName = originalFileName || sharedFileName;
  const localPath = `/data/${senderUsername}/${fileName}`;
  const domain = recipientUrl
    ? recipientUrl.replace(/^https?:\/\/|\/$/g, '')
    : recipientDisplayName || '';
  const shareWith = `${recipientUsername}@${domain}`;

  implementation.fillOutgoingShareForm(senderUrl, shareWith, localPath);
}

/**
 * Accept an incoming share received via invite link.
 * Identical to acceptNativeShareWithShare (the inbox UI is the same).
 */
export function acceptInviteLinkShare({
  recipientUrl,
  recipientUsername,
  recipientPassword,
  sharedFileName,
}) {
  login({ url: recipientUrl, username: recipientUsername, password: recipientPassword });
  implementation.acceptShareInInbox(recipientUrl, sharedFileName);
}

// ---------------------------------------------------------------------------
// WAYF (Where Are You From)
// ---------------------------------------------------------------------------

/**
 * Create an invite, visit the sender's WAYF page, discover the recipient
 * provider, and capture the redirect URL (on the recipient's domain).
 * Writes the redirect URL to file for the recipient to consume.
 *
 * All browser activity stays on the sender's origin -- no cross-origin.
 */
export function createWayfInviteLink({
  senderUrl,
  senderUsername,
  senderPassword,
  recipientUrl,
  inviteLinkFileName,
}) {
  login({ url: senderUrl, username: senderUsername, password: senderPassword });

  cy.request({
    method: 'POST',
    url: `${senderUrl}/api/invites/outgoing`,
    body: {},
  }).then((res) => {
    expect(res.status).to.eq(201);
    const wayfUrl = `${senderUrl}/ui/wayf?token=${res.body.token}`;

    implementation.captureWayfRedirectUrl(wayfUrl, recipientUrl).then((redirectUrl) => {
      cy.writeFile(inviteLinkFileName, redirectUrl);
    });
  });
}

/**
 * Read the redirect URL from file (on the recipient's own domain),
 * log in on the recipient, and accept the WAYF invite. No cross-origin.
 */
export function acceptWayfInviteLink({
  recipientUrl,
  recipientUsername,
  recipientPassword,
  inviteLinkFileName,
}) {
  cy.readFile(inviteLinkFileName).then((raw) => {
    const redirectUrl = String(raw).trim();
    expect(redirectUrl).to.be.a('string').and.not.be.empty;

    implementation.doLogin(recipientUrl, recipientUsername, recipientPassword);
    implementation.acceptWayfInvite(redirectUrl);
  });
}

// ---------------------------------------------------------------------------
// Cross-platform helpers
// ---------------------------------------------------------------------------

/**
 * Build a federated share details object for metadata verification by other
 * platform adapters (e.g. when ocmstub verifies an incoming share from ocmgo).
 */
export function buildFederatedShareDetails({
  recipientUsername,
  recipientUrl,
  sharedFileName,
  senderUsername,
  senderUrl,
}) {
  const strip = (u) => u.replace(/^https?:\/\/|\/$/g, '');
  return {
    shareWith: `${recipientUsername}@${strip(recipientUrl)}`,
    fileName: sharedFileName,
    owner: `${senderUsername}@${strip(senderUrl)}`,
    sender: `${senderUsername}@${strip(senderUrl)}`,
    shareType: 'user',
    resourceType: 'file',
    protocol: 'webdav',
  };
}

/**
 * Accept a federated link share. Same flow as acceptNativeShareWithShare
 * for OCM-Go (the inbox UI handles both).
 */
export function acceptFederatedLinkShare({
  recipientUrl,
  recipientUsername,
  recipientPassword,
  sharedFileName,
}) {
  login({ url: recipientUrl, username: recipientUsername, password: recipientPassword });
  implementation.acceptShareInInbox(recipientUrl, sharedFileName);
}
