/// <reference types="cypress" />

import { createNextcloudWebappShareReceiverAdapter } from "./webapp-share-receiver-impl";
import { createNextcloudWebappShareSenderAdapter } from "./webapp-share-sender-impl";

export type NextcloudWebappShareVersion = "v35";

export function createNextcloudWebappShareAdapters(
  version: NextcloudWebappShareVersion,
) {
  return {
    webappShareFlowSender: createNextcloudWebappShareSenderAdapter(version),
    webappShareFlowReceiver: createNextcloudWebappShareReceiverAdapter(version),
  };
}
