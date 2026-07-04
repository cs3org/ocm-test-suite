/// <reference types="cypress" />

import { createNextcloudLoginAdapter } from "../shared/login-impl";

const loginAdapter = createNextcloudLoginAdapter("v35");
export const nextcloudV35LoginAdapter = loginAdapter;
