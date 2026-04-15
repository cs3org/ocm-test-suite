# CI domain: workflow generation, suite planning, artifact aggregation.
# Run `nu scripts/ocmts.nu ci <verb> [flags]` from the repo root.

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/blocker.nu [eval-blocked-cells emit-blocked-cell-artifact]
use ../../lib/ci/aggregate.nu [aggregate-suite-manifests write-aggregated-suite-manifest create-suite-archive reconstruct-suite-index]
use ../../lib/ci/workflow-gen.nu [build-ci-matrix-yml build-run-wave-yml build-run-cell-yml build-flow-assets]
use ../../lib/cell.nu [compute-cell]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/run-metadata.nu [utc-now]

def main [] {
    print "Usage: nu scripts/ocmts.nu ci <verb> [flags]"
    print ""
    print "Verbs:"
    print "  plan                        Compute a CI execution plan and emit it as JSON"
    print "  workflows generate github   Generate committed .github/workflows/ YAML files"
    print "  workflows check github      Check committed .github/workflows/ for drift"
    print "  aggregate                   Aggregate per-cell artifacts into one suite manifest"
    print "  emit-blocked                Emit a blocked artifact for a planned cell"
}

# Compute and print the CI execution plan as JSON.
# The plan expands all enabled matrix cells, pre-assigns execution_ids, and
# resolves prerequisite dependencies from config/ci/prerequisites.nuon.
def "main plan" [
    --suite-id: string = "",   # Override generated suite_id
    --output: string = "",     # Write plan to this JSON file instead of stdout
    --cell-ids,                # Output only comma-separated cell_ids (for scripting)
] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
    let prereqs = open ($root | path join "config/ci/prerequisites.nuon")
    let plan = if ($suite_id | is-empty) {
        plan-suite $rules $prereqs
    } else {
        plan-suite $rules $prereqs --suite-id $suite_id
    }
    if $cell_ids {
        $plan.cells | each {|c| $c.cell_id} | str join ","
    } else if ($output | is-empty) {
        $plan | to json --indent 2
    } else {
        $plan | to json --indent 2 | save --force $output
        print $"CI plan written to ($output)"
    }
}

def "main workflows" [] {
    print "Usage: nu scripts/ocmts.nu ci workflows <action> <provider> [flags]"
    print ""
    print "Actions:"
    print "  generate github   Generate committed .github/workflows/ YAML files"
    print "  check github      Compare committed .github/workflows/ against expected"
}

def "main workflows generate" [] {
    print "Usage: nu scripts/ocmts.nu ci workflows generate <provider>"
    print ""
    print "Providers:"
    print "  github   Generate GitHub Actions workflow YAML files"
}

# Generate committed .github/workflows/ YAML files from the planner and config.
# Writes:
#   .github/workflows/ci-matrix.yml                - orchestration workflow (flow-id jobs)
#   .github/workflows/ci-run-wave.yml              - reusable per-flow matrix runner
#   .github/workflows/ci-run-cell.yml              - reusable single-cell runner
#   .github/workflows/assets/<flow>.json           - per-flow cell data (one per active flow)
#
# Stale asset files are removed automatically. The assets directory is
# generator-owned; do not add files there manually.
#
# To regenerate after changing config/matrix-rules.nuon,
# config/ci/prerequisites.nuon, or config/ci/toolchain.nuon, run:
#   nu scripts/ocmts.nu ci workflows generate github
def "main workflows generate github" [
    --dry-run,  # Print generated YAML and JSON to stdout instead of writing files
] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
    let prereqs = open ($root | path join "config/ci/prerequisites.nuon")
    let plan = plan-suite $rules $prereqs

    let matrix_yml = (build-ci-matrix-yml $plan)
    let run_wave_yml = (build-run-wave-yml)
    let run_cell_yml = (build-run-cell-yml)
    let flow_assets = (build-flow-assets $plan)

    if $dry_run {
        print "# === ci-matrix.yml ==="
        print $matrix_yml
        print "\n# === ci-run-wave.yml ==="
        print $run_wave_yml
        print "\n# === ci-run-cell.yml ==="
        print $run_cell_yml
        for asset in $flow_assets {
            print $"\n# === ($asset.path) ==="
            print $asset.content
        }
        return
    }

    let wf_dir = ($root | path join ".github/workflows")
    let assets_dir = ($wf_dir | path join "assets")
    mkdir $assets_dir
    $matrix_yml | save --force ($wf_dir | path join "ci-matrix.yml")
    $run_wave_yml | save --force ($wf_dir | path join "ci-run-wave.yml")
    $run_cell_yml | save --force ($wf_dir | path join "ci-run-cell.yml")

    # Write per-flow asset files.
    for asset in $flow_assets {
        let abs_path = ($root | path join $asset.path)
        $asset.content | save --force $abs_path
    }

    # Reconcile: remove stale asset files no longer in the generated set.
    let expected_names = ($flow_assets | each {|a| $a.path | path basename})
    let existing_names = (
        glob $"($assets_dir)/*.json" | each {|p| $p | path basename}
    )
    for name in $existing_names {
        if not ($name in $expected_names) {
            rm ($assets_dir | path join $name)
            print $"Removed stale asset: .github/workflows/assets/($name)"
        }
    }

    print "Generated workflows:"
    print $"  ($wf_dir | path join 'ci-matrix.yml')"
    print $"  ($wf_dir | path join 'ci-run-wave.yml')"
    print $"  ($wf_dir | path join 'ci-run-cell.yml')"
    for asset in $flow_assets {
        print $"  ($root | path join $asset.path)"
    }
}

def "main workflows check" [] {
    print "Usage: nu scripts/ocmts.nu ci workflows check <provider>"
    print ""
    print "Providers:"
    print "  github   Check GitHub Actions workflow files for drift"
}

# Compare committed .github/workflows/ YAML and asset JSON against freshly
# generated content. Exits nonzero and prints a useful message when drift is
# detected. Also reports stale asset files in the generator-owned assets dir.
def "main workflows check github" [] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
    let prereqs = open ($root | path join "config/ci/prerequisites.nuon")
    let plan = plan-suite $rules $prereqs

    let expected_matrix = (build-ci-matrix-yml $plan)
    let expected_run_wave = (build-run-wave-yml)
    let expected_run_cell = (build-run-cell-yml)
    let flow_assets = (build-flow-assets $plan)

    let wf_dir = ($root | path join ".github/workflows")
    let assets_dir = ($wf_dir | path join "assets")
    let matrix_path = ($wf_dir | path join "ci-matrix.yml")
    let run_wave_path = ($wf_dir | path join "ci-run-wave.yml")
    let run_cell_path = ($wf_dir | path join "ci-run-cell.yml")

    mut drift = false

    if not ($matrix_path | path exists) {
        print $"DRIFT: ($matrix_path) does not exist -- run: nu scripts/ocmts.nu ci workflows generate github"
        $drift = true
    } else {
        let committed_matrix = (open --raw $matrix_path)
        if $committed_matrix != $expected_matrix {
            print $"DRIFT: ($matrix_path) is out of date -- run: nu scripts/ocmts.nu ci workflows generate github"
            $drift = true
        } else {
            print $"ok: ($matrix_path)"
        }
    }

    if not ($run_wave_path | path exists) {
        print $"DRIFT: ($run_wave_path) does not exist -- run: nu scripts/ocmts.nu ci workflows generate github"
        $drift = true
    } else {
        let committed_run_wave = (open --raw $run_wave_path)
        if $committed_run_wave != $expected_run_wave {
            print $"DRIFT: ($run_wave_path) is out of date -- run: nu scripts/ocmts.nu ci workflows generate github"
            $drift = true
        } else {
            print $"ok: ($run_wave_path)"
        }
    }

    if not ($run_cell_path | path exists) {
        print $"DRIFT: ($run_cell_path) does not exist -- run: nu scripts/ocmts.nu ci workflows generate github"
        $drift = true
    } else {
        let committed_run_cell = (open --raw $run_cell_path)
        if $committed_run_cell != $expected_run_cell {
            print $"DRIFT: ($run_cell_path) is out of date -- run: nu scripts/ocmts.nu ci workflows generate github"
            $drift = true
        } else {
            print $"ok: ($run_cell_path)"
        }
    }

    # Check per-flow asset files.
    let expected_asset_names = ($flow_assets | each {|a| $a.path | path basename})
    for asset in $flow_assets {
        let abs_path = ($root | path join $asset.path)
        if not ($abs_path | path exists) {
            print $"DRIFT: ($asset.path) does not exist -- run: nu scripts/ocmts.nu ci workflows generate github"
            $drift = true
        } else {
            let committed = (open --raw $abs_path)
            if $committed != $asset.content {
                print $"DRIFT: ($asset.path) is out of date -- run: nu scripts/ocmts.nu ci workflows generate github"
                $drift = true
            } else {
                print $"ok: ($asset.path)"
            }
        }
    }

    # Detect stale asset files that are no longer generated.
    if ($assets_dir | path exists) {
        let existing_names = (
            glob $"($assets_dir)/*.json" | each {|p| $p | path basename}
        )
        for name in $existing_names {
            if not ($name in $expected_asset_names) {
                print $"STALE: .github/workflows/assets/($name) is no longer generated -- run: nu scripts/ocmts.nu ci workflows generate github"
                $drift = true
            }
        }
    }

    if $drift {
        error make {msg: "Workflow drift detected. Regenerate with: nu scripts/ocmts.nu ci workflows generate github"}
    }
}

# Aggregate per-cell artifact directories into one suite manifest.
# artifact_dirs is a newline-separated list of paths read from --dirs-file,
# or can be passed directly as positional args.
# --expected-cells: comma-separated cell_ids planned for this suite (enables
#   missing-cell detection; cells with no manifest get a "missing" result).
# --archive: create a zstd tar archive of the artifacts tree after aggregation.
def "main aggregate" [
    ...artifact_dirs: string,
    --dirs-file: string = "",       # Read per-cell artifact dirs from this file
    --suite-id: string = "",        # Suite ID to stamp on the output
    --output-dir: string = "",      # Write aggregated manifest here
    --expected-cells: string = "",  # Comma-separated planned cell_ids for completeness check
    --archive,                      # Create suite-artifacts.tar.zst after aggregation
] {
    let root = get-ocmts-root
    let dirs = if not ($dirs_file | is-empty) {
        open --raw $dirs_file | lines | where {|l| not ($l | is-empty)} | each {|l| $l | str trim}
    } else {
        $artifact_dirs
    }
    if ($dirs | is-empty) {
        error make {msg: "aggregate: no artifact directories provided. Use positional args or --dirs-file"}
    }
    let eff_id = if ($suite_id | is-empty) { "unknown-suite" } else { $suite_id }
    let out_dir = if ($output_dir | is-empty) {
        $root | path join "artifacts/suites/aggregated"
    } else {
        $output_dir
    }
    let expected_ids = if ($expected_cells | is-empty) {
        []
    } else {
        $expected_cells | split row "," | each {|s| $s | str trim} | where {|s| not ($s | is-empty)}
    }
    let path = (write-aggregated-suite-manifest $dirs $eff_id $out_dir
        --expected-cell-ids $expected_ids)
    print $"Aggregated suite manifest written to ($path)"

    let artifacts_root = ($root | path join "artifacts")

    # Reconstruct suite index so downstream suite-based consumers can find
    # all runs (including blocked/missing) via artifacts/suites/.
    let manifest = (open $path)
    let suite_record_path = (reconstruct-suite-index $manifest $artifacts_root)
    if $suite_record_path != null {
        print $"Suite index written to ($suite_record_path)"
    } else {
        print "Suite index reconstruction skipped: suite_id not in expected format"
    }

    if $archive {
        let archive_path = (create-suite-archive $artifacts_root $out_dir)
        print $"Suite archive created: ($archive_path)"
    }
}

# Emit a blocked artifact for a single planned cell.
# Called in CI when a prerequisite cell fails and we need to record blocked
# status for dependent cells without running them.
#
# flow_id, pair, artifact_name, and cell_id are derived from scenario +
# participant inputs when not provided explicitly. This allows the workflow
# to call emit-blocked with only the inputs it already has.
def "main emit-blocked" [
    --cell-id: string = "",         # cell_id; derived from scenario+participants if omitted
    --execution-id: string,         # execution_id for this blocked run
    --flow-id: string = "",         # flow_id; derived from scenario via matrix-rules if omitted
    --scenario: string,             # scenario key (required; used to derive missing fields)
    --pair: string = "",            # pair slug; derived from sender+receiver if omitted
    --artifact-name: string = "",   # artifact_name; derived from sender+receiver if omitted
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --failure-reason: string,       # concrete reason naming the failed prerequisite
    --suite-id: string = "",
    --suite-kind: string = "suite",
] {
    let root = get-ocmts-root

    # Look up flow_id from matrix-rules.nuon when not explicitly provided.
    let eff_flow_id = if not ($flow_id | is-empty) {
        $flow_id
    } else {
        let rules = open ($root | path join "config/matrix-rules.nuon")
        let sc_rules = ($rules.scenarios? | default {} | get? $scenario | default {})
        $sc_rules.flow_id? | default $scenario
    }

    # Derive pair, artifact_name, cell_id from scenario+participants when omitted.
    let derived = (compute-cell $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version $eff_flow_id)
    let eff_cell_id = if ($cell_id | is-empty) { $derived.cell_id } else { $cell_id }
    let eff_pair = if ($pair | is-empty) { $derived.pair } else { $pair }
    let eff_artifact_name = if ($artifact_name | is-empty) { $derived.artifact_name } else { $artifact_name }

    let is_two_party = not ($receiver_platform | is-empty)
    let planned_cell = {
        cell_id: $eff_cell_id,
        execution_id: $execution_id,
        flow_id: $eff_flow_id,
        scenario: $scenario,
        scenario_module: $eff_flow_id,
        pair: $eff_pair,
        artifact_name: $eff_artifact_name,
        sender_platform: $sender_platform,
        sender_version: $sender_version,
        receiver_platform: $receiver_platform,
        receiver_version: $receiver_version,
        is_two_party: $is_two_party,
        browser: "chrome",
    }
    let base = (emit-blocked-cell-artifact $root $planned_cell $failure_reason
        --suite-id $suite_id --suite-kind $suite_kind)
    print $"Blocked artifact written to ($base)"
}
