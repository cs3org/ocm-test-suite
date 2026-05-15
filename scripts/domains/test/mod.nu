# Test domain - orchestrates BOTH Cypress integration tests and internal
# Nushell unit tests. The verb path itself disambiguates them.

use ../../lib/domain/core/nu-forward.nu [forward-to]

def main [] {
    print "Usage: nu scripts/ocmts.nu test <subdomain> <verb> [flags]"
    print ""
    print "CYPRESS (end-to-end integration tests; slow; Docker-driven):"
    print "  cypress run     Run Cypress headless against an already-up stack"
    print "  cypress suite   Run the full enabled matrix suite sequentially"
    print "                  (supports --publish-site, and --preview from Wave 7-B)"
    print ""
    print "UNITS (internal Nushell unit tests for the ocmts CLI; fast; no Docker):"
    print "  units                              Run all non-manual suites; emits combined JSON"
    print "  units --suite <area/topic>         Run one suite (e.g. ci/planner)"
    print "  units --suites <a,b,c>             Run multiple suites by comma-separated IDs"
    print "  units --list                       List non-manual suites"
    print "  units --list --include-manual      List all suites including manual"
    print "  units --human                      Human-friendly streaming output (all modes)"
    print "  units --suite <id> --include-manual  Allow a manual suite"
    print ""
    print "Notes:"
    print "  Video recording is enabled by default. To opt out, pass --no-video"
    print "  to 'services up', 'services up run', or 'services up open'."
    print "  'test cypress run' reuses the runner-ci.yml overlay pre-rendered by"
    print "  'services up' / 'services up open', so the video setting is"
    print "  inherited from that prior step."
    print ""
    print "  'test cypress run' does NOT tear down services after the test pass."
    print "  Platform service logs (platform container stdout/stderr) are"
    print "  NOT collected automatically by 'test cypress run'. Only the Cypress"
    print "  container output is captured. If you need platform logs,"
    print "  run the following while the stack is still up:"
    print "    nu scripts/ocmts.nu artifacts collect --include-logs ..."
    print "  Platform log collection is otherwise tied to the teardown"
    print "  path ('services up run') which calls 'services down'."
    print ""
    print "  'test cypress suite' can optionally publish the completed suite into"
    print "  the results site. Pass --publish-site to enable. By default"
    print "  the site repo is cloned automatically; pass --site-dir <path>"
    print "  to use a local worktree instead (requires --publish-site)."
    print ""
    print "See scripts/ocmts-command-map.md for the full command surface."
}

def "main cypress" [] {
    print "Usage: nu scripts/ocmts.nu test cypress <verb> [flags]"
    print ""
    print "  run    Run Cypress headless against an already-up stack"
    print "  suite  Run the full enabled matrix suite sequentially"
}

def --wrapped "main cypress run" [...args: string] {
    forward-to "scripts/domains/test/cypress-run.nu" $args
}

def --wrapped "main cypress suite" [...args: string] {
    forward-to "scripts/domains/test/cypress-suite.nu" $args
}

def --wrapped "main units" [...args: string] {
    forward-to "scripts/domains/test/units.nu" $args
}
