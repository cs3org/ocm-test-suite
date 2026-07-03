/// <reference types="cypress" />

function resolveRequiredExpose(key: string): string {
  const value = Cypress.expose(key);
  if (value === undefined || value === null || String(value) === "") {
    throw new Error(
      [
        `Missing required Cypress value: Cypress.expose("${key}").`,
        `This value should be injected via compose as CYPRESS_${key}.`,
      ].join(" "),
    );
  }

  return String(value);
}

export function resolveReceiverBaseUrl(): string {
  return resolveRequiredExpose("receiver_baseUrl");
}

export function resolveCurrentHost(): Cypress.Chainable<string> {
  return cy.location("host", { timeout: 20000 }).then((host) => {
    if (!host || String(host).trim() === "") {
      throw new Error("Could not resolve current host from cy.location('host')");
    }
    return String(host);
  });
}

export function ensureContactsAppActive(): void {
  // Contacts' RootNavigation collapses at smaller widths; keep a wide viewport
  // so navigation actions remain visible and consistent across runs.
  cy.viewport(1280, 720);
  cy.visit("/");

  cy.location("pathname", { timeout: 20000 }).then((pathname) => {
    if (typeof pathname === "string" && pathname.includes("/apps/contacts")) {
      return;
    }
    cy.visit("/apps/contacts/");
  });

  cy.location("pathname", { timeout: 20000 }).should("include", "/apps/contacts");
}

function matchesCreateInvitationLabel(text: string, aria: string): boolean {
  const normalizedText = text.replace(/\s+/g, " ").trim().toLowerCase();
  const normalizedAria = aria.replace(/\s+/g, " ").trim().toLowerCase();
  if (
    normalizedText.includes("create invit") ||
    normalizedAria.includes("create invit") ||
    normalizedText.includes("invite contact") ||
    normalizedAria.includes("invite contact")
  ) {
    return true;
  }

  return false;
}

function matchesAcceptInvitationLabel(text: string, aria: string): boolean {
  const normalizedText = text.replace(/\s+/g, " ").trim().toLowerCase();
  const normalizedAria = aria.replace(/\s+/g, " ").trim().toLowerCase();
  if (
    normalizedText.includes("accept invit") ||
    normalizedAria.includes("accept invit") ||
    normalizedText.includes("accept invite") ||
    normalizedAria.includes("accept invite")
  ) {
    return true;
  }

  return false;
}

function getInviteContactButton(): Cypress.Chainable<JQuery<HTMLElement>> {
  return cy
    .get("button, a, [role=\"button\"]", { timeout: 20000 })
    .filter((_, el) => {
      const text = (el.textContent ?? "").trim();
      const aria = (el.getAttribute("aria-label") ?? "").trim();
      return matchesCreateInvitationLabel(text, aria);
    })
    .first();
}

export function getAcceptInviteButton(): Cypress.Chainable<JQuery<HTMLElement>> {
  return cy
    .get("button, a, [role=\"button\"]", { timeout: 20000 })
    .filter((_, el) => {
      const text = (el.textContent ?? "").trim();
      const aria = (el.getAttribute("aria-label") ?? "").trim();
      return matchesAcceptInvitationLabel(text, aria);
    })
    .first();
}

function openOcmInviteActionsMenu(): void {
  cy.get(".ocm-invites-actions button", { timeout: 20000 })
    .first()
    .should("be.visible")
    .click({ force: true });
}

function clickVisibleInvitationAction(
  matcher: (text: string, aria: string) => boolean,
): void {
  cy.get('button, a, [role="menuitem"], li button, .action-button', { timeout: 20000 })
    .filter((_, el) => {
      const text = (el.textContent ?? "").trim();
      const aria = (el.getAttribute("aria-label") ?? "").trim();
      return matcher(text, aria);
    })
    .first()
    .should("be.visible")
    .click({ force: true });
}

export function clickCreateInvitation(): void {
  cy.get("body").then(($body) => {
    const visibleEmptyStateCreateButton = $body
      .find(".empty-content button, .empty-content a, .empty-content [role=\"button\"]")
      .filter((_, el) => {
        const text = (el.textContent ?? "").trim();
        const aria = (el.getAttribute("aria-label") ?? "").trim();
        return matchesCreateInvitationLabel(text, aria);
      })
      .filter(":visible");

    if (visibleEmptyStateCreateButton.length > 0) {
      cy.wrap(visibleEmptyStateCreateButton.first()).scrollIntoView().click({ force: true });
      return;
    }

    if ($body.find(".ocm-invites-actions").length > 0) {
      openOcmInviteActionsMenu();
      clickVisibleInvitationAction(matchesCreateInvitationLabel);
      return;
    }

    cy.get(".header, .import-and-new-contact-buttons", { timeout: 20000 })
      .first()
      .scrollIntoView();
    getInviteContactButton().scrollIntoView().should("be.visible").click({ force: true });
  });
}

export function clickAcceptInvitation(): void {
  cy.get("body").then(($body) => {
    if ($body.find(".ocm-invites-actions").length > 0) {
      openOcmInviteActionsMenu();
      clickVisibleInvitationAction(matchesAcceptInvitationLabel);
      return;
    }

    getAcceptInviteButton().should("be.visible").click({ force: true });
  });
}

export function ensureOcmInvitesViewActive(): void {
  cy.viewport(1280, 720);
  ensureContactsAppActive();

  cy.intercept("GET", "**/apps/contacts/ocm/invitations").as("ocmInvitesList");

  cy.visit("/apps/contacts/ocm-invites");
  cy.location("pathname", { timeout: 20000 }).should("include", "/apps/contacts");

  cy.wait("@ocmInvitesList", { timeout: 60000 });
  cy.contains(/Loading invit/i, { timeout: 60000 }).should("not.exist");

  cy.get(".app-navigation, nav.app-navigation", { timeout: 20000 })
    .first()
    .scrollIntoView();
  cy.get(".header, .import-and-new-contact-buttons", { timeout: 20000 })
    .first()
    .scrollIntoView();
}

function ensureSendEmailUnchecked(): void {
  cy.get("body").then(($body) => {
    const checkboxSel = '[data-testid="ocm-invite-send-email-checkbox"]';
    if ($body.find(checkboxSel).length === 0) {
      return;
    }

    cy.get<HTMLInputElement>(checkboxSel).then(($cb) => {
      const isChecked = $cb.is(":checked");
      if (isChecked) {
        cy.wrap($cb).uncheck({ force: true });
      }
    });
  });
}

function openMostRecentInviteFromList(): void {
  // After creating an invite the UI sometimes lands on a detail route where the
  // list is not mounted yet. Re-open the list route so the copy buttons can be
  // reached deterministically.
  cy.visit("/apps/contacts/ocm-invites");

  cy.get('[data-testid^="ocm-invite-item-"]', { timeout: 60000 })
    .should(($items) => {
      expect($items.length, "ocm invite items count").to.be.greaterThan(0);
    })
    .first()
    .scrollIntoView()
    .should("be.visible")
    .click({ force: true });
}

function stubClipboardWriteText(): void {
  cy.window({ timeout: 20000 }).then((win) => {
    const ensureClipboardWithWriteText = () => {
      const nav = win.navigator as unknown as { clipboard?: { writeText?: unknown } };
      const clipboard = nav.clipboard;
      if (clipboard && typeof clipboard.writeText === "function") {
        return;
      }

      try {
        Object.defineProperty(win.navigator, "clipboard", {
          value: { writeText: () => Promise.resolve() },
          configurable: true,
        });
      } catch {
        (win.navigator as unknown as { clipboard?: unknown }).clipboard = {
          writeText: () => Promise.resolve(),
        };
      }
    };

    ensureClipboardWithWriteText();

    const clipboard = (win.navigator as unknown as { clipboard?: { writeText?: unknown } }).clipboard;
    if (!clipboard || typeof clipboard.writeText !== "function") {
      throw new Error("Could not stub clipboard writeText (navigator.clipboard.writeText missing)");
    }

    const writeTextStub = cy.stub(clipboard, "writeText").resolves(undefined);
    cy.wrap(writeTextStub, { log: false }).as("clipboardWriteText");
  });
}

function readCopiedTextFromClipboardStub(): Cypress.Chainable<string> {
  return cy
    .get("@clipboardWriteText")
    .should("have.been.called")
    .then((stubUnknown: unknown) => {
      const stub = stubUnknown as unknown as {
        getCall: (index: number) => { args: unknown[] } | null | undefined;
      };
      const call = stub.getCall(0);
      const copied = call?.args?.[0];
      if (typeof copied !== "string" || copied.trim() === "") {
        throw new Error("Clipboard stub did not capture copied invite value");
      }
      return cy.wrap(copied, { log: false });
    });
}

function submitNewInviteForm(): void {
  cy.intercept("POST", "**/apps/contacts/ocm/invitations").as("ocmInviteCreate");

  cy.get("body").then(($body) => {
    const submitWithTestId = $body.find('[data-testid="ocm-invite-new-submit-btn"]').filter(":visible");
    if (submitWithTestId.length > 0) {
      cy.wrap(submitWithTestId.first()).click({ force: true });
      return;
    }

    cy.contains(
      ".new-invite-form__buttons-row button, .ocm-invite-form button",
      /Send invitation|Generate invitation/i,
      { timeout: 20000 },
    )
      .should("be.visible")
      .click({ force: true });
  });

  cy.wait("@ocmInviteCreate", { timeout: 20000 }).then((interception) => {
    const statusCode = interception.response?.statusCode;
    expect(statusCode, "create invite status code").to.be.oneOf([200, 201]);
  });
}

function revealInviteShareActionsIfNeeded(): void {
  cy.get("body").then(($body) => {
    const shareToggle = $body.find('[data-testid="ocm-invite-share-toggle"]');
    const hasVisibleCopyButton =
      $body
        .find('[data-testid="ocm-invite-code-copy-btn"], [data-testid="ocm-invite-link-copy-btn"]')
        .filter(":visible").length > 0;

    if (shareToggle.length > 0 && !hasVisibleCopyButton) {
      cy.get('[data-testid="ocm-invite-share-toggle"]').click({ force: true });
    }
  });
}

function copyInviteCodeFromDetailPage(): Cypress.Chainable<string> {
  revealInviteShareActionsIfNeeded();
  stubClipboardWriteText();
  cy.get('[data-testid="ocm-invite-code-copy-btn"]', { timeout: 20000 })
    .should("be.visible")
    .click({ force: true });

  return readCopiedTextFromClipboardStub();
}

function copyInviteLinkFromDetailPage(): Cypress.Chainable<string> {
  revealInviteShareActionsIfNeeded();
  stubClipboardWriteText();
  cy.get('[data-testid="ocm-invite-link-copy-btn"]', { timeout: 20000 })
    .should("be.visible")
    .click({ force: true });

  return readCopiedTextFromClipboardStub();
}

function fillNewInviteForm(params: { note: string }): void {
  ensureSendEmailUnchecked();

  cy.get("body").then(($body) => {
    const checkboxSel = '[data-testid="ocm-invite-send-email-checkbox"]';
    const emailInputSel = '[data-testid="ocm-invite-email-input"]';
    const messageInputSel = '[data-testid="ocm-invite-message-input"]';
    const hasSendEmailCheckbox = $body.find(checkboxSel).length > 0;

    if (!hasSendEmailCheckbox && $body.find(emailInputSel).filter(":visible").length > 0) {
      cy.get(emailInputSel, { timeout: 20000 })
        .should("be.visible")
        .clear()
        .type(`cypress-${Date.now()}@example.test`);
    }

    if (params.note.trim() !== "" && $body.find(messageInputSel).filter(":visible").length > 0) {
      cy.get(messageInputSel, { timeout: 20000 })
        .should("be.visible")
        .clear()
        .type(params.note);
    }
  });
}

function createInviteViaUi(params: { note: string }): void {
  clickCreateInvitation();
  fillNewInviteForm({ note: params.note });
  submitNewInviteForm();
}

function createInviteViaUiAndCopyCode(params: { note: string }): Cypress.Chainable<string> {
  createInviteViaUi({ note: params.note });
  openMostRecentInviteFromList();
  return copyInviteCodeFromDetailPage();
}

function createInviteViaUiAndCopyLink(params: { note: string }): Cypress.Chainable<string> {
  createInviteViaUi({ note: params.note });
  openMostRecentInviteFromList();
  return copyInviteLinkFromDetailPage();
}

export function createInviteAndCopyInviteLink(params: {
  note: string;
}): Cypress.Chainable<string> {
  ensureOcmInvitesViewActive();
  return createInviteViaUiAndCopyLink({ note: params.note });
}

export function createInviteAndCopyInviteCode(params: {
  note: string;
}): Cypress.Chainable<string> {
  ensureOcmInvitesViewActive();
  return createInviteViaUiAndCopyCode({ note: params.note });
}
