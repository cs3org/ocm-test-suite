# Evidence enrichment tests for publish-envelope helpers.
# Run: nu scripts/tests/publish/envelope.nu
# Returns exit 0 on all pass, exit 1 with details on any failure.

const SUITE_PATH = path self

use ../../lib/publish/envelope.nu [
    emit-publish-envelope
    path-to-evidence-id
    parse-screenshot-stem
    parse-video-stem
    enrich-ev-row
    sort-evidence-rows
]
use ../../lib/tests/fixtures.nu [with-tmp-dir]
use ../../lib/site/copy.nu [copy-allowlisted-artifacts]
use ../../lib/services/postrun-artifacts.nu [normalize-cypress-video]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# --- path-to-evidence-id ---

def test-path-to-evidence-id [] {
    test-log "\n[test-path-to-evidence-id]"
    [
        (assert-eq
            (path-to-evidence-id "cypress/screenshots/login__opencloud-v6--001--single--authenticated.png")
            "cypress--screenshots--login__opencloud-v6--001--single--authenticated"
            "screenshot path -> slug")
        (assert-eq
            (path-to-evidence-id "cypress/videos/login__opencloud-v6--run.mp4")
            "cypress--videos--login__opencloud-v6--run"
            "video path -> slug")
        (assert-eq
            (path-to-evidence-id "meta/run.json")
            "meta--run"
            "metadata path -> slug")
        (assert-eq
            (path-to-evidence-id "docker/logs/sender.log")
            "docker--logs--sender"
            "log path -> slug")
        (assert-eq
            (path-to-evidence-id "mitm/flows/traffic.jsonl")
            "mitm--flows--traffic"
            "mitm flow path -> slug")
        (assert-eq
            (path-to-evidence-id "mitm/redaction-report.json")
            "mitm--redaction-report"
            "mitm report path -> slug, stem with hyphen preserved")
    ]
}

# --- parse-screenshot-stem ---

def test-parse-screenshot-stem [] {
    test-log "\n[test-parse-screenshot-stem]"
    let simple = (parse-screenshot-stem "login__opencloud-v6--001--single--login-page-ready")
    let two_party = (parse-screenshot-stem "share-with__nextcloud-v34__nextcloud-v34--004--receiver--share-visible")
    let multi_checkpoint = (parse-screenshot-stem "contact-token__nc__nc--007--sender--share-saved")
    mut results = [
        (assert-not-null $simple "simple cell_id matches convention")
        (assert-not-null $two_party "two-party cell_id matches convention")
        (assert-not-null $multi_checkpoint "contact-token cell matches convention")
    ]
    if $simple != null {
        $results = ($results | append [
            (assert-eq $simple.cell_id "login__opencloud-v6" "cell_id extracted")
            (assert-eq $simple.order 1 "order 001 parsed as int 1")
            (assert-eq $simple.actor "single" "actor single extracted")
            (assert-eq $simple.checkpoint "login-page-ready" "checkpoint with hyphens extracted")
        ])
    }
    if $two_party != null {
        $results = ($results | append [
            (assert-eq $two_party.cell_id "share-with__nextcloud-v34__nextcloud-v34" "two-party cell_id with double-underscore pairs")
            (assert-eq $two_party.order 4 "order 004 parsed as int 4")
            (assert-eq $two_party.actor "receiver" "receiver actor extracted")
            (assert-eq $two_party.checkpoint "share-visible" "checkpoint extracted")
        ])
    }
    $results = ($results | append [
        (assert-null (parse-screenshot-stem "some-test-failure-screenshot") "bare name without convention returns null")
        (assert-null (parse-screenshot-stem "foo--999--unknown-actor--bar") "invalid actor name returns null")
        (assert-null (parse-screenshot-stem "foo--abc--single--bar") "non-digit order returns null")
        (assert-null (parse-screenshot-stem "foo--12--single--bar") "two-digit order returns null")
        (assert-null (parse-screenshot-stem "") "empty stem returns null")
    ])
    $results
}

# --- parse-video-stem ---

def test-parse-video-stem [] {
    test-log "\n[test-parse-video-stem]"
    let ok = (parse-video-stem "login__opencloud-v6--run")
    let two_party = (parse-video-stem "share-with__nextcloud-v34__nextcloud-v34--run")
    mut results = [
        (assert-not-null $ok "convention video stem matches")
        (assert-not-null $two_party "two-party convention video matches")
    ]
    if $ok != null {
        $results = ($results | append [
            (assert-eq $ok.cell_id "login__opencloud-v6" "cell_id extracted from video stem")
        ])
    }
    if $two_party != null {
        $results = ($results | append [
            (assert-eq $two_party.cell_id "share-with__nextcloud-v34__nextcloud-v34" "two-party cell_id from video stem")
        ])
    }
    $results = ($results | append [
        (assert-null (parse-video-stem "e2e-login-steps.ts") "legacy spec video stem returns null")
        (assert-null (parse-video-stem "steps.ts") "bare spec name returns null")
        (assert-null (parse-video-stem "") "empty stem returns null")
        (assert-null (parse-video-stem "login__opencloud-v6--run--extra") "extra suffix after --run returns null")
    ])
    $results
}

# --- enrich-ev-row ---

def test-enrich-ev-row [] {
    test-log "\n[test-enrich-ev-row]"
    let fallback_cell = "login__opencloud-v6"

    let ss_proof = {
        kind: "screenshot"
        scope: "cypress"
        logical_name: "login__opencloud-v6--001--single--authenticated.png"
        path: "cypress/screenshots/login__opencloud-v6--001--single--authenticated.png"
        availability: "artifact"
    }
    let ss_failure = {
        kind: "screenshot"
        scope: "cypress"
        logical_name: "Some test failed (1).png"
        path: "cypress/screenshots/e2e/login/steps.ts/Some test failed (1).png"
        availability: "artifact"
    }
    let vid_run = {
        kind: "video"
        scope: "cypress"
        logical_name: "login__opencloud-v6--run.mp4"
        path: "cypress/videos/login__opencloud-v6--run.mp4"
        availability: "artifact"
    }
    let vid_legacy = {
        kind: "video"
        scope: "cypress"
        logical_name: "steps.ts.mp4"
        path: "cypress/videos/steps.ts.mp4"
        availability: "artifact"
    }
    let log_row = {
        kind: "log"
        scope: "docker"
        logical_name: "sender.log"
        path: "docker/logs/sender.log"
        availability: "artifact"
    }
    let meta_row = {
        kind: "metadata"
        scope: "meta"
        logical_name: "run.json"
        path: "meta/run.json"
        availability: "artifact"
    }

    let r_proof = (enrich-ev-row $ss_proof $fallback_cell)
    let r_fail = (enrich-ev-row $ss_failure $fallback_cell)
    let r_vid = (enrich-ev-row $vid_run $fallback_cell)
    let r_vleg = (enrich-ev-row $vid_legacy $fallback_cell)
    let r_log = (enrich-ev-row $log_row $fallback_cell)
    let r_meta = (enrich-ev-row $meta_row $fallback_cell)

    let cap_class_log = ($r_log | get --optional capture_class)
    let cap_class_meta = ($r_meta | get --optional capture_class)
    [
        # proof screenshot: full enrichment
        (assert-eq $r_proof.capture_class "proof" "proof screenshot gets capture_class=proof")
        (assert-eq $r_proof.order 1 "proof screenshot: order parsed from NNN")
        (assert-eq $r_proof.actor "single" "proof screenshot: actor parsed")
        (assert-eq $r_proof.checkpoint "authenticated" "proof screenshot: checkpoint parsed")
        (assert-eq $r_proof.cell_id "login__opencloud-v6" "proof screenshot: cell_id from filename")
        (assert-not-null $r_proof.evidence_id "proof screenshot: evidence_id present")
        # existing fields preserved
        (assert-eq $r_proof.kind "screenshot" "proof screenshot: kind preserved")
        (assert-eq $r_proof.availability "artifact" "proof screenshot: availability preserved")

        # failure-auto screenshot: minimal enrichment with fallback cell_id
        (assert-eq $r_fail.capture_class "failure-auto" "non-convention screenshot gets capture_class=failure-auto")
        (assert-eq $r_fail.cell_id $fallback_cell "failure-auto: uses manifest cell_id fallback")
        (assert-not-null $r_fail.evidence_id "failure-auto: evidence_id present")

        # run video: cell_id parsed from filename
        (assert-eq $r_vid.capture_class "run" "convention video gets capture_class=run")
        (assert-eq $r_vid.cell_id "login__opencloud-v6" "convention video: cell_id from filename")
        (assert-not-null $r_vid.evidence_id "convention video: evidence_id present")

        # legacy video: fallback cell_id
        (assert-eq $r_vleg.capture_class "legacy" "legacy video gets capture_class=legacy")
        (assert-eq $r_vleg.cell_id $fallback_cell "legacy video: uses manifest cell_id fallback")

        # log and metadata: evidence_id only, no capture_class
        (assert-not-null $r_log.evidence_id "log row: evidence_id present")
        (assert-null $cap_class_log "log row: no capture_class field")
        (assert-not-null $r_meta.evidence_id "meta row: evidence_id present")
        (assert-null $cap_class_meta "meta row: no capture_class field")

        # evidence_id values are non-empty strings
        (assert-truthy (not ($r_proof.evidence_id | is-empty)) "proof screenshot: evidence_id non-empty")
        (assert-truthy (not ($r_fail.evidence_id | is-empty)) "failure-auto: evidence_id non-empty")
    ]
}

# --- download filtering (site-ingest path filter via copy-allowlisted-artifacts) ---
# Tests that downloads are excluded from the site copy without needing Docker or live runs.

def test-download-filtering [] {
    test-log "\n[test-download-filtering]"
    let tmp = (^mktemp -d | str trim)
    let src = ($tmp | path join "src")
    let dst = ($tmp | path join "dst")
    mkdir $src
    mkdir $dst

    # Create representative files in each evidence class
    mkdir ($src | path join "meta")
    mkdir ($src | path join "docker" "logs")
    mkdir ($src | path join "cypress" "screenshots")
    mkdir ($src | path join "cypress" "videos")
    mkdir ($src | path join "cypress" "downloads")
    mkdir ($src | path join "mitm" "reports")

    "run" | save --force ($src | path join "meta" "run.json")
    "log" | save --force ($src | path join "docker" "logs" "sender.log")
    "ss" | save --force ($src | path join "cypress" "screenshots" "shot.png")
    "vid" | save --force ($src | path join "cypress" "videos" "run.mp4")
    "dl" | save --force ($src | path join "cypress" "downloads" "file.txt")
    "rpt" | save --force ($src | path join "mitm" "reports" "01-01-overview.md")

    let count = (copy-allowlisted-artifacts $src $dst)

    let has_meta = (($dst | path join "meta" "run.json") | path exists)
    let has_log = (($dst | path join "docker" "logs" "sender.log") | path exists)
    let has_ss = (($dst | path join "cypress" "screenshots" "shot.png") | path exists)
    let has_vid = (($dst | path join "cypress" "videos" "run.mp4") | path exists)
    let has_dl = (($dst | path join "cypress" "downloads" "file.txt") | path exists)
    let has_rpt = (($dst | path join "mitm" "reports" "01-01-overview.md") | path exists)

    try { rm -rf $tmp } catch {}
    [
        (assert-truthy $has_meta "meta files copied to site")
        (assert-truthy $has_log "docker logs copied to site")
        (assert-truthy $has_ss "screenshots copied to site")
        (assert-truthy $has_vid "videos copied to site")
        (assert-truthy (not $has_dl) "downloads NOT copied to site")
        (assert-truthy $has_rpt "mitm reports copied to site")
        (assert-eq $count 5 "exactly 5 files copied (downloads excluded)")
    ]
}

# --- normalize-cypress-video ---
# Tests filesystem behavior: move, idempotency, empty cell_id, no videos dir.

def test-normalize-cypress-video [] {
    test-log "\n[test-normalize-cypress-video]"
    let cell_id = "login__opencloud-v6"

    # Case 1: legacy video moved to normalized name; source removed.
    let tmp1 = (^mktemp -d | str trim)
    let vids1 = ($tmp1 | path join "cypress" "videos")
    mkdir $vids1
    let legacy1 = ($vids1 | path join "e2e-steps.ts.mp4")
    let target1 = ($vids1 | path join $"($cell_id)--run.mp4")
    "video-content" | save --force $legacy1
    normalize-cypress-video $tmp1 $cell_id
    let has_target = ($target1 | path exists)
    let src_gone = (not ($legacy1 | path exists))

    # Case 2: target already present; extra mp4 is cleaned up, target content unchanged.
    let legacy2 = ($vids1 | path join "other-spec.mp4")
    "other-video" | save --force $legacy2
    normalize-cypress-video $tmp1 $cell_id
    let target_still = ($target1 | path exists)
    let legacy2_removed = (not ($legacy2 | path exists))
    let target_content = (open --raw $target1 | str trim)

    # Case 3: empty cell_id - no target created, no error.
    let tmp2 = (^mktemp -d | str trim)
    let vids2 = ($tmp2 | path join "cypress" "videos")
    mkdir $vids2
    "v" | save --force ($vids2 | path join "spec.mp4")
    normalize-cypress-video $tmp2 ""
    let no_target_empty_id = ((glob $"($vids2)/*--run.mp4") | is-empty)

    # Case 4: no videos dir - no error thrown (reaches this line means safe).
    let tmp3 = (^mktemp -d | str trim)
    normalize-cypress-video $tmp3 $cell_id
    let no_vid_dir_safe = true

    # Case 5: multiple legacy mp4s, no target; first sorted moved, extras removed.
    let tmp4 = (^mktemp -d | str trim)
    let vids4 = ($tmp4 | path join "cypress" "videos")
    mkdir $vids4
    "video-a" | save --force ($vids4 | path join "aaa-spec.mp4")
    "video-b" | save --force ($vids4 | path join "bbb-spec.mp4")
    let target5 = ($vids4 | path join $"($cell_id)--run.mp4")
    normalize-cypress-video $tmp4 $cell_id
    let multi_target_created = ($target5 | path exists)
    let multi_extra_removed = (not (($vids4 | path join "bbb-spec.mp4") | path exists))
    let multi_content = (open --raw $target5 | str trim)

    try { rm -rf $tmp1 } catch {}
    try { rm -rf $tmp2 } catch {}
    try { rm -rf $tmp3 } catch {}
    try { rm -rf $tmp4 } catch {}

    [
        (assert-truthy $has_target "legacy video moved to normalized name")
        (assert-truthy $src_gone "legacy source removed after move")
        (assert-truthy $target_still "target stays when already present")
        (assert-truthy $legacy2_removed "target exists: extra mp4 removed best-effort")
        (assert-eq $target_content "video-content" "target content unchanged after extra cleanup")
        (assert-truthy $no_target_empty_id "empty cell_id: no normalized target created")
        (assert-truthy $no_vid_dir_safe "no videos dir: no error thrown")
        (assert-truthy $multi_target_created "multiple mp4s: target created from first sorted")
        (assert-truthy $multi_extra_removed "multiple mp4s: remaining extras removed best-effort")
        (assert-eq $multi_content "video-a" "multiple mp4s: target has content of first sorted file")
    ]
}

# --- sort-evidence-rows ---
# Verifies that proof screenshots with glob-unstable order (002 before 001)
# are emitted in ascending order (001 then 002), and that kind buckets
# are respected (metadata < screenshot < video). Rows without order sort last
# among screenshots and break ties by path.

def test-sort-evidence-rows [] {
    test-log "\n[test-sort-evidence-rows]"
    let cell = "login__opencloud-v6"

    let ss_002 = {
        kind: "screenshot" scope: "cypress"
        logical_name: "login__opencloud-v6--002--single--confirmed.png"
        path: "cypress/screenshots/login__opencloud-v6--002--single--confirmed.png"
        availability: "artifact"
    }
    let ss_001 = {
        kind: "screenshot" scope: "cypress"
        logical_name: "login__opencloud-v6--001--single--authenticated.png"
        path: "cypress/screenshots/login__opencloud-v6--001--single--authenticated.png"
        availability: "artifact"
    }
    let vid_row = {
        kind: "video" scope: "cypress"
        logical_name: "login__opencloud-v6--run.mp4"
        path: "cypress/videos/login__opencloud-v6--run.mp4"
        availability: "artifact"
    }
    let meta_row = {
        kind: "metadata" scope: "meta"
        logical_name: "run.json"
        path: "meta/run.json"
        availability: "artifact"
    }
    let ss_fail = {
        kind: "screenshot" scope: "cypress"
        logical_name: "Some test failed (1).png"
        path: "cypress/screenshots/e2e/Some test failed (1).png"
        availability: "artifact"
    }

    # Input: 002 before 001, then video, then meta (glob-unstable order).
    let enriched = [
        (enrich-ev-row $ss_002 $cell)
        (enrich-ev-row $ss_001 $cell)
        (enrich-ev-row $vid_row $cell)
        (enrich-ev-row $meta_row $cell)
        (enrich-ev-row $ss_fail $cell)
    ]
    let sorted = ($enriched | sort-evidence-rows)

    # Expected order: metadata(0), screenshot-001(2,order=1), screenshot-002(2,order=2),
    #                 screenshot-fail(2,order=999999), video(3).
    [
        (assert-eq ($sorted | length) 5 "sort: all 5 rows preserved")
        (assert-eq ($sorted | get 0 | get kind) "metadata"
            "sort: metadata is first")
        (assert-eq ($sorted | get 1 | get order) 1
            "sort: screenshot order 001 sorts before 002")
        (assert-eq ($sorted | get 2 | get order) 2
            "sort: screenshot order 002 sorts after 001")
        (assert-eq ($sorted | get 3 | get capture_class) "failure-auto"
            "sort: failure-auto screenshot (no order) sorts after proof screenshots")
        (assert-eq ($sorted | get 4 | get kind) "video"
            "sort: video comes after all screenshots")

        # Idempotent: already-sorted input stays sorted.
        (assert-eq
            ([$meta_row $ss_001 $ss_002] | each {|r| enrich-ev-row $r $cell} | sort-evidence-rows | each {|r| $r.path})
            ([$meta_row $ss_001 $ss_002] | each {|r| enrich-ev-row $r $cell} | each {|r| $r.path})
            "sort: already-sorted input is unchanged")
    ]
}

def write-sparse-publish-fixture [
    tmp: string,
    cell: record,
    execution_id: string = "20260101t120000-abcdef01",
    --run-extra: record = {},
    --result-extra: record = {},
] {
    mkdir ($tmp | path join "meta")
    ($cell | to json) | save --force ($tmp | path join "meta/cell.json")
    ({
        execution_id: $execution_id
        started_at: "2026-01-01T12:00:00Z"
        finished_at: "2026-01-01T12:05:00Z"
    } | merge $run_extra | to json) | save --force ($tmp | path join "meta/run.json")
    ({
        execution_id: $execution_id
        status: "passed"
        exit_code: 0
        finished_at: "2026-01-01T12:05:00Z"
    } | merge $result_extra | to json) | save --force ($tmp | path join "meta/result.v1.json")
}

def test-emit-publish-envelope-carries-matrix-key-on-run-and-result [] {
    test-log "\n[test-emit-publish-envelope-carries-matrix-key-on-run-and-result]"
    with-tmp-dir {|tmp|
        write-sparse-publish-fixture $tmp {
            cell_id: "login__nextcloud-v34"
            artifact_name: "cell-login-nextcloud-v34"
            flow_id: "login"
            sender_platform: "nextcloud"
            sender_version: "v34"
        } --run-extra {matrix_key: "login__nextcloud"}
        emit-publish-envelope $tmp
        let manifest = (open ($tmp | path join "meta/suite-manifest.v1.json"))
        let cell_entry = ($manifest.cells | values | first)
        let run_entry = ($manifest.runs | values | first)
        let result_entry = ($manifest.results | values | first)
        [
            (assert-eq $cell_entry.flow_id "login"
                "cell_entry carries canonical flow_id from cell.json")
            (assert-eq ($cell_entry.matrix_key? | default "") "login__nextcloud"
                "cell_entry carries matrix_key from run.json")
            (assert-eq ($run_entry.matrix_key? | default "") "login__nextcloud"
                "run_entry carries matrix_key from run.json")
            (assert-eq ($result_entry.matrix_key? | default "") "login__nextcloud"
                "result_entry carries matrix_key from run.json")
        ]
    }
}

def test-emit-publish-envelope-backfills-matrix-key-from-run-json [] {
    test-log "\n[test-emit-publish-envelope-backfills-matrix-key-from-run-json]"
    with-tmp-dir {|tmp|
        write-sparse-publish-fixture $tmp {
            cell_id: "login__nextcloud-v34"
            artifact_name: "cell-login-nextcloud-v34"
            flow_id: "login"
            sender_platform: "nextcloud"
            sender_version: "v34"
        } --run-extra {matrix_key: "login__nextcloud"}
        emit-publish-envelope $tmp
        let manifest = (open ($tmp | path join "meta/suite-manifest.v1.json"))
        let cell_entry = ($manifest.cells | values | first)
        let run_entry = ($manifest.runs | values | first)
        let result_entry = ($manifest.results | values | first)
        [
            (assert-eq ($cell_entry.matrix_key? | default "") "login__nextcloud"
                "cell_entry backfills matrix_key from run.json when cell omits it")
            (assert-eq ($run_entry.matrix_key? | default "") "login__nextcloud"
                "run_entry backfills matrix_key from run.json when cell omits it")
            (assert-eq ($result_entry.matrix_key? | default "") "login__nextcloud"
                "result_entry backfills matrix_key from run.json when cell omits it")
        ]
    }
}

def test-emit-publish-envelope-errors-without-flow-id [] {
    test-log "\n[test-emit-publish-envelope-errors-without-flow-id]"
    with-tmp-dir {|tmp|
        write-sparse-publish-fixture $tmp {
            cell_id: "login__nextcloud-v34"
            artifact_name: "cell-login-nextcloud-v34"
            scenario: "login"
            scenario_module: "login"
            sender_platform: "nextcloud"
            sender_version: "v34"
        } --run-extra {matrix_key: "login__nextcloud"}
        let result = (try { emit-publish-envelope $tmp; "no-error" } catch {|e| "error"})
        [
            (assert-eq $result "error"
                "emit-publish-envelope errors when cell.json lacks flow_id")
        ]
    }
}

def test-emit-publish-envelope-scenario-module-on-cell-entry [] {
    test-log "\n[test-emit-publish-envelope-scenario-module-on-cell-entry]"
    with-tmp-dir {|tmp|
        write-sparse-publish-fixture $tmp {
            cell_id: "contact-wayf__nextcloud-v34"
            artifact_name: "cell-contact-wayf-nextcloud-v34"
            flow_id: "share-with"
            scenario_module: "contact-wayf"
            sender_platform: "nextcloud"
            sender_version: "v34"
        } --run-extra {matrix_key: "share-with__nextcloud"}
        emit-publish-envelope $tmp
        let with_module = (open ($tmp | path join "meta/suite-manifest.v1.json"))
        let cell_with = ($with_module.cells | values | first)

        write-sparse-publish-fixture $tmp {
            cell_id: "login__nextcloud-v34"
            artifact_name: "cell-login-nextcloud-v34"
            flow_id: "login"
            sender_platform: "nextcloud"
            sender_version: "v34"
        } --run-extra {matrix_key: "login__nextcloud"}
        emit-publish-envelope $tmp
        let without_module = (open ($tmp | path join "meta/suite-manifest.v1.json"))
        let cell_without = ($without_module.cells | values | first)

        [
            (assert-eq ($cell_with.scenario_module? | default "") "contact-wayf"
                "cell_entry preserves scenario_module when present in cell.json")
            (assert-truthy (not ("scenario_module" in ($cell_without | columns)))
                "cell_entry omits scenario_module when absent from cell.json")
        ]
    }
}

def main [] {
    test-log "=== Publish Envelope Evidence Tests ==="
    let results = (
        (test-emit-publish-envelope-carries-matrix-key-on-run-and-result)
        | append (test-emit-publish-envelope-backfills-matrix-key-from-run-json)
        | append (test-emit-publish-envelope-errors-without-flow-id)
        | append (test-emit-publish-envelope-scenario-module-on-cell-entry)
        | append (test-path-to-evidence-id)
        | append (test-parse-screenshot-stem)
        | append (test-parse-video-stem)
        | append (test-enrich-ev-row)
        | append (test-sort-evidence-rows)
        | append (test-download-filtering)
        | append (test-normalize-cypress-video)
    ) | flatten
    run-suite "publish/envelope" $SUITE_PATH $results
}
