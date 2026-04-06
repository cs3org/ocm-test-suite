/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import { assertNextcloudLoggedIn, loginNextcloudViaUi } from "../shared/login";

export const nextcloudV32LoginAdapter: LoginAdapter = {
  key: "nextcloud/v32",
  login(credentials) {
    loginNextcloudViaUi(credentials);
  },
  assertLoggedIn() {
    assertNextcloudLoggedIn();
  },
};
