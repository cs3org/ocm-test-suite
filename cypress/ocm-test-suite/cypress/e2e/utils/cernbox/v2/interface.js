import * as general from "../../general.js";
import * as implementation from "./implementation.js";

export const platform = "cernbox";
export const version = "v2";

/**
 * Login to CERNBox v2 and land on the Files app.
 * Delegates to the v2 implementation loginCore helper.
 */
export function login({ url, username, password }) {
  implementation.loginCore({ url, username, password });
}

export function createInviteLink({
  senderUrl,
  senderDomain,
  senderUsername,
  senderPassword,
  recipientPlatform,
  recipientDomain,
  inviteLinkFileName,
}) {
  // Keep interface as the orchestrator (v1 style): login first, then perform UI flow.
  login({ url: senderUrl, username: senderUsername, password: senderPassword });
  implementation.openScienceMeshInvitations();

  // Treat plain Nextcloud/ownCloud as legacy receivers and others as token-based ScienceMesh peers.
  if (recipientPlatform === "nextcloud" || recipientPlatform === "owncloud") {
    implementation
      .createLegacyInviteLink(recipientDomain, senderDomain)
      .then((legacyUrl) => {
        cy.writeFile(inviteLinkFileName, legacyUrl);
      });
  } else {
    implementation.createInviteLink({
      senderUrl,
      senderDomain,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientDomain,
      inviteLinkFileName,
    });
  }
}

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
  login({ url: recipientUrl, username: recipientUsername, password: recipientPassword });

  cy.readFile(inviteLinkFileName).then((rawToken) => {
    const token = String(rawToken).trim();

    // Normalize sender domain to a bare host for token encoding
    const senderHost = (() => {
      try {
        const url = new URL(senderDomain.startsWith("http") ? senderDomain : `https://${senderDomain}`);
        return url.hostname;
      } catch (_e) {
        return senderDomain.replace(/^https?:\/\//, "").replace(/\/+$/, "");
      }
    })();

    let normalizedToken = token;
    if (!general.isBase64(token)) {
      normalizedToken = general.encodeBase64(`${token}@${senderHost}`);
    }

    implementation.acceptInviteLink({
      token: normalizedToken,
      senderDomain,
      senderPlatform,
      senderUsername,
      senderDisplayName,
      recipientUrl,
      recipientUsername,
      recipientPassword,
    });
  });
}

export function shareViaInviteLink({
  senderUrl,
  senderUsername,
  senderPassword,
  sharedFileName,
  sharedFileContent,
  recipientUsername,
  recipientDisplayName,
}) {
  login({ url: senderUrl, username: senderUsername, password: senderPassword });
  implementation.openFilesPersonalView();
  implementation.createFolder(sharedFileName);
  implementation.createShare(sharedFileName, recipientUsername, recipientDisplayName);
}

export function acceptInviteLinkShare({
  senderDisplayName,
  recipientUrl,
  recipientUsername,
  recipientPassword,
  recipientDisplayName,
  sharedFileName,
}) {
  login({ url: recipientUrl, username: recipientUsername, password: recipientPassword });
  implementation.openSharesWithMe();
  implementation.verifySharedWithMe({ senderDisplayName, sharedFileName });
}

export function createWayfInviteLink({
  senderUrl,
  senderUsername,
  senderPassword,
  recipientPlatform,
  recipientUrl,
  inviteLinkFileName,
}) {
  login({ url: senderUrl, username: senderUsername, password: senderPassword });
  implementation.openFilesPersonalView();
  implementation.openScienceMeshInvitations();
  implementation.createWayfInviteUrl().then((wayfUrl) => {
    cy.visit(wayfUrl);
    implementation.captureWayfRedirectUrl(recipientUrl).then((redirectUrl) => {
      cy.writeFile(inviteLinkFileName, redirectUrl);
    });
  });
}

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
  cy.readFile(inviteLinkFileName).then((redirectUrl) => {
    expect(redirectUrl).to.be.a("string").and.not.be.empty;

    login({ url: recipientUrl, username: recipientUsername, password: recipientPassword });

    implementation.acceptWayfInvite({
      senderDomain,
      senderUsername,
      senderDisplayName,
      redirectUrl,
    });
  });
}
