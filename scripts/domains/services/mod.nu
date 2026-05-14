# Services domain: docker compose lifecycle management.

use ../../lib/domain/core/nu-forward.nu [forward-to]

def main [] {
    print "Usage: nu scripts/ocmts.nu services <verb> [flags]"
    print ""
    print "Verbs:"
    print "  up              Bring up platform+helper services for a cell"
    print "  down            Tear down services for a cell"
    print "  list-cell-images  Print runtime image refs for a cell (one per line)"
    print ""
    print "Shortcuts:"
    print "  up run   Bring up + run tests (headless) + collect artifacts + tear down"
    print "  up open  Bring up + start dev Cypress workspace (no auto-down)"
}

def --wrapped "main up" [...args: string] {
    forward-to "scripts/domains/services/up.nu" $args
}

def --wrapped "main up run" [...args: string] {
    forward-to "scripts/domains/services/up-run.nu" $args
}

def --wrapped "main up open" [...args: string] {
    forward-to "scripts/domains/services/up-open.nu" $args
}

def --wrapped "main down" [...args: string] {
    forward-to "scripts/domains/services/down.nu" $args
}

def --wrapped "main list-cell-images" [...args: string] {
    forward-to "scripts/domains/services/list-cell-images.nu" $args
}
