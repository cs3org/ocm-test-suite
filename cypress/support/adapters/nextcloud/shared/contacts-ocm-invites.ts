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

function getInviteContactButton(): Cypress.Chainable<JQuery<HTMLElement>> {
  return cy
    .get("button, a, [role=\"button\"]", { timeout: 20000 })
    .filter((_, el) => {
      const text = (el.textContent ?? "").trim();
      const aria = (el.getAttribute("aria-label") ?? "").trim();
      return text === "Invite contact" || aria === "Invite contact" || aria.includes("Invite contact");
    })
    .first();
}

export function ensureOcmInvitesViewActive(): void {
  cy.viewport(1280, 720);
  ensureContactsAppActive();

  cy.visit("/apps/contacts/ocm-invites");
  cy.location("pathname", { timeout: 20000 }).should("include", "/apps/contacts");

  cy.get("body").then(($body) => {
    const inviteMounted =
      $body
        .find("button, a, [role=\"button\"]")
        .filter((_, el) => {
          const text = (el.textContent ?? "").trim();
          const aria = (el.getAttribute("aria-label") ?? "").trim();
          return text === "Invite contact" || aria === "Invite contact" || aria.includes("Invite contact");
        });
    const inviteVisible = inviteMounted.filter(":visible").length > 0;
    if (inviteVisible) {
      return;
    }

    const toggleCandidates = [
      "button.app-navigation-toggle",
      "button#app-navigation-toggle",
      'button[aria-label*="Toggle navigation"]',
      'button[aria-label*="toggle navigation"]',
      'button[aria-label*="Navigation"]',
      'button[aria-label*="navigation"]',
    ];

    const toggleSel = toggleCandidates.find((sel) => {
      return $body.find(sel).filter(":visible").length > 0;
    });

    if (toggleSel) {
      cy.get(toggleSel).filter(":visible").first().click({ force: true });
    }
  });

  getInviteContactButton().should("exist");
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

function createOcmInvite(params: {
  note: string;
}): void {
  ensureOcmInvitesViewActive();

  getInviteContactButton().click({ force: true });

  cy.get('[data-testid="ocm-invite-note-input"]', { timeout: 20000 })
    .should("be.visible")
    .clear()
    .type(params.note);

  ensureSendEmailUnchecked();

  cy.intercept("POST", "**/apps/contacts/ocm/invitations").as("ocmInviteCreate");

  cy.get('[data-testid="ocm-invite-new-submit-btn"]', { timeout: 20000 })
    .should("be.visible")
    .click();

  cy.wait("@ocmInviteCreate", { timeout: 20000 }).then((interception) => {
    const statusCode = interception.response?.statusCode;
    expect(statusCode, "create invite status code").to.be.oneOf([200, 201]);
  });
}

export function createInviteAndCopyInviteLink(params: {
  note: string;
}): Cypress.Chainable<string> {
  createOcmInvite({ note: params.note });
  openMostRecentInviteFromList();

  stubClipboardWriteText();
  cy.get('[data-testid="ocm-invite-link-copy-btn"]', { timeout: 20000 })
    .should("be.visible")
    .click({ force: true });

  return readCopiedTextFromClipboardStub();
}

export function createInviteAndCopyInviteCode(params: {
  note: string;
}): Cypress.Chainable<string> {
  createOcmInvite({ note: params.note });
  openMostRecentInviteFromList();

  stubClipboardWriteText();
  cy.get('[data-testid="ocm-invite-token-copy-btn"]', { timeout: 20000 })
    .should("be.visible")
    .click({ force: true });

  return readCopiedTextFromClipboardStub();
}
