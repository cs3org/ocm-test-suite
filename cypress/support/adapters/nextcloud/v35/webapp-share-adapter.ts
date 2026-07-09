/// <reference types="cypress" />

import { createNextcloudWebappShareReceiverAdapter } from "../shared/webapp-share-receiver-impl";
import { createNextcloudWebappShareSenderAdapter } from "../shared/webapp-share-impl";

export const nextcloudV35WebappShareFlowSenderAdapter =
  createNextcloudWebappShareSenderAdapter("v35");

export const nextcloudV35WebappShareFlowReceiverAdapter =
  createNextcloudWebappShareReceiverAdapter("v35");
