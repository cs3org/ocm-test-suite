# Artifacts domain: artifact inspection and log collection.

use ../../lib/domain/core/nu-forward.nu [forward-to]

def main [] {
    print "Usage: nu scripts/ocmts.nu artifacts <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list     List artifact runs for a cell"
    print "  show     Show metadata for a run"
    print "  collect  Collect artifacts for a run (use --include-logs for docker logs)"
    print "  publish  Regenerate suite-manifest.v1.json, summary.json, summary.md"
    print "  prune    Prune run directories or evidence files across artifact runs"
    print "           Default mode (runs): deletes entire run dirs except the latest."
    print "           Evidence mode (--mode evidence): deletes videos/logs and republishes."
}

def --wrapped "main list" [...args: string] {
    forward-to "scripts/domains/artifacts/list.nu" $args
}

def --wrapped "main show" [...args: string] {
    forward-to "scripts/domains/artifacts/show.nu" $args
}

def --wrapped "main collect" [...args: string] {
    forward-to "scripts/domains/artifacts/collect.nu" $args
}

def --wrapped "main publish" [...args: string] {
    forward-to "scripts/domains/artifacts/publish.nu" $args
}

def --wrapped "main prune" [...args: string] {
    forward-to "scripts/domains/artifacts/prune.nu" $args
}
