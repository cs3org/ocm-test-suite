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

// Policy: Do not use cy.origin().
// Avoid cross-origin flows by splitting sender and receiver into separate tests.
// Enforce early so each test stays on a single origin.
try {
  Cypress.Commands.overwrite("origin", () => {
    throw new Error(
      [
        "cy.origin() is forbidden in this test suite.",
        "Rule: Each test must stay on a single origin. Split sender and receiver flows into separate tests.",
      ].join(" "),
    );
  });
} catch {
  // Ignore if this Cypress version has no origin command.
}

export {};
