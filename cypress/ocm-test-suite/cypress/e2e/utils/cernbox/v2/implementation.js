// CERNBox v2 Cypress implementations.

function maybeDismissUnsupportedBrowserGate() {
  cy.get("body").then(($body) => {
    const root = $body.get(0);
    if (!root) return;

    const text = root.textContent || "";
    if (!text.includes("Your browser is not supported")) return;

    const candidates = Array.from(root.querySelectorAll("button, a"));
    const el = candidates.find((node) =>
      (node.textContent || "").includes("I want to continue anyway")
    );

    // The page often redirects immediately to /login and then to the IdP.
    // Use a synchronous DOM click so Cypress does not wait for actionability
    // on an element that can disappear mid-command.
    if (el && typeof el.click === "function") {
      el.click();
    }
  });
}

export const getApplicationMenu = () =>
  cy.get('nav[id="applications-menu"]', { timeout: 15000 }).should("be.visible");

export const getApplicationSwitcher = () =>
  getApplicationMenu()
    .find('button[id="_appSwitcherButton"]', { timeout: 15000 })
    .scrollIntoView()
    .should("be.visible")
    .click({ force: true });

export const getApplication = (appName) =>
  getApplicationMenu()
    .find(
      `a[href="/${appName}"], a[href="/${appName}/"], a[data-test-id="${appName}"]`,
      { timeout: 15000 }
    )
    .filter(":visible")
    .first()
    .should("be.visible")
    .click({ force: true });

function openNewFileMenu(attempts = 3) {
  cy.wait(2000);
  cy.get('button[id="new-file-menu-btn"]', { timeout: 15000 })
    .scrollIntoView()
    .should("be.visible")
    .click({ force: true });

  cy.wait(250);

  cy.get("body").then(($body) => {
    if ($body.find('#new-file-menu-drop:visible').length) return;
    if (attempts === 0) throw new Error("Menu never opened");
    openNewFileMenu(attempts - 1);
  });
}

export function createFolder(folderName) {
  openNewFileMenu();

  cy.get('div[id="new-file-menu-drop"]', { timeout: 15000 })
    .scrollIntoView()
    .should("be.visible")
    .within(() => {
      cy.contains("span", /Folder/i, { timeout: 15000 })
        .first()
        .parent()
        .click({ force: true });
    });

  cy.get('div[class="oc-modal-background"]', { timeout: 15000 })
    .scrollIntoView()
    .should("be.visible")
    .within(() => {
      cy.get('input[id^="oc-textinput"]', { timeout: 15000 })
        .clear()
        .type(folderName)
        .should("have.value", folderName);

      cy.contains("button", "Create", { timeout: 15000 })
        .scrollIntoView()
        .should("be.visible")
        .click({ force: true });
    });

  cy.get(`[data-test-resource-name="${CSS.escape(folderName)}"]`, {
    timeout: 20000,
  })
    .scrollIntoView()
    .should("be.visible");
}

// possible actionIds are: share | copyLink | contextMenu
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

// Yes, I know this is horrible! :)
export const getRowForFile = (filename) =>
  cy.get(`[data-test-resource-name="${CSS.escape(filename)}"]`)
    .parent()
    .parent()
    .parent()
    .parent()
    .parent()
    .parent();

const getSidebarNav = () =>
  cy.get('nav[aria-label="Sidebar navigation menu"]', { timeout: 15000 }).should(
    "be.visible"
  );

const clickSidebarEntry = (label) =>
  getSidebarNav()
    // v1-style: click the visible label span (OC Web renders links with nested spans)
    .contains("span", label, { timeout: 15000 })
    .scrollIntoView()
    .should("be.visible")
    .click({ force: true });

export function openFilesPersonalView() {
  cy.url({ timeout: 15000 }).should("include", "/files/");
  clickSidebarEntry("Personal");
}

export function openSharesWithMe() {
  cy.url({ timeout: 15000 }).should("include", "/files/");
  clickSidebarEntry("Shares");
  cy.url({ timeout: 15000 }).should("include", "/files/shares/with-me");
  cy.contains("span", "Shared with me").should("be.visible");
}

export function openScienceMeshInvitations() {
  getApplicationSwitcher();
  getApplication("open-cloud-mesh");
  cy.url({ timeout: 15000 }).should("include", "/open-cloud-mesh/invitations");
}

// Ensure the share search is scoped to the wanted directory before typing.
// CERNBox/OC Web can render this as a pill dropdown or as an "Internal" mode button.
function ensureShareSearchScope(scope) {
  cy.get('div[id="oc-files-sharing-sidebar"]', { timeout: 15000 })
    .should("be.visible")
    .then(($sidebar) => {
      const $pill = $sidebar.find(".invite-form-share-role-type .oc-pill");
      if ($pill.length) {
        const current = ($pill.text() || "").trim();
        if (!current.startsWith(scope.split(" ")[0])) {
          cy.wrap($pill).click({ force: true });
          cy.contains(".invite-form-share-role-type-item, button", scope, {
            timeout: 15000,
          }).click({ force: true });
        }
        return;
      }
    });
}

export function createShare(filename, recipientUsername) {
  triggerActionForFile(filename, "share");

  ensureShareSearchScope("External users");

  cy.intercept({
    times: 1,
    method: "GET",
    url: "**/graph/v1.0/users?*",
  }).as("userSearch");

  cy.get('div[id="oc-files-sharing-sidebar"]', { timeout: 15000 })
    .should("be.visible")
    .within(() => {
      cy.get('input[id="files-share-invite-input"]', { timeout: 15000 })
        .clear()
        .type(recipientUsername);
    });

  cy.wait("@userSearch", { timeout: 20000 });

  const recipientKey = recipientUsername.split("@")[0];
  const optionTestId = `recipient-autocomplete-item-${recipientKey}`;

  cy.get(`#vs2__listbox [data-testid="${optionTestId}"]`, { timeout: 15000 })
    .scrollIntoView()
    .should("be.visible")
    .click({ force: true });

  cy.get('div[id="oc-files-sharing-sidebar"]', { timeout: 15000 })
    .should("be.visible")
    .within(() => {
      cy.get('button[id="new-collaborators-form-create-button"]', {
        timeout: 15000,
      })
        .scrollIntoView()
        .should("be.visible")
        .click({ force: true });
    });
}

export function loginCore({ url, username, password }) {
  cy.visit(url);

  // Optional unsupported-browser gate
  maybeDismissUnsupportedBrowserGate();

  let expectedHost = "";
  try {
    expectedHost = new URL(url).hostname;
  } catch (_e) {
    throw new Error(`Invalid CERNBox url passed to loginCore: "${url}"`);
  }

  // After visiting CERNBox, we either get redirected to the Keycloak realm login
  // or (if we have an existing session) land directly in Files.
  cy.url({ timeout: 50000 })
    .should((currentUrl) => {
      const ok =
        currentUrl.includes("/realms/cernbox/") ||
        currentUrl.includes("/files/spaces/");
      expect(ok).to.equal(true);
    })
    .then((currentUrl) => {
      if (currentUrl.includes("/files/spaces/")) {
        expect(currentUrl).to.include(expectedHost);
        expect(currentUrl).to.match(/\/files\/spaces\/(home|personal)/);
        return;
      }

      cy.get("form#kc-form-login", { timeout: 10000 })
        .should("be.visible")
        .within(() => {
          cy.get('input#username, input[name="username"]')
            .clear()
            .type(username);

          cy.get('input#password, input[name="password"]')
            .clear()
            .type(password);

          cy.get('button#kc-login, button[name="login"]')
            .should("be.enabled")
            .click();
        });

      cy.url({ timeout: 50000 }).should("include", "/web-oidc-callback");

      cy.url({ timeout: 50000 }).should((finalUrl) => {
        expect(finalUrl).to.include(expectedHost);
        expect(finalUrl).to.match(/\/files\/spaces\/(home|personal)/);
      });
    });
}

export function createInviteToken(description = "Invite-link test invite") {
  // Assumes we are already logged in and on /open-cloud-mesh/invitations
  cy.url({ timeout: 15000 }).should("include", "/open-cloud-mesh/invitations");
  cy.contains("h2", "Invite users to federate").should("be.visible");

  // Generate invitation in ScienceMesh
  cy.contains("button", "Generate invitation").click();
  cy.contains("h2", "Generate new invitation").should("be.visible");

  cy.contains("label, div", "Add a description (optional)")
    .parent()
    .find("textarea, input")
    .clear()
    .type(description, { delay: 10 });

  cy.contains('[role="dialog"] button', "Generate").click();

  // Wait for table to update
  cy.wait(1000);

  // Extract the token from the first row in the invitations table
  return cy
    .get("table tbody tr")
    .first()
    .should("be.visible")
    .invoke("attr", "data-item-id")
    .then((token) => {
      expect(token).to.be.a("string").and.not.be.empty;
      return token;
    });
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
  // Assumes we are already logged in and on /open-cloud-mesh/invitations
  createInviteToken("Invite-link test invite").then((token) => {
    cy.writeFile(inviteLinkFileName, token);
  });
}

export function createLegacyInviteLink(recipientDomain, senderDomain) {
  // Generate a new ScienceMesh invite token and wrap it in a legacy accept URL
  return createInviteToken("Invite-link legacy test invite").then((token) => {
    const url = `https://${recipientDomain}/index.php/apps/sciencemesh/accept?token=${token}&providerDomain=${senderDomain}`;
    return url;
  });
}

export function acceptInviteLink({
  token,
  senderDomain,
  senderPlatform,
  senderUsername,
  senderDisplayName,
  recipientUrl,
  recipientUsername,
  recipientPassword,
}) {
  expect(token).to.be.a("string").and.not.be.empty;

  // Navigate to the invitations page
  openScienceMeshInvitations();

  // Wait for the page to load and tolerate minor wording/casing changes
  cy.url({ timeout: 15000 }).should("include", "/open-cloud-mesh/invitations");
  cy.contains("h2", /Accept invitations?/i).should("be.visible");

  // Enter the token
  cy.contains("label, div", "Enter invite token")
    .parent()
    .find("input, textarea")
    .clear()
    .type(token, { delay: 10 })
    .should("have.value", token);

  // Click accept button
  cy.contains("button", "Accept").should("not.be.disabled").click();

  // Wait for acceptance confirmation
  cy.url({ timeout: 15000 }).should("include", "/open-cloud-mesh/invitations");

  // Verify the federated connection appears in the table
  const expectedName = senderDisplayName || senderUsername || "";

  cy.contains("table tr", senderDomain, { timeout: 10000 })
    .should("be.visible")
    .within(() => {
      if (expectedName) {
        cy.contains("td", expectedName);
      }
      cy.contains("td", senderDomain);
    });
}

export function createWayfInviteUrl() {
  // Assumes we are already on /open-cloud-mesh/invitations
  cy.url({ timeout: 15000 }).should("include", "/open-cloud-mesh/invitations");
  cy.contains("h2", "Invite users to federate").should("be.visible");

  // Generate invitation in ScienceMesh
  cy.contains("button", "Generate invitation").click();
  cy.contains("h2", "Generate new invitation").should("be.visible");

  cy.contains("label, div", "Add a description (optional)")
    .parent()
    .find("textarea, input")
    .clear()
    .type("WAYF test invite", { delay: 10 });

  cy.contains('[role="dialog"] button', "Generate").click();

  // Capture WAYF link via clipboard stub
  cy.window().then((win) => {
    if (!win.navigator.clipboard) {
      win.navigator.clipboard = {
        writeText: () => Promise.resolve(),
      };
    }
    cy.stub(win.navigator.clipboard, "writeText").as("copyWayfLink");
  });

  cy.get("table tbody tr")
    .first()
    .within(() => {
      cy.get('button[aria-label="Copy Invite link"]').click();
    });

  cy.contains("WAYF link copied").should("be.visible");

  return cy.get("@copyWayfLink").then((stub) => {
    const wayfUrl = stub.args[0][0];
    expect(wayfUrl).to.match(/\/open-cloud-mesh\/wayf\?token=[0-9a-f-]{36}$/);
    return wayfUrl;
  });
}

export function captureWayfRedirectUrl(recipientUrl) {
  // Assumes we are on the WAYF page already
  cy.contains("h1", "Where Are You From?").should("be.visible");
  cy.contains("h3", "Manual Provider Entry").should("be.visible");

  const remoteProviderDomain = recipientUrl;

  cy.contains("label, div", "Enter provider domain manually")
    .parent()
    .find("input, textarea")
    .type(remoteProviderDomain);

  let expectedRecipientHost = "";
  try {
    expectedRecipientHost = new URL(remoteProviderDomain).hostname;
  } catch (_e) {
    throw new Error(
      `Invalid recipientUrl passed to captureWayfRedirectUrl: "${remoteProviderDomain}". Expected a full URL like "https://host".`
    );
  }

  // CERNBox triggers a discover call and then redirects the browser to the recipient host.
  cy.intercept("POST", "**/sciencemesh/discover").as("sciencemeshDiscover");

  cy.contains("button", "Continue").should("not.be.disabled").click();

  return cy
    .wait("@sciencemeshDiscover", { timeout: 60000 })
    .its("response.statusCode")
    .should("eq", 200)
    .then(() =>
      cy.location({ timeout: 60000 }).should((loc) => {
        expect(loc.hostname).to.equal(expectedRecipientHost);
      })
    )
    .then((loc) => loc.href);
}

export function acceptWayfInvite({ senderDomain, senderUsername, senderDisplayName, redirectUrl }) {
  // Now visit the accept-invite URL while already logged in.
  cy.visit(redirectUrl);

  // Accept-invite dialog
  cy.url({ timeout: 15000 }).should("include", "/open-cloud-mesh/accept-invite");

  cy.contains("h2", "Accept Invitation", { timeout: 20000 }).should("be.visible");

  cy.contains("strong", "Provider:", { timeout: 20000 })
    .parent()
    .should("contain.text", senderDomain);

  cy.contains('[role="dialog"] button', "Accept", { timeout: 20000 }).click();

  // Invitations table with new federated connection
  cy.url({ timeout: 15000 }).should("include", "/open-cloud-mesh/invitations");

  const expectedName = senderDisplayName || senderUsername || "";

  cy.contains("table tr", senderDomain, { timeout: 10000 })
    .should("be.visible")
    .within(() => {
      if (expectedName) {
        cy.contains("td", expectedName);
      }
      cy.contains("td", senderDomain);
    });
}

export function verifySharedWithMe({ senderDisplayName, sharedFileName }) {
  // Verify the shared file row exists and has the expected metadata
  cy.contains("table tbody tr", sharedFileName, { timeout: 20000 })
    .should("be.visible")
    .within(() => {
      cy.contains("td", sharedFileName);

      if (senderDisplayName) {
        cy.contains("button", `This file is shared by ${senderDisplayName}`).should(
          "be.visible"
        );
      }
    });
}
