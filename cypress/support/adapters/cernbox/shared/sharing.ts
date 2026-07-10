/// <reference types="cypress" />

// CERNBox sharing-panel helpers.

import { cssEscapeAttributeValue } from "../../../shared/selectors";
import {
  parseRemoteHostFromFederatedRecipientId,
  parseSearchTermFromFederatedRecipientId,
} from "../../../shared/urls";
import type { CernboxProfile } from "./profile";
import type { CernboxFilesHelpers } from "./files";

const sharingTimeoutMs = 20000;
const sharesNavTimeoutMs = 60000;

export interface CernboxSharingHelpers {
  openSharingPanel: (sharedFileName: string) => void;
  openSharesWithMe: () => void;
  openResourceContextMenu: (
    resourceSelector: string,
    timeoutMs?: number,
  ) => void;
  addExternalShare: (
    sharedFileName: string,
    federatedRecipientId: string,
  ) => void;
  acceptIncomingShare: (sharedFileName: string) => void;
}

export function makeCernboxSharingHelpers(
  profile: CernboxProfile,
  files: CernboxFilesHelpers,
): CernboxSharingHelpers {
  const sel = profile.selectors.sharing;
  const net = profile.network;

  // Opens the row/tile context menu for a resource and waits for the menu to be
  // visible. Callers then pick a menu entry (share, "Open remotely", ...).
  function openResourceContextMenu(
    resourceSelector: string,
    timeoutMs: number = sharingTimeoutMs,
  ): void {
    cy.get(resourceSelector, { timeout: timeoutMs })
      .filter(":visible")
      .first()
      .scrollIntoView()
      .should("be.visible")
      .closest("tr, .oc-tile-card")
      .find(sel.contextMenuTrigger)
      .first()
      .should("be.visible")
      .click({ force: true });

    cy.get(sel.contextMenu, { timeout: timeoutMs }).should("be.visible");
  }

  function triggerShareAction(fileName: string): void {
    const escaped = cssEscapeAttributeValue(fileName);

    openResourceContextMenu(`[data-test-resource-name="${escaped}"]`);

    cy.get(sel.contextMenu, { timeout: sharingTimeoutMs })
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

  function typeShareRecipient(searchTerm: string): void {
    cy.get(sel.sharingSidebar).within(() => {
      cy.intercept({
        times: 1,
        method: "GET",
        url: net.graphUserSearchGlob,
      }).as("cernboxUserSearch");

      cy.get(sel.inviteInput, { timeout: sharingTimeoutMs })
        .should("be.visible")
        .clear()
        .type(searchTerm);

      cy.wait("@cernboxUserSearch", { timeout: sharingTimeoutMs });
    });
  }

  const NO_RESULTS_PATTERNS = [
    "no external users found",
    "no users or groups found",
  ];

  function isNoResultsText(text: string): boolean {
    const lower = text.toLowerCase().trim();
    return NO_RESULTS_PATTERNS.some((p) => lower.includes(p));
  }

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

    cy.intercept({
      times: 1,
      method: "POST",
      url: net.graphInviteGlob,
    }).as("cernboxShareCreate");

    cy.document().then((doc) => {
      const btn = doc.querySelector<HTMLElement>(sel.createShareButton);
      btn?.dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
    });

    cy.wait("@cernboxShareCreate", { timeout: sharingTimeoutMs }).then(
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

  function verifySharedCollaborator(federatedRecipientId: string): void {
    const searchTerm =
      parseSearchTermFromFederatedRecipientId(federatedRecipientId);
    const receiverHost =
      parseRemoteHostFromFederatedRecipientId(federatedRecipientId);

    cy.get(sel.sharingSidebar, { timeout: sharingTimeoutMs }).should(
      "be.visible",
    );

    cy.get(sel.sharingSidebar).within(() => {
      cy.get(sel.collaboratorsList, { timeout: sharingTimeoutMs })
        .should("be.visible")
        .find("li")
        .should("have.length.at.least", 1);

      cy.get(sel.collaboratorsList)
        .invoke("text")
        .then((text) => {
          const lower = text.toLowerCase();
          const hasSearchTerm = lower.includes(searchTerm.toLowerCase());
          const hasReceiverHost = lower.includes(receiverHost.toLowerCase());
          expect(
            hasSearchTerm || hasReceiverHost,
            `Collaborators list should contain "${searchTerm}" or "${receiverHost}" after external share`,
          ).to.be.true;
        });
    });
  }

  function openSharingPanel(sharedFileName: string): void {
    triggerShareAction(sharedFileName);

    cy.get(sel.sharingSidebar, { timeout: sharingTimeoutMs }).should(
      "be.visible",
    );
  }

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
    verifySharedCollaborator(federatedRecipientId);
  }

  function openSharesWithMe(): void {
    files.stubWindowOpenForInTabNavigation();

    cy.get(sel.webNavSidebar, { timeout: sharingTimeoutMs })
      .should("be.visible")
      .within(() => {
        cy.contains("span, a, li", sel.sharesNavLabel, {
          timeout: sharingTimeoutMs,
        })
          .first()
          .click({ force: true });
      });
  }

  function acceptIncomingShare(sharedFileName: string): void {
    const escapedName = cssEscapeAttributeValue(sharedFileName);

    openSharesWithMe();

    cy.get(sel.receivedResourceByName(escapedName), {
      timeout: sharesNavTimeoutMs,
    })
      .scrollIntoView()
      .should("be.visible");
  }

  return {
    openSharingPanel,
    openSharesWithMe,
    openResourceContextMenu,
    addExternalShare,
    acceptIncomingShare,
  };
}
