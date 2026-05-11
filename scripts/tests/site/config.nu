# Site config loading, validation, and resolver tests.
# Run: nu scripts/tests/site/config.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/site/config.nu [
    load-site-cfg
    validate-site-cfg
    resolve-effective-site-ref
    resolve-effective-site-repo-url
    resolve-effective-deploy-base-path
    resolve-effective-deploy-site-url
    resolve-zstd-archive-policy
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
        (assert-not-null ($cfg.deploy_base_path?) "deploy_base_path present")
    ]
}

# load-site-cfg returns expected default values.
def test-load-site-cfg-values [] {
    test-log "\n[test-load-site-cfg-values]"
    let cfg = (load-site-cfg)
    [
        (assert-eq $cfg.repo_slug "MahdiBaghbani/ocm-web-site" "repo_slug is default")
        (assert-eq $cfg.ref "master" "ref is master")
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
        (assert-eq ($cfg.deploy_base_path? | default "") "/ocm-test-suite/"
            "deploy_base_path is Pages base path for cs3org/ocm-test-suite")
    ]
}

# validate-site-cfg passes a complete valid config without error.
# upsert ensures deploy_base_path is present regardless of config file state.
def test-validate-site-cfg-valid [] {
    test-log "\n[test-validate-site-cfg-valid]"
    let cfg = (load-site-cfg | upsert deploy_base_path "/ocm-test-suite/")
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
    # upsert ensures deploy_base_path is present regardless of config file state
    let cfg = (load-site-cfg | upsert deploy_base_path "/ocm-test-suite/" | update repo_slug "")
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
    let cfg = (load-site-cfg | upsert deploy_base_path "/ocm-test-suite/" | update publish_branch_gate "")
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
    let cfg = (load-site-cfg | upsert deploy_base_path "/ocm-test-suite/" | update site_build_output_path "")
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
    # Explicitly clear OCMTS_SITE_REF; config/site.nuon has ref = "master".
    let result = (with-env { OCMTS_SITE_REF: "" } {
        resolve-effective-site-ref ""
    })
    [
        (assert-eq $result "master" "config ref is used when no arg or env set")
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

# validate-site-cfg errors when deploy_base_path is empty.
def test-validate-site-cfg-empty-deploy-base [] {
    test-log "\n[test-validate-site-cfg-empty-deploy-base]"
    let cfg = (load-site-cfg | upsert deploy_base_path "")
    let result = (
        try { validate-site-cfg $cfg; "no-error" } catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "empty deploy_base_path causes an error")
        (assert-string-contains $result "deploy_base_path"
            "error message mentions deploy_base_path")
    ]
}

# resolve-effective-deploy-base-path: explicit arg takes top priority.
def test-resolve-deploy-base-arg-wins [] {
    test-log "\n[test-resolve-deploy-base-arg-wins]"
    let result = (with-env { OCMTS_DEPLOY_BASE: "/env-base/" } {
        resolve-effective-deploy-base-path "/arg-base/"
    })
    [
        (assert-eq $result "/arg-base/" "explicit arg wins over env and config")
    ]
}

# resolve-effective-deploy-base-path: env var wins over config when arg is empty.
def test-resolve-deploy-base-env-wins [] {
    test-log "\n[test-resolve-deploy-base-env-wins]"
    let result = (with-env { OCMTS_DEPLOY_BASE: "/env-base/" } {
        resolve-effective-deploy-base-path ""
    })
    [
        (assert-eq $result "/env-base/" "OCMTS_DEPLOY_BASE env wins when arg is empty")
    ]
}

# resolve-effective-deploy-base-path: config used when no arg or env.
def test-resolve-deploy-base-config-default [] {
    test-log "\n[test-resolve-deploy-base-config-default]"
    # config/site.nuon has deploy_base_path = "/ocm-test-suite/".
    let result = (with-env { OCMTS_DEPLOY_BASE: "" } {
        resolve-effective-deploy-base-path ""
    })
    [
        (assert-eq $result "/ocm-test-suite/"
            "config deploy_base_path is used when no arg or env")
    ]
}

# resolve-effective-deploy-site-url: env var wins.
def test-resolve-deploy-site-url-env-wins [] {
    test-log "\n[test-resolve-deploy-site-url-env-wins]"
    let result = (with-env { OCMTS_DEPLOY_SITE_URL: "https://override.example.com/" } {
        resolve-effective-deploy-site-url
    })
    [
        (assert-eq $result "https://override.example.com/"
            "OCMTS_DEPLOY_SITE_URL env overrides config")
    ]
}

# resolve-effective-deploy-site-url: config used when no env.
def test-resolve-deploy-site-url-config-default [] {
    test-log "\n[test-resolve-deploy-site-url-config-default]"
    let result = (with-env { OCMTS_DEPLOY_SITE_URL: "" } {
        resolve-effective-deploy-site-url
    })
    [
        (assert-truthy ($result | str contains "cs3org.github.io")
            "config deploy_site_url is used when no env override")
    ]
}

# config/site.nuon includes archive_zstd with required keys.
def test-load-site-cfg-archive-zstd-keys [] {
    test-log "\n[test-load-site-cfg-archive-zstd-keys]"
    let cfg = (load-site-cfg)
    let zstd = ($cfg.archive_zstd? | default null)
    [
        (assert-not-null $zstd "archive_zstd key present")
        (assert-not-null ($zstd.level?) "archive_zstd.level present")
        (assert-not-null ($zstd.threads?) "archive_zstd.threads present")
        (assert-not-null ($zstd.checksum?) "archive_zstd.checksum present")
    ]
}

# config/site.nuon archive_zstd has CI-appropriate default values.
def test-load-site-cfg-archive-zstd-values [] {
    test-log "\n[test-load-site-cfg-archive-zstd-values]"
    let zstd = (load-site-cfg).archive_zstd
    [
        (assert-eq $zstd.level 3 "level is 3 (zstd default, CI-appropriate)")
        (assert-eq $zstd.threads 0 "threads is 0 (auto-detect all CPUs)")
        (assert-eq $zstd.checksum true "checksum is true")
    ]
}

# validate-site-cfg accepts config with valid archive_zstd.
def test-validate-site-cfg-archive-zstd-valid [] {
    test-log "\n[test-validate-site-cfg-archive-zstd-valid]"
    let cfg = (load-site-cfg | upsert deploy_base_path "/ocm-test-suite/")
    let result = (try { validate-site-cfg $cfg; "ok" } catch {|e| $"error: ($e.msg)"})
    [
        (assert-eq $result "ok" "config with valid archive_zstd passes validation")
    ]
}

# validate-site-cfg rejects archive_zstd with out-of-range level.
def test-validate-site-cfg-archive-zstd-bad-level [] {
    test-log "\n[test-validate-site-cfg-archive-zstd-bad-level]"
    let cfg = (load-site-cfg
        | upsert deploy_base_path "/ocm-test-suite/"
        | upsert archive_zstd {level: 25, threads: 0, checksum: true})
    let result = (try { validate-site-cfg $cfg; "no-error" } catch {|e| $"error: ($e.msg)"})
    [
        (assert-truthy ($result | str starts-with "error:") "level 25 is rejected")
        (assert-string-contains $result "level" "error mentions level")
    ]
}

# validate-site-cfg rejects archive_zstd with missing key.
def test-validate-site-cfg-archive-zstd-missing-key [] {
    test-log "\n[test-validate-site-cfg-archive-zstd-missing-key]"
    let cfg = (load-site-cfg
        | upsert deploy_base_path "/ocm-test-suite/"
        | upsert archive_zstd {level: 3, threads: 0})
    let result = (try { validate-site-cfg $cfg; "no-error" } catch {|e| $"error: ($e.msg)"})
    [
        (assert-truthy ($result | str starts-with "error:") "missing checksum key is rejected")
        (assert-string-contains $result "checksum" "error mentions checksum")
    ]
}

# validate-site-cfg rejects archive_zstd with non-bool checksum.
def test-validate-site-cfg-archive-zstd-bad-checksum [] {
    test-log "\n[test-validate-site-cfg-archive-zstd-bad-checksum]"
    let cfg = (load-site-cfg
        | upsert deploy_base_path "/ocm-test-suite/"
        | upsert archive_zstd {level: 3, threads: 0, checksum: "yes"})
    let result = (try { validate-site-cfg $cfg; "no-error" } catch {|e| $"error: ($e.msg)"})
    [
        (assert-truthy ($result | str starts-with "error:") "string checksum is rejected")
        (assert-string-contains $result "checksum" "error mentions checksum")
        (assert-string-contains $result "bool" "error mentions expected type bool")
    ]
}

# resolve-zstd-archive-policy returns the policy from config when available.
def test-resolve-zstd-policy-from-config [] {
    test-log "\n[test-resolve-zstd-policy-from-config]"
    let policy = (resolve-zstd-archive-policy)
    [
        (assert-eq $policy.level 3 "resolved level matches config default")
        (assert-eq $policy.threads 0 "resolved threads matches config default")
        (assert-eq $policy.checksum true "resolved checksum matches config default")
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
        | append (test-validate-site-cfg-empty-deploy-base)
        | append (test-resolve-ref-arg-wins)
        | append (test-resolve-ref-env-wins-over-config)
        | append (test-resolve-ref-config-default)
        | append (test-resolve-url-env-override)
        | append (test-resolve-url-slug-env-over-config)
        | append (test-resolve-url-config-slug)
        | append (test-resolve-deploy-base-arg-wins)
        | append (test-resolve-deploy-base-env-wins)
        | append (test-resolve-deploy-base-config-default)
        | append (test-resolve-deploy-site-url-env-wins)
        | append (test-resolve-deploy-site-url-config-default)
        | append (test-load-site-cfg-archive-zstd-keys)
        | append (test-load-site-cfg-archive-zstd-values)
        | append (test-validate-site-cfg-archive-zstd-valid)
        | append (test-validate-site-cfg-archive-zstd-bad-level)
        | append (test-validate-site-cfg-archive-zstd-missing-key)
        | append (test-validate-site-cfg-archive-zstd-bad-checksum)
        | append (test-resolve-zstd-policy-from-config)
    ) | flatten
    run-suite "site/config" $SUITE_PATH $results
}
