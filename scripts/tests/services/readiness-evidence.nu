# Readiness evidence store tests. Tmp-dir fixtures, no docker.
# Run: nu scripts/tests/services/readiness-evidence.nu

const SUITE_PATH = path self

use ../../lib/run/readiness-evidence.nu [
    readiness-evidence-commit
    readiness-evidence-load
    readiness-evidence-path
    readiness-evidence-reset
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [with-tmp-dir]
use ../../lib/tests/runner.nu [run-suite]

def caught-msg [block: closure] {
    try { do $block; "" } catch {|e| $e.msg}
}

def passed-body [at: string] {
    {
        status: "passed",
        captured_at: $at,
        parties: [{role: "sender", processes: 12}],
    }
}

def failed-body [] {
    {
        status: "failed",
        captured_at: "2026-10-07T04:01:02Z",
        reasons: ["sender:watcher-count"],
    }
}

def test-reset-replaces-phases-and-id [] {
    test-log "\n[test-reset-replaces-phases-and-id]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        readiness-evidence-commit $art "old-id" "cernbox-registry" "before-cypress" (passed-body "t0")
        let reset = (readiness-evidence-reset $art "new-id")
        let loaded = (readiness-evidence-load $art)
        let path = (readiness-evidence-path $art)
        [
            (assert-eq $reset.schema_version 1 "reset schema_version is 1")
            (assert-eq $reset.execution_id "new-id" "reset stamps the caller execution id")
            (assert-eq ($reset.providers | columns | is-empty) true
                "reset drops every provider phase")
            (assert-truthy (not ($reset.run_started_at | is-empty))
                "reset records run_started_at")
            (assert-eq $loaded $reset "load returns the reset store")
            (assert-eq ($path | path basename) "readiness.v1.json"
                "store file is meta/readiness.v1.json")
            (assert-eq ($path | path dirname | path basename) "meta"
                "store file lives under meta")
        ]
    }
}

def test-commit-preserves-other-providers [] {
    test-log "\n[test-commit-preserves-other-providers]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let started = (readiness-evidence-reset $art "id-1").run_started_at
        readiness-evidence-commit $art "id-1" "prov-a" "platform-ready" (passed-body "t1")
        readiness-evidence-commit $art "id-2" "prov-b" "before-cypress" (failed-body)
        readiness-evidence-commit $art "id-3" "prov-a" "after-cypress" (passed-body "t3")
        let store = (open (readiness-evidence-path $art))
        let a = ($store.providers | get "prov-a" | get phases)
        let b = ($store.providers | get "prov-b" | get phases | get "before-cypress")
        [
            (assert-eq $store.execution_id "id-3"
                "every commit re-stamps the caller execution id")
            (assert-eq $store.run_started_at $started
                "commit keeps the attempt run_started_at")
            (assert-eq ($a | columns | sort) ["after-cypress" "platform-ready"]
                "a provider keeps its other phases")
            (assert-eq $b.status "failed" "failed phase status is failed")
            (assert-eq $b.captured_at "2026-10-07T04:01:02Z"
                "failed phase keeps captured_at")
            (assert-eq $b.reasons ["sender:watcher-count"]
                "failed phase records reason codes")
            (assert-eq ($b.parties? | default null) null
                "failed phase has no parties")
        ]
    }
}

def test-load-self-heals-bad-files [] {
    test-log "\n[test-load-self-heals-bad-files]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir ($art | path join "meta")
        let path = (readiness-evidence-path $art)
        let missing = (readiness-evidence-load $art)
        let missing_left_absent = (not ($path | path exists))
        "not-json" | save --force $path
        let garbage = (readiness-evidence-load $art)
        {schema_version: 99, execution_id: "stale", providers: {keep: {}}}
            | to json
            | save --force $path
        let wrong = (readiness-evidence-load $art)
        "{}" | save --force $path
        let bare = (readiness-evidence-load $art)
        readiness-evidence-commit $art "fresh-id" "cernbox-registry" "platform-ready" (passed-body "t")
        let healed = (open $path)
        [
            (assert-eq $missing.execution_id "" "a missing file loads as an empty store")
            (assert-eq ($missing.providers | columns | is-empty) true
                "a missing file has no providers")
            (assert-eq $missing_left_absent true
                "load does not create a missing file")
            (assert-eq $garbage.schema_version 1 "unparsable input loads as schema 1")
            (assert-eq $garbage.execution_id "" "unparsable input drops the execution id")
            (assert-eq $wrong.execution_id "" "schema 99 loads as an empty store")
            (assert-eq ($wrong.providers | columns | is-empty) true
                "schema 99 drops its provider tree")
            (assert-eq $bare.execution_id "" "a record without schema_version loads empty")
            (assert-eq $healed.schema_version 1 "the next commit rewrites a bad file")
            (assert-eq $healed.execution_id "fresh-id"
                "the rewrite stamps the caller execution id")
        ]
    }
}

def load-via-child [art: string] {
    let lib = (
        $SUITE_PATH | path dirname | path dirname | path dirname
        | path join "lib/run/readiness-evidence.nu"
    )
    let code = (
        [
            "use "
            ($lib | to nuon)
            " [readiness-evidence-load]; let s = (readiness-evidence-load "
            ($art | to nuon)
            "); print $s.schema_version"
        ] | str join ""
    )
    ^nu -c $code | complete
}

def warning-lines [text: string] {
    $text | lines | where {|line| $line | str starts-with "WARNING:"}
}

def test-load-self-heal-warning [] {
    test-log "\n[test-load-self-heal-warning]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir ($art | path join "meta")
        let path = (readiness-evidence-path $art)
        "SECRET-BODY-not-json" | save --force $path
        let bad = (load-via-child $art)
        rm $path
        let missing = (load-via-child $art)
        let bad_warn = (warning-lines $bad.stdout)
        let missing_warn = (warning-lines $missing.stdout)
        [
            (assert-eq $bad.exit_code 0 "bad-file load child exits 0")
            (assert-eq $bad_warn ["WARNING: readiness evidence load failed"]
                "unusable store warns with a fixed line")
            (assert-truthy (not ($bad.stdout | str contains "SECRET-BODY"))
                "the load warning does not include file text")
            (assert-truthy (not ($bad.stderr | str contains "SECRET-BODY"))
                "stderr does not include the unusable file text")
            (assert-eq $missing_warn [] "a missing file does not warn")
            (assert-string-contains $missing.stdout "1"
                "a missing file still loads schema 1")
        ]
    }
}

def test-blank-artifacts-base-rejected [] {
    test-log "\n[test-blank-artifacts-base-rejected]"
    let cwd_receipt = ("meta/readiness.v1.json" | path expand)
    let rel_base = "ocmts-readiness-blank-reject"
    let rel_receipt = ($rel_base | path join "meta" "readiness.v1.json" | path expand)
    let cwd_before = ($cwd_receipt | path exists)
    let rel_before = ($rel_receipt | path exists)
    let want = "artifacts_base must be a non-blank absolute path"
    let path_msg = (caught-msg {|| readiness-evidence-path "" })
    let load_msg = (caught-msg {|| readiness-evidence-load "" })
    let reset_msg = (caught-msg {|| readiness-evidence-reset "   " "exec" })
    let commit_msg = (caught-msg {||
        readiness-evidence-commit "" "exec" "prov" "before-cypress" (failed-body)
    })
    let rel_msg = (caught-msg {||
        readiness-evidence-commit $rel_base "exec" "prov" "before-cypress" (failed-body)
    })
    [
        (assert-eq $path_msg $want "path rejects a blank artifacts_base")
        (assert-eq $load_msg $want "load rejects a blank artifacts_base")
        (assert-eq $reset_msg $want "reset rejects a whitespace artifacts_base")
        (assert-eq $commit_msg $want "commit rejects a blank artifacts_base")
        (assert-eq $rel_msg $want "a relative artifacts_base is rejected")
        (assert-eq ($cwd_receipt | path exists) $cwd_before
            "blank input does not create a relative receipt")
        (assert-eq ($rel_receipt | path exists) $rel_before
            "a relative artifacts_base does not create a receipt")
    ]
}

def test-commit-write-failure [] {
    test-log "\n[test-commit-write-failure]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        "block" | save --force ($art | path join "meta")
        let msg = (caught-msg {||
            readiness-evidence-commit $art "id" "cernbox-registry" "before-cypress" (failed-body)
        })
        [
            (assert-string-contains $msg "evidence-write"
                "a blocked meta path raises evidence-write")
        ]
    }
}

def main [] {
    test-log "=== services/readiness-evidence tests ==="
    let results = (
        (test-reset-replaces-phases-and-id)
        | append (test-commit-preserves-other-providers)
        | append (test-load-self-heals-bad-files)
        | append (test-load-self-heal-warning)
        | append (test-blank-artifacts-base-rejected)
        | append (test-commit-write-failure)
    ) | flatten
    run-suite "services/readiness-evidence" $SUITE_PATH $results
}
