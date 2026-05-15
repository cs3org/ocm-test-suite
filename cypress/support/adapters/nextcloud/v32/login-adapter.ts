/// <reference types="cypress" />

import { createNextcloudLoginAdapter } from "../shared/login-impl";

const loginAdapter = createNextcloudLoginAdapter("v32");
export const nextcloudV32LoginAdapter = loginAdapter;
