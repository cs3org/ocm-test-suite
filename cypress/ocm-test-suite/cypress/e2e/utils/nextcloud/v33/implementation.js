/**
 * @fileoverview
 * Implementation functions for Cypress tests interacting with Nextcloud version 33.
 * These functions provide v33-specific implementations based on the Contacts app and WAYF flow.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

/**
 * Login to Nextcloud Core.
 * Logs into Nextcloud using provided credentials, ensuring the login page is visible before interacting with it.
 *
 * @param {string} url - The URL of the Nextcloud instance.
 * @param {string} username - The username for login.
 * @param {string} password - The password for login.
 */
export function loginCore({ url, username, password }) {
  cy.visit(url);

  // Ensure the login page is visible
  cy.get('form[name="login"]', { timeout: 10000 }).should("be.visible");

  // Fill in login credentials and submit
  cy.get('form[name="login"]').within(() => {
    cy.get('input[name="user"]').type(username);
    cy.get('input[name="password"]').type(password);
    cy.contains("button[data-login-form-submit]", "Log in").click();
  });
}

/**
 * Recursively look for a file-row using v33 table structure, reloading the view between attempts.
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

  return cy.get("body").then(($body) => {
    // Check if the table exists
    const tableExists = $body.find("table.files-list__table").length > 0;
    if (tableExists) {
      const row = $body.find(
        `tbody.files-list__tbody [data-cy-files-list-row-name="${name}"]`
      );

      if (row.length > 0) {
        // Row is present in the current table; ensure it is visible.
        return cy.wrap(row.first()).scrollIntoView().should("be.visible");
      }

      // File not found in table yet, proceed to reload logic
      if (depth >= maxDepth) {
        throw new Error(
          `File "${name}" not found after ${maxDepth} reload attempts`
        );
      }

      cy.reload(true);
      return ensureFileExists(name, timeout, depth + 1, maxDepth, waitMs);
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
 *
 * @param {string} fileName - The current name of the file.
 * @param {string} newFileName - The new name for the file.
 */
export function renameFile(fileName, newFileName) {
  // Intercept the MOVE API request for renaming files
  cy.intercept("MOVE", /\/remote\.php\/dav\/files\//).as("moveFile");

  // Find the file row using v33 table structure. The Files app uses a single
  // table with class "files-list__table" and each row exposes the file name via
  // data-cy-files-list-row-name.
  cy.get("table.files-list__table", { timeout: 20000 })
    .find(`tbody.files-list__tbody [data-cy-files-list-row-name="${fileName}"]`)
    .as("fileRow");

  // Open the per-file Actions menu from that row
  cy.get("@fileRow").within(() => {
    cy.get('button[aria-label="Actions"]').click();
  });

  // Click Rename in the Actions popover.
  cy.get('[data-cy-files-list-row-action="rename"] button', {
    timeout: 10000,
  }).click();

  // Use the inline Rename file form textbox to type the new name and press Enter
  cy.get('form[aria-label="Rename file"]')
    .find("input.input-field__input")
    .clear()
    .type(`${newFileName}{enter}`);

  // Wait for the move operation to complete
  cy.wait("@moveFile");
}

/**
 * Opens the sharing panel for a specific file using v33 table structure.
 *
 * @param {string} fileName - The name of the file.
 */
export function openSharingPanel(fileName) {
  // Find the file row using v33 table structure
  cy.get("table.files-list__table", { timeout: 20000 })
    .find(`tbody.files-list__tbody [data-cy-files-list-row-name="${fileName}"]`)
    .as("fileRow");

  // Click Sharing options button in that row. In v33 this lives in a row-action
  // wrapper with data-cy-files-list-row-action="sharing-status" and an inner
  // icon-only button with aria-label="Sharing options".
  cy.get("@fileRow")
    .find(
      '[data-cy-files-list-row-action="sharing-status"] button, button[aria-label="Sharing options"]'
    )
    .first()
    .click();

  // Assert that the Sharing sidebar is open and the Sharing tab/panel is visible.
  cy.contains('[role="tab"]', "Sharing", { timeout: 20000 }).should("exist");
  cy.contains("h4", "Internal shares").should("be.visible");
  cy.contains("h4", "External shares").should("be.visible");
  cy.get(
    'input[role="combobox"][placeholder*="Type an email or federated cloud ID"]'
  ).should("be.visible");
}

/**
 * Creates a federated share for a specific contact and file using v33 Sharing sidebar.
 *
 * @param {string} domain - The domain of the Nextcloud instance.
 * @param {string} username - The username of the remote account on the recipient EFSS.
 * @param {string} displayName - The display name of the contact.
 * @param {string} contactDomain - The domain of the contact.
 * @param {string} fileName - The name of the file to be shared.
 */
export function createFederatedShare(
  domain,
  username,
  displayName,
  contactDomain,
  fileName
) {
  if (!username) {
    throw new Error(
      "createFederatedShare requires the remote account username so we can type username@domain (not displayName@domain)."
    );
  }

  // Navigate to the files app
  cy.visit(`https://${domain}/index.php/apps/files`);

  // Open the sharing panel for the file
  openSharingPanel(fileName);

  // Construct the Federated Cloud ID (e.g., einstein@cernbox1.docker).
  // IMPORTANT: this must use the remote account's username, not the display name.
  const remoteFederatedCloudId = `${username}@${contactDomain}`;
  const remoteInstanceHost = contactDomain.replace(/^https?:\/\//, "");

  // Type the remote user's Federated Cloud ID into the External shares combobox
  cy.get(
    'input[role="combobox"][placeholder*="Type an email or federated cloud ID"]'
  )
    .click()
    .type(remoteFederatedCloudId);

  // Select the host-based option (without mail icon) - e.g.,
  // "admin-builtin on 2.nextcloud.cloud.test.azadehafzar.io"
  cy.contains('[role="option"]', `on ${remoteInstanceHost}`).click();

  // Confirm the share in the "Share with ... on remote server ..." view.
  // The left-hand side of the heading (remote user label) is not stable across EFSSes:
  // sometimes it shows the username (einstein), sometimes the display name (Albert Einstein).
  // The stable bit is the remote server host.
  cy.contains("h1", `on remote server ${remoteInstanceHost}`, {
    timeout: 20000,
  }).should("be.visible");

  cy.intercept("POST", "**/ocs/v2.php/apps/files_sharing/api/v1/shares*").as(
    "createShare"
  );

  cy.contains("button", "Save share").should("be.visible").click();
  cy.wait("@createShare")
    .its("response.statusCode")
    .should("be.oneOf", [200, 201]);

  // Assert toast "Share saved"
  cy.contains("div", "Share saved").should("be.visible");

  cy.wait(1000);

  // Assert External shares list has an entry with remote badge.
  // The visible label is not stable across platforms and Nextcloud UI variants:
  // - Nextcloud -> CERNBox often shows "username@host (remote)"
  // - Nextcloud -> Nextcloud often shows "displayName (remote)"
  //
  // Click "External shares" to remove the textbox overlay that can block elements.
  cy.contains("h4", "External shares", { timeout: 20000 })
    .should("be.visible")
    .click();
  cy.wait(1000);

  const escapeRegExp = (value) =>
    String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

  const expectedFederatedId = `${username}@${remoteInstanceHost}`;
  const labelRegex = new RegExp(
    `(${escapeRegExp(expectedFederatedId)}|${escapeRegExp(
      `${displayName} (remote)`
    )}|${escapeRegExp(`${username} (remote)`)})`
  );

  // Do not scope to a specific sidebar element - it varies across Nextcloud versions/themes.
  // Use a retryable cy.contains(regex) and then validate remote badge + permissions in the same entry.
  cy.contains(labelRegex, { timeout: 20000 })
    .should("be.visible")
    .parent()
    .within(() => {
      cy.contains("(remote)").should("be.visible");
    });
}

/**
 * Handles multiple share acceptance pop-ups that may appear after reloads.
 *
 * @param {string} fileName - The name of the shared file to verify exists.
 * @param {number} [timeout=10000] - Optional timeout for the final file existence check.
 * @param {string} [appId='files'] - The app ID to navigate to after accepting shares.
 * @param {number} [depth=0] - Current recursion depth.
 * @param {number} [maxDepth=5] - Maximum allowed recursion depth to prevent infinite loops.
 */
export function handleShareAcceptance(
  fileName,
  timeout = 10000,
  appId = "files",
  depth = 0,
  maxDepth = 5
) {
  // Check if maximum recursion depth has been reached
  if (depth >= maxDepth) {
    throw new Error(`Maximum recursion depth (${maxDepth}) reached while handling share acceptance. 
      This might indicate an issue with the sharing process.`);
  }

  // Wait for the page to be fully loaded
  cy.wait(500);

  // Try to find the Remote share dialog with a reasonable timeout
  cy.get("body", { timeout: 10000 }).then(($body) => {
    // Check if Remote share dialog exists and is visible.
    const hasRemoteShareDialog =
      $body.find('[role="dialog"] h2:contains("Remote share")').length > 0;

    if (hasRemoteShareDialog) {
      // If Remote share dialog exists, accept it
      cy.contains('[role="dialog"] h2', "Remote share")
        .closest('[role="dialog"]')
        .within(() => {
          cy.contains("button", "Add remote share").click();
        });

      // Wait a bit for the acceptance to be processed
      cy.wait(500);

      // Reload and continue checking in case multiple dialogs appear
      cy.reload(true).then(() => {
        cy.wait(500);
        handleShareAcceptance(fileName, timeout, appId, depth + 1, maxDepth);
      });
    } else {
      // No more Remote share dialogs: navigate to the Shares overview and
      // verify that the shared file exists there using the v33 table structure.
      cy.wait(1000);

      ensureFileExists(fileName, timeout);
    }
  });
}

/**
 * Creates a share for a specific file and user using the same v33 Sharing sidebar
 * mechanics as federated/WAYF flows, but for native share-with scenarios.
 *
 * For Nextcloud v33, native share-with between instances is implemented as a
 * remote/federated share, so this mirrors createFederatedShare:
 *   - Go to Files app on the sender instance.
 *   - Open sharing panel for the file.
 *   - Type username@remoteHost into the External shares combobox.
 *   - Confirm the remote host dialog and save the share.
 *
 * @param {string} fileName - The name of the file to be shared.
 * @param {string} username - The username of the remote account on the recipient.
 * @param {string} domain  - The domain/host of the recipient (e.g. "nextcloud2.docker").
 */
export function createShare(fileName, username, domain) {
  if (!username) {
    throw new Error(
      "createShare requires the remote account username so we can type username@domain (not displayName@domain)."
    );
  }

  // Derive sender (local) host from current location and normalize remote host.
  return cy.location().then((loc) => {
    const localHost = loc.hostname || loc.host;
    const contactDomain = String(domain).replace(/^https?:\/\/|\/$/g, "");

    // Navigate to the Files app on the sender.
    cy.visit(`https://${localHost}/index.php/apps/files`);

    // Open the sharing panel for the file.
    openSharingPanel(fileName);

    const remoteFederatedCloudId = `${username}@${contactDomain}`;
    const remoteInstanceHost = contactDomain.replace(/^https?:\/\//, "");

    // Use the External shares combobox to type the Federated Cloud ID.
    cy.get(
      'input[role="combobox"][placeholder*="Type an email or federated cloud ID"]'
    )
      .click()
      .type(remoteFederatedCloudId);

    // Select the host-based option (without mail icon) - e.g.,
    // "username on nextcloud2.docker"
    cy.contains('[role="option"]', `on ${remoteInstanceHost}`).click();

    // Confirm the share in the "Share with ... on remote server ..." view.
    cy.contains("h1", `on remote server ${remoteInstanceHost}`, {
      timeout: 20000,
    }).should("be.visible");

    cy.intercept("POST", "**/ocs/v2.php/apps/files_sharing/api/v1/shares*").as(
      "createShare"
    );

    cy.contains("button", "Save share").should("be.visible").click();
    cy.wait("@createShare")
      .its("response.statusCode")
      .should("be.oneOf", [200, 201]);

    // Assert toast "Share saved" for parity with federated flows.
    cy.contains("div", "Share saved").should("be.visible");

    cy.wait(1000);
  });
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
    cy.stub(win.navigator.clipboard, "writeText").as("copy");
  });

  cy.get('[role="complementary"]').within(() => {
    // Locate and click the "Create a new share link" button
    cy.contains("button", "Create a new share link")
      .should("be.visible")
      .click();
  });

  // Verify that the link was copied to the clipboard and retrieve it
  return cy
    .get("@copy")
    .should("have.been.calledOnce")
    .then((stub) => {
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
export function createAndSendShareLink(
  fileName,
  recipientUsername,
  recipientDomain
) {
  return createShareLink(fileName).then((shareLink) => {
    cy.visit(shareLink);

    // Open the header actions menu and click save external share
    cy.get('button[id="header-actions-toggle"]').click();
    cy.get('button[id="save-external-share"]').click();

    // Fill in the recipient's address and save
    cy.get('form[class="save-form"]').within(() => {
      cy.get('input[id="remote_address"]').type(
        `${recipientUsername}@${recipientDomain}`
      );
      cy.get('input[id="save-button-confirm"]').click();
    });
  });
}

export function navigationPaneOpen() {
  return cy.get("body").then(($body) => {
    const $toggle = $body.find('button[aria-label="Open navigation"]');

    if ($toggle.length > 0 && Cypress.$($toggle).is(":visible")) {
      cy.wrap($toggle.first()).click();
    }
  });
}

export function navigationPaneClose() {
  return cy.get("body").then(($body) => {
    const $toggle = $body.find('button[aria-label="Close navigation"]');
    if ($toggle.length > 0 && Cypress.$($toggle).is(":visible")) {
      cy.wrap($toggle.first()).click();
    }
  });
}

/**
 * Generates an invite token for federated sharing using Contacts app.
 *
 * @param {string} recipientUrl - The URL of the recipient (used for link construction).
 * @returns {Cypress.Chainable<string>} - A chainable containing the extracted invite token.
 */
export function createInviteToken(recipientUrl) {
  // Open the Invite contact dialog
  navigationPaneOpen();
  cy.contains("button", "Invite contact").click();
  cy.contains(
    "h5",
    "Invite someone outside your organisation to collaborate."
  ).should("be.visible");

  // Fill in invite label (optional but helps with identification)
  cy.contains("label", "Invite label")
    .parent()
    .find("input")
    .type("OCM Test Invite");

  // Do NOT check "Send invite via email" - we want link-only
  // Click Send invite
  cy.contains("button", "Send invite").click();

  // Wait for redirect to invite detail page
  cy.url({ timeout: 10000 }).should("match", /\/apps\/contacts\/ocm-invites\//);
  cy.contains("h2", "OCM invite").should("be.visible");

  // Extract token from URL
  return cy.url().then((url) => {
    const urlObj = new URL(url);
    const pathParts = urlObj.pathname.split("/");
    const tokenIndex = pathParts.indexOf("ocm-invites");
    if (tokenIndex === -1 || tokenIndex === pathParts.length - 1) {
      throw new Error(
        "Token extraction failed: ocm-invites path not found in URL."
      );
    }
    const token = pathParts[tokenIndex + 1];
    if (!token) {
      throw new Error("Token extraction failed: Token not found in URL path.");
    }
    return token;
  });
}

/**
 * Generates a WAYF invite link for federated sharing using Contacts app.
 * This is the WAYF-specific implementation.
 *
 * @param {string} recipientUrl - The URL of the recipient (used for link construction, but WAYF link is on sender).
 * @returns {Cypress.Chainable<string>} - A chainable containing the generated WAYF invite link.
 */
export function createWayfInviteLink(recipientUrl) {
  // Open the Invite contact dialog
  navigationPaneOpen();
  cy.contains("button", "Invite contact").click();
  cy.contains(
    "h5",
    "Invite someone outside your organisation to collaborate."
  ).should("be.visible");

  // Fill in invite label (optional but helps with identification)
  cy.contains("label", "Invite label")
    .parent()
    .find("input")
    .type("OCM Test Invite");

  // Do NOT check "Send invite via email" - we want link-only
  // Click Send invite
  cy.contains("button", "Send invite").click();

  // Wait for redirect to invite detail page
  cy.url({ timeout: 10000 }).should("match", /\/apps\/contacts\/ocm-invites\//);
  cy.contains("h2", "OCM invite").should("be.visible");

  // Stub clipboard to capture the invite link
  cy.window().then((win) => {
    cy.stub(win.navigator.clipboard, "writeText").as("copyInvite");
  });

  // Click Copy invite link button
  cy.contains("button", "Copy invite link").click();

  // Extract the invite link from clipboard stub
  return cy
    .get("@copyInvite")
    .should("have.been.calledOnce")
    .then((stub) => {
      const inviteLink = stub.args[0][0];
      if (!inviteLink) {
        throw new Error(
          "Invite link generation failed: No link found in clipboard."
        );
      }
      return inviteLink;
    });
}

/**
 * Handles the WAYF flow: enters provider, captures redirect URL.
 * Assumes we're already on the WAYF page (called from interface.createInviteLink after visiting wayfLink).
 *
 * @param {string} recipientUrl - The recipient provider URL to enter.
 * @returns {Cypress.Chainable<string>} - A chainable containing the first redirect URL on the recipient host.
 */
export function handleWayfFlow(recipientUrl) {
  // Verify WAYF page structure
  cy.url({ timeout: 10000 }).should("match", /\/apps\/contacts\/wayf\?token=/);
  cy.contains("h2", "Providers").should("be.visible");
  cy.contains("p", "Where are you from?").should("be.visible");
  cy.contains("p", "Please tell us your Cloud Provider.").should("be.visible");

  let expectedRecipientHost = "";
  try {
    expectedRecipientHost = new URL(recipientUrl).hostname;
  } catch (e) {
    throw new Error(
      `Invalid recipientUrl passed to handleWayfFlow: "${recipientUrl}". Expected a full URL like "https://host".`
    );
  }

  // Nextcloud Contacts performs a discovery call and then navigates the browser to the recipient host.

  cy.intercept("GET", "**/apps/contacts/discover*").as("contactsDiscover");

  // Enter provider manually
  cy.contains("label", "Enter provider manually")
    .parent()
    .find("input")
    .type(`${recipientUrl}{enter}`);

  // The recipient EFSS is not necessarily Nextcloud. Capture the first redirect URL
  // whose hostname matches the provider the user entered (recipientUrl).
  //
  // For CERNBox, this is typically an /open-cloud-mesh/... URL which may then redirect
  // to an IdP for login. We intentionally capture the recipient-side URL, not the IdP URL.
  return cy
    .wait("@contactsDiscover", { timeout: 60000 })
    .its("response.statusCode")
    .should("eq", 200)
    .then(() =>
      cy.location({ timeout: 60000 }).should((loc) => {
        expect(loc.hostname).to.equal(expectedRecipientHost);
      })
    )
    .then((loc) => loc.href);
}

/**
 * Accepts the invite dialog on recipient instance after WAYF flow.
 *
 * @param {string} senderDomain - The domain of the sender instance.
 * @param {string} senderUsername - The username of the sender.
 */
export function acceptInviteDialog(senderDomain, senderUsername) {
  // Parse token and providerDomain from current URL's redirect_url parameter
  cy.url().then((currentUrl) => {
    const url = new URL(currentUrl);

    let expectedToken = url.searchParams.get("token");
    let expectedProvider = url.searchParams.get("providerDomain");

    if (!expectedToken || !expectedProvider) {
      throw new Error(
        `Token or providerDomain not found in url. Token: ${expectedToken}, Provider: ${expectedProvider}`
      );
    }

    // Wait for the invite-accept dialog to appear
    cy.contains("h5", "Accept exchange of contact info?", {
      timeout: 10000,
    }).should("be.visible");
    cy.contains(
      "p",
      "Accepting this invite will add the inviter to your contacts and share your contact info with them."
    ).should("be.visible");

    // Assert invite code matches (row contains label + token)
    cy.contains("div.detail-row", "Invite code").should(
      "contain.text",
      expectedToken
    );

    // Assert cloud provider matches (row contains label + provider host)
    cy.contains("div.detail-row", "Cloud provider").should(
      "contain.text",
      expectedProvider
    );

    // Click the Accept button inside the invite-accept dialog.
    // The visible text " Accept" lives in a span.button-vue__text inside the button,
    // so we target that span and climb back up to the button element.
    cy.contains(
      "div.contact-header__infos",
      "Accept exchange of contact info?"
    ).within(() => {
      cy.contains("span.button-vue__text", "Accept")
        .closest("button")
        .scrollIntoView()
        .click({ force: true });
    });

    // Wait for dialog to close and contact to be created
    cy.contains("h5", "Accept exchange of contact info?").should("not.exist");

    // wait even more, but we need to realod the contacts app at this stage to amke sure this is not a UI cache
    // and the contacts is really submitted to the db, I  know it sounds a bit to strict but I have seen occasions
    // that this is a case
    cy.wait(3000);
  });
}

/**
 * Verifies a federated contact in the Contacts app.
 *
 * @param {string} domain - The domain of the application.
 * @param {string} displayName - The display name of the contact.
 * @param {string} contactDomain - The expected domain of the contact.
 */
export function verifyFederatedContact(domain, displayName, contactDomain) {
  // Navigate to Contacts app
  cy.visit(`https://${domain}/apps/contacts/`);

  cy.wait(1000);
  cy.reload();
  cy.wait(1000);

  // On small viewports the Contacts nav may be collapsed and the default view
  // may not be "All contacts". Ensure nav is open and select All contacts
  // before searching for the federated contact.
  navigationPaneOpen();
  cy.contains("a", "All contacts").click();

  // Close navigation again so the contact list is fully visible.
  navigationPaneClose();

  // Verify contact exists in the contact list and open details.
  // In v33 the email is rendered inside a span.envelope__subtitle__subject
  // and wrapped by an anchor.list-item__anchor that navigates to the details view.
  cy.contains(".envelope__subtitle__subject", displayName, { timeout: 10000 })
    .should("be.visible")
    .closest("li.list-item__wrapper")
    .find("a.list-item__anchor")
    .should("be.visible");
}
