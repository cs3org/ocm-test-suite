/// <reference types="cypress" />

const resizeObserverUndeliveredNotifications =
  "ResizeObserver loop completed with undelivered notifications";

Cypress.on("uncaught:exception", (err) => {
  const message = String(
    (err as unknown as { message?: unknown } | null | undefined)?.message ?? err ?? "",
  );

  if (message.includes(resizeObserverUndeliveredNotifications)) {
    return false;
  }
});

Cypress.on("window:before:load", (win) => {
  const prevOnError = (win as unknown as { onerror?: unknown }).onerror;
  (win as unknown as { onerror?: unknown }).onerror = (
    message: unknown,
    source?: unknown,
    lineno?: unknown,
    colno?: unknown,
    error?: unknown,
  ) => {
    const messageString = String(message ?? "");
    if (messageString.includes(resizeObserverUndeliveredNotifications)) {
      return true;
    }
    if (typeof prevOnError === "function") {
      return (prevOnError as any)(message, source, lineno, colno, error);
    }
    return false;
  };
});

// Policy: Do not use cy.origin().
// Avoid cross-origin flows by splitting sender and receiver into separate tests.
// Exceptions:
// - contact-wayf may use cy.origin() only to capture the receiver redirect URL
//   after WAYF provider discovery.
// - login may use cy.origin() solely to drive an external IdP (Keycloak) login
//   form; it must not act as a second EFSS party.
// Invite accept, contact proof, and share flow must stay on the receiver origin
// without cy.origin().
const normalizedSpecRelative = String(Cypress.spec.relative ?? "")
  .split("\\")
  .join("/");
const allowOriginForSpec =
  normalizedSpecRelative === "cypress/e2e/contact-wayf/index.cy.ts" ||
  normalizedSpecRelative === "cypress/e2e/login/index.cy.ts";
try {
  if (!allowOriginForSpec) {
    Cypress.Commands.overwrite("origin", () => {
      throw new Error(
        [
          "cy.origin() is forbidden in this test suite.",
          "Rule: split sender and receiver work into separate tests.",
          "Only contact-wayf redirect capture and login IdP form submission may use cy.origin(); it must not act as a second EFSS party or drive invite accept, contact proof, or share flows.",
        ].join(" "),
      );
    });
  }
} catch {
  // Ignore if this Cypress version has no origin command.
}

export {};
