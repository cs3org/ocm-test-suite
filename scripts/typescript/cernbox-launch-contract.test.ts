// Native CI runs bun test scripts/typescript/. Import the Cypress-owned pure
// contracts here so they run in CI without duplicating their implementation.
import "../../cypress/support/shared/cernbox-launch-replay.test";
import "../../cypress/support/shared/cernbox-launch-replay-driver.test";
