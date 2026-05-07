# Download prerequisite artifacts into the prereqs/<dep> layout.
# Mirrors the bash "Download prerequisite artifacts" step in ci-run-cell.yml.tpl.
# Tolerates individual download failures and continues to the next dep (like || true).

def main [
    --run-id: string,                    # GitHub run ID to download artifacts from
    --deps: string = "",                 # Comma-separated prerequisite cell IDs
    --prereqs-root: string = "prereqs",  # Root directory for per-dep artifact subdirs
] {
    if ($run_id | is-empty) {
        error make {msg: "download-prereqs: --run-id is required"}
    }

    let dep_list = if ($deps | is-empty) {
        []
    } else {
        $deps | split row "," | each {|d| $d | str trim} | where {|d| not ($d | is-empty)}
    }

    for dep in $dep_list {
        let dir = ($prereqs_root | path join $dep)
        mkdir $dir
        try {
            ^gh run download $run_id --name $dep --dir $dir
        } catch {|err|
            print $"warning: download failed for prereq ($dep): ($err.msg)"
        }
    }
}
