/// <reference types="cypress" />

import { createNextcloudWebappShareSenderAdapter } from "../shared/webapp-share-impl";

export const nextcloudV35WebappShareFlowSenderAdapter =
  createNextcloudWebappShareSenderAdapter("v35");
