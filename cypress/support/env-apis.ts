/// <reference types="cypress" />

export {};

declare global {
  namespace Cypress {
    interface Chainable<Subject = any> {
      env(key: string): Chainable<unknown>;
    }

    interface CypressStatic {
      expose(key: string): unknown;
    }
  }
}
