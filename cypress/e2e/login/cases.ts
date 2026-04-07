/// <reference types="cypress" />

import type { AdapterRef } from "../../support/adapters/registry";
import { resolveLoginAdapter } from "../../support/adapters/registry";
import type { ActorRef, ScenarioCase } from "../../support/contracts/login";

const nextcloudMichielActor: ActorRef = {
  id: "nextcloud-michiel",
  usernameEnvKeys: ["nextcloud_username"],
  passwordEnvKeys: ["nextcloud_password"],
};

const ocmgoActor: ActorRef = {
  id: "ocmgo",
  usernameEnvKeys: ["ocmgo_username"],
  passwordEnvKeys: ["ocmgo_password"],
};

const actorByPlatform: Record<string, ActorRef> = {
  nextcloud: nextcloudMichielActor,
  ocmgo: ocmgoActor,
};

function parsePlatformVersionToken(token: string): AdapterRef {
  const idx = token.lastIndexOf("-");
  const platform = idx > 0 ? token.slice(0, idx) : "";
  const versionLine = idx > 0 ? token.slice(idx + 1) : "";

  if (platform.length === 0 || versionLine.length === 0) {
    throw new Error(
      [
        `[login] Invalid case token "${token}".`,
        'Expected "<platform>-<versionLine>", for example "nextcloud-v32".',
      ].join(" "),
    );
  }

  return { platform, versionLine };
}

function makeLoginCase(ref: AdapterRef): ScenarioCase {
  const actor = actorByPlatform[ref.platform];
  if (!actor) {
    throw new Error(
      [
        `[login] No actor mapping for platform "${ref.platform}".`,
        `Known platforms: ${Object.keys(actorByPlatform).sort().join(", ")}`,
      ].join(" "),
    );
  }

  return {
    id: `login__${ref.platform}-${ref.versionLine}`,
    adapter: resolveLoginAdapter(ref),
    actor,
  };
}

export function resolveLoginScenarioCase(caseId: string): ScenarioCase {
  const parts = caseId.split("__");
  if (parts.length !== 2 || parts[0] !== "login") {
    throw new Error(
      [
        `[login] proof_cell="${caseId}" is not a login case id.`,
        'Expected "login__<platform>-<versionLine>".',
      ].join(" "),
    );
  }

  const ref = parsePlatformVersionToken(parts[1] ?? "");
  return { ...makeLoginCase(ref), id: caseId };
}

export const loginCases: ScenarioCase[] = [
  makeLoginCase({ platform: "nextcloud", versionLine: "v33" }),
  makeLoginCase({ platform: "ocmgo", versionLine: "v1" }),
];
