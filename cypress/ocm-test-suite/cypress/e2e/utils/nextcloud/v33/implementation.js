/**
 * @fileoverview
 * Implementation functions for Cypress tests interacting with Nextcloud version 33.
 * These functions provide v33-specific implementations based on the Contacts app and WAYF flow.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import {
  escapeCssSelector,
} from '../../general.js';

/**
 * Login to Nextcloud Core.
 * Logs into Nextcloud using provided credentials, ensuring the login page is visible before interacting with it.
 * Uses the same form selectors as v27 (journal: login-page).
 *
 * @param {string} url - The URL of the Nextcloud instance.
 * @param {string} username - The username for login.
 * @param {string} password - The password for login.
 */
export function loginCore({ url, username, password }) {
  cy.visit(url);

  // Ensure the login page is visible
  cy.get('form[name="login"]', { timeout: 10000 }).should('be.visible');

  // Fill in login credentials and submit
  cy.get('form[name="login"]').within(() => {
    cy.get('input[name="user"]').type(username);
    cy.get('input[name="password"]').type(password);
    cy.contains('button[data-login-form-submit]', 'Log in').click();
  });
}

/**
 * Recursively look for a file-row using v33 table structure, reloading the view between attempts.
 * Uses table[aria-label^="List of your files and folders"] instead of [data-file] (journal: job3-ensure-and-rename-sender).
 *
 * @param {string} name      The file name to locate.
 * @param {number} timeout   Final visible-check timeout (ms). Default 20 000.
 * @param {number} depth     Current recursion depth - do not set manually.
 * @param {number} maxDepth  Maximum reload attempts. Default 3.
 * @param {number} waitMs    Delay between attempts (ms). Default 500.
 */
export function ensureFileExists(
  name,
  timeout = 20000,
  depth = 0,
  maxDepth = 3,
  waitMs = 500
) {
  cy.wait(waitMs);

  return cy.get('body').then(($body) => {
    // Check if the table exists
    const tableExists = $body.find('table[aria-label^="List of your files and folders"]').length > 0;
    if (tableExists) {
      // Try to find the file row - use contains to match text in the row
      return cy.get('table[aria-label^="List of your files and folders"]', { timeout: 5000 })
        .contains('tr', name, { timeout })
        .should('be.visible')
        .catch(() => {
          // File not found in table, proceed to reload logic
          if (depth >= maxDepth) {
            throw new Error(
              `File "${name}" not found after ${maxDepth} reload attempts`
            );
          }
          cy.reload(true);
          return ensureFileExists(name, timeout, depth + 1, maxDepth, waitMs);
        });
    }
    
    // Table doesn't exist, reload and retry
    if (depth >= maxDepth) {
      throw new Error(
        `File "${name}" not found after ${maxDepth} reload attempts`
      );
    }

    cy.reload(true);
    return ensureFileExists(name, timeout, depth + 1, maxDepth, waitMs);
  });
}

/**
 * Renames a file using v33 table structure and Actions menu.
 * Uses table row + Actions button + Rename menu item + Rename file form (journal: job3-ensure-and-rename-sender).
 * 
 * @param {string} fileName - The current name of the file.
 * @param {string} newFileName - The new name for the file.
 */
export function renameFile(fileName, newFileName) {
  // Intercept the MOVE API request for renaming files
  cy.intercept('MOVE', /\/remote\.php\/dav\/files\//).as('moveFile');

  // Find the file row using v33 table structure
  cy.get('table[aria-label^="List of your files and folders"]').within(() => {
    cy.contains('tr', fileName, { timeout: 20000 }).as('fileRow');
  });

  // Open the per-file Actions menu from that row
  cy.get('@fileRow').within(() => {
    cy.contains('button', 'Actions').click();
  });

  // Click Rename in the Actions menu
  cy.contains('menu[aria-label="Actions"] menuitem', 'Rename').click();

  // Use the inline Rename file form textbox to type the new name and press Enter
  cy.get('form[aria-label="Rename file"] input[aria-label="Filename"]')
    .clear()
    .type(`${newFileName}{enter}`);

  // Wait for the move operation to complete
  cy.wait('@moveFile');
}

/**
 * Opens the sharing panel for a specific file using v33 table structure.
 * Uses table row + Sharing options button (journal: job3-share-design-sender).
 * 
 * @param {string} fileName - The name of the file.
 */
export function openSharingPanel(fileName) {
  // Find the file row using v33 table structure
  cy.get('table[aria-label^="List of your files and folders"]').within(() => {
    cy.contains('tr', fileName, { timeout: 20000 }).as('fileRow');
  });

  // Click Sharing options button in that row
  cy.get('@fileRow').within(() => {
    cy.contains('button', 'Sharing options').click();
  });

  // Assert that the Sharing sidebar is open and the Sharing tab/panel is visible
  cy.get('[role="complementary"]').within(() => {
    cy.contains('[role="tab"]', 'Sharing').should('exist');
    cy.contains('h3', 'Sharing').should('be.visible');
    cy.contains('h4', 'Internal shares').should('be.visible');
    cy.contains('h4', 'External shares').should('be.visible');
    cy.get('[role="combobox"][aria-label*="Enter external recipients"]').should('be.visible');
  });
}

/**
 * Creates a federated share for a specific contact and file using v33 Sharing sidebar.
 * Uses External shares combobox and host-based recipient selection (journal: job3-share-design-sender).
 * 
 * @param {string} domain - The domain of the Nextcloud instance.
 * @param {string} displayName - The display name of the contact.
 * @param {string} contactDomain - The domain of the contact.
 * @param {string} fileName - The name of the file to be shared.
 */
export function createFederatedShare(domain, displayName, contactDomain, fileName) {
  // Navigate to the files app
  cy.visit(`https://${domain}/index.php/apps/files`);

  // Open the sharing panel for the file
  openSharingPanel(fileName);

  // Construct the Federated Cloud ID (e.g., admin-builtin@2.nextcloud.cloud.test.azadehafzar.io)
  const remoteFederatedCloudId = `${displayName}@${contactDomain}`;
  const remoteInstanceHost = contactDomain.replace(/^https?:\/\//, '');

  // Type the remote user's Federated Cloud ID into the External shares combobox
  cy.get('[role="combobox"][aria-label*="Enter external recipients"]')
    .click()
    .type(remoteFederatedCloudId);

  // Select the host-based option (without mail icon) - e.g., "admin-builtin on 2.nextcloud..."
  cy.contains('[role="option"]', `on ${remoteInstanceHost}`).click();

  // Click Save share
  cy.get('[role="button"]').contains('Save share').click();

  // Assert toast "Share saved"
  cy.contains('div', 'Share saved').should('be.visible');

  // Assert file row now shows Shared with others
  cy.get('table[aria-label^="List of your files and folders"]').within(() => {
    cy.contains('tr', fileName).within(() => {
      cy.contains('button', 'Shared with others').should('be.visible');
    });
  });

  // Assert External shares list has an entry with remote badge
  cy.get('[role="complementary"]').within(() => {
    cy.contains('h4', 'External shares').should('be.visible');
    cy.contains('div', displayName).parent().within(() => {
      cy.contains('(remote)').should('be.visible');
      cy.contains('button', 'Can edit').should('be.visible');
    });
  });
}

/**
 * Handles multiple share acceptance pop-ups that may appear after reloads.
 * Uses v33 Remote share dialog instead of v27 oc-dialog (journal: job3-share-design-recipient).
 * 
 * @param {string} fileName - The name of the shared file to verify exists.
 * @param {number} [timeout=10000] - Optional timeout for the final file existence check.
 * @param {string} [appId='files'] - The app ID to navigate to after accepting shares.
 * @param {number} [depth=0] - Current recursion depth.
 * @param {number} [maxDepth=5] - Maximum allowed recursion depth to prevent infinite loops.
 */
export function handleShareAcceptance(fileName, timeout = 10000, appId = 'files', depth = 0, maxDepth = 5) {
  // Check if maximum recursion depth has been reached
  if (depth >= maxDepth) {
    throw new Error(`Maximum recursion depth (${maxDepth}) reached while handling share acceptance. 
      This might indicate an issue with the sharing process.`);
  }

  // Wait for the page to be fully loaded
  cy.wait(500);

  // Try to find the Remote share dialog with a reasonable timeout
  cy.get('body', { timeout: 10000 }).then($body => {
    // Check if Remote share dialog exists and is visible (v33 uses dialog h2 instead of div.oc-dialog)
    const hasRemoteShareDialog = $body.find('dialog h2:contains("Remote share")').length > 0;

    if (hasRemoteShareDialog) {
      // If dialog exists, accept it
      cy.contains('dialog h2', 'Remote share').parent().within(() => {
        cy.contains('button', 'Add remote share').click();
      });
      // Wait a bit for the acceptance to be processed
      cy.wait(500);
      // Reload and continue checking
      cy.reload(true).then(() => {
        // Wait for page load after reload
        cy.wait(500);
        // Recursively check for more pop-ups with incremented depth
        handleShareAcceptance(fileName, timeout, appId, depth + 1, maxDepth);
      });
    } else {
      // No more pop-ups, wait for the file list to be loaded
      cy.wait(1000);

      // Verify the shared file exists with specified timeout using v33 table structure
      ensureFileExists(fileName, timeout);
    }
  });
}

/**
 * Creates a share for a specific file and user using v33 Sharing sidebar.
 * 
 * @param {string} fileName - The name of the file to be shared.
 * @param {string} username - The username of the recipient.
 * @param {string} domain - The domain of the recipient.
 */
export function createShare(fileName, username, domain) {
  // Open the sharing panel for the specified file
  openSharingPanel(fileName);

  // Set up an intercept for the user search API request
  cy.intercept('GET', '**/apps/files_sharing/api/v1/sharees?*').as('userSearch');

  cy.get('[role="complementary"]').within(() => {
    // Use Internal shares combobox for local users
    cy.get('[role="combobox"][aria-label*="Search for internal recipients"]')
      .clear()
      .type(`${username}@${domain}`);
  });

  // Wait for the user search API request to complete
  cy.wait('@userSearch');

  // Select the correct user from the search results
  cy.get(`[user="${username}"]`)
    .should('be.visible')
    .click();

  // Click the "Save share" button to finalize the share
  cy.get('[role="button"]')
    .contains('Save share')
    .should('be.visible')
    .click();
}

/**
 * Creates a shareable link for a file and returns the copied link using v33 Sharing sidebar.
 * 
 * @param {string} fileName - The name of the file to create a link for.
 * @returns {Cypress.Chainable<string>} - A chainable containing the copied share link.
 */
export function createShareLink(fileName) {
  // Open the sharing panel for the specified file
  openSharingPanel(fileName);

  // Stub the clipboard API to intercept the copied link
  cy.window().then((win) => {
    cy.stub(win.navigator.clipboard, 'writeText').as('copy');
  });

  cy.get('[role="complementary"]').within(() => {
    // Locate and click the "Create a new share link" button
    cy.contains('button', 'Create a new share link')
      .should('be.visible')
      .click();
  });

  // Verify that the link was copied to the clipboard and retrieve it
  return cy.get('@copy').should('have.been.calledOnce').then((stub) => {
    const copiedLink = stub.args[0][0];
    return copiedLink;
  });
}

/**
 * Creates and sends a federated share link to a recipient.
 * 
 * @param {string} fileName - The name of the file to share.
 * @param {string} recipientUsername - The username of the recipient.
 * @param {string} recipientDomain - The domain of the recipient (without protocol).
 * @returns {Cypress.Chainable} - A chainable Cypress command.
 */
export function createAndSendShareLink(fileName, recipientUsername, recipientDomain) {
  return createShareLink(fileName).then((shareLink) => {
    cy.visit(shareLink);

    // Open the header actions menu and click save external share
    cy.get('button[id="header-actions-toggle"]').click();
    cy.get('button[id="save-external-share"]').click();

    // Fill in the recipient's address and save
    cy.get('form[class="save-form"]').within(() => {
      cy.get('input[id="remote_address"]').type(`${recipientUsername}@${recipientDomain}`);
      cy.get('input[id="save-button-confirm"]').click();
    });
  });
}

/**
 * Generates an invite token for federated sharing using Contacts app.
 * Extracts the token from the invite detail page (journal: invite-token-page).
 * 
 * @param {string} recipientUrl - The URL of the recipient (used for link construction).
 * @returns {Cypress.Chainable<string>} - A chainable containing the extracted invite token.
 */
export function createInviteToken(recipientUrl) {
  // Open the Invite contact dialog
  cy.contains('button', 'Invite contact').click();
  cy.contains('h5', 'Invite someone outside your organisation to collaborate.').should('be.visible');

  // Fill in invite label (optional but helps with identification)
  cy.contains('label', 'Invite label').parent().find('input').type('OCM Test Invite');

  // Do NOT check "Send invite via email" - we want link-only
  // Click Send invite
  cy.contains('button', 'Send invite').click();

  // Wait for redirect to invite detail page
  cy.url({ timeout: 10000 }).should('match', /\/apps\/contacts\/ocm-invites\//);
  cy.contains('h2', 'OCM invite').should('be.visible');

  // Extract token from URL
  return cy.url().then((url) => {
    const urlObj = new URL(url);
    const pathParts = urlObj.pathname.split('/');
    const tokenIndex = pathParts.indexOf('ocm-invites');
    if (tokenIndex === -1 || tokenIndex === pathParts.length - 1) {
      throw new Error('Token extraction failed: ocm-invites path not found in URL.');
    }
    const token = pathParts[tokenIndex + 1];
    if (!token) {
      throw new Error('Token extraction failed: Token not found in URL path.');
    }
    return token;
  });
}

/**
 * Generates a WAYF invite link for federated sharing using Contacts app.
 * Creates invite via Contacts dialog and returns the WAYF link (journal: contacts-invite-dialog, invite-token-page).
 * This is the WAYF-specific implementation.
 * 
 * @param {string} recipientUrl - The URL of the recipient (used for link construction, but WAYF link is on sender).
 * @returns {Cypress.Chainable<string>} - A chainable containing the generated WAYF invite link.
 */
export function createWayfInviteLink(recipientUrl) {
  // Open the Invite contact dialog
  cy.contains('button', 'Invite contact').click();
  cy.contains('h5', 'Invite someone outside your organisation to collaborate.').should('be.visible');

  // Fill in invite label (optional but helps with identification)
  cy.contains('label', 'Invite label').parent().find('input').type('OCM Test Invite');

  // Do NOT check "Send invite via email" - we want link-only
  // Click Send invite
  cy.contains('button', 'Send invite').click();

  // Wait for redirect to invite detail page
  cy.url({ timeout: 10000 }).should('match', /\/apps\/contacts\/ocm-invites\//);
  cy.contains('h2', 'OCM invite').should('be.visible');

  // Stub clipboard to capture the invite link
  cy.window().then((win) => {
    cy.stub(win.navigator.clipboard, 'writeText').as('copyInvite');
  });

  // Click Copy invite link button
  cy.contains('button', 'Copy invite link').click();

  // Extract the invite link from clipboard stub
  return cy.get('@copyInvite').should('have.been.calledOnce').then((stub) => {
    const inviteLink = stub.args[0][0];
    if (!inviteLink) {
      throw new Error('Invite link generation failed: No link found in clipboard.');
    }
    return inviteLink;
  });
}

/**
 * Handles the WAYF flow: enters provider, captures redirect URL.
 * Assumes we're already on the WAYF page (called from interface.createInviteLink after visiting wayfLink).
 * This handles cross-origin constraint (journal: wayf-page, recipient-login-redirect-url).
 * 
 * @param {string} recipientUrl - The recipient provider URL to enter.
 * @returns {Cypress.Chainable<string>} - A chainable containing the redirect URL to recipient login page.
 */
export function handleWayfFlow(recipientUrl) {
  // Verify WAYF page structure
  cy.url({ timeout: 10000 }).should('match', /\/apps\/contacts\/wayf\?token=/);
  cy.contains('h2', 'Providers').should('be.visible');
  cy.contains('p', 'Where are you from?').should('be.visible');
  cy.contains('p', 'Please tell us your Cloud Provider.').should('be.visible');

  // Enter provider manually
  cy.contains('label', 'Enter provider manually').parent().find('input')
    .type(`${recipientUrl}{enter}`);

  // Wait for redirect to recipient login page and capture the URL
  const recipientHost = recipientUrl.replace(/^https?:\/\//, '');
  cy.url({ timeout: 10000 }).should('include', `${recipientHost}/index.php/login?redirect_url=`);
  
  return cy.url().then((redirectUrl) => {
    return redirectUrl;
  });
}

/**
 * Accepts the invite dialog on recipient instance after WAYF flow.
 * Parses token and providerDomain from redirect_url and verifies them in the dialog (journal: invite-accept-dialog-ui).
 * 
 * @param {string} senderDomain - The domain of the sender instance.
 * @param {string} senderUsername - The username of the sender.
 */
export function acceptInviteDialog(senderDomain, senderUsername) {
  // Parse token and providerDomain from current URL's redirect_url parameter
  cy.url().then((currentUrl) => {
    const url = new URL(currentUrl);
    const redirectParam = url.searchParams.get('redirect_url');
    if (!redirectParam) {
      throw new Error('redirect_url parameter not found in URL');
    }
    const redirectUrl = new URL(redirectParam, currentUrl);
    const expectedToken = redirectUrl.searchParams.get('token');
    const expectedProvider = redirectUrl.searchParams.get('providerDomain');

    if (!expectedToken || !expectedProvider) {
      throw new Error(`Token or providerDomain not found in redirect_url. Token: ${expectedToken}, Provider: ${expectedProvider}`);
    }

    // Wait for the invite-accept dialog to appear
    cy.contains('h5', 'Accept exchange of contact info?', { timeout: 10000 }).should('be.visible');
    cy.contains('p', 'Accepting this invite will add the inviter to your contacts and share your contact info with them.').should('be.visible');

    // Assert invite code matches
    cy.contains('div, span', 'Invite code').next().should('have.text', expectedToken);

    // Assert cloud provider matches
    cy.contains('div, span', 'Cloud provider').next().should('have.text', expectedProvider);

    // Click Accept button
    cy.contains('button', 'Accept').click();

    // Wait for dialog to close and contact to be created
    cy.contains('h5', 'Accept exchange of contact info?').should('not.exist');
  });
}

/**
 * Verifies a federated contact in the Contacts app.
 * Uses v33 Contacts app structure instead of ScienceMesh contacts table (journal: invite-accept-dialog-ui).
 * 
 * @param {string} domain - The domain of the application.
 * @param {string} displayName - The display name of the contact.
 * @param {string} contactDomain - The expected domain of the contact.
 */
export function verifyFederatedContact(domain, displayName, contactDomain) {
  // Navigate to Contacts app
  cy.visit(`https://${domain}/index.php/apps/contacts/`);

  // Verify contact exists in the contact list
  // The contact should appear as "displayName displayName@contactDomain"
  cy.contains('a', `${displayName}@${contactDomain}`, { timeout: 10000 }).should('be.visible');

  // Click on the contact to view details
  cy.contains('a', `${displayName}@${contactDomain}`).click();

  // Verify Federated Cloud ID field matches expected value
  cy.contains('h3', 'Federated Cloud ID').parent().find('input, textarea')
    .should('have.value', `${displayName}@${contactDomain}`);
}
