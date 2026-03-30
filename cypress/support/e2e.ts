/// <reference types="cypress" />

const resizeObserverUndeliveredNotifications =
  "ResizeObserver loop completed with undelivered notifications";

Cypress.on("uncaught:exception", (err) => {
  const message =
    err && typeof err.message === "string" ? err.message : undefined;

  if (
    message &&
    message.includes(resizeObserverUndeliveredNotifications)
  ) {
    return false;
  }
});

// Policy: do not use cy.origin().
// avoid cross-origin flows by splitting sender/receiver into separate tests.
// Enforce early so we do not drift into Cypress cross-origin experiment traps.
try {
  Cypress.Commands.overwrite("origin", () => {
    throw new Error(
      [
        "cy.origin() is forbidden in repos/ots-rebooted.",
        "Split cross-instance flows into separate tests (one origin per test) like legacy.",
      ].join(" "),
    );
  });
} catch {
  // Ignore if this Cypress version has no origin command.
}

export {};
