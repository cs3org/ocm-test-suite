# Site config loading, validation, and resolver tests.
# Run: nu scripts/tests/site/config.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/site/config.nu [
    load-site-cfg
    validate-site-cfg
    resolve-effective-site-ref
    resolve-effective-site-repo-url
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# load-site-cfg returns a record with expected keys present.
def test-load-site-cfg-keys [] {
    test-log "\n[test-load-site-cfg-keys]"
    let cfg = (load-site-cfg)
    [
        (assert-not-null ($cfg.schema_version?) "schema_version present")
        (assert-not-null ($cfg.repo_slug?) "repo_slug present")
        (assert-not-null ($cfg.ref?) "ref present")
        (assert-not-null ($cfg.publish_branch_gate?) "publish_branch_gate present")
        (assert-not-null ($cfg.site_build_output_path?) "site_build_output_path present")
        (assert-not-null ($cfg.raw_aggregate_artifact_name?) "raw_aggregate_artifact_name present")
        (assert-not-null ($cfg.optimized_artifact_pattern?) "optimized_artifact_pattern present")
        (assert-not-null ($cfg.optimized_aggregate_artifact_name?) "optimized_aggregate_artifact_name present")
        (assert-not-null ($cfg.rebuild_source_workflow?) "rebuild_source_workflow present")
    ]
}

# load-site-cfg returns expected default values.
def test-load-site-cfg-values [] {
    test-log "\n[test-load-site-cfg-values]"
    let cfg = (load-site-cfg)
    [
        (assert-eq $cfg.repo_slug "MahdiBaghbani/ocm-web-site" "repo_slug is default")
        (assert-eq $cfg.ref "main" "ref is main")
        (assert-eq $cfg.publish_branch_gate "main" "publish_branch_gate is main")
        (assert-eq $cfg.site_build_output_path "dist"
            "site_build_output_path is site-relative output subpath")
        (assert-eq $cfg.raw_aggregate_artifact_name "aggregate-summary"
            "raw_aggregate_artifact_name correct")
        (assert-eq $cfg.optimized_artifact_pattern "optimized-media-cell-*"
            "optimized_artifact_pattern correct")
        (assert-eq $cfg.optimized_aggregate_artifact_name "optimized-media-summary"
            "optimized_aggregate_artifact_name correct")
        (assert-eq $cfg.rebuild_source_workflow "ci-matrix.yml"
            "rebuild_source_workflow correct")
    ]
}

# validate-site-cfg passes a complete valid config without error.
def test-validate-site-cfg-valid [] {
    test-log "\n[test-validate-site-cfg-valid]"
    let cfg = (load-site-cfg)
    let result = (try { validate-site-cfg $cfg; "ok" } catch {|e| $"error: ($e.msg)"})
    [
        (assert-eq $result "ok" "valid config passes validate-site-cfg")
    ]
}

# validate-site-cfg errors when a required key is missing.
def test-validate-site-cfg-missing-key [] {
    test-log "\n[test-validate-site-cfg-missing-key]"
    let incomplete = {schema_version: 1, repo_slug: "a/b", ref: "main", publish_branch_gate: "main"}
    let result = (
        try { validate-site-cfg $incomplete; "no-error" } catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "missing required key causes an error")
        (assert-string-contains $result "missing required key"
            "error message mentions missing required key")
    ]
}

# validate-site-cfg errors when repo_slug is empty.
def test-validate-site-cfg-empty-slug [] {
    test-log "\n[test-validate-site-cfg-empty-slug]"
    let cfg = (load-site-cfg | update repo_slug "")
    let result = (
        try { validate-site-cfg $cfg; "no-error" } catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "empty repo_slug causes an error")
        (assert-string-contains $result "repo_slug"
            "error message mentions repo_slug")
    ]
}

# validate-site-cfg errors when publish_branch_gate is empty.
def test-validate-site-cfg-empty-branch-gate [] {
    test-log "\n[test-validate-site-cfg-empty-branch-gate]"
    let cfg = (load-site-cfg | update publish_branch_gate "")
    let result = (
        try { validate-site-cfg $cfg; "no-error" } catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "empty publish_branch_gate causes an error")
        (assert-string-contains $result "publish_branch_gate"
            "error message mentions publish_branch_gate")
    ]
}

# validate-site-cfg errors when site_build_output_path is empty.
def test-validate-site-cfg-empty-build-output [] {
    test-log "\n[test-validate-site-cfg-empty-build-output]"
    let cfg = (load-site-cfg | update site_build_output_path "")
    let result = (
        try { validate-site-cfg $cfg; "no-error" } catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "empty site_build_output_path causes an error")
        (assert-string-contains $result "site_build_output_path"
            "error message mentions site_build_output_path")
    ]
}

# resolve-effective-site-ref: explicit arg takes top priority.
def test-resolve-ref-arg-wins [] {
    test-log "\n[test-resolve-ref-arg-wins]"
    let result = (with-env { OCMTS_SITE_REF: "env-branch" } {
        resolve-effective-site-ref "my-branch"
    })
    [
        (assert-eq $result "my-branch" "explicit arg wins over env and config")
    ]
}

# resolve-effective-site-ref: env var wins over config when arg is empty.
def test-resolve-ref-env-wins-over-config [] {
    test-log "\n[test-resolve-ref-env-wins-over-config]"
    let result = (with-env { OCMTS_SITE_REF: "env-branch" } {
        resolve-effective-site-ref ""
    })
    [
        (assert-eq $result "env-branch" "env var wins over config when arg is empty")
    ]
}

# resolve-effective-site-ref: config ref used when no arg or env.
def test-resolve-ref-config-default [] {
    test-log "\n[test-resolve-ref-config-default]"
    # Explicitly clear OCMTS_SITE_REF; config/site.nuon has ref = "main".
    let result = (with-env { OCMTS_SITE_REF: "" } {
        resolve-effective-site-ref ""
    })
    [
        (assert-eq $result "main" "config ref is used when no arg or env set")
    ]
}

# resolve-effective-site-repo-url: OCMTS_SITE_REPO_URL env wins.
def test-resolve-url-env-override [] {
    test-log "\n[test-resolve-url-env-override]"
    let result = (with-env { OCMTS_SITE_REPO_URL: "https://custom.example.com/repo.git" } {
        resolve-effective-site-repo-url
    })
    [
        (assert-eq $result "https://custom.example.com/repo.git"
            "OCMTS_SITE_REPO_URL env overrides everything")
    ]
}

# resolve-effective-site-repo-url: OCMTS_SITE_REPO_SLUG env wins over config slug.
def test-resolve-url-slug-env-over-config [] {
    test-log "\n[test-resolve-url-slug-env-over-config]"
    let result = (with-env { OCMTS_SITE_REPO_URL: "", OCMTS_SITE_REPO_SLUG: "custom-org/custom-site" } {
        resolve-effective-site-repo-url
    })
    [
        (assert-truthy ($result | str contains "custom-org/custom-site")
            "OCMTS_SITE_REPO_SLUG env wins over config repo_slug")
        (assert-truthy ($result | str starts-with "https://github.com/")
            "result is a github.com HTTPS URL")
    ]
}

# resolve-effective-site-repo-url: config slug used when no env overrides.
def test-resolve-url-config-slug [] {
    test-log "\n[test-resolve-url-config-slug]"
    let result = (with-env { OCMTS_SITE_REPO_URL: "", OCMTS_SITE_REPO_SLUG: "" } {
        resolve-effective-site-repo-url
    })
    [
        (assert-truthy ($result | str contains "MahdiBaghbani/ocm-web-site")
            "config repo_slug is used when no env overrides")
        (assert-truthy ($result | str ends-with ".git")
            "URL ends with .git")
    ]
}

def main [] {
    test-log "=== Site Config Tests ==="
    let results = (
        (test-load-site-cfg-keys)
        | append (test-load-site-cfg-values)
        | append (test-validate-site-cfg-valid)
        | append (test-validate-site-cfg-missing-key)
        | append (test-validate-site-cfg-empty-slug)
        | append (test-validate-site-cfg-empty-branch-gate)
        | append (test-validate-site-cfg-empty-build-output)
        | append (test-resolve-ref-arg-wins)
        | append (test-resolve-ref-env-wins-over-config)
        | append (test-resolve-ref-config-default)
        | append (test-resolve-url-env-override)
        | append (test-resolve-url-slug-env-over-config)
        | append (test-resolve-url-config-slug)
    ) | flatten
    run-suite "site/config" $SUITE_PATH $results
}
