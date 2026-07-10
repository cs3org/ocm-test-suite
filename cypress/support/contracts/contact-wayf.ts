/// <reference types="cypress" />

import type {
  ContactWayfReceiverAdapter,
  ContactWayfSenderAdapter,
  ProviderIdentityAdapter,
} from "./contact";
import type { ActorRef, LoginAdapter } from "./login";
import type {
  ShareFileReceiverAdapter,
  ShareFileSenderAdapter,
} from "./share-file";

export type ScenarioCase = {
  id: string;
  sender: ActorRef;
  receiver: ActorRef;
  senderLogin: LoginAdapter;
  receiverLogin: LoginAdapter;
  senderShareFile: ShareFileSenderAdapter;
  receiverShareFile: ShareFileReceiverAdapter;
  contactWayfSender: ContactWayfSenderAdapter;
  contactWayfReceiver: ContactWayfReceiverAdapter;
  receiverIdentity: ProviderIdentityAdapter;
};
