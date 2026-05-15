/// <reference types="cypress" />

import { createNextcloudShareWithAdapters } from "../shared/share-with-impl";

const { shareWithFlowSender, shareWithFlowReceiver, shareFileSender, shareFileReceiver } =
  createNextcloudShareWithAdapters("v34");

export const nextcloudV34ShareWithFlowSenderAdapter = shareWithFlowSender;
export const nextcloudV34ShareWithFlowReceiverAdapter = shareWithFlowReceiver;
export const nextcloudV34ShareFileSenderAdapter = shareFileSender;
export const nextcloudV34ShareFileReceiverAdapter = shareFileReceiver;
