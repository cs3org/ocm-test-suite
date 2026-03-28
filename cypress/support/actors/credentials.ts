/// <reference types="cypress" />

import type { ActorCredentials, ActorRef } from "../contracts/login";

type ActorEnvLookup = {
  label: "username" | "password";
  envKeys: string[];
};

export function resolveActorCredentials(actor: ActorRef): ActorCredentials {
  const username = resolveEnvFirst(actor.usernameEnvKeys);
  const password = resolveEnvFirst(actor.passwordEnvKeys);
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
        "so compose injects CYPRESS_nextcloud_username and CYPRESS_nextcloud_password.",
        "For manual Cypress runs, pass nextcloud_username and nextcloud_password",
        "in Cypress env.",
      ].join(" "),
    );
  }

  return { username, password };
}

function resolveEnvFirst(envKeys: string[]): string | undefined {
  for (const key of envKeys) {
    const value = Cypress.env(key);
    if (value !== undefined && value !== null && String(value) !== "") {
      return String(value);
    }
  }

  return undefined;
}

function missingCredentialMessage(
  lookup: ActorEnvLookup,
  value: string | undefined,
): string | undefined {
  if (value !== undefined) {
    return undefined;
  }

  const envKeys = lookup.envKeys
    .map((key) => `Cypress.env("${key}")`)
    .join(", ");
  return `${lookup.label} (${envKeys})`;
}
