/**
 * @fileoverview
 * Utility functions for Cypress tests interacting with Nextcloud version 33.
 * These functions provide abstractions for common actions such as sharing files,
 * updating permissions, renaming files, and navigating the UI.
 *
 * For v33, the Contacts app and WAYF flow replace the legacy ScienceMesh app.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import * as general from "../../general.js";

import * as implementation from "./implementation.js";

export const platform = "nextcloud";
export const version = "v33";

/**
 * Login to Nextcloud and navigate to the files app.
 * Extends the core login functionality by verifying the dashboard and navigating to the files app.
 * Uses v33 Applications menu for navigation instead of v27 header nav.
 *
 * @param {string} url - The URL of the Nextcloud instance.
 * @param {string} username - The username for login.
 * @param {string} password - The password for login.
 */
export function login({ url, username, password }) {
  implementation.loginCore({ url, username, password });

  // Verify dashboard visibility
  cy.url({ timeout: 10000 }).should("match", /apps\/dashboard(\/|$)/);
}

/**
 * Creates an invite link via WAYF flow (Contacts app -> WAYF page -> provider entry -> redirect URL).
 * This is the WAYF-specific flow that includes the extra step of entering the provider on the WAYF page.
 *
 * For pure invite links (direct token exchange without WAYF), use createInviteLink instead.
 */
export function createWayfInviteLink({
  senderUrl,
  senderUsername,
  senderPassword,
  recipientPlatform,
  recipientUrl,
  inviteLinkFileName,
}) {
  // Step 1: Log in to the sender's instance
  login({ url: senderUrl, username: senderUsername, password: senderPassword });

  // Step 2: Navigate to the Contacts app (v33 uses Contacts instead of ScienceMesh)
  cy.get('nav[aria-label="Applications menu"]').within(() => {
    cy.get('a[href*="/apps/contacts/"]').click();
  });
  cy.url({ timeout: 10000 }).should("match", /apps\/contacts\/?/);

  // Step 3: Generate the WAYF invite link
  implementation.createWayfInviteLink(recipientUrl).then((wayfLink) => {
    // Step 4: Ensure the WAYF link is not empty
    expect(wayfLink).to.be.a("string").and.not.be.empty;

    // Step 5: Visit WAYF page and handle WAYF flow to get the first redirect URL
    // on the recipient host
    cy.visit(wayfLink);
    implementation.handleWayfFlow(recipientUrl).then((redirectUrl) => {
      // Step 6: Save the redirect URL (not the WAYF link) for recipient-side job
      cy.writeFile(inviteLinkFileName, redirectUrl);
    });
  });
}

/**
 * Creates a pure invite link (direct token/link exchange without WAYF flow).
 * This is a placeholder for future implementation of pure invite links in v33.
 *
 * For WAYF flow (with provider selection), use createWayfInviteLink instead.
 */
export function createInviteLink({
  senderUrl,
  senderUsername,
  senderPassword,
  recipientPlatform,
  recipientUrl,
  inviteLinkFileName,
}) {
  throw new Error(
    "createInviteLink for pure invite exchange is not yet implemented for Nextcloud v33. Use createWayfInviteLink for WAYF flow."
  );
}

/**
 * Accepts an invite link via WAYF flow (reads redirect URL saved by createWayfInviteLink).
 * This handles the recipient side after WAYF redirect has occurred.
 *
 * For pure invite links (direct token exchange without WAYF), use acceptInviteLink instead.
 */
export function acceptWayfInviteLink({
  senderPlatform,
  senderDomain,
  senderUsername,
  senderDisplayName,
  recipientUrl,
  recipientDomain,
  recipientUsername,
  recipientPassword,
  inviteLinkFileName,
}) {
  const flagReva = general.revaBasedWayfPlatforms.has(senderPlatform);
  const flagUsername = general.usernameContactPlatforms.has(senderPlatform);

  // Step 1: Load the redirect URL from the saved file (saved by createWayfInviteLink after WAYF flow)
  cy.readFile(inviteLinkFileName).then((redirectUrl) => {
    // Step 2: Ensure the redirect URL is valid
    expect(redirectUrl).to.be.a("string").and.not.be.empty;

    // Step 3: Log in on recipient instance
    implementation.loginCore({
      url: recipientUrl,
      username: recipientUsername,
      password: recipientPassword,
    });
    
    
    // Step 4: Visit the redirect URL
    cy.visit(redirectUrl);

    // Step 5: Accept the invitation dialog
    implementation.acceptInviteDialog(senderDomain, senderUsername);

    // Step 6: Verify that the sender is now a contact in the recipient's contacts list
    implementation.verifyFederatedContact(
      recipientDomain,
      flagUsername ? senderUsername : senderDisplayName,
      flagReva ? `reva${senderDomain}` : senderDomain
    );
  });
}

/**
 * Accepts a pure invite link (direct token/link exchange without WAYF flow).
 * This is a placeholder for future implementation of pure invite links in v33.
 *
 * For WAYF flow (with redirect URL), use acceptWayfInviteLink instead.
 */
export function acceptInviteLink({
  senderPlatform,
  senderDomain,
  senderUsername,
  senderDisplayName,
  recipientUrl,
  recipientDomain,
  recipientUsername,
  recipientPassword,
  inviteLinkFileName,
}) {
  throw new Error(
    "acceptInviteLink for pure invite exchange is not yet implemented for Nextcloud v33. Use acceptWayfInviteLink for WAYF flow."
  );
}

export function shareViaInviteLink({
  senderUrl,
  senderDomain,
  senderPlatform,
  senderUsername,
  senderPassword,
  recipientPlatform,
  recipientDomain,
  recipientUsername,
  recipientDisplayName,
  originalFileName,
  sharedFileName,
}) {
  // Step 1: Log in to the sender's Nextcloud instance
  login({ url: senderUrl, username: senderUsername, password: senderPassword });

  cy.get('nav[aria-label="Applications menu"]').within(() => {
    cy.get('a[href*="/apps/files/"]').click();
  });
  cy.url({ timeout: 10000 }).should("match", /apps\/files\/?/);

  // Step 2: Ensure the original file exists before renaming
  implementation.ensureFileExists(originalFileName);

  // Step 3: Rename the file to prepare it for sharing
  implementation.renameFile(originalFileName, sharedFileName);

  // Step 4: Verify the file has been renamed
  implementation.ensureFileExists(sharedFileName);

  const useRevaPrefix = general.revaBasedWayfPlatforms.has(senderPlatform);
  const contactDomainForShare = useRevaPrefix
    ? `reva${recipientDomain}`
    : recipientDomain;

  implementation.createFederatedShare(
    senderDomain,
    recipientUsername,
    recipientDisplayName,
    contactDomainForShare,
    sharedFileName
  );
}

export function acceptInviteLinkShare({
  recipientUrl,
  recipientUsername,
  recipientPassword,
  sharedFileName,
}) {
  // Step 1: Log in to the recipient's instance
  login({
    url: recipientUrl,
    username: recipientUsername,
    password: recipientPassword,
  });

  // Step 2: Navigate to the Files app. The Remote share dialog only appears
  // when the Files app is active, not on the Dashboard.
  cy.get('nav[aria-label="Applications menu"]').within(() => {
    cy.get('a[href*="/apps/files/"]').click();
  });
  cy.url({ timeout: 10000 }).should("match", /apps\/files\/?/);

  // Step 3: Handle any share acceptance pop-ups and verify the file exists
  implementation.handleShareAcceptance(sharedFileName);
}

export function shareViaNativeShareWith({
  senderUrl,
  senderUsername,
  senderPassword,
  originalFileName,
  sharedFileName,
  recipientUsername,
  recipientUrl,
}) {
  // Step 1: Log in to the sender's Nextcloud instance
  login({ url: senderUrl, username: senderUsername, password: senderPassword });

  // Step 2: Navigate to the Files app before interacting with the v33 files table
  cy.get('nav[aria-label="Applications menu"]').within(() => {
    cy.get('a[href*="/apps/files/"]').click();
  });
  cy.url({ timeout: 10000 }).should("match", /apps\/files\/?/);

  // Step 3: Ensure the original file exists before renaming
  implementation.ensureFileExists(originalFileName);

  // Step 4: Rename the file to prepare it for sharing
  implementation.renameFile(originalFileName, sharedFileName);

  // Step 5: Verify the file has been renamed
  implementation.ensureFileExists(sharedFileName);

  // Step 6: Create a federated share for the recipient
  implementation.createShare(
    sharedFileName,
    recipientUsername,
    recipientUrl.replace(/^https?:\/\/|\/$/g, "")
  );
}

export function acceptNativeShareWithShare({
  recipientUrl,
  recipientUsername,
  recipientPassword,
  sharedFileName,
}) {
  // Step 1: Log in to the recipient's instance
  login({
    url: recipientUrl,
    username: recipientUsername,
    password: recipientPassword,
  });

  // Step 2: Navigate to the Files app so v33 table structure is present
  cy.get('nav[aria-label="Applications menu"]').within(() => {
    cy.get('a[href*="/apps/files/"]').click();
  });
  cy.url({ timeout: 10000 }).should("match", /apps\/files\/?/);

  // Step 3: Handle any share acceptance pop-ups and verify the file exists
  implementation.handleShareAcceptance(sharedFileName);
}

export function shareViaFederatedLink({
  senderUrl,
  senderUsername,
  senderPassword,
  originalFileName,
  sharedFileName,
  recipientUsername,
  recipientUrl,
}) {
  // Step 1: Log in to the sender's Nextcloud instance
  login({ url: senderUrl, username: senderUsername, password: senderPassword });

  // Step 2: Ensure the original file exists before renaming
  implementation.ensureFileExists(originalFileName);

  // Step 3: Rename the file to prepare it for sharing
  implementation.renameFile(originalFileName, sharedFileName);

  // Step 4: Verify the file has been renamed
  implementation.ensureFileExists(sharedFileName);

  // Step 5: Create and send the share link to the recipient
  implementation.createAndSendShareLink(
    sharedFileName,
    recipientUsername,
    recipientUrl.replace(/^https?:\/\/|\/$/g, "")
  );
}

export function acceptFederatedLinkShare({
  senderPlatform,
  senderUrl,
  senderUsername,
  recipientPlatform,
  recipientUrl,
  recipientUsername,
  recipientPassword,
  sharedFileName,
}) {
  // Step 1: Log in to the recipient's instance
  login({
    url: recipientUrl,
    username: recipientUsername,
    password: recipientPassword,
  });

  if (senderPlatform == "owncloud") {
    // Step 2: Read the share URL from file
    cy.readFile("share-link-url.txt").then((shareUrl) => {
      // Step 3: Construct the federated share URL
      const federatedShareUrl = general.constructFederatedShareUrl({
        shareUrl,
        senderUrl,
        recipientUrl,
        senderUsername,
        fileName: sharedFileName,
        platform: recipientPlatform,
      });

      cy.visit(federatedShareUrl);
    });
  }

  implementation.handleShareAcceptance(sharedFileName);
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
  senderUrl,
}) {
  return {
    shareWith: `${recipientUsername}@${recipientUrl}`,
    fileName: sharedFileName,
    owner: `${senderUsername}@${senderUrl}/`,
    sender: `${senderUsername}@${senderUrl}/`,
    shareType: "user",
    resourceType: "file",
    protocol: "webdav",
  };
}
