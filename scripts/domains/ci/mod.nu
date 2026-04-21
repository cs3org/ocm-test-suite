# CI domain: workflow generation, suite planning, artifact aggregation.
# Run `nu scripts/ocmts.nu ci <verb> [flags]` from the repo root.

use ../../lib/domain/core/nu-forward.nu [forward-to]

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

def --wrapped "main plan" [...args: string] {
    forward-to "scripts/domains/ci/plan.nu" $args
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

def --wrapped "main workflows generate github" [...args: string] {
    forward-to "scripts/domains/ci/workflows-generate-github.nu" $args
}

def "main workflows check" [] {
    print "Usage: nu scripts/ocmts.nu ci workflows check <provider>"
    print ""
    print "Providers:"
    print "  github   Check GitHub Actions workflow files for drift"
}

def --wrapped "main workflows check github" [...args: string] {
    forward-to "scripts/domains/ci/workflows-check-github.nu" $args
}

def --wrapped "main aggregate" [...args: string] {
    forward-to "scripts/domains/ci/aggregate.nu" $args
}

def --wrapped "main emit-blocked" [...args: string] {
    forward-to "scripts/domains/ci/emit-blocked.nu" $args
}
