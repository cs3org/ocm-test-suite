/// <reference types="cypress" />

import { ocmgoV1LoginAdapter } from "../../support/adapters/ocmgo/v1/login-adapter";
import { nextcloudV33LoginAdapter } from "../../support/adapters/nextcloud/v33/login-adapter";
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

export const loginCases: ScenarioCase[] = [
  {
    id: "login__nextcloud-v33",
    adapter: nextcloudV33LoginAdapter,
    actor: nextcloudMichielActor,
  },
  {
    id: "login__ocmgo-v1",
    adapter: ocmgoV1LoginAdapter,
    actor: ocmgoActor,
  },
];
