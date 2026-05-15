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

export type LoginAdapter = {
  key: string;
  openLoginPage(): void;
  submitLogin(credentials: ActorCredentials): void;
  login(credentials: ActorCredentials): void;
  assertLoggedIn(): void;
};

export type ScenarioCase = {
  id: string;
  adapter: LoginAdapter;
  actor: ActorRef;
};
