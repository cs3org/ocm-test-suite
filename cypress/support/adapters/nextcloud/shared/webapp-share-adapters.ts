/// <reference types="cypress" />

import { createNextcloudWebappShareReceiverAdapter } from "./webapp-share-receiver-impl";
import { createNextcloudWebappShareSenderAdapter } from "./webapp-share-sender-impl";

export function createNextcloudWebappShareAdapters(version: "v35") {
  return {
    webappShareFlowSender: createNextcloudWebappShareSenderAdapter(version),
    webappShareFlowReceiver: createNextcloudWebappShareReceiverAdapter(version),
  };
}
