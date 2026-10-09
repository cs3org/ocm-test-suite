# Readiness engine tests. Canned provider, no docker.
# Run: nu scripts/tests/services/readiness.nu

const SUITE_PATH = path self

use ../../lib/run/readiness-evidence.nu [readiness-evidence-path]
use ../../lib/services/readiness.nu [sample-readiness wait-readiness]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [with-tmp-dir]
use ../../lib/tests/runner.nu [run-suite]

def caught-msg [block: closure] {
    try { do $block; "" } catch {|e| $e.msg}
}

def ctx [art: string, id: string, stack: string] {
    {
        artifacts_base: $art,
        execution_id: $id,
        stack_id: $stack,
        cell: {},
    }
}

def write-script [path: string, steps: list] {
    {idx: 0, steps: $steps} | to json | save --force $path
}

def scripted-sample [path: string] {
    {|ctx, files, roles|
        let raw = (open $path)
        let idx = ($raw.idx? | default 0)
        let steps = $raw.steps
        let step = ($steps | get $idx)
        let next = if ($idx + 1) < ($steps | length) { $idx + 1 } else { $idx }
        {idx: $next, steps: $steps} | to json | save --force $path
        $step
    }
}

def canned [
    name: string,
    roles: list<string>,
    interval: duration,
    sample: closure,
] {
    {
        name: $name,
        label: "Canned registry",
        stability_interval: $interval,
        reason_codes: ["compose-query" "samples-disagree" "wrong-bucket"],
        role_names: ["sender" "receiver"],
        parties: {|cell| $roles},
        sample: $sample,
    }
}

def identity [marker: string] {
    {
        roles: ["sender"],
        bindings: [{role: "sender", ips: ["10.0.0.1"]}],
        parties: [{
            role: "sender",
            processes: 12,
            connections: 12,
            bucket: "reva_registry",
            ttl_seconds: 30,
            hostname_ok: true,
            image_id: $marker,
        }],
    }
}

def ok-step [marker: string, watchers: int] {
    {
        ok: true,
        reasons: [],
        identity: (identity $marker),
        parties: [{role: "sender", watchers: $watchers, processes: 12}],
    }
}

def phase-of [art: string, provider: string, phase: string] {
    let store = (open (readiness-evidence-path $art))
    let tree = ($store.providers | get $provider)
    $tree.phases | get $phase
}

def test-stable-samples-commit-passed [] {
    test-log "\n[test-stable-samples-commit-passed]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let script = ($tmp | path join "script.json")
        write-script $script [(ok-step "img-a" 12) (ok-step "img-a" 99)]
        let provider = (canned "cernbox-registry" ["sender"] 0sec (scripted-sample $script))
        let run_ctx = (ctx $art "exec-1" "proj")
        let sampled = (sample-readiness $run_ctx ["compose.yml"] $provider)
        write-script $script [(ok-step "img-a" 12) (ok-step "img-a" 99)]
        let body = (wait-readiness $run_ctx ["compose.yml"] $provider --timeout 10sec --phase "before-cypress")
        let stored = (phase-of $art "cernbox-registry" "before-cypress")
        let store = (open (readiness-evidence-path $art))
        [
            (assert-eq $sampled.ok true "sample-readiness returns the canned sample")
            (assert-eq $body.status "passed" "two equal samples return a passed body")
            (assert-eq ($body.parties | first | get watchers) 99
                "the passed body keeps the later sample's watchers")
            (assert-eq $stored.status "passed" "the store records the passed phase")
            (assert-eq $store.execution_id "exec-1" "the store stamps the caller execution id")
        ]
    }
}

def test-middle-failure-does-not-block-pass [] {
    test-log "\n[test-middle-failure-does-not-block-pass]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let script = ($tmp | path join "script.json")
        let bad = {ok: false, reasons: ["sender:restarts"], identity: {}, parties: []}
        write-script $script [(ok-step "img-a" 12) $bad (ok-step "img-a" 12) (ok-step "img-a" 40)]
        let provider = (canned "cernbox-registry" ["sender"] 0sec (scripted-sample $script))
        let body = (wait-readiness (ctx $art "exec-2" "proj") ["compose.yml"] $provider --timeout 20sec --phase "after-cypress")
        [
            (assert-eq $body.status "passed"
                "a not-ok sample between equal identities still passes")
            (assert-eq ($body.parties | first | get watchers) 40
                "the passing sample supplies the receipt watchers")
        ]
    }
}

def test-identity-disagreement-times-out [] {
    test-log "\n[test-identity-disagreement-times-out]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let script = ($tmp | path join "script.json")
        write-script $script [
            (ok-step "img-a" 12)
            (ok-step "img-b" 12)
            (ok-step "img-a" 12)
            (ok-step "img-b" 12)
        ]
        let provider = (canned "cernbox-registry" ["sender"] 1hr (scripted-sample $script))
        let msg = (caught-msg {||
            wait-readiness (ctx $art "exec-3" "proj") ["compose.yml"] $provider --timeout 5sec --phase "before-cypress"
        })
        let phase = (phase-of $art "cernbox-registry" "before-cypress")
        [
            (assert-eq $msg "Canned registry readiness failed: samples-disagree"
                "identity disagreement times out as samples-disagree")
            (assert-eq $phase.status "failed" "timeout records a failed phase")
            (assert-eq $phase.reasons ["samples-disagree"]
                "the failed phase keeps the last reasons")
        ]
    }
}

def test-young-match-clears-disagreement [] {
    test-log "\n[test-young-match-clears-disagreement]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let script = ($tmp | path join "script.json")
        write-script $script [
            (ok-step "img-a" 12)
            (ok-step "img-b" 12)
            (ok-step "img-b" 12)
            (ok-step "img-b" 12)
        ]
        let provider = (canned "cernbox-registry" ["sender"] 1hr (scripted-sample $script))
        let msg = (caught-msg {||
            wait-readiness (ctx $art "exec-young" "proj") ["compose.yml"] $provider --timeout 10sec --phase "before-cypress"
        })
        let phase = (phase-of $art "cernbox-registry" "before-cypress")
        let idx = (open $script).idx
        [
            (assert-eq $idx 3
                "the wait consumes the disagree sample and the young match")
            (assert-eq $msg "Canned registry readiness failed: timeout"
                "a young match clears samples-disagree before timeout")
            (assert-eq $phase.status "failed" "the young match still times out")
            (assert-eq $phase.reasons ["timeout"]
                "timeout reasons follow the latest matching sample")
        ]
    }
}

def test-compose-query-and-masked-write [] {
    test-log "\n[test-compose-query-and-masked-write]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let provider = (canned "cernbox-registry" ["sender"] 0sec {|ctx, files, roles|
            {ok: true, reasons: [], identity: {}, parties: []}
        })
        let query = (caught-msg {||
            wait-readiness (ctx $art "exec-4" "") ["compose.yml"] $provider --timeout 5sec --phase "platform-ready"
        })
        let phase = (phase-of $art "cernbox-registry" "platform-ready")
        rm -rf ($art | path join "meta")
        "block" | save --force ($art | path join "meta")
        let masked = (caught-msg {||
            wait-readiness (ctx $art "exec-4" "") ["compose.yml"] $provider --timeout 5sec --phase "platform-ready"
        })
        [
            (assert-eq $query "Canned registry readiness failed: compose-query"
                "unusable compose args fail with compose-query")
            (assert-eq $phase.status "failed" "compose-query records a failed phase")
            (assert-eq $phase.reasons ["compose-query"]
                "the failed phase records compose-query")
            (assert-eq $masked "Canned registry readiness failed: compose-query"
                "a store failure does not mask the readiness reasons")
        ]
    }
}

def test-undeclared-codes-and-roles-collapse [] {
    test-log "\n[test-undeclared-codes-and-roles-collapse]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let provider = {
            name: "other-registry",
            label: "Canned registry",
            stability_interval: 0sec,
            reason_codes: ["samples-disagree"],
            role_names: ["left"],
            parties: {|cell| ["left"]},
            sample: {|ctx, files, roles|
                {
                    ok: false,
                    reasons: ["compose-query" "left:restarts" "sender:restarts" "js-off"],
                    identity: {},
                    parties: [],
                }
            },
        }
        let msg = (caught-msg {||
            wait-readiness (ctx $art "exec-6" "proj") ["compose.yml"] $provider --timeout 2sec --phase "before-cypress"
        })
        let phase = (phase-of $art "other-registry" "before-cypress")
        [
            (assert-eq $msg "Canned registry readiness failed: readiness-check, left:restarts"
                "undeclared codes and roles collapse to readiness-check")
            (assert-eq $phase.reasons ["readiness-check" "left:restarts"]
                "the failed phase keeps only declared role prefixes")
            (assert-truthy (not ($msg | str contains "compose-query"))
                "compose-query is absent unless the provider lists it")
            (assert-truthy (not ($msg | str contains "js-off"))
                "js-off is absent unless the provider lists it")
            (assert-truthy (not ($msg | str contains "sender:"))
                "sender is absent unless the provider lists that role")
        ]
    }
}

def test-empty-parties-write-nothing [] {
    test-log "\n[test-empty-parties-write-nothing]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let provider = (canned "cernbox-registry" [] 0sec {|ctx, files, roles|
            error make {msg: "sample must not run"}
        })
        let got = (wait-readiness (ctx $art "exec-5" "proj") ["compose.yml"] $provider --phase "platform-ready")
        [
            (assert-eq $got.schema_version 1 "an empty party list returns schema 1")
            (assert-eq ($got.providers | columns | is-empty) true
                "an empty party list returns no providers")
            (assert-truthy (not ((readiness-evidence-path $art) | path exists))
                "an empty party list writes nothing")
        ]
    }
}

def main [] {
    test-log "=== services/readiness tests ==="
    let results = (
        (test-stable-samples-commit-passed)
        | append (test-middle-failure-does-not-block-pass)
        | append (test-identity-disagreement-times-out)
        | append (test-young-match-clears-disagreement)
        | append (test-compose-query-and-masked-write)
        | append (test-undeclared-codes-and-roles-collapse)
        | append (test-empty-parties-write-nothing)
    ) | flatten
    run-suite "services/readiness" $SUITE_PATH $results
}
