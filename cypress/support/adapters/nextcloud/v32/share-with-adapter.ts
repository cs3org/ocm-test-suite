/// <reference types="cypress" />

import { createNextcloudShareWithAdapters } from "../shared/share-with-impl";

const { shareWithFlowSender, shareWithFlowReceiver, shareFileSender, shareFileReceiver } =
  createNextcloudShareWithAdapters("v32");

export const nextcloudV32ShareWithFlowSenderAdapter = shareWithFlowSender;
export const nextcloudV32ShareWithFlowReceiverAdapter = shareWithFlowReceiver;
export const nextcloudV32ShareFileSenderAdapter = shareFileSender;
export const nextcloudV32ShareFileReceiverAdapter = shareFileReceiver;
