/// <reference types="cypress" />

import type {
  ContactTokenReceiverAdapter,
  ContactTokenSenderAdapter,
  ContactWayfReceiverAdapter,
  ContactWayfSenderAdapter,
  ProviderIdentityAdapter,
} from "../../../contracts/contact";
import {
  createInviteAndCopyInviteCode,
  createInviteAndCopyInviteLink,
  ensureContactsAppActive,
  resolveReceiverBaseUrl,
} from "../shared/contacts-ocm-invites";

function assertNonEmptyCopiedValue(value: string, label: string): Cypress.Chainable<string> {
  expect(value, label).to.be.a("string").and.not.be.empty;
  return cy.wrap(value, { log: false });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmedValue = value.trim();
  if (trimmedValue === "") {
    return null;
  }

  return trimmedValue;
}

function getAcceptedContactUrlFromResponseBody(body: unknown): string | null {
  if (!isRecord(body)) {
    return null;
  }

  const contact = getNonEmptyString(body.contact);
  if (contact !== null) {
    return contact;
  }

  if (!isRecord(body.data)) {
    return null;
  }

  return getNonEmptyString(body.data.contact);
}

function requireAcceptedContactUrlFromResponseBody(body: unknown): string {
  const acceptedContactUrl = getAcceptedContactUrlFromResponseBody(body);
  if (acceptedContactUrl === null) {
    throw new Error("OCM invite accept response did not include contact");
  }

  return acceptedContactUrl;
}

function normalizeAcceptedContactUrl(value: unknown, label: string): string {
  expect(value, label).to.be.a("string");

  const acceptedContactUrl = String(value).trim();
  expect(acceptedContactUrl, label).to.not.eq("");
  expect(acceptedContactUrl, label).to.not.eq("about:blank");

  return acceptedContactUrl;
}

function resolveAcceptedContactUrl(acceptedContactUrl: string): URL {
  try {
    return new URL(acceptedContactUrl, resolveReceiverBaseUrl());
  } catch (error) {
    throw new Error(
      [
        `Invalid accepted contact URL: ${acceptedContactUrl}`,
        String(error),
      ].join(" "),
    );
  }
}

function assertContactSpecificUrl(acceptedContactUrl: string): void {
  const url = resolveAcceptedContactUrl(acceptedContactUrl);
  const normalizedPath = url.pathname.replace(/\/+$/, "");
  const hasContactRoutePath = normalizedPath !== "/apps/contacts";
  const hasContactRouteHash = url.hash.trim() !== "";

  expect(url.pathname, "accepted contact URL path").to.include("/apps/contacts");
  expect(
    hasContactRoutePath || hasContactRouteHash,
    "accepted contact URL targets a contact-specific route",
  ).to.eq(true);
}

function assertCurrentLocationMatchesAcceptedContactUrl(acceptedContactUrl: string): void {
  const expectedUrl = resolveAcceptedContactUrl(acceptedContactUrl);

  cy.location("href", { timeout: 20000 }).should((currentHref) => {
    const currentUrl = new URL(currentHref);
    expect(
      currentUrl.pathname.replace(/\/+$/, ""),
      "current accepted contact path",
    ).to.eq(expectedUrl.pathname.replace(/\/+$/, ""));

    if (expectedUrl.search !== "") {
      expect(currentUrl.search, "current accepted contact query").to.eq(expectedUrl.search);
    }
    if (expectedUrl.hash !== "") {
      expect(currentUrl.hash, "current accepted contact hash").to.eq(expectedUrl.hash);
    }
  });
}

function resolveWayfInviteAcceptUrl(redirectUrl: string): URL {
  const outerUrl = new URL(redirectUrl, resolveReceiverBaseUrl());
  const hasTopLevelToken = (outerUrl.searchParams.get("token") ?? "").trim() !== "";
  const hasTopLevelProvider = (
    outerUrl.searchParams.get("providerDomain") ??
    outerUrl.searchParams.get("provider") ??
    ""
  ).trim() !== "";

  if (hasTopLevelToken && hasTopLevelProvider) {
    return outerUrl;
  }

  const nestedRedirect = (outerUrl.searchParams.get("redirect_url") ?? "").trim();
  if (nestedRedirect === "") {
    return outerUrl;
  }

  try {
    return new URL(nestedRedirect, outerUrl.origin);
  } catch (error) {
    throw new Error(
      [
        "Invalid WAYF receiver redirect_url.",
        `URL: ${redirectUrl}`,
        String(error),
      ].join(" "),
    );
  }
}

function parseWayfRedirectParams(redirectUrl: string): {
  provider: string;
  token: string;
} {
  const url = resolveWayfInviteAcceptUrl(redirectUrl);
  const token = (url.searchParams.get("token") ?? "").trim();
  const provider = (
    url.searchParams.get("providerDomain") ??
    url.searchParams.get("provider") ??
    ""
  ).trim();

  if (token === "" || provider === "") {
    throw new Error(
      [
        "WAYF receiver redirect URL is missing token or provider.",
        `URL: ${redirectUrl}`,
      ].join(" "),
    );
  }

  return { provider, token };
}

function normalizeWayfRedirectUrl(value: unknown, providerUrl: string): string {
  expect(value, "WAYF receiver redirect URL").to.be.a("string");

  const redirectUrl = String(value).trim();
  expect(redirectUrl, "WAYF receiver redirect URL").to.not.eq("");
  expect(redirectUrl, "WAYF receiver redirect URL").to.not.eq("about:blank");

  const actual = new URL(redirectUrl);
  const expectedProvider = new URL(providerUrl);
  expect(actual.origin, "WAYF redirect receiver origin").to.eq(expectedProvider.origin);
  parseWayfRedirectParams(redirectUrl);

  return redirectUrl;
}

function openManualInviteAccept(): void {
  ensureContactsAppActive();
  cy.visit("/apps/contacts/ocm-invites");

  cy.contains("button, a, [role=\"button\"]", /Accept invite/i, {
    timeout: 20000,
  })
    .should("be.visible")
    .click({ force: true });

  cy.get(".ocm_manual_form", { timeout: 20000 }).should("be.visible");
}

function submitManualInviteToken(inviteToken: string): Cypress.Chainable<string> {
  cy.get('.ocm_manual_form input[type="text"]', { timeout: 20000 })
    .should("be.visible")
    .clear()
    .type(inviteToken);

  cy.intercept("PATCH", "**/apps/contacts/ocm/invitations/*/accept").as(
    "ocmInviteAccept",
  );

  cy.get(".ocm_manual_buttons", { timeout: 20000 })
    .should("be.visible")
    .within(() => {
      cy.contains("button, [role=\"button\"], a", /Accept/i, {
        timeout: 20000,
      })
        .should("be.visible")
        .click({ force: true });
    });

  return cy
    .wait("@ocmInviteAccept", { timeout: 20000 })
    .then((interception) => {
      const statusCode = interception.response?.statusCode;
      expect(statusCode, "accept contact invite status code").to.be.oneOf([200, 201]);
      return requireAcceptedContactUrlFromResponseBody(interception.response?.body);
    })
    .then((acceptedContactUrlFromResponse) => {
      cy.location("pathname", { timeout: 20000 }).should("include", "/apps/contacts");
      const acceptedContactUrl = normalizeAcceptedContactUrl(
        acceptedContactUrlFromResponse,
        "accepted contact URL",
      );
      assertContactSpecificUrl(acceptedContactUrl);
      return cy.wrap(acceptedContactUrl, { log: false });
    });
}

const contactDetailSelector = ".contact-title, #contact-fullname";

function assertAcceptedContactExists(params: {
  acceptedContactUrl: string;
}): void {
  const acceptedContactUrl = normalizeAcceptedContactUrl(
    params.acceptedContactUrl,
    "accepted contact URL",
  );
  assertContactSpecificUrl(acceptedContactUrl);

  cy.viewport(1280, 720);
  cy.visit(resolveAcceptedContactUrl(acceptedContactUrl).toString());
  cy.location("pathname", { timeout: 20000 }).should("include", "/apps/contacts");
  assertCurrentLocationMatchesAcceptedContactUrl(acceptedContactUrl);

  cy.get(contactDetailSelector, { timeout: 60000 }).should(($elements) => {
    expect(
      $elements.filter(":visible").length,
      "visible contact detail for accepted contact URL",
    ).to.be.greaterThan(0);
  });
}

function assertWayfProviderEntryVisible(): void {
  cy.contains("h2", /^Providers$/, { timeout: 20000 }).should("be.visible");
  cy.get("#wayf-manual", { timeout: 20000 }).should("be.visible");
}

function submitManualWayfProvider(providerUrl: string): void {
  cy.intercept("GET", "**/apps/contacts/discover*").as("contactsDiscover");

  cy.get("#wayf-manual", { timeout: 20000 })
    .should("be.visible")
    .clear()
    .type(providerUrl);

  cy.get("body").then(($body) => {
    const hasContinue =
      $body.find("button").filter((_, el) => {
        return /Continue/i.test((el.textContent ?? "").trim());
      }).length > 0;

    if (hasContinue) {
      cy.contains("button", /Continue/i, { timeout: 20000 })
        .should("be.visible")
        .click({ force: true });
      return;
    }

    cy.get("#wayf-manual").type("{enter}");
  });

  cy.wait("@contactsDiscover", { timeout: 60000 }).then((interception) => {
    const statusCode = interception.response?.statusCode;
    expect(statusCode, "WAYF provider discovery status code").to.eq(200);
  });
}

function getReceiverProviderUrl(inviteLink?: string): string {
  const receiverBaseUrl = new URL(resolveReceiverBaseUrl());
  if (inviteLink) {
    receiverBaseUrl.protocol = new URL(inviteLink).protocol;
  }
  return receiverBaseUrl.origin;
}

function clickInviteDialogAccept(): void {
  cy.get(".contact-header__infos", { timeout: 20000 })
    .should("be.visible")
    .within(() => {
      cy.get(".invite-accept-form__buttons-row", { timeout: 20000 })
        .should("be.visible")
        .find("button")
        .first()
        .scrollIntoView()
        .click({ force: true });
    });
}

function assertInviteValueMatches(
  selector: string,
  expectedValue: string,
  label: string,
): void {
  cy.get(selector, { timeout: 20000 })
    .should("be.visible")
    .should(($element) => {
      const visibleText = $element.text().trim();
      const fieldValue = String($element.val() ?? "").trim();
      const combinedValue = `${visibleText} ${fieldValue}`.trim();
      expect(combinedValue, label).to.include(expectedValue);
    });
}

function acceptWayfRedirectInvite(redirectUrl: string): Cypress.Chainable<string> {
  const expected = parseWayfRedirectParams(redirectUrl);

  cy.visit(redirectUrl);
  cy.location("href", { timeout: 20000 }).should((currentHref) => {
    const actual = parseWayfRedirectParams(currentHref);
    expect(actual.token, "WAYF redirect token").to.eq(expected.token);
    expect(actual.provider, "WAYF redirect provider").to.eq(expected.provider);
  });

  assertInviteValueMatches(
    '[data-testid="ocm-invite-accept-token"]',
    expected.token,
    "visible invite token",
  );
  assertInviteValueMatches(
    '[data-testid="ocm-invite-accept-provider"]',
    expected.provider,
    "visible invite provider",
  );

  cy.intercept("PATCH", "**/apps/contacts/ocm/invitations/*/accept").as(
    "ocmWayfInviteAccept",
  );
  clickInviteDialogAccept();

  return cy
    .wait("@ocmWayfInviteAccept", { timeout: 20000 })
    .then((interception) => {
      const statusCode = interception.response?.statusCode;
      expect(statusCode, "WAYF accept contact invite status code").to.be.oneOf([200, 201]);
      const acceptedContactUrl = normalizeAcceptedContactUrl(
        requireAcceptedContactUrlFromResponseBody(interception.response?.body),
        "accepted contact URL",
      );
      assertContactSpecificUrl(acceptedContactUrl);
      return acceptedContactUrl;
    })
    .then((acceptedContactUrl) => {
      cy.visit(resolveAcceptedContactUrl(acceptedContactUrl).toString());
      cy.location("pathname", { timeout: 20000 }).should("include", "/apps/contacts");
      assertCurrentLocationMatchesAcceptedContactUrl(acceptedContactUrl);
      return cy.wrap(acceptedContactUrl, { log: false });
    });
}

export const nextcloudV34ContactTokenSenderAdapter: ContactTokenSenderAdapter = {
  key: "nextcloud/v34",

  createInviteToken({ note }) {
    return createInviteAndCopyInviteCode({ note }).then((inviteToken) => {
      return assertNonEmptyCopiedValue(inviteToken, "copied contact invite token");
    });
  },
};

export const nextcloudV34ContactTokenReceiverAdapter: ContactTokenReceiverAdapter = {
  key: "nextcloud/v34",

  acceptInviteToken({ inviteToken }) {
    openManualInviteAccept();
    return submitManualInviteToken(inviteToken);
  },

  assertAcceptedContactExists({ acceptedContactUrl }) {
    assertAcceptedContactExists({ acceptedContactUrl });
  },
};

export const nextcloudV34ContactWayfSenderAdapter: ContactWayfSenderAdapter = {
  key: "nextcloud/v34",

  createInviteLink({ note }) {
    return createInviteAndCopyInviteLink({ note }).then((inviteLink) => {
      return assertNonEmptyCopiedValue(inviteLink, "copied WAYF invite link");
    });
  },

  captureReceiverRedirectUrl({ inviteLink, providerUrl }) {
    const receiverOrigin = new URL(providerUrl).origin;

    cy.visit(inviteLink);
    assertWayfProviderEntryVisible();
    submitManualWayfProvider(providerUrl);

    return cy
      .origin(receiverOrigin, () => {
        return cy.location("href", { timeout: 60000 }).then((href) => {
          expect(href, "WAYF receiver redirect URL").to.match(/^https?:\/\//);
          return href;
        });
      })
      .then((href) => {
        return normalizeWayfRedirectUrl(href, providerUrl);
      });
  },
};

export const nextcloudV34ContactWayfReceiverAdapter: ContactWayfReceiverAdapter = {
  key: "nextcloud/v34",

  acceptInviteFromRedirect({ redirectUrl }) {
    return acceptWayfRedirectInvite(redirectUrl);
  },

  assertAcceptedContactExists({ acceptedContactUrl }) {
    assertAcceptedContactExists({ acceptedContactUrl });
  },
};

export const nextcloudV34ProviderIdentityAdapter: ProviderIdentityAdapter = {
  key: "nextcloud/v34",

  getBaseUrl() {
    return resolveReceiverBaseUrl();
  },

  getProviderUrl({ inviteLink }: { inviteLink?: string } = {}) {
    return getReceiverProviderUrl(inviteLink);
  },

  getHost() {
    return new URL(resolveReceiverBaseUrl()).host;
  },

  buildFederatedRecipientId({ credentials }) {
    return `${credentials.username}@${new URL(resolveReceiverBaseUrl()).host}`;
  },

};
