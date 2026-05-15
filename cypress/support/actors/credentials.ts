/// <reference types="cypress" />

import type { ActorCredentials, ActorRef } from "../contracts/login";

type ActorEnvLookup = {
  label: "username" | "password";
  envKeys: string[];
};

export function resolveActorCredentials(
  actor: ActorRef,
): Cypress.Chainable<ActorCredentials> {
  return resolveEnvFirst(actor.usernameEnvKeys).then((username) => {
    return resolveEnvFirst(actor.passwordEnvKeys).then((password) => {
      const missing = [
        missingCredentialMessage(
          { label: "username", envKeys: actor.usernameEnvKeys },
          username,
        ),
        missingCredentialMessage(
          { label: "password", envKeys: actor.passwordEnvKeys },
          password,
        ),
      ].filter((message): message is string => Boolean(message));

      if (missing.length > 0) {
        throw new Error(
          [
            `Missing Cypress actor credentials for "${actor.id}": ${missing.join("; ")}.`,
            "Actor credentials must come from config/actors and compose env injection.",
            "Run `nu scripts/ocmts.nu actors validate` and use `services up run`",
            "so compose injects the required CYPRESS_* environment variables.",
            `For manual Cypress runs, set the actor's env keys: ${[
              ...actor.usernameEnvKeys,
              ...actor.passwordEnvKeys,
            ].join(", ")}.`,
          ].join(" "),
        );
      }

      return { username: username!, password: password! };
    });
  });
}

function resolveEnvFirst(envKeys: string[]): Cypress.Chainable<string | undefined> {
  if (envKeys.length === 0) {
    return cy.wrap<string | undefined>(undefined, { log: false });
  }

  return cy.env(envKeys).then((values) => {
    for (const key of envKeys) {
      const value = values[key];
      if (value !== undefined && value !== null && String(value) !== "") {
        return cy.wrap<string | undefined>(String(value), { log: false });
      }
    }

    return cy.wrap<string | undefined>(undefined, { log: false });
  });
}

function missingCredentialMessage(
  lookup: ActorEnvLookup,
  value: string | undefined,
): string | undefined {
  if (value !== undefined) {
    return undefined;
  }

  const envKeys = lookup.envKeys
    .map((key) => `cy.env(["${key}"])`)
    .join(", ");
  return `${lookup.label} (${envKeys})`;
}
