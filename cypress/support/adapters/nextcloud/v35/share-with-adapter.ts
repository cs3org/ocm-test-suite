/// <reference types="cypress" />

import { createNextcloudShareWithAdapters } from "../shared/share-with-impl";

const { shareWithFlowSender, shareWithFlowReceiver, shareFileSender, shareFileReceiver } =
  createNextcloudShareWithAdapters("v35");

export const nextcloudV35ShareWithFlowSenderAdapter = shareWithFlowSender;
export const nextcloudV35ShareWithFlowReceiverAdapter = shareWithFlowReceiver;
export const nextcloudV35ShareFileSenderAdapter = shareFileSender;
export const nextcloudV35ShareFileReceiverAdapter = shareFileReceiver;
