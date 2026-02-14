/**
 * @fileoverview
 * Cypress test suite for testing the login functionality of OCM-Go.
 */

import { getUtils } from '../utils/index.js';

describe('OCM-Go Login Tests', () => {
  it('should successfully log into OCM-Go with valid credentials', () => {
    const platform = Cypress.env('EFSS_PLATFORM_1') ?? 'ocmgo';
    const platformVersion = Cypress.env('EFSS_PLATFORM_1_VERSION') ?? 'v1';
    const url = Cypress.env('OCMGO1_URL') || 'https://ocm-go1.docker';
    const username = Cypress.env('OCMGO1_USERNAME') || 'marie';
    const password = Cypress.env('OCMGO1_PASSWORD') || 'radioactivity';

    const platformUtils = getUtils(platform, platformVersion);

    platformUtils.login({ url, username, password });
  });
});
