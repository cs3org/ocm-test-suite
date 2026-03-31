/// <reference types="cypress" />

export {};

declare global {
  namespace Cypress {
    interface Chainable<Subject = any> {
      env(keys: string[]): Chainable<Record<string, string | undefined>>;
    }

    interface CypressStatic {
      expose(key: string): unknown;
    }
  }
}
