/// <reference types="cypress" />

const runtimeDir = "/artifacts/cypress/runtime";

export function runtimePath(flowId: string, scenarioId: string): string {
  return `${runtimeDir}/${flowId}-${scenarioId}.json`;
}

export function installHooks(options: { stopOnFailure?: boolean } = {}): void {
  const originalBaseUrl = Cypress.config("baseUrl");
  const stopOnFailure = options.stopOnFailure ?? true;

  afterEach(function () {
    Cypress.config("baseUrl", originalBaseUrl);

    if (stopOnFailure && this.currentTest?.state === "failed") {
      Cypress.stop();
      return;
    }
  });
}

export function ensureRuntimeDir(): Cypress.Chainable<Cypress.Exec> {
  return cy.exec(`mkdir -p ${runtimeDir}`, { log: false });
}

export function clearRuntime(runtimeFilePath: string): Cypress.Chainable<Cypress.Exec> {
  return cy.exec(`rm -f "${runtimeFilePath}"`, { log: false });
}

export function writeRuntime(
  runtimeFilePath: string,
  runtime: Record<string, unknown>,
): Cypress.Chainable<Cypress.Exec> {
  return cy.writeFile(runtimeFilePath, runtime, { log: false }).then(() => {
    return cy.exec(`test -f "${runtimeFilePath}"`, { log: false });
  });
}

function isRuntimeRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function readRuntime(
  runtimeFilePath: string,
): Cypress.Chainable<Record<string, unknown>> {
  return cy
    .readFile(runtimeFilePath, { log: false, timeout: 30000 })
    .then((runtimeUnknown: unknown) => {
      if (!isRuntimeRecord(runtimeUnknown)) {
        throw new Error(
          `Invalid runtime file ${runtimeFilePath}. Expected a JSON object.`,
        );
      }

      return cy.wrap(runtimeUnknown, { log: false });
    });
}

export function requireString(
  runtimeFilePath: string,
  runtime: Record<string, unknown>,
  key: string,
): string {
  const value = runtime[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(
      `Missing runtime key "${key}" in ${runtimeFilePath}. ` +
        "An earlier procedural step must write it before this step runs.",
    );
  }

  return value;
}

export function setBaseUrl(baseUrl: string): void {
  Cypress.config("baseUrl", baseUrl);
}

export function screenshot(scenarioId: string, phase: string, step: string): void {
  cy.screenshot(`${scenarioId}--${phase}--${step}`);
}
