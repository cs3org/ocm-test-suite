/// <reference types="cypress" />

// Resolves the full download path for a file using the Cypress downloadsFolder
// config value. Using the config key means the helper works whether the runner
// is on a developer machine, a CI node, or any custom path set in cypress.config.
export function resolveCypressDownloadPath(fileName: string): string {
  return `${Cypress.config("downloadsFolder")}/${fileName}`;
}
