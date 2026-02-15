/**
 * @fileoverview
 * DOM and API helpers for Cypress tests interacting with OCM-Go.
 * Selectors sourced from Playwright e2e tests in the ocm-go repo.
 */

/**
 * Log in via the /ui/login page.
 */
export function doLogin(url, username, password) {
  cy.visit(`${url}/ui/login`);
  cy.get('#username', { timeout: 10000 }).should('be.visible').clear().type(username);
  cy.get('#password').clear().type(password);
  cy.get('#submit-btn').click();
  cy.url({ timeout: 10000 }).should('include', '/ui/inbox');
}

/**
 * Fill and submit the outgoing share form.
 * @param {string} url       - Base URL of the OCM-Go instance.
 * @param {string} shareWith - Recipient in user@host format.
 * @param {string} localPath - Server-side path to the file being shared.
 */
export function fillOutgoingShareForm(url, shareWith, localPath) {
  cy.visit(`${url}/ui/outgoing`);
  cy.get('#share-with', { timeout: 10000 }).should('be.visible').clear().type(shareWith);
  cy.get('#local-path').clear().type(localPath);
  cy.get('#share-submit').click();
  cy.get('#share-result', { timeout: 15000 }).should('be.visible');
}

/**
 * Accept an incoming share by matching its display name in the inbox.
 */
export function acceptShareInInbox(url, sharedFileName) {
  cy.visit(`${url}/ui/inbox`);

  // Locate the share item by name and click accept
  cy.contains('.share-name', sharedFileName, { timeout: 30000 })
    .parents('.share-item')
    .first()
    .find('.btn-accept')
    .click();

  // Verify the item transitioned to accepted
  cy.contains('.share-name', sharedFileName, { timeout: 10000 })
    .parents('.share-item')
    .first()
    .find('.status-accepted')
    .should('exist');
}

/**
 * Create an outgoing invite via the UI and return the base64 invite string.
 * Returns a Cypress chainable that resolves to the invite string.
 */
export function createInvite(url) {
  cy.visit(`${url}/ui/outgoing`);
  cy.get('#invite-create-btn', { timeout: 10000 }).should('be.visible').click();
  cy.get('#invite-string', { timeout: 10000 }).should('be.visible').and('not.have.value', '');
  return cy.get('#invite-string').invoke('val').then((val) => val.trim());
}

/**
 * Import an invite string and accept it via the API.
 * Requires an active session (call doLogin first).
 */
export function importAndAcceptInvite(url, inviteString) {
  cy.request({
    method: 'POST',
    url: `${url}/api/inbox/invites/import`,
    body: { inviteString },
  }).then((importRes) => {
    expect(importRes.status).to.be.oneOf([200, 201]);

    const inviteId = importRes.body.id;

    cy.request({
      method: 'POST',
      url: `${url}/api/inbox/invites/${inviteId}/accept`,
      body: {},
    }).then((acceptRes) => {
      expect(acceptRes.status).to.eq(200);
      expect(acceptRes.body.status).to.eq('accepted');
    });
  });
}

/**
 * WAYF discovery on the sender's domain. Visits the WAYF page, enters the
 * recipient URL, discovers the provider, and extracts the redirect URL from
 * the page's JavaScript context without navigating away.
 *
 * Returns a Cypress chainable resolving to the redirect URL (recipient domain).
 */
export function captureWayfRedirectUrl(wayfUrl, recipientUrl) {
  cy.visit(wayfUrl);
  cy.get('#manual-url', { timeout: 10000 }).should('be.visible').clear().type(recipientUrl);
  cy.get('#discover-btn').click();
  cy.get('#discover-result .provider-item', { timeout: 15000 }).first().should('be.visible');

  // Derive token and providerDomain from the WAYF URL itself (the template
  // renders them as block-scoped const, not window properties).
  const wayfParsed = new URL(wayfUrl);
  const token = wayfParsed.searchParams.get('token');
  const providerDomain = wayfParsed.host;

  // Extract the inviteAcceptDialog base URL from the discovered provider item's
  // onclick attribute, then build the full redirect URL without navigating.
  return cy.window().then((win) => {
    const item = win.document.querySelector('#discover-result .provider-item');
    const onclick = item.getAttribute('onclick') || '';
    const match = onclick.match(/redirectToProvider\('([^']+)'\)/);
    expect(match).to.not.be.null;

    const dialog = match[1];
    const sep = dialog.includes('?') ? '&' : '?';
    const url = dialog + sep +
      'token=' + encodeURIComponent(token) +
      '&providerDomain=' + encodeURIComponent(providerDomain);
    expect(url).to.include('/ui/accept-invite');
    return url;
  });
}

/**
 * Accept a WAYF invite on the recipient's domain. Visits the redirect URL
 * (which is on the recipient's own domain) and clicks accept.
 *
 * Call doLogin on the recipient BEFORE this so the session cookie is available.
 */
export function acceptWayfInvite(redirectUrl) {
  cy.visit(redirectUrl);
  cy.url({ timeout: 15000 }).should('include', '/ui/accept-invite');
  cy.get('#accept-btn', { timeout: 10000 }).should('be.visible').click();
  cy.get('#success-msg', { timeout: 10000 }).should('be.visible');
  cy.url({ timeout: 10000 }).should('include', '/ui/inbox');
}
