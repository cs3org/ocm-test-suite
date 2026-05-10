# Reusable ci-site.yml and ci-matrix -> ci-site integration tests.
# Run: nu scripts/tests/ci/site-reusable-workflow.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/workflow-gen.nu [
    build-ci-matrix-yml
    build-ci-site-yml
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Minimal matrix rules fixture covering key cases.
def fixture-rules [] {
    {
        scenarios: {
            login: {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v33" "v34"]},
                receiver: null,
                mitm: false,
            },
            "login-v34-only": {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: null,
                mitm: false,
            },
            "share-with": {
                enabled: true,
                flow_id: "share-with",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: {platform: "nextcloud", version_lines: ["v34"]},
                mitm: true,
            },
            "disabled-flow": {
                enabled: false,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v33"]},
                receiver: null,
                mitm: false,
            },
        }
    }
}

def fixture-prereqs [] {
    {
        capability_rules: [
            {
                capability_flow: "login",
                required_for_flows: ["share-with" "contact-token" "contact-wayf" "code-flow"],
                required_roles: ["sender" "receiver"],
            }
        ]
    }
}

# Flow caps with no capability requirements (empty sender/receiver lists).
# Passing this to plan-suite means derive-cell-impl-info finds no blockers
# and every enabled cell comes out as "supported" / capability_action "run".
def fixture-flow-caps [] {
    {
        "login": {sender: [], receiver: []},
        "share-with": {sender: [], receiver: []},
    }
}

# ---- tests ----

def test-site-env-names [] {
    test-log "\n[test-site-env-names]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "OCMTS_SITE_REPO_SLUG")
            "ci-site.yml uses OCMTS_SITE_REPO_SLUG env name")
        (assert-truthy ($ci_site_yml | str contains "OCMTS_SITE_REF")
            "ci-site.yml uses OCMTS_SITE_REF env name")
        (assert-truthy ($ci_site_yml | str contains "OCMTS_SITE_REPO_URL")
            "ci-site.yml uses OCMTS_SITE_REPO_URL env name")
        (assert-truthy (not ($ci_site_yml | str contains "SITE_REPO:"))
            "ci-site.yml does not use old SITE_REPO env name")
    ]
}

def test-site-publish-downloads-cell-artifacts [] {
    test-log "\n[test-site-publish-downloads-cell-artifacts]"
    let ci_site_yml = (build-ci-site-yml)
    # ci-site.yml downloads the raw aggregate bundle and unpacks it, then
    # downloads optimized-media-cell-* artifacts separately.
    [
        (assert-truthy ($ci_site_yml | str contains "Download raw aggregate artifact")
            "ci-site.yml has Download raw aggregate artifact step")
        (assert-truthy ($ci_site_yml | str contains "Extract aggregate archive")
            "ci-site.yml has Extract aggregate archive step")
        (assert-truthy ($ci_site_yml | str contains "tar -x -I zstd")
            "ci-site.yml extract step uses tar with zstd decompression")
        (assert-truthy (not ($ci_site_yml | str contains "pattern: 'cell-*'"))
            "ci-site.yml does not download raw cell-* artifacts directly")
    ]
}

def test-site-publish-artifacts-root [] {
    test-log "\n[test-site-publish-artifacts-root]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "--artifacts-root artifacts")
            "ci-site.yml publish command uses --artifacts-root artifacts")
        (assert-truthy ($ci_site_yml | str contains "--latest-suite")
            "ci-site.yml publish command uses --latest-suite for suite-based ingest")
        (assert-truthy ($ci_site_yml | str contains "--optimized-media-dir")
            "ci-site.yml publish command passes --optimized-media-dir")
    ]
}

def test-ci-matrix-calls-ci-site [] {
    test-log "\n[test-ci-matrix-calls-ci-site]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "  ci-site:")
            "ci-matrix.yml has ci-site reusable workflow job")
        (assert-truthy ($yml | str contains "./.github/workflows/ci-site.yml")
            "ci-matrix.yml ci-site job calls ci-site.yml")
        (assert-truthy (not ($yml | str contains "  site-publish:"))
            "ci-matrix.yml does not have inline site-publish job")
        (assert-truthy ($yml | str contains "needs: [aggregate]")
            "ci-site job needs aggregate")
        (assert-truthy ($yml | str contains "source-run-id: ${{ github.run_id }}")
            "ci-matrix.yml passes caller run ID to ci-site reusable workflow")
    ]
}

def test-ci-matrix-branch-gate-from-config [] {
    test-log "\n[test-ci-matrix-branch-gate-from-config]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    # Branch gate must come from config/site.nuon (publish_branch_gate: "main"),
    # not hardcoded in multiple places.
    let ci_site_pos = ($yml | str index-of "  ci-site:")
    let ci_site_section = ($yml | str substring $ci_site_pos..)
    [
        (assert-truthy ($ci_site_section | str contains "refs/heads/main")
            "ci-site if condition uses publish_branch_gate from config")
        (assert-truthy (not ($yml | str contains "refs/heads/main\n      runs-on:"))
            "ci-matrix.yml has no inline runner after branch gate (site is reusable call)")
    ]
}

def test-ci-site-has-both-triggers [] {
    test-log "\n[test-ci-site-has-both-triggers]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "workflow_call:")
            "ci-site.yml accepts workflow_call trigger")
        (assert-truthy ($ci_site_yml | str contains "workflow_dispatch:")
            "ci-site.yml accepts workflow_dispatch trigger")
    ]
}

def test-ci-site-resolves-source-run [] {
    test-log "\n[test-ci-site-resolves-source-run]"
    let ci_site_yml = (build-ci-site-yml)
    # For workflow_call: caller passes source-run-id input (its own github.run_id).
    # For workflow_dispatch: gh run list resolves the latest eligible source run.
    [
        (assert-truthy ($ci_site_yml | str contains "Resolve artifact source run")
            "ci-site.yml has source run resolution step")
        (assert-truthy ($ci_site_yml | str contains "workflow_dispatch")
            "ci-site.yml source resolution branches on workflow_dispatch")
        (assert-truthy ($ci_site_yml | str contains "ci resolve-source-run")
            "ci-site.yml calls ci resolve-source-run to find source run")
        (assert-truthy ($ci_site_yml | str contains "inputs['source-run-id']")
            "ci-site.yml uses source-run-id input as source for workflow_call")
        (assert-truthy ($ci_site_yml | str contains "source-run-id")
            "ci-site.yml passes source-run-id between prepare and downstream jobs")
    ]
}

def test-ci-site-downloads-optimized-media [] {
    test-log "\n[test-ci-site-downloads-optimized-media]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "Download optimized media artifacts")
            "ci-site.yml downloads optimized media artifacts")
        (assert-truthy ($ci_site_yml | str contains "optimized-media-cell-")
            "ci-site.yml references optimized-media-cell- pattern")
        (assert-truthy ($ci_site_yml | str contains "Aggregate optimized media")
            "ci-site.yml has aggregate optimized media step")
        (assert-truthy ($ci_site_yml | str contains "aggregate-optimized-media")
            "ci-site.yml runs aggregate-optimized-media command")
        (assert-truthy ($ci_site_yml | str contains "--scan-dir")
            "ci-site.yml aggregate-optimized-media uses --scan-dir flag")
        (assert-truthy ($ci_site_yml | str contains "artifacts/optimized")
            "ci-site.yml aggregate-optimized-media --scan-dir points to artifacts/optimized")
        (assert-truthy ($ci_site_yml | str contains "Upload optimized media summary")
            "ci-site.yml uploads optimized media summary artifact")
        (assert-truthy (not ($ci_site_yml | str contains "No optimized media artifact dirs found; skipping aggregate"))
            "ci-site.yml does not allow empty optimized-media aggregate fallback")
    ]
}

def test-ci-site-config-values-injected [] {
    test-log "\n[test-ci-site-config-values-injected]"
    let ci_site_yml = (build-ci-site-yml)
    # Values come from config/site.nuon.
    # gh run list takes a bare branch name (not refs/heads/ prefix).
    [
        (assert-truthy ($ci_site_yml | str contains "ci-matrix.yml")
            "ci-site.yml uses rebuild_source_workflow from site config")
        (assert-truthy ($ci_site_yml | str contains "aggregate-summary")
            "ci-site.yml uses raw_aggregate_artifact_name from site config")
        (assert-truthy ($ci_site_yml | str contains "optimized-media-cell-*")
            "ci-site.yml uses optimized_artifact_pattern from site config")
        (assert-truthy ($ci_site_yml | str contains "--branch main")
            "ci-site.yml uses publish_branch_gate from site config in resolve-source-run call")
        (assert-truthy ($ci_site_yml | str contains "optimized-media-summary")
            "ci-site.yml uses optimized_aggregate_artifact_name from site config")
        (assert-truthy ($ci_site_yml | str contains "../ocm-web-site/dist")
            "ci-site.yml upload path is CI-owned site checkout dir joined with site output subpath")
    ]
}

def test-ci-site-job-topology [] {
    test-log "\n[test-ci-site-job-topology]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "  prepare:")
            "ci-site.yml has prepare job")
        (assert-truthy ($ci_site_yml | str contains "  aggregate-media:")
            "ci-site.yml has aggregate-media job")
        (assert-truthy ($ci_site_yml | str contains "  build:")
            "ci-site.yml has build job")
        (assert-truthy ($ci_site_yml | str contains "  deploy:")
            "ci-site.yml has deploy job")
        (assert-truthy ($ci_site_yml | str contains "needs: [prepare]")
            "aggregate-media needs prepare")
        (assert-truthy ($ci_site_yml | str contains "needs: [prepare, aggregate-media]")
            "build needs prepare and aggregate-media")
        (assert-truthy ($ci_site_yml | str contains "needs: [build]")
            "deploy needs build")
    ]
}

def test-ci-site-build-job [] {
    test-log "\n[test-ci-site-build-job]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "Publish site")
            "ci-site.yml build job has Publish site step")
        (assert-truthy ($ci_site_yml | str contains "--optimized-media-dir artifacts/optimized-summary/")
            "ci-site.yml build job passes --optimized-media-dir to site publish")
        (assert-truthy ($ci_site_yml | str contains "Download optimized media summary")
            "ci-site.yml build job downloads optimized media summary from aggregate-media job")
        (assert-truthy ($ci_site_yml | str contains "Upload built site")
            "ci-site.yml build job uploads built site artifact")
        (assert-truthy ($ci_site_yml | str contains "actions/upload-pages-artifact@v3")
            "ci-site.yml build job uses upload-pages-artifact action")
        (assert-truthy ($ci_site_yml | str contains "../ocm-web-site/dist")
            "ci-site.yml upload-pages-artifact path is CI checkout dir joined with site output subpath")
    ]
}

def test-ci-site-deploy-job [] {
    test-log "\n[test-ci-site-deploy-job]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "Deploy to GitHub Pages")
            "ci-site.yml deploy job has Deploy to GitHub Pages step")
        (assert-truthy ($ci_site_yml | str contains "actions/deploy-pages@v4")
            "ci-site.yml deploy job uses deploy-pages action")
        (assert-truthy ($ci_site_yml | str contains "pages: write")
            "ci-site.yml deploy job has pages: write permission")
        (assert-truthy ($ci_site_yml | str contains "id-token: write")
            "ci-site.yml deploy job has id-token: write permission")
        (assert-truthy ($ci_site_yml | str contains "name: github-pages")
            "ci-site.yml deploy job uses github-pages environment")
        (assert-truthy ($ci_site_yml | str contains "page_url")
            "ci-site.yml deploy job exposes page_url via environment url")
    ]
}

def test-ci-site-has-optimizer-probe-step [] {
    test-log "\n[test-ci-site-has-optimizer-probe-step]"
    let ci_site_yml = (build-ci-site-yml)
    let probe_pos = ($ci_site_yml | str index-of "Probe optimizer image")
    let download_pos = ($ci_site_yml | str index-of "Download optimized media artifacts")
    let probe_section = ($ci_site_yml | str substring $probe_pos..$download_pos)
    [
        (assert-truthy ($ci_site_yml | str contains "Probe optimizer image")
            "ci-site.yml aggregate-media job has Probe optimizer image step")
        (assert-truthy ($probe_section | str contains "nu scripts/ocmts.nu artifacts probe-optimizer")
            "Probe optimizer image step runs nu scripts/ocmts.nu artifacts probe-optimizer")
        (assert-truthy ($probe_pos < $download_pos)
            "Probe optimizer image step appears before Download optimized media artifacts")
    ]
}

def test-ci-site-download-no-or-true [] {
    test-log "\n[test-ci-site-download-no-or-true]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy (not ($ci_site_yml | str contains "--dir artifacts/optimized/ || true"))
            "ci-site.yml gh run download line does not contain || true fallback")
    ]
}

def main [] {
    test-log "=== CI site reusable workflow tests ==="
    let results = (
        (test-site-env-names)
        | append (test-site-publish-downloads-cell-artifacts)
        | append (test-site-publish-artifacts-root)
        | append (test-ci-matrix-calls-ci-site)
        | append (test-ci-matrix-branch-gate-from-config)
        | append (test-ci-site-has-both-triggers)
        | append (test-ci-site-resolves-source-run)
        | append (test-ci-site-downloads-optimized-media)
        | append (test-ci-site-config-values-injected)
        | append (test-ci-site-job-topology)
        | append (test-ci-site-build-job)
        | append (test-ci-site-deploy-job)
        | append (test-ci-site-has-optimizer-probe-step)
        | append (test-ci-site-download-no-or-true)
    ) | flatten
    run-suite "ci/site-reusable-workflow" $SUITE_PATH $results
}
