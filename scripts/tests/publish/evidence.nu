# emit-evidence unit tests.
# Run: nu scripts/tests/publish/evidence.nu
# Returns exit 0 on all pass, exit 1 with details on any failure.

const SUITE_PATH = path self

use ../../lib/publish/evidence.nu [emit-evidence]
use ../../lib/publish/envelope.nu [collect-evidence]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def make-tmp [] {
    let t = ($nu.temp-dir | path join $"evidence-emit-test-(random uuid)")
    mkdir $t
    $t
}

def write-file [tmp: string, rel: string, content: string] {
    let abs = ($tmp | path join $rel)
    mkdir ($abs | path dirname)
    $content | save --force $abs
}

# Only meta/run.json and meta/result.v1.json present.
def test-emit-evidence-empty-cell [] {
    test-log "\n[test-emit-evidence-empty-cell]"
    let tmp = (make-tmp)
    write-file $tmp "meta/run.json" "{}"
    write-file $tmp "meta/result.v1.json" "{}"
    emit-evidence $tmp "cell-x" "run-x"
    let ev = (open ($tmp | path join "meta/evidence.v1.json"))
    let items = $ev.items
    let results = [
        (assert-eq ($items | length) 2 "empty cell: items length is 2")
        (assert-truthy ($items | all {|it| $it.envelope == "jsonl.v1"})
            "all items have envelope=jsonl.v1")
        (assert-truthy ($items | all {|it| $it.tab == "meta"})
            "all items have tab=meta")
        (assert-truthy ($items | all {|it| $it.sha256 =~ '^[0-9a-f]{64}$'})
            "all sha256 values are 64 lowercase hex chars")
    ]
    rm -rf $tmp
    $results
}

# Full cell fixture: 4 meta + 3 stack + 2 logs + 7 mitm = 16 items.
def test-emit-evidence-full-cell [] {
    test-log "\n[test-emit-evidence-full-cell]"
    let tmp = (make-tmp)
    # meta (4)
    write-file $tmp "meta/run.json" "{}"
    write-file $tmp "meta/result.v1.json" "{}"
    write-file $tmp "meta/cell.json" "{}"
    write-file $tmp "meta/images.v1.json" "{}"
    # stack (3)
    write-file $tmp "compose/manifest.v1.json" "{}"
    write-file $tmp "compose/inputs/base.yml" "version: \"3\"\n"
    write-file $tmp "compose/inputs/stack.env" "KEY=value\n"
    # logs (2)
    write-file $tmp "docker/logs/sender.log" "line1\nline2\nline3\n"
    write-file $tmp "docker/logs/cypress-run.log" "cypress output\nmore output\n"
    # mitm (7)
    write-file $tmp "mitm/flows/traffic.jsonl" "{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n"
    write-file $tmp "mitm/flows/session.json" "{}"
    write-file $tmp "mitm/startup.v1.json" "{}"
    write-file $tmp "mitm/connect-errors.v1.jsonl" "{\"e\":1}\n"
    write-file $tmp "mitm/peers.json" "{}"
    write-file $tmp "mitm/reports/01-01-traffic-overview.json" "{}"
    write-file $tmp "mitm/reports/03-03-ocm-details.tsv" "col1\tcol2\nval1\tval2\n"
    # excluded
    write-file $tmp "mitm/reports/01-01-traffic-overview.md" "# report"
    write-file $tmp "cypress/screenshots/x.png" "fake-png"
    write-file $tmp "cypress/videos/x.mp4" "fake-mp4"
    write-file $tmp "cypress/downloads/blob.bin" "fake-bin"
    write-file $tmp "meta/suite-manifest.v1.json" "{}"

    emit-evidence $tmp "cell-full" "run-full"
    let ev = (open ($tmp | path join "meta/evidence.v1.json"))
    let items = $ev.items
    let paths = ($items | get path)
    let envelopes = ($items | get envelope)
    let tabs = ($items | get tab)

    let cypress_run_item = ($items | where path == "docker/logs/cypress-run.log" | first)
    let sender_item = ($items | where path == "docker/logs/sender.log" | first)
    let base_yml_item = ($items | where path == "compose/inputs/base.yml" | first)
    let stack_env_item = ($items | where path == "compose/inputs/stack.env" | first)
    let tsv_item = ($items | where path == "mitm/reports/03-03-ocm-details.tsv" | first)
    let traffic_item = ($items | where path == "mitm/flows/traffic.jsonl" | first)
    let connect_item = ($items | where path == "mitm/connect-errors.v1.jsonl" | first)

    let valid_envelopes = ["text-log.v1" "jsonl.v1" "event-stream.v1" "stub.v1"]
    let valid_tabs = ["overview" "screenshots" "mitm" "logs" "meta" "stack"]

    let results = [
        (assert-eq ($items | length) 16 "full cell: items length is 16")
        (assert-list-not-contains $paths "meta/evidence.v1.json" "no self-reference in items")
        (assert-truthy (not ("markdown.v1" in $envelopes)) "no markdown.v1 envelope")
        (assert-truthy ($paths | all {|p| not ($p | str starts-with "cypress/")})
            "no cypress/ paths")
        (assert-list-not-contains $paths "meta/suite-manifest.v1.json"
            "suite-manifest excluded")
        (assert-truthy ($items | all {|it|
            let cols = ($it | columns)
            (("path" in $cols)
                and ("envelope" in $cols)
                and ("tab" in $cols)
                and ("size_bytes" in $cols)
                and ("sha256" in $cols)
                and ("logical_name" in $cols))
        }) "all items have required columns")
        (assert-truthy ($envelopes | all {|e| $e in $valid_envelopes})
            "all envelope values are valid")
        (assert-truthy ($tabs | all {|t| $t in $valid_tabs})
            "all tab values are valid")
        (assert-truthy ($items | all {|it| $it.sha256 =~ '^[0-9a-f]{64}$'})
            "all sha256 are 64 hex chars")
        (assert-truthy ($cypress_run_item.ansi == true)
            "cypress-run.log has ansi=true")
        (assert-truthy (not ("service" in ($cypress_run_item | columns)))
            "cypress-run.log has no service field")
        (assert-eq $sender_item.service "sender" "sender.log has service=sender")
        (assert-eq $sender_item.truncated false "sender.log has truncated=false")
        (assert-eq $base_yml_item.language "yaml" "base.yml has language=yaml")
        (assert-eq $stack_env_item.language "env" "stack.env has language=env")
        (assert-eq $tsv_item.language "tsv" "tsv report has language=tsv")
        (assert-eq $traffic_item.record_count 3 "traffic.jsonl has record_count=3")
        (assert-eq $connect_item.record_count 1 "connect-errors.v1.jsonl has record_count=1")
    ]
    rm -rf $tmp
    $results
}

# A log file < 256 bytes starting with "SKIPPED:" is emitted as stub.v1.
def test-emit-evidence-stub-sentinel [] {
    test-log "\n[test-emit-evidence-stub-sentinel]"
    let tmp = (make-tmp)
    write-file $tmp "meta/run.json" "{}"
    write-file $tmp "meta/result.v1.json" "{}"
    write-file $tmp "docker/logs/receiver.log" "SKIPPED: service not present in compose project\n"
    emit-evidence $tmp "cell-stub" "run-stub"
    let ev = (open ($tmp | path join "meta/evidence.v1.json"))
    let receiver_item = ($ev.items | where path == "docker/logs/receiver.log" | first)
    let results = [
        (assert-eq $receiver_item.envelope "stub.v1" "receiver.log is stub.v1")
        (assert-eq $receiver_item.tab "logs" "receiver.log tab is logs")
        (assert-eq $receiver_item.service "receiver" "receiver.log service is receiver")
        (assert-eq $receiver_item.stub_reason "service not present in compose project"
            "stub_reason is correct")
    ]
    rm -rf $tmp
    $results
}

# Top-level schema fields are populated correctly.
def test-emit-evidence-schema-fields [] {
    test-log "\n[test-emit-evidence-schema-fields]"
    let tmp = (make-tmp)
    write-file $tmp "meta/run.json" "{}"
    emit-evidence $tmp "cid" "rid"
    let ev = (open ($tmp | path join "meta/evidence.v1.json"))
    let results = [
        (assert-eq $ev.schema_version 1 "schema_version is 1")
        (assert-eq $ev.cell_id "cid" "cell_id matches argument")
        (assert-eq $ev.run_id "rid" "run_id matches argument")
        (assert-truthy (($ev.items | describe) =~ "^list|^table") "items is a list")
        (assert-truthy ($ev.captured_at =~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}Z$')
            "captured_at is RFC3339 nanosecond format")
    ]
    rm -rf $tmp
    $results
}

# Items are sorted by path ascending regardless of creation order.
def test-emit-evidence-sorted [] {
    test-log "\n[test-emit-evidence-sorted]"
    let tmp = (make-tmp)
    write-file $tmp "mitm/flows/traffic.jsonl" "{\"x\":1}\n"
    write-file $tmp "meta/run.json" "{}"
    write-file $tmp "docker/logs/sender.log" "line1\nline2\n"
    write-file $tmp "compose/manifest.v1.json" "{}"
    write-file $tmp "meta/cell.json" "{}"
    emit-evidence $tmp "cell-sort" "run-sort"
    let ev = (open ($tmp | path join "meta/evidence.v1.json"))
    let paths = ($ev.items | get path)
    let results = [
        (assert-eq $paths ($paths | sort) "items are sorted by path ascending")
    ]
    rm -rf $tmp
    $results
}

# sha256 of unchanged files is identical across two consecutive emits.
def test-emit-evidence-sha256-deterministic [] {
    test-log "\n[test-emit-evidence-sha256-deterministic]"
    let tmp = (make-tmp)
    write-file $tmp "meta/run.json" "{}\n"
    emit-evidence $tmp "cell-det" "run-det"
    let ev1 = (open ($tmp | path join "meta/evidence.v1.json"))
    emit-evidence $tmp "cell-det" "run-det"
    let ev2 = (open ($tmp | path join "meta/evidence.v1.json"))
    mut results = []
    for it1 in $ev1.items {
        let matching = ($ev2.items | where path == $it1.path)
        if not ($matching | is-empty) {
            let it2 = ($matching | first)
            $results = ($results | append (
                assert-eq $it1.sha256 $it2.sha256 $"sha256 deterministic for ($it1.path)"
            ))
        }
    }
    rm -rf $tmp
    $results
}

# Second emit must not include evidence.v1.json itself in items.
def test-emit-evidence-no-self-reference [] {
    test-log "\n[test-emit-evidence-no-self-reference]"
    let tmp = (make-tmp)
    write-file $tmp "meta/run.json" "{}"
    emit-evidence $tmp "cell-noself" "run-noself"
    emit-evidence $tmp "cell-noself" "run-noself"
    let ev = (open ($tmp | path join "meta/evidence.v1.json"))
    let paths = ($ev.items | get path)
    let results = [
        (assert-list-not-contains $paths "meta/evidence.v1.json" "no self-reference on second emit")
    ]
    rm -rf $tmp
    $results
}

# collect-evidence sees the three new mitm files and the new meta/compose paths.
def test-collect-evidence-counts-new-files [] {
    test-log "\n[test-collect-evidence-counts-new-files]"
    let tmp = (make-tmp)
    write-file $tmp "meta/run.json" "{}"
    write-file $tmp "meta/result.v1.json" "{}"
    write-file $tmp "meta/cell.json" "{}"
    write-file $tmp "meta/images.v1.json" "{}"
    write-file $tmp "compose/manifest.v1.json" "{}"
    write-file $tmp "compose/inputs/base.yml" "version: \"3\"\n"
    write-file $tmp "compose/inputs/stack.env" "KEY=value\n"
    write-file $tmp "docker/logs/sender.log" "line1\nline2\nline3\n"
    write-file $tmp "docker/logs/cypress-run.log" "cypress output\n"
    write-file $tmp "mitm/flows/traffic.jsonl" "{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n"
    write-file $tmp "mitm/flows/session.json" "{}"
    write-file $tmp "mitm/startup.v1.json" "{}"
    write-file $tmp "mitm/connect-errors.v1.jsonl" "{\"e\":1}\n"
    write-file $tmp "mitm/peers.json" "{}"
    write-file $tmp "mitm/reports/01-01-traffic-overview.json" "{}"
    write-file $tmp "mitm/reports/03-03-ocm-details.tsv" "col1\tcol2\n"
    write-file $tmp "mitm/reports/01-01-traffic-overview.md" "# report"
    write-file $tmp "cypress/screenshots/x.png" "fake"
    write-file $tmp "cypress/videos/x.mp4" "fake"
    write-file $tmp "cypress/downloads/blob.bin" "fake"
    write-file $tmp "meta/suite-manifest.v1.json" "{}"

    let ev = (collect-evidence $tmp)
    let all_paths = ($ev.rows | get path)
    let mitm_paths = ($ev.rows | where {|r| $r.path | str starts-with "mitm/"} | get path)

    let results = [
        (assert-list-contains $mitm_paths "mitm/peers.json"
            "mitm/peers.json present in rows")
        (assert-list-contains $mitm_paths "mitm/startup.v1.json"
            "mitm/startup.v1.json present in rows")
        (assert-list-contains $mitm_paths "mitm/connect-errors.v1.jsonl"
            "mitm/connect-errors.v1.jsonl present in rows")
        (assert-list-contains $all_paths "meta/cell.json"
            "meta/cell.json present in rows")
        (assert-list-contains $all_paths "meta/images.v1.json"
            "meta/images.v1.json present in rows")
        (assert-list-contains $all_paths "compose/manifest.v1.json"
            "compose/manifest.v1.json present in rows")
        (assert-truthy ($ev.counts.total >= 13) "total count >= 13")
    ]
    rm -rf $tmp
    $results
}

# items[] only contains entries whose path exists on disk at emit time.
# Verifies the existence filter: paths that collectors would normally emit
# but that are absent from the artifact dir are excluded from items[].
def test-emit-evidence-exists-filter [] {
    test-log "\n[test-emit-evidence-exists-filter]"
    let tmp = (make-tmp)
    # Write only two of the fixed mitm paths; leave session.json and peers.json absent.
    write-file $tmp "meta/run.json" "{}"
    write-file $tmp "mitm/flows/traffic.jsonl" "{\"a\":1}\n"
    # mitm/flows/session.json is intentionally NOT written.
    # mitm/peers.json is intentionally NOT written.
    emit-evidence $tmp "cell-filter" "run-filter"
    let ev = (open ($tmp | path join "meta/evidence.v1.json"))
    let paths = ($ev.items | get path)
    let results = [
        (assert-list-contains $paths "meta/run.json"
            "meta/run.json present when it exists")
        (assert-list-contains $paths "mitm/flows/traffic.jsonl"
            "mitm/flows/traffic.jsonl present when it exists")
        (assert-list-not-contains $paths "mitm/flows/session.json"
            "mitm/flows/session.json absent when file does not exist")
        (assert-list-not-contains $paths "mitm/peers.json"
            "mitm/peers.json absent when file does not exist")
        (assert-truthy ($ev.items | all {|it|
            ($tmp | path join $it.path) | path exists
        }) "every item in items[] points to a file that physically exists")
    ]
    rm -rf $tmp
    $results
}

# mitm/conf/** is excluded from items[] (contains CA private key).
def test-emit-evidence-excludes-mitm-conf [] {
    test-log "\n[test-emit-evidence-excludes-mitm-conf]"
    let tmp = (make-tmp)
    write-file $tmp "meta/run.json" "{}"
    write-file $tmp "meta/result.v1.json" "{}"
    write-file $tmp "mitm/conf/config.yaml" "addons:\n  - jsonl.py\n"
    write-file $tmp "mitm/conf/mitmproxy-ca.pem" "-----BEGIN CERTIFICATE-----\ndummy\n-----END CERTIFICATE-----\n"
    write-file $tmp "mitm/conf/mitmproxy-dhparam.pem" "-----BEGIN DH PARAMETERS-----\ndummy\n-----END DH PARAMETERS-----\n"
    write-file $tmp "mitm/conf/upstream-ca-bundle.pem" "-----BEGIN CERTIFICATE-----\ndummy\n-----END CERTIFICATE-----\n"
    emit-evidence $tmp "test-cell" "test-run"
    let ev = (open ($tmp | path join "meta/evidence.v1.json"))
    let items = $ev.items
    let paths = ($items | get path)
    let results = [
        (assert-truthy (not ($paths | any {|p| $p | str starts-with "mitm/conf/"}))
            "mitm/conf/* must be excluded from evidence.v1.json (contains CA private key)")
        (assert-eq ($items | length) 2
            "only the 2 meta files are in items when mitm/conf/* present")
    ]
    rm -rf $tmp
    $results
}

def main [] {
    test-log "=== publish/evidence Tests ==="
    let results = (
        (test-emit-evidence-empty-cell)
        | append (test-emit-evidence-full-cell)
        | append (test-emit-evidence-stub-sentinel)
        | append (test-emit-evidence-schema-fields)
        | append (test-emit-evidence-sorted)
        | append (test-emit-evidence-sha256-deterministic)
        | append (test-emit-evidence-no-self-reference)
        | append (test-emit-evidence-excludes-mitm-conf)
        | append (test-emit-evidence-exists-filter)
        | append (test-collect-evidence-counts-new-files)
    ) | flatten
    run-suite "publish/evidence" $SUITE_PATH $results
}
