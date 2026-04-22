# Strict compose config validation for mutating paths.

# Validate a compose file set using docker compose config.
# Errors loudly on non-zero exit (never swallows failures).
# When artifact_path is non-empty, saves resolved output there for audit.
# When env_file is non-empty, passes --env-file for variable substitution.
export def validate-compose-strict [
    files: list<string>,
    project: string,
    artifact_path: string = "",
    env_file: string = "",
] {
    let f_args = ($files | each {|f| ["-f" $f]} | flatten)
    let env_args = if ($env_file | is-empty) { [] } else { ["--env-file" $env_file] }
    let result = (^docker compose ...$env_args ...$f_args -p $project config | complete)
    if $result.exit_code != 0 {
        error make {
            msg: $"Compose config validation failed for project ($project): ($result.stderr | str trim)"
        }
    }
    if not ($artifact_path | is-empty) {
        $result.stdout | save --force $artifact_path
    }
}
