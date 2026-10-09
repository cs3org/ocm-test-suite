# Run: nu scripts/tests/compose/benchmark-runner-env.nu
const SUITE_PATH = path self
use ../../lib/compose/topology-two-party.nu [webapp-runner-diagnostics-env-lines]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def main [] {
    let off = (with-env {
        OCMTS_WEBAPP_LAUNCH_DIAGNOSTICS: ""
        OCMTS_WEBAPP_BROWSER_EXPERIMENT: ""
        OCMTS_WEBAPP_REQUEST_REPLAY: ""
    } { webapp-runner-diagnostics-env-lines "webapp-share" })
    let on = (with-env {
        OCMTS_WEBAPP_LAUNCH_DIAGNOSTICS: "1"
        OCMTS_WEBAPP_BROWSER_EXPERIMENT: "1"
        OCMTS_WEBAPP_REQUEST_REPLAY: "0"
    } { webapp-runner-diagnostics-env-lines "webapp-share" })
    let other = (with-env {
        OCMTS_WEBAPP_LAUNCH_DIAGNOSTICS: "1"
        OCMTS_WEBAPP_BROWSER_EXPERIMENT: "1"
    } { webapp-runner-diagnostics-env-lines "share-with" })
    let invalid = (try {
        with-env {OCMTS_WEBAPP_BROWSER_EXPERIMENT: "yes"} {
            webapp-runner-diagnostics-env-lines "webapp-share"
        }
        "accepted"
    } catch { "rejected" })
    run-suite "compose/benchmark-runner-env" $SUITE_PATH [
        (assert-eq $off [] "defaults do not alter runner environment")
        (assert-eq $on [
            "      - OCMTS_WEBAPP_LAUNCH_DIAGNOSTICS=1"
            "      - OCMTS_WEBAPP_BROWSER_EXPERIMENT=1"
            "      - OCMTS_WEBAPP_REQUEST_REPLAY=0"
            "      - DEBUG=cypress:server:proxy,cypress:driver,cypress:server:automation"
        ] "exact switches and DEBUG enter the runner")
        (assert-eq $other [] "non-webapp flows stay unchanged")
        (assert-eq $invalid "rejected" "invalid experiment value fails")
    ]
}
