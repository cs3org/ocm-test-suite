# MITM traffic row tests. captured_at column, ts fallback, access-token bodies.
# Run: nu scripts/tests/mitm/summary.nu

const SUITE_PATH = path self

use ../../lib/mitm/ocm-summary.nu [write-ocm-mitm-summaries]
use ../../lib/mitm/summary.nu [summarize-mitm-flows]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [with-tmp-dir]
use ../../lib/tests/runner.nu [run-suite]

def write-traffic [art: string] {
    mkdir ($art | path join "meta")
    {flow_id: "login", cell_id: "cell-login"} | to json | save --force ($art | path join "meta/cell.json")
    {execution_id: "run-1", matrix_key: "login__nextcloud"} | to json | save --force ($art | path join "meta/run.json")
    let dir = ($art | path join "mitm" "flows")
    mkdir $dir
    let lines = [
        {
            captured_at: "2026-01-02T03:04:05Z",
            ts: "1999-01-01T00:00:00Z",
            request: {method: "GET", url: "https://cloud.example/a", host: "cloud.example"},
            response: {status_code: 200},
        }
        {
            ts: "2026-02-03T04:05:06Z",
            request: {method: "POST", url: "https://cloud.example/b", host: "cloud.example"},
            response: {status_code: 201},
        }
        {
            request: {method: "POST", url: "https://cloud.example/ocm/shares", host: "cloud.example"},
            response: {status_code: 204},
        }
    ]
    ($lines | each {|row| $row | to json --raw} | str join "\n")
        | save --force ($dir | path join "traffic.jsonl")
}

def index-of [text: string, needle: string] {
    $text | str index-of $needle
}

def test-traffic-rows-include-captured-at [] {
    test-log "\n[test-traffic-rows-include-captured-at]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        write-traffic $art
        summarize-mitm-flows $art
        write-ocm-mitm-summaries $art
        let md = (open --raw ($art | path join "mitm/reports/01-01-traffic-overview.md"))
        let overview = (open ($art | path join "mitm/reports/01-02-traffic-overview.json"))
        let ep_md = (open --raw ($art | path join "mitm/reports/02-01-ocm-endpoints.md"))
        let ep = (open ($art | path join "mitm/reports/02-02-ocm-endpoints.json"))
        let flows = $overview.flows
        let ep_flows = $ep.flows
        let preferred = "2026-01-02T03:04:05Z"
        let fallback = "2026-02-03T04:05:06Z"
        let stale = "1999-01-01T00:00:00Z"
        [
            (assert-eq ($flows | length) 3 "overview keeps input row order length")
            (assert-eq ($flows | get 0 | get captured_at) $preferred
                "captured_at wins over ts")
            (assert-eq ($flows | get 1 | get captured_at) $fallback
                "ts is the fallback when captured_at is absent")
            (assert-eq ($flows | get 2 | get captured_at) ""
                "a flow with neither timestamp yields an empty captured_at")
            (assert-eq ($flows | each {|row| $row.url}) [
                "https://cloud.example/a"
                "https://cloud.example/b"
                "https://cloud.example/ocm/shares"
            ] "overview row order matches the jsonl")
            (assert-truthy (not ($md | str contains $stale))
                "the stale ts is not shown when captured_at is set")
            (assert-string-contains $md $preferred
                "overview markdown shows the captured_at value")
            (assert-string-contains $md $fallback
                "overview markdown shows the ts fallback")
            (assert-truthy (($md | str index-of "| captured_at |") >= 0)
                "overview markdown leads with captured_at")
            (assert-truthy ((index-of $md $preferred) < (index-of $md $fallback))
                "overview markdown keeps captured_at then ts fallback order")
            (assert-eq ($ep_flows | each {|row| $row.captured_at}) [$preferred $fallback ""]
                "ocm endpoint rows use the same captured_at fallback")
            (assert-eq ($ep_flows | each {|row| $row.url}) ($flows | each {|row| $row.url})
                "ocm endpoint row order matches the overview")
            (assert-truthy (($ep_md | str index-of "| captured_at |") >= 0)
                "ocm endpoint markdown leads with captured_at")
        ]
    }
}

def write-identity [art: string] {
    mkdir ($art | path join "meta")
    {flow_id: "login", cell_id: "cell-login"} | to json | save --force ($art | path join "meta/cell.json")
    {execution_id: "run-1", matrix_key: "login__nextcloud"} | to json | save --force ($art | path join "meta/run.json")
}

def test-access-token-bodies-in-detail-json [] {
    test-log "\n[test-access-token-bodies-in-detail-json]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        write-identity $art
        let dir = ($art | path join "mitm" "flows")
        mkdir $dir
        let form_body = "grant_type=authorization_code&code=abc"
        let refresh_body = "grant_type=refresh_token&refresh_token=r1"
        let token_json = "{\"access_token\":\"t1\",\"token_type\":\"Bearer\"}"
        let plain_resp = "not-json-token-body"
        let lines = [
            {
                captured_at: "2026-03-04T05:06:07Z",
                request: {
                    method: "POST",
                    url: "https://cloud.example/ocm/shares",
                    host: "cloud.example",
                    body: {preview: "{\"shareWith\":\"alice@example.com\"}"},
                },
                response: {
                    status_code: 201,
                    body: {preview: "{\"recipientDisplayName\":\"Alice\"}"},
                },
            }
            {
                captured_at: "2026-03-04T05:06:08Z",
                request: {
                    method: "POST",
                    url: "https://cloud.example/apps/cloud_federation_api/api/v1/access-token",
                    host: "cloud.example",
                    headers: {"Content-Type": "application/x-www-form-urlencoded"},
                    body: {
                        preview: $form_body,
                        encoding: "identity",
                        length_decoded: 40,
                        preview_truncated: false,
                    },
                },
                response: {
                    status_code: 200,
                    body: {
                        preview: $token_json,
                        encoding: "identity",
                    },
                },
            }
            {
                ts: "2026-03-04T05:06:09Z",
                request: {
                    method: "POST",
                    url: "https://cloud.example/apps/cloud_federation_api/api/v1/access-token",
                    host: "cloud.example",
                    content_preview: $refresh_body,
                    content_encoding: "identity",
                    content_length_decoded: 48,
                    content_preview_truncated: true,
                },
                response: {
                    status_code: 200,
                    content_preview: $plain_resp,
                },
            }
        ]
        ($lines | each {|row| $row | to json --raw} | str join "\n")
            | save --force ($dir | path join "traffic.jsonl")
        write-ocm-mitm-summaries $art
        let det = (open ($art | path join "mitm/reports/03-02-ocm-details.json"))
        let ep = (open ($art | path join "mitm/reports/02-02-ocm-endpoints.json"))
        let share = ($det | get 0)
        let coded = ($det | get 1)
        let refreshed = ($det | get 2)
        let coded_req = ($coded | get "access-token" | get request | get body)
        let coded_resp = ($coded | get "access-token" | get response | get body)
        let refresh_req = ($refreshed | get "access-token" | get request | get body)
        let refresh_resp = ($refreshed | get "access-token" | get response | get body)
        [
            (assert-eq ($det | length) 3 "detail json keeps input row order length")
            (assert-eq ($det | each {|row| $row.url}) [
                "https://cloud.example/ocm/shares"
                "https://cloud.example/apps/cloud_federation_api/api/v1/access-token"
                "https://cloud.example/apps/cloud_federation_api/api/v1/access-token"
            ] "detail row order matches the jsonl")
            (assert-eq ($det | each {|row| $row.captured_at}) [
                "2026-03-04T05:06:07Z"
                "2026-03-04T05:06:08Z"
                "2026-03-04T05:06:09Z"
            ] "detail captured_at keeps the ts fallback")
            (assert-eq $share.endpoint_id "shares" "shares endpoint id is unchanged")
            (assert-eq $share.shares.request.shareWith "alice@example.com"
                "shares request body stays a parsed object")
            (assert-truthy (not ("access-token" in ($share | columns)))
                "shares rows do not grow an access-token object")
            (assert-eq $coded.endpoint_id "access-token"
                "cloud_federation_api token path matches access-token")
            (assert-eq $coded_req.preview $form_body
                "form-urlencoded request preview is kept")
            (assert-eq $coded_req.meta.encoding "identity"
                "request body metadata is kept")
            (assert-eq $coded_req.meta.preview_truncated false
                "request preview_truncated metadata is kept")
            (assert-eq $coded_resp.preview $token_json
                "token response preview is kept as text")
            (assert-eq $coded_resp.meta.encoding "identity"
                "token response metadata is kept")
            (assert-truthy (not ("shares" in ($coded | columns)))
                "access-token rows do not grow a shares object")
            (assert-eq $refreshed.captured_at "2026-03-04T05:06:09Z"
                "content_preview flow uses ts as captured_at")
            (assert-eq $refresh_req.preview $refresh_body
                "content_preview form body is not dropped")
            (assert-eq $refresh_req.meta {
                encoding: "identity",
                length_decoded: 48,
                preview_truncated: true,
            } "content_* fields become body metadata")
            (assert-eq $refresh_resp.preview $plain_resp
                "non-JSON response preview is kept")
            (assert-truthy (not ("meta" in ($refresh_resp | columns)))
                "response without metadata omits the meta key")
            (assert-eq ($ep.flows | each {|row| $row.endpoint_id}) [
                "shares" "access-token" "access-token"
            ] "endpoint summary ids stay in row order")
        ]
    }
}

def main [] {
    test-log "=== mitm/summary tests ==="
    let results = [
        (test-traffic-rows-include-captured-at)
        (test-access-token-bodies-in-detail-json)
    ] | flatten
    run-suite "mitm/summary" $SUITE_PATH $results
}
