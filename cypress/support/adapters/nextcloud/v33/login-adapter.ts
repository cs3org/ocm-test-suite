/// <reference types="cypress" />

import { createNextcloudLoginAdapter } from "../shared/login-impl";

const loginAdapter = createNextcloudLoginAdapter("v33");
export const nextcloudV33LoginAdapter = loginAdapter;
