/// <reference types="cypress" />

import { createNextcloudShareWithAdapters } from "../shared/share-with-impl";

const { shareWithFlowSender, shareWithFlowReceiver, shareFileSender, shareFileReceiver } =
  createNextcloudShareWithAdapters("v33");

export const nextcloudV33ShareWithFlowSenderAdapter = shareWithFlowSender;
export const nextcloudV33ShareWithFlowReceiverAdapter = shareWithFlowReceiver;
export const nextcloudV33ShareFileSenderAdapter = shareFileSender;
export const nextcloudV33ShareFileReceiverAdapter = shareFileReceiver;
