/// <reference types="cypress" />

import { createNextcloudLoginAdapter } from "../shared/login-impl";

const loginAdapter = createNextcloudLoginAdapter("v34");
export const nextcloudV34LoginAdapter = loginAdapter;
