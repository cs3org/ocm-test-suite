/// <reference types="cypress" />

export type ActorRef = {
  id: string;
  usernameEnvKeys: string[];
  passwordEnvKeys: string[];
};

export type ActorCredentials = {
  username: string;
  password: string;
};

export type LoginMechanism = "same-origin" | "external-idp";

type LoginAdapterBase = {
  key: string;
  login(credentials: ActorCredentials): void;
  assertLoggedIn(): void;
};

// EFSS whose login form lives on the application origin (Nextcloud, oCIS,
// OpenCloud, OCM-Go). The login spec drives open -> capture -> submit -> assert
// on a single origin.
export type SameOriginLoginAdapter = LoginAdapterBase & {
  mechanism: "same-origin";
  openLoginPage(): void;
  captureLoginPageReadyEvidence(scenarioId: string): void;
  submitLogin(credentials: ActorCredentials): void;
};

// EFSS that authenticate against an external Keycloak/OIDC IdP (CERNBox). The
// user logs in at the IdP origin first (cached via cy.session, no cy.origin),
// then the app picks up the session through a silent OIDC handshake.
export type ExternalIdpLoginAdapter = LoginAdapterBase & {
  mechanism: "external-idp";
  establishIdpSession(credentials: ActorCredentials, scenarioId?: string): void;
  completeAppLogin(): void;
};

export type LoginAdapter = SameOriginLoginAdapter | ExternalIdpLoginAdapter;

export type ScenarioCase = {
  id: string;
  adapter: LoginAdapter;
  actor: ActorRef;
};
