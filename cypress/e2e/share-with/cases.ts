/// <reference types="cypress" />

import { nextcloudV33ShareWithAdapter } from "../../support/adapters/nextcloud/v33/share-with-adapter";
import type { ActorRef, ScenarioCase } from "../../support/contracts/share-with";

const senderActor: ActorRef = {
  id: "sender",
  usernameEnvKeys: ["sender_username"],
  passwordEnvKeys: ["sender_password"],
};

const receiverActor: ActorRef = {
  id: "receiver",
  usernameEnvKeys: ["receiver_username"],
  passwordEnvKeys: ["receiver_password"],
};

export const shareWithCases: ScenarioCase[] = [
  {
    id: "share-with__nextcloud-v33__nextcloud-v33",
    adapter: nextcloudV33ShareWithAdapter,
    sender: senderActor,
    receiver: receiverActor,
  },
];
