# Forward a subcommand to an OCMTS repo script under `nu`.
# Used by the ocmts.nu router to delegate into domain modules.

use ./ocmts-root.nu [get-ocmts-root]

# Run `nu <ocmts-root>/<script> ...<args>`, streaming output live, then
# exit with the same code. Does not return. `script` is relative to root.
export def forward-to [script: string, args: list<string>] {
    let root = get-ocmts-root
    let full_path = ($root | path join $script)
    ^nu $full_path ...$args
    exit $env.LAST_EXIT_CODE
}
