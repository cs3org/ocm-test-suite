/// <reference types="cypress" />

import { ocmgoV1LoginAdapter } from "../../support/adapters/ocmgo/v1/login-adapter";
import { ocmgoV1ShareWithReceiverAdapter } from "../../support/adapters/ocmgo/v1/share-with-receiver-adapter";
import { ocmgoV1ShareWithSenderAdapter } from "../../support/adapters/ocmgo/v1/share-with-sender-adapter";
import { nextcloudV33LoginAdapter } from "../../support/adapters/nextcloud/v33/login-adapter";
import {
  nextcloudV33ShareWithReceiverAdapter,
  nextcloudV33ShareWithSenderAdapter,
} from "../../support/adapters/nextcloud/v33/share-with-adapter";
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
    senderAdapter: nextcloudV33ShareWithSenderAdapter,
    receiverAdapter: nextcloudV33ShareWithReceiverAdapter,
    senderLogin: nextcloudV33LoginAdapter,
    receiverLogin: nextcloudV33LoginAdapter,
    sender: senderActor,
    receiver: receiverActor,
  },
  {
    id: "share-with__nextcloud-v33__ocmgo-v1",
    senderAdapter: nextcloudV33ShareWithSenderAdapter,
    receiverAdapter: ocmgoV1ShareWithReceiverAdapter,
    senderLogin: nextcloudV33LoginAdapter,
    receiverLogin: ocmgoV1LoginAdapter,
    sender: senderActor,
    receiver: receiverActor,
  },
  {
    id: "share-with__ocmgo-v1__nextcloud-v33",
    senderAdapter: ocmgoV1ShareWithSenderAdapter,
    receiverAdapter: nextcloudV33ShareWithReceiverAdapter,
    senderLogin: ocmgoV1LoginAdapter,
    receiverLogin: nextcloudV33LoginAdapter,
    sender: senderActor,
    receiver: receiverActor,
  },
  {
    id: "share-with__ocmgo-v1__ocmgo-v1",
    senderAdapter: ocmgoV1ShareWithSenderAdapter,
    receiverAdapter: ocmgoV1ShareWithReceiverAdapter,
    senderLogin: ocmgoV1LoginAdapter,
    receiverLogin: ocmgoV1LoginAdapter,
    sender: senderActor,
    receiver: receiverActor,
  },
];
