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
use ./fixtures.nu [fixture-rules fixture-prereqs fixture-flow-caps]

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
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
    let site = ($wf.github.filenames.site? | default "ci-site.yml")
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "  ci-site:")
            "ci-matrix.yml has ci-site reusable workflow job")
        (assert-truthy ($yml | str contains $"./.github/workflows/($site)")
            "ci-matrix.yml ci-site job calls configured site workflow")
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
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let site_cfg = (open ($real_root | path join "config/site.nuon"))
    let branch_gate = ($site_cfg.publish_branch_gate? | default "main")
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    # Branch gate must come from config/site.nuon (publish_branch_gate),
    # not hardcoded in multiple places.
    let ci_site_pos = ($yml | str index-of "  ci-site:")
    let ci_site_section = ($yml | str substring $ci_site_pos..)
    [
        (assert-truthy ($ci_site_section | str contains $"refs/heads/($branch_gate)")
            "ci-site if condition uses publish_branch_gate from config")
        (assert-truthy (not ($yml | str contains $"refs/heads/($branch_gate)\n      runs-on:"))
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
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let site_cfg = (open ($real_root | path join "config/site.nuon"))
    let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
    let matrix_filename = ($wf.github.filenames.matrix? | default "ci-matrix.yml")
    let branch_gate = ($site_cfg.publish_branch_gate? | default "main")
    let rebuild_src = ($site_cfg.rebuild_source_workflow? | default $matrix_filename)
    let raw_agg_name = ($site_cfg.raw_aggregate_artifact_name? | default "aggregate-summary")
    let opt_pattern = ($site_cfg.optimized_artifact_pattern? | default "optimized-media-cell-*")
    let opt_agg_name = ($site_cfg.optimized_aggregate_artifact_name? | default "optimized-media-summary")
    let site_output_subpath = ($site_cfg.site_build_output_path? | default "dist")
    let ci_site_yml = (build-ci-site-yml)
    # Values come from config/site.nuon.
    # gh run list takes a bare branch name (not refs/heads/ prefix).
    [
        (assert-truthy ($ci_site_yml | str contains $rebuild_src)
            "ci-site.yml uses rebuild_source_workflow from site config")
        (assert-truthy ($ci_site_yml | str contains $raw_agg_name)
            "ci-site.yml uses raw_aggregate_artifact_name from site config")
        (assert-truthy ($ci_site_yml | str contains $opt_pattern)
            "ci-site.yml uses optimized_artifact_pattern from site config")
        (assert-truthy ($ci_site_yml | str contains $"--branch ($branch_gate)")
            "ci-site.yml uses publish_branch_gate from site config in resolve-source-run call")
        (assert-truthy ($ci_site_yml | str contains $opt_agg_name)
            "ci-site.yml uses optimized_aggregate_artifact_name from site config")
        (assert-truthy ($ci_site_yml | str contains ("../ocm-web-site" | path join $site_output_subpath))
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
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
    let site_cfg = (open ($real_root | path join "config/site.nuon"))
    let upload_pages_action = ($wf.github.action_upload_pages_artifact? | default "actions/upload-pages-artifact@v5")
    let site_output_subpath = ($site_cfg.site_build_output_path? | default "dist")
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
        (assert-truthy ($ci_site_yml | str contains $upload_pages_action)
            "ci-site.yml build job uses upload-pages-artifact action from config")
        (assert-truthy ($ci_site_yml | str contains ("../ocm-web-site" | path join $site_output_subpath))
            "ci-site.yml upload-pages-artifact path is CI checkout dir joined with site output subpath")
    ]
}

def test-ci-site-action-refs [] {
    test-log "\n[test-ci-site-action-refs]"
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
    let download = ($wf.github.action_download_artifact? | default "actions/download-artifact@v7")
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains $download)
            "ci-site.yml uses download-artifact action from config")
        (assert-truthy (not ($ci_site_yml | str contains "actions/download-artifact@v4"))
            "ci-site.yml does not contain stale download-artifact@v4")
    ]
}

def test-ci-site-deploy-job [] {
    test-log "\n[test-ci-site-deploy-job]"
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
    let deploy_pages_action = ($wf.github.action_deploy_pages? | default "actions/deploy-pages@v5")
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "Deploy to GitHub Pages")
            "ci-site.yml deploy job has Deploy to GitHub Pages step")
        (assert-truthy ($ci_site_yml | str contains $deploy_pages_action)
            "ci-site.yml deploy job uses deploy-pages action from config")
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

# OCMTS_SITE_REF must not hardcode any branch name as a fallback in ci-site.yml.
# When the env var is unset the value should fall through to config/site.nuon
# (ref field), not silently default to a hardcoded branch name in the YAML.
# Positive assertion: empty-string fallback proves config fall-through is wired.
def test-ci-site-ref-not-hardcoded [] {
    test-log "\n[test-ci-site-ref-not-hardcoded]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "OCMTS_SITE_REF || ''")
            "ci-site.yml uses empty-string fallback for OCMTS_SITE_REF so config supplies ref when var is unset")
        (assert-truthy (not ($ci_site_yml | str contains "OCMTS_SITE_REF || 'main'"))
            "ci-site.yml does not hardcode 'main' as OCMTS_SITE_REF fallback")
        (assert-truthy ($ci_site_yml | str contains "OCMTS_SITE_REF")
            "ci-site.yml still passes OCMTS_SITE_REF env to publish step")
    ]
}

# ci-site.yml passes deploy-target env vars (ASTRO_BASE, ASTRO_SITE) to the
# Astro build step. Values come from config/site.nuon deploy_base_path and
# deploy_site_url so the built site has correct asset base paths and canonical
# URL for the Pages host repo (cs3org/ocm-test-suite).
def test-ci-site-deploy-target-env [] {
    test-log "\n[test-ci-site-deploy-target-env]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "ASTRO_BASE:")
            "ci-site.yml Publish site step sets ASTRO_BASE env for Astro build")
        (assert-truthy ($ci_site_yml | str contains "ASTRO_SITE:")
            "ci-site.yml Publish site step sets ASTRO_SITE env for Astro build")
        (assert-truthy ($ci_site_yml | str contains "/ocm-test-suite/")
            "ci-site.yml ASTRO_BASE uses deploy_base_path from config")
        (assert-truthy ($ci_site_yml | str contains "cs3org.github.io")
            "ci-site.yml ASTRO_SITE references the cs3org GitHub Pages host")
    ]
}

# When deploy_site_url is empty, ASTRO_SITE must render as ASTRO_SITE: ''
# (explicit empty scalar) rather than bare ASTRO_SITE: (ambiguous YAML).
# The non-empty case is covered by test-ci-site-deploy-target-env.
def test-ci-site-empty-site-url-renders-explicit [] {
    test-log "\n[test-ci-site-empty-site-url-renders-explicit]"
    let ci_site_yml = (build-ci-site-yml --site-cfg-overrides {deploy_site_url: ""})
    [
        (assert-truthy ($ci_site_yml | str contains "ASTRO_SITE: ''")
            "empty deploy_site_url renders ASTRO_SITE: '' (explicit empty scalar, not bare ASTRO_SITE:)")
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
        | append (test-ci-site-action-refs)
        | append (test-ci-site-deploy-job)
        | append (test-ci-site-has-optimizer-probe-step)
        | append (test-ci-site-download-no-or-true)
        | append (test-ci-site-ref-not-hardcoded)
        | append (test-ci-site-deploy-target-env)
        | append (test-ci-site-empty-site-url-renders-explicit)
    ) | flatten
    run-suite "ci/site-reusable-workflow" $SUITE_PATH $results
}
