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

export {};
