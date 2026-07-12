/// <reference types="cypress" />

import {
  CROSS_ORIGIN_ALLOWED_SPECS,
  CROSS_ORIGIN_POLICY_TEXT,
} from "./shared/cross-origin-policy";

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
// External IdP (Keycloak) login does NOT use cy.origin(): the IdP is visited as
// a first-class origin and the session is cached with cy.session(), so the app
// completes a silent OIDC handshake. See cypress/support/shared/idp-session.ts.
// Exceptions (bounded cy.origin use only):
// - contact-wayf: capture the receiver redirect URL after WAYF provider discovery.
// - webapp-share: after sender/receiver, accept, and launch-gate work complete,
//   the launch is a client-side cross-origin POST handoff to the remote hub;
//   cy.origin() is used only for the terminal JupyterLab visual-proof assertion
//   and success screenshot. It must not drive login, accept, contact proof, or
//   share flows.
const normalizedSpecRelative = String(Cypress.spec.relative ?? "")
  .split("\\")
  .join("/");
const allowOriginForSpec = (
  CROSS_ORIGIN_ALLOWED_SPECS as readonly string[]
).includes(normalizedSpecRelative);
try {
  if (!allowOriginForSpec) {
    Cypress.Commands.overwrite("origin", () => {
      throw new Error(CROSS_ORIGIN_POLICY_TEXT);
    });
  }
} catch {
  // Ignore if this Cypress version has no origin command.
}

export {};
