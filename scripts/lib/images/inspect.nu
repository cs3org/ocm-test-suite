# Best-effort docker image inspect helpers.
# Returns {local_image_id, repo_digests} or null on any failure.

# Inspect one docker image ref. Returns {local_image_id, repo_digests} or null.
export def inspect-one-image [ref: string] {
    if ($ref | is-empty) { return null }
    let result = (try {
        ^docker image inspect $ref | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: ""}
    })
    if $result.exit_code != 0 { return null }
    let parsed = (try { $result.stdout | from json } catch { return null })
    if ($parsed | is-empty) { return null }
    let info = ($parsed | first)
    {
        local_image_id: ($info.Id? | default null),
        repo_digests: ($info.RepoDigests? | default []),
    }
}
