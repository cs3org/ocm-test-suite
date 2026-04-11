/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import {
  assertNextcloudLoggedIn,
  loginNextcloudViaUi,
} from "../shared/login";

export const nextcloudV34LoginAdapter: LoginAdapter = {
  key: "nextcloud/v34",
  login(credentials) {
    loginNextcloudViaUi(credentials);
  },
  assertLoggedIn() {
    assertNextcloudLoggedIn();
  },
};
