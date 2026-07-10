/// <reference types="cypress" />

import { createNextcloudWebappShareAdapters } from "../shared/webapp-share-adapters";

const { webappShareFlowSender, webappShareFlowReceiver } =
  createNextcloudWebappShareAdapters("v35");

export const nextcloudV35WebappShareFlowSenderAdapter = webappShareFlowSender;
export const nextcloudV35WebappShareFlowReceiverAdapter = webappShareFlowReceiver;
