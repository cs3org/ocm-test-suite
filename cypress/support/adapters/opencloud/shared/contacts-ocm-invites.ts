/// <reference types="cypress" />

// OpenCloud OCM / ScienceMesh invite helpers.

import { cssEscapeAttributeValue } from "../../../shared/selectors";

const ocmAppMenuTimeoutMs = 10000;
const ocmActionTimeoutMs = 20000;
const ocmApiTimeoutMs = 30000;

// OCM app menu IDs across versions. open-cloud-mesh is current; older
// versions exposed it as ocm or sciencemesh-app.
const ocmAppMenuItemTestIds = [
  "app.open-cloud-mesh.menuItem",
  "app.ocm.menuItem",
  "app.sciencemesh-app.menuItem",
];

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

export function resolveOpenCloudOcmReceiverBaseUrl(): string {
  return resolveRequiredExpose("receiver_baseUrl");
}

function openOcmViaAppSwitcher(): void {
  cy.get('nav#applications-menu button#_appSwitcherButton', {
    timeout: ocmAppMenuTimeoutMs,
  })
    .should("be.visible")
    .click({ force: true });

  cy.get("body").then(($body) => {
    for (const testId of ocmAppMenuItemTestIds) {
      const sel = `nav#applications-menu a[data-test-id="${cssEscapeAttributeValue(testId)}"]`;
      if ($body.find(sel).filter(":visible").length > 0) {
        cy.get(sel).first().click({ force: true });
        return;
      }
    }
    // Text fallback for future rebrands.
    cy.get("nav#applications-menu")
      .contains("a, [role=\"menuitem\"]", /sciencemesh|open.?cloud.?mesh|ocm/i, {
        timeout: ocmAppMenuTimeoutMs,
      })
      .first()
      .click({ force: true });
  });
}

export function openOpenCloudOcmApp(): void {
  cy.viewport(1280, 720);
  cy.visit("/");
  cy.get("#web-content", { timeout: ocmActionTimeoutMs }).should("be.visible");
  openOcmViaAppSwitcher();

  cy.get(
    "#sciencemesh-invite, #sciencemesh-accept-invites, #sciencemesh-connections",
    { timeout: ocmActionTimeoutMs },
  ).should("exist");
}

// Encodes a sender domain as a synthetic contact URL.
// assertOpenCloudConnectionExists decodes and verifies the connection.
export function encodeOpenCloudAcceptedContactUrl(senderDomain: string): string {
  return `ocm-contact://${senderDomain}`;
}

export function decodeOpenCloudAcceptedContactUrl(
  acceptedContactUrl: string,
): string {
  return acceptedContactUrl.replace(/^ocm-contact:\/\//, "");
}

function extractSenderDomainFromToken(inviteToken: string): string {
  // Modern Reva emits base64(token@host); try to decode first.
  try {
    const decoded = atob(inviteToken.trim());
    const atIdx = decoded.lastIndexOf("@");
    if (atIdx > 0) {
      return decoded.slice(atIdx + 1).trim();
    }
  } catch {
    // Not valid base64; fall through to raw token@host parse.
  }
  // Raw token@host or plain token.
  const atIdx = inviteToken.lastIndexOf("@");
  if (atIdx > 0) {
    return inviteToken.slice(atIdx + 1).trim();
  }
  return inviteToken;
}

// Always yields base64(token@host). The .invite-code-wrapper span path
// returns the value the server already encoded. The data-item-id fallback
// normalizes the raw token to the same shape by composing
// btoa(`${token}@${senderHost}`) so callers and extractSenderDomainFromToken
// receive a consistent format regardless of which UI path was taken.
export function createOpenCloudInviteTokenBase64(
  note: string,
): Cypress.Chainable<string> {
  openOpenCloudOcmApp();

  cy.get("#sciencemesh-invite", { timeout: ocmActionTimeoutMs }).should("exist");

  // Stub clipboard.writeText before the Generate flow so the app's automatic
  // copyToken call does not throw NotAllowedError ("Write permission denied").
  cy.window().then((win) => {
    if (
      win.navigator.clipboard &&
      typeof win.navigator.clipboard.writeText === "function" &&
      !(win.navigator.clipboard.writeText as unknown as { isSinonProxy?: boolean }).isSinonProxy
    ) {
      cy.stub(win.navigator.clipboard, "writeText").resolves();
    }
  });

  cy.get("#sciencemesh-invite")
    .contains("span, button, a", /Generate invitation/i, {
      timeout: ocmActionTimeoutMs,
    })
    .closest("span, button, a")
    .scrollIntoView()
    .should("be.visible")
    .click({ force: true });

  cy.get('div[role="dialog"]', { timeout: ocmActionTimeoutMs }).should("be.visible");

  cy.get('div[role="dialog"]').then(($dialog) => {
    const noteInput = $dialog
      .find('input[type="text"], textarea')
      .filter(":visible");
    if (noteInput.length > 0) {
      cy.wrap(noteInput.first()).clear().type(note);
    }
  });

  // Primary: .oc-modal-body-actions-confirm. Fallback: text-based.
  cy.get('div[role="dialog"]:visible').then(($dialog) => {
    const confirmBtn = $dialog
      .find(".oc-modal-body-actions-confirm")
      .filter(":visible");
    if (confirmBtn.length > 0) {
      cy.wrap(confirmBtn.first())
        .scrollIntoView()
        .should("be.visible")
        .click({ force: true });
    } else {
      cy.wrap($dialog).within(() => {
        cy.contains(
          'button, [role="button"], a, span',
          /^Generate$/i,
          { timeout: ocmActionTimeoutMs },
        )
          .closest('button, [role="button"], a')
          .scrollIntoView()
          .should("be.visible")
          .click({ force: true });
      });
    }
  });

  cy.get("#sciencemesh-invite table tbody tr", { timeout: ocmApiTimeoutMs })
    .first()
    .should("be.visible");

  return cy.location("host").then((senderHost) => {
    return cy
      .get("#sciencemesh-invite table tbody tr")
      .first()
      .then(($row) => {
        const codeSpan = $row.find(".invite-code-wrapper span");
        if (codeSpan.length > 0 && codeSpan.text().trim() !== "") {
          const code = codeSpan.text().trim();
          expect(code, `OCM invite code (note: ${note})`).to.not.be.empty;
          return cy.wrap(code, { log: false });
        }

        // Fallback: raw token from data-item-id. Normalize to
        // base64(token@senderHost) so the accept-invite UI and
        // extractSenderDomainFromToken receive the expected format.
        const tokenId = ($row.attr("data-item-id") ?? "").trim();
        if (tokenId !== "") {
          const normalized = btoa(`${tokenId}@${senderHost}`);
          expect(normalized, `OCM invite token id (note: ${note})`).to.not.be.empty;
          return cy.wrap(normalized, { log: false });
        }

        throw new Error(
          [
            "Could not extract OCM invite code.",
            "Expected .invite-code-wrapper span text or data-item-id on table row.",
          ].join(" "),
        );
      });
  });
}

export function acceptOpenCloudInviteToken(
  inviteToken: string,
): Cypress.Chainable<string> {
  openOpenCloudOcmApp();

  cy.get("#sciencemesh-accept-invites", { timeout: ocmActionTimeoutMs }).should(
    "exist",
  );

  cy.get("#sciencemesh-accept-invites")
    .find("label")
    .contains(/Enter invite token/i, { timeout: ocmActionTimeoutMs })
    .parent()
    .scrollIntoView()
    .should("be.visible")
    .within(() => {
      cy.get('input[type="text"]')
        .should("be.visible")
        .clear()
        .type(inviteToken, { delay: 50 });
    });

  cy.get("#sciencemesh-accept-invites")
    .find("span")
    .contains(/Accept invitation/i, { timeout: ocmActionTimeoutMs })
    .parent()
    .scrollIntoView()
    .should("be.visible")
    .should("not.be.disabled")
    .click({ force: true });

  cy.get("#sciencemesh-connections table tbody tr", { timeout: ocmApiTimeoutMs })
    .should("have.length.at.least", 1);

  const senderDomain = extractSenderDomainFromToken(inviteToken);
  return cy.wrap(encodeOpenCloudAcceptedContactUrl(senderDomain), { log: false });
}

export function assertOpenCloudConnectionExists(params: {
  acceptedContactUrl: string;
}): void {
  const senderDomain = decodeOpenCloudAcceptedContactUrl(
    params.acceptedContactUrl,
  );

  cy.get("#sciencemesh-connections", { timeout: ocmActionTimeoutMs }).should(
    "exist",
  );
  cy.get("#sciencemesh-connections table tbody tr", { timeout: ocmApiTimeoutMs })
    .should("have.length.at.least", 1);

  if (senderDomain.trim() !== "") {
    cy.get("#sciencemesh-connections table tbody").should(($tbody) => {
      const text = $tbody.text().toLowerCase();
      expect(
        text.includes(senderDomain.toLowerCase()),
        `connections table contains sender domain "${senderDomain}"`,
      ).to.eq(true);
    });
  }
}
