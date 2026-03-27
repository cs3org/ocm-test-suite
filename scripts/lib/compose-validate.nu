# Strict compose config validation for mutating paths.

# Validate a compose file set using docker compose config.
# Errors loudly on non-zero exit (never swallows failures).
# When artifact_path is non-empty, saves resolved output there for audit.
export def validate-compose-strict [
    files: list<string>,
    project: string,
    artifact_path: string = "",
] {
    let f_args = ($files | each {|f| ["-f" $f]} | flatten)
    let result = (^docker compose ...$f_args -p $project config | complete)
    if $result.exit_code != 0 {
        error make {
            msg: $"Compose config validation failed for project ($project): ($result.stderr | str trim)"
        }
    }
    if not ($artifact_path | is-empty) {
        $result.stdout | save --force $artifact_path
    }
}
