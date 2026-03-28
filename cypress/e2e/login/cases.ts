/// <reference types="cypress" />

import { nextcloudV33LoginAdapter } from "../../support/adapters/nextcloud/v33/login-adapter";
import type { ActorRef, ScenarioCase } from "../../support/contracts/login";

const nextcloudMichielActor: ActorRef = {
  id: "nextcloud-michiel",
  usernameEnvKeys: ["nextcloud_username"],
  passwordEnvKeys: ["nextcloud_password"],
};

export const loginCases: ScenarioCase[] = [
  {
    id: "login__nextcloud-v33",
    adapter: nextcloudV33LoginAdapter,
    actor: nextcloudMichielActor,
  },
];
