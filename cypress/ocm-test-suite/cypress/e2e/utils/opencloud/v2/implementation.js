/**
 * Login to Opencloud Core.
 * Logs into Opencloud using provided credentials, ensuring the login page is visible before interacting with it.
 *
 * @param {string} url - The URL of the Opencloud instance.
 * @param {string} username - The username for login.
 * @param {string} password - The password for login.
 */
export function loginCore({ url, username, password }) {
  cy.visit(url);

  // Ensure the login page is visible
  cy.get("form.oc-login-form", { timeout: 10000 }).should("be.visible");

  // Fill in login credentials and submit
  cy.get("form.oc-login-form").within(() => {
    cy.get("input#oc-login-username").type(username);
    cy.get("input#oc-login-password").type(password);
    cy.get('button[type="submit"]').click();
  });
}

export function openFilesApp() {
  getApplicationSwitcher();
  getApplication("app.files.menuItem");
}

export function openScienceMeshApp() {
  getApplicationSwitcher();
  getApplication("app.open-cloud-mesh.menuItem");
}

export function createInviteToken() {
  cy.get('div[id="sciencemesh-invite"]')
    .get("span")
    .contains("Generate invitation")
    .parent()
    .scrollIntoView()
    .should("be.visible")
    .click();

  cy.get('div[id="sciencemesh-invite"]')
    .get('div[role="dialog"]')
    .within(() => {
      cy.get("button")
        .contains("Generate")
        .scrollIntoView()
        .should("be.visible")
        .click();
    });

  // we want to make sure that code is created and is displayed on the table.
  return cy
    .get('div[id="sciencemesh-invite"]')
    .get("table")
    .find("tbody>tr")
    .eq(0)
    .scrollIntoView()
    .should("be.visible")
    .invoke("attr", "data-item-id")
    .then((sometext) => {
      return sometext;
    });
}

export function createInviteBase64() {
  cy.get('div[id="sciencemesh-invite"]')
    .get("span")
    .contains("Generate invitation")
    .parent()
    .scrollIntoView()
    .should("be.visible")
    .click();

  cy.get('div[id="sciencemesh-invite"]')
    .get('div[role="dialog"]')
    .within(() => {
      cy.get("button")
        .contains("Generate")
        .scrollIntoView()
        .should("be.visible")
        .click();
    });

  // we want to make sure that code is created and is displayed on the table.
  return cy
    .get('div[id="sciencemesh-invite"]')
    .get("table")
    .find("tbody>tr")
    .eq(0)
    .scrollIntoView()
    .should("be.visible")
    .find(".invite-code-wrapper span")
    .invoke("text")
    .then((sometext) => {
      return sometext;
    });
}

export function createLegacyInviteLink(domain, providerDomain) {
  return createInviteToken().then((token) => {
    return `https://${domain}/index.php/apps/sciencemesh/accept?token=${token}&providerDomain=${providerDomain}`;
  });
}

export function acceptInviteLink(token) {
  openScienceMeshApp();

  // Log the token for debugging
  cy.log("Attempting to use token:", token);

  getScienceMeshAcceptInvitePart("label", "token").within(() => {
    cy.get('input[type="text"]')
      .clear() // Clear any existing value
      .type(token, { delay: 100 }) // Type slower to ensure input
      .should("have.value", token); // Verify the value is actually set
  });

  // Wait a bit after token verification
  cy.wait(1000);

  // Wait for button to be enabled after valid input
  getScienceMeshAcceptInvitePart("span", "accept")
    .should("not.be.disabled")
    .click();
}

export function verifyFederatedContact(name, domain) {
  openScienceMeshApp();

  getFederatedContactRow(0).eq(0).should("have.text", name);

  getFederatedContactRow(0).eq(2).should("contain", domain);
}

function openNewFileMenu(attempts = 3) {
  cy.get('button[id="new-file-menu-btn"]')
    .scrollIntoView()
    .should("be.visible")
    .click({ force: true });

  cy.wait(250);

  cy.get("body").then(($body) => {
    if ($body.find("#new-file-menu-drop:visible").length) return;
    if (attempts === 0) throw new Error("Menu never opened");
    openNewFileMenu(attempts - 1);
  });
}

export function createTextFile(filename, data) {
  openNewFileMenu();

  cy.get('div[id="new-file-menu-drop"]')
    .scrollIntoView()
    .should("be.visible")
    .find("span")
    .contains("Plain text file")
    .parent()
    .click({ force: true });

  cy.get('div[class="oc-modal-background"]')
    .scrollIntoView()
    .should("be.visible")
    .within(() => {
      cy.get('input[id^="oc-textinput"]')
        .clear()
        .type(filename)
        .should("have.value", filename);

      cy.get("button")
        .contains("Create")
        .scrollIntoView()
        .should("be.visible")
        .click({ force: true });
    });

  cy.get('div[role="textbox"]')
    .scrollIntoView()
    .should("be.visible")
    .focus()
    .type(data, { delay: 100 });

  cy.get('button[id="app-save-action"]')
    .as("saveBtn")
    .scrollIntoView()
    .should("be.visible")
    .should("be.enabled")
    .click({ force: true });

  cy.get("@saveBtn").should("be.disabled");
}

function normalizeIdentity(value) {
  return String(value || "")
    .trim()
    .toLowerCase();
}

function findBestShareRecipientOption(
  optionsLike,
  { username, recipientDisplayName }
) {
  const optionsArray = Array.from(optionsLike || []);

  if (!optionsArray.length) {
    throw new Error("No recipient autocomplete options found for share search");
  }

  const usernameNorm = normalizeIdentity(username);
  const displayNorm = normalizeIdentity(recipientDisplayName);

  const getTextNorm = (el) => normalizeIdentity(el.textContent || "");

  const findBy = (predicate) =>
    optionsArray.find((el) => {
      const textNorm = getTextNorm(el);
      return predicate(textNorm, el);
    });

  if (displayNorm) {
    const exactDisplay = findBy((textNorm) => textNorm === displayNorm);
    if (exactDisplay) return exactDisplay;
  }

  if (displayNorm) {
    const containsDisplay = findBy((textNorm) =>
      textNorm.includes(displayNorm)
    );
    if (containsDisplay) return containsDisplay;
  }

  if (usernameNorm) {
    const exactUser = findBy((textNorm) => textNorm === usernameNorm);
    if (exactUser) return exactUser;
  }

  if (usernameNorm) {
    const containsUser = findBy((textNorm) => textNorm.includes(usernameNorm));
    if (containsUser) return containsUser;
  }

  return optionsArray[0];
}

function selectShareRecipientFromAutocomplete({
  username,
  recipientDisplayName,
}) {
  cy.get('div[id="oc-files-sharing-sidebar"]').within(() => {
    cy.get('ul[role="listbox"]')
      .find('li, span, [role="option"]')
      .then(($options) => {
        const target = findBestShareRecipientOption($options, {
          username,
          recipientDisplayName,
        });

        cy.wrap(target).scrollIntoView().should("be.visible").click();
      });
  });
}

function findBestShareCollaboratorRow(
  rowsLike,
  { username, recipientDisplayName }
) {
  const rowsArray = Array.from(rowsLike || []);

  if (!rowsArray.length) {
    throw new Error("No collaborators found after creating share");
  }

  const usernameNorm = normalizeIdentity(username);
  const displayNorm = normalizeIdentity(recipientDisplayName);

  const getTextNorm = (el) => normalizeIdentity(el.textContent || "");

  const findBy = (predicate) =>
    rowsArray.find((el) => {
      const textNorm = getTextNorm(el);
      return predicate(textNorm, el);
    });

  if (displayNorm) {
    const exactDisplay = findBy((textNorm) => textNorm === displayNorm);
    if (exactDisplay) return exactDisplay;
  }

  if (displayNorm) {
    const containsDisplay = findBy((textNorm) =>
      textNorm.includes(displayNorm)
    );
    if (containsDisplay) return containsDisplay;
  }

  if (usernameNorm) {
    const exactUser = findBy((textNorm) => textNorm === usernameNorm);
    if (exactUser) return exactUser;
  }

  if (usernameNorm) {
    const containsUser = findBy((textNorm) => textNorm.includes(usernameNorm));
    if (containsUser) return containsUser;
  }

  return rowsArray[0];
}

function verifyShareRecipientInCollaboratorsList({
  username,
  recipientDisplayName,
}) {
  cy.get('div[id="oc-files-sharing-sidebar"]').within(() => {
    cy.get("#files-collaborators-list")
      .should("be.visible")
      .within(() => {
        cy.get("li").then(($rows) => {
          const row = findBestShareCollaboratorRow($rows, {
            username,
            recipientDisplayName,
          });

          cy.wrap(row)
            .as("row")
            .should("exist")
            .within(() => {
              const expectedNorms = [
                normalizeIdentity(recipientDisplayName),
                normalizeIdentity(username),
              ].filter(Boolean);

              if (expectedNorms.length) {
                cy.wrap(row)
                  .invoke("text")
                  .then((text) => {
                    const rowNorm = normalizeIdentity(text);
                    const ok = expectedNorms.some((expected) =>
                      rowNorm.includes(expected)
                    );
                    expect(ok).to.equal(true);
                  });
              }
            });
        });
      });
  });
}

export function createShare(filename, username, recipientDisplayName) {
  triggerActionForFile(filename, "share");

  ensureSearchScope("External users");

  cy.get('div[id="oc-files-sharing-sidebar"]').within(() => {
    cy.get('input[id="files-share-invite-input"]').clear();
    cy.intercept({ times: 1, method: "GET", url: "**/graph/v1.0/users?*" }).as(
      "userSearch"
    );
    cy.get('input[id="files-share-invite-input"]').type(username);
    cy.wait("@userSearch");
  });

  selectShareRecipientFromAutocomplete({ username, recipientDisplayName });

  cy.get('div[id="oc-files-sharing-sidebar"]').within(() => {
    cy.get('button[id="new-collaborators-form-create-button"]')
      .scrollIntoView()
      .should("be.visible")
      .click({ force: true });
  });

  cy.wait(1000);

  verifyShareRecipientInCollaboratorsList({
    username,
    recipientDisplayName,
  });
}

/**
 * Make sure the sidebar is set to the wanted directory
 * (“Internal users” | “External users”) before the search starts.
 */
function ensureSearchScope(scope) {
  cy.get('div[id="oc-files-sharing-sidebar"]').within(() => {
    // the pill shows the active scope
    cy.get(".invite-form-share-role-type .oc-pill").then(($pill) => {
      const current = $pill.text().trim(); // e.g. “Internal”
      if (!current.startsWith(scope.split(" ")[0])) {
        // already correct? nothing to do
        cy.wrap($pill).click(); // open the dropdown
        cy.contains(".invite-form-share-role-type-item", scope).click();
      }
    });
  });
}

export function acceptShare(filename) {
  cy.get('div[id="web-nav-sidebar"]')
    .should("be.visible")
    .find("span")
    .contains("Shares")
    .click();

  cy.get(`span[data-test-resource-name="${CSS.escape(filename)}"]`)
    .scrollIntoView()
    .should("be.visible");

  cy.get(`span[data-test-resource-name="${CSS.escape(filename)}"]`)
    .parent()
    .parent()
    .parent()
    .parent()
    .parent()
    .parent()
    .within(() => {
      cy.get('button[aria-label="Show context menu"]')
        .scrollIntoView()
        .should("be.visible")
        .click({ force: true });

      cy.get("span")
        .contains("Enable sync")
        .scrollIntoView()
        .should("be.visible")
        .click({ force: true });
    });
}

export function verifyShare(filename, owner, receiver) {
  cy.get('div[id="web-nav-sidebar"]')
    .should("be.visible")
    .find("span")
    .contains("Shares")
    .click();

  cy.get(`span[data-test-resource-name="${CSS.escape(filename)}"]`)
    .scrollIntoView()
    .should("be.visible");

  cy.get(`span[data-test-resource-name="${CSS.escape(filename)}"]`)
    .parent()
    .parent()
    .parent()
    .parent()
    .parent()
    .parent()
    .within(() => {
      cy.get(`span[data-test-user-name="${CSS.escape(owner)}"]`).should(
        "exist"
      );
      cy.get(`span[data-test-user-name="${CSS.escape(receiver)}"]`).should(
        "exist"
      );
    });
}

export const getFederatedContactRow = (row) =>
  cy
    .get('div[id="sciencemesh-connections"]')
    .get("table")
    .find("tbody>tr")
    .eq(row)
    .find("td");

export const getApplication = (appName) =>
  getApplicationMenu()
    .find(`a[data-test-id="${CSS.escape(appName)}"]`, { timeout: 5000 })
    .should("be.visible")
    .click({ force: true });

export const getApplicationSwitcher = () =>
  getApplicationMenu()
    .find('button[id="_appSwitcherButton"]', { timeout: 5000 })
    .should("be.visible")
    .click({ force: true });

export const getApplicationMenu = () =>
  cy.get('nav[id="applications-menu"]', { timeout: 5000 }).should("be.visible");

// possible partIds are:
// - token
// - accept
export function getScienceMeshAcceptInvitePart(element, partId) {
  const partIdList = new Map([
    ["token", "Enter invite token"],
    ["accept", "Accept invitation"],
  ]);

  const partLabel = partIdList.get(partId) ?? partIdList.get("token");

  return cy
    .get('div[id="sciencemesh-accept-invites"]')
    .find(element)
    .contains(partLabel)
    .parent()
    .scrollIntoView()
    .should("be.visible");
}

// possible actionIds are:
// - share
// - copyLink
// - contextMenu
export function triggerActionForFile(filename, actionId) {
  const actionIdList = new Map([
    ["share", "Share"],
    ["copyLink", "Copy link"],
    ["contextMenu", "Show context menu"],
  ]);

  const actionAriaLabel =
    actionIdList.get(actionId) ?? actionIdList.get("share");

  getActionsForFile(filename)
    .find(`button[aria-label="${CSS.escape(actionAriaLabel)}"]`)
    .should("exist")
    .scrollIntoView()
    .should("be.visible")
    .click({ force: true });
}

export const getActionsForFile = (filename) =>
  getRowForFile(filename).find('*[class^="resource-table-actions"]');

// @MahdiBaghbani: Yes, I know this is horrible! :)
export const getRowForFile = (filename) =>
  cy
    .get(`[data-test-resource-name="${CSS.escape(filename)}"]`)
    .parent()
    .parent()
    .parent()
    .parent()
    .parent()
    .parent();
