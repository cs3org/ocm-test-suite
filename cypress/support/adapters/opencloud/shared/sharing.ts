/// <reference types="cypress" />

// OpenCloud sharing-panel helpers.

import { cssEscapeAttributeValue } from "../../../shared/selectors";
import {
  parseRemoteHostFromFederatedRecipientId,
  parseSearchTermFromFederatedRecipientId,
} from "../../../shared/urls";
import type { OpenCloudProfile } from "./profile";
import type { OpenCloudFilesHelpers } from "./files";

const sharingTimeoutMs = 20000;
const sharesNavTimeoutMs = 60000;

export interface OpenCloudSharingHelpers {
  openSharingPanel: (sharedFileName: string) => void;
  addExternalShare: (
    sharedFileName: string,
    federatedRecipientId: string,
  ) => void;
  acceptIncomingShare: (sharedFileName: string) => void;
}

export function makeOpenCloudSharingHelpers(
  profile: OpenCloudProfile,
  files: OpenCloudFilesHelpers,
): OpenCloudSharingHelpers {
  const sel = profile.selectors.sharing;
  const net = profile.network;

  // ---------------------------------------------------------------------------
  // Sender-side helpers
  // ---------------------------------------------------------------------------

  function triggerShareAction(fileName: string): void {
    const escaped = cssEscapeAttributeValue(fileName);

    // View-agnostic per-resource context menu trigger. The action-dropdown
    // button is rendered with a stable data-test attribute and either the
    // tile-variant or table-variant class depending on view mode. We match
    // both via the OR-form selector built in the profile.
    cy.get(sel.resourceActionDropdown(escaped), { timeout: sharingTimeoutMs })
      .filter(":visible")
      .first()
      .should("be.visible")
      .click();

    // Wait for the resource context menu to mount, then jump straight to
    // the sharing panel via the dedicated trigger.
    cy.get(sel.contextMenu, { timeout: sharingTimeoutMs })
      .should("be.visible")
      .find(sel.showSharesAction)
      .first()
      .should("be.visible")
      .click();

    cy.get(sel.sharingSidebar, { timeout: sharingTimeoutMs }).should(
      "be.visible",
    );
  }

  function ensureExternalUsersScope(): void {
    cy.get(sel.sharingSidebar, { timeout: sharingTimeoutMs }).should(
      "be.visible",
    );

    cy.get(sel.sharingSidebar).then(($sidebar) => {
      const pill = $sidebar.find(sel.inviteRoleTypePill).first();
      const currentText = pill.text().trim();
      if (!currentText.toLowerCase().startsWith("external")) {
        cy.wrap(pill).click({ force: true });
        cy.contains(sel.inviteRoleTypeItem, sel.externalUsersLabel, {
          timeout: sharingTimeoutMs,
        }).click({ force: true });
      }
    });
  }

  // Types the search term (not the full federated ID) into the recipient input
  // and waits for the Graph user-search response. The search term is derived
  // from the federated recipient ID by cutting at the last "@", so usernames
  // containing "@" are handled correctly.
  function typeShareRecipient(searchTerm: string): void {
    cy.get(sel.sharingSidebar).within(() => {
      cy.intercept({
        times: 1,
        method: "GET",
        url: net.graphUserSearchGlob,
      }).as("openCloudUserSearch");

      cy.get(sel.inviteInput, { timeout: sharingTimeoutMs })
        .should("be.visible")
        .clear()
        .type(searchTerm);

      cy.wait("@openCloudUserSearch", { timeout: sharingTimeoutMs });
    });
  }

  // No-options messages the web UI renders when a user search returns no matches.
  const NO_RESULTS_PATTERNS = [
    "no external users found",
    "no users or groups found",
  ];

  function isNoResultsText(text: string): boolean {
    const lower = text.toLowerCase().trim();
    return NO_RESULTS_PATTERNS.some((p) => lower.includes(p));
  }

  // Builds search candidates from a federatedRecipientId by cutting at the last
  // "@". Examples:
  //   marie@opencloud2.docker         -> ["marie"]
  //   mahdi@it@ponder.com@host        -> ["mahdi@it@ponder.com"]
  function recipientCandidates(federatedRecipientId: string): string[] {
    const searchTerm =
      parseSearchTermFromFederatedRecipientId(federatedRecipientId);
    const titleCased =
      searchTerm.charAt(0).toUpperCase() + searchTerm.slice(1);
    const candidates: string[] = [searchTerm];
    if (titleCased !== searchTerm) {
      candidates.push(titleCased);
    }
    return candidates;
  }

  // Picks an autocomplete item using provider-aware logic: among real (non
  // no-results) items, prefer the one whose rendered text includes receiverHost
  // (the external issuer shown for federated users). Falls back to the first
  // real item when no host match is found.
  function pickBestOption(
    $listbox: JQuery<HTMLElement>,
    receiverHost: string,
  ): JQuery<HTMLElement> | null {
    const preferred = $listbox.find(sel.recipientItemPreferred);
    const pool =
      preferred.length > 0
        ? preferred
        : $listbox.find(sel.recipientItemFallback);

    const real = pool.filter((_, el) => !isNoResultsText(el.textContent ?? ""));
    if (real.length === 0) return null;

    const hostMatch = real.filter((_, el) =>
      (el.textContent ?? "").toLowerCase().includes(receiverHost.toLowerCase()),
    );
    if (hostMatch.length > 0) return hostMatch.first();

    return real.first();
  }

  // Tries each candidate in turn. For each: types the search term, waits for
  // the user-search API, then selects the best provider-matched item.
  // Throws if all candidates fail.
  function selectRecipientWithFallback(
    candidates: string[],
    receiverHost: string,
  ): void {
    function attempt(idx: number): void {
      if (idx >= candidates.length) {
        throw new Error(
          `No real autocomplete option found for: [${candidates.join(", ")}]`,
        );
      }

      typeShareRecipient(candidates[idx]);

      cy.get(sel.sharingSidebar)
        .find(sel.recipientListbox, { timeout: sharingTimeoutMs })
        .should("be.visible")
        .then(($listbox) => {
          const target = pickBestOption($listbox, receiverHost);
          if (target) {
            cy.wrap(target)
              .scrollIntoView()
              .should("be.visible")
              .click({ force: true });
            return;
          }

          attempt(idx + 1);
        });
    }

    attempt(0);
  }

  function createShare(): void {
    cy.get(sel.sharingSidebar).within(() => {
      cy.get(sel.createShareButton, { timeout: sharingTimeoutMs })
        .scrollIntoView()
        .should("be.visible")
        .should("not.be.disabled");
    });

    // Intercept the Graph invite POST before dispatching the click so cy.wait()
    // captures the response even if it resolves very quickly.
    cy.intercept({
      times: 1,
      method: "POST",
      url: net.graphInviteGlob,
    }).as("openCloudShareCreate");

    // Dispatch a native MouseEvent on the DOM node so Vue's @click="share"
    // handler fires. Cypress synthetic .click() can miss the handler inside
    // vs__actions; native dispatch avoids that gap.
    cy.document().then((doc) => {
      const btn = doc.querySelector<HTMLElement>(sel.createShareButton);
      btn?.dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
    });

    cy.wait("@openCloudShareCreate", { timeout: sharingTimeoutMs }).then(
      (interception) => {
        expect(
          interception.response?.statusCode,
          "Graph invite POST status",
        ).to.be.oneOf([200, 201]);

        const recipients: Array<{ objectId?: string }> =
          interception.request?.body?.recipients ?? [];
        if (recipients.length > 0) {
          expect(
            recipients[0].objectId,
            "invite recipients[0].objectId should be set",
          )
            .to.be.a("string")
            .and.not.be.empty;
        }
      },
    );

    cy.contains(sel.shareSuccessText, { timeout: sharingTimeoutMs });
  }

  // Navigates back to the file list and reopens the sharing sidebar, waiting for
  // the Graph listPermissions response as the signal that the share is
  // persisted. Fails with a useful error if the permissions endpoint returns no
  // entries or the collaborators list is absent from the UI.
  function verifySharedWithAfterReopen(sharedFileName: string): void {
    files.ensureFilesAppActive();

    cy.intercept({
      method: "GET",
      url: net.graphListPermissionsGlob,
    }).as("openCloudListPermissions");

    openSharingPanel(sharedFileName);

    cy.wait("@openCloudListPermissions", { timeout: sharingTimeoutMs }).then(
      (interception) => {
        const permissions: unknown[] = Array.isArray(
          interception.response?.body?.value,
        )
          ? interception.response.body.value
          : [];
        if (permissions.length === 0) {
          throw new Error(
            `listPermissions returned no entries for "${sharedFileName}". ` +
              `Share may not have propagated yet.`,
          );
        }
      },
    );

    cy.get(sel.sharingSidebar, { timeout: sharingTimeoutMs }).should(
      "be.visible",
    );

    cy.get(sel.sharingSidebar).within(() => {
      cy.get(sel.collaboratorsList, { timeout: sharingTimeoutMs }).should(
        "exist",
      );
    });
  }

  function openSharingPanel(sharedFileName: string): void {
    triggerShareAction(sharedFileName);

    cy.get(sel.sharingSidebar, { timeout: sharingTimeoutMs }).should(
      "be.visible",
    );
  }

  // sharedFileName is required so verifySharedWithAfterReopen can reopen the
  // sidebar and confirm the share is visible via the permissions API.
  function addExternalShare(
    sharedFileName: string,
    federatedRecipientId: string,
  ): void {
    const receiverHost =
      parseRemoteHostFromFederatedRecipientId(federatedRecipientId);
    ensureExternalUsersScope();
    selectRecipientWithFallback(
      recipientCandidates(federatedRecipientId),
      receiverHost,
    );
    createShare();
    verifySharedWithAfterReopen(sharedFileName);
  }

  // ---------------------------------------------------------------------------
  // Receiver-side helpers
  // ---------------------------------------------------------------------------

  function acceptIncomingShare(sharedFileName: string): void {
    const escapedName = cssEscapeAttributeValue(sharedFileName);

    cy.get(sel.webNavSidebar, { timeout: sharingTimeoutMs })
      .should("be.visible")
      .within(() => {
        cy.contains("span, a, li", sel.sharesNavLabel, {
          timeout: sharingTimeoutMs,
        })
          .first()
          .click({ force: true });
      });

    cy.get(sel.receivedResourceByName(escapedName), {
      timeout: sharesNavTimeoutMs,
    })
      .scrollIntoView()
      .should("be.visible");

    cy.get(sel.resourceActionDropdown(escapedName), {
      timeout: sharingTimeoutMs,
    })
      .filter(":visible")
      .first()
      .should("be.visible")
      .click();

    cy.get(sel.contextMenu, { timeout: sharingTimeoutMs })
      .should("be.visible")
      .find(sel.enableSyncAction)
      .first()
      .should("be.visible")
      .click();

    cy.get(sel.receivedResourceByName(escapedName), {
      timeout: sharesNavTimeoutMs,
    }).should("be.visible");
  }

  return { openSharingPanel, addExternalShare, acceptIncomingShare };
}
