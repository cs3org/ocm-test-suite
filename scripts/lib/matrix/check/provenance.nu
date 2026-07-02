# Provenance block validation for repos/ocm-web-site/public/*.v1.json.
# Returns {skipped: bool, violations: [{file, issue}]}.
# Skips gracefully when the sibling public dir does not exist.

const PROVENANCE_FILES = [
    "matrix-rules.v1.json",
    "matrix-not-in-scope.v1.json",
    "suite-manifest.v1.json",
]

# RFC3339 nanosecond pattern: YYYY-MM-DDThh:mm:ss.nnnnnnnnnZ
const GENERATED_AT_PATTERN = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}Z$'
const GENERATOR_PATTERN = '^scripts/lib/.*#[A-Za-z][\w-]*$'

export def check-provenance-blocks [ocmts_root: string] {
    # Sibling repo: repos/ocm-web-site/public/.
    let public_dir = ($ocmts_root | path dirname | path join "ocm-web-site/public")
    if not ($public_dir | path exists) {
        return {skipped: true, violations: []}
    }

    mut violations = []
    for $name in $PROVENANCE_FILES {
        let p = ($public_dir | path join $name)
        if not ($p | path exists) {
            $violations = ($violations | append {file: $name, issue: "file not readable"})
            continue
        }
        let parsed = try { open $p } catch {|_| null}
        if $parsed == null {
            $violations = ($violations | append {file: $name, issue: "invalid JSON"})
            continue
        }
        if not (($parsed | describe) | str starts-with "record") {
            $violations = ($violations | append {file: $name, issue: "top-level value must be an object"})
            continue
        }

        if ($parsed.schema_version? | default null) != 1 {
            $violations = ($violations | append {file: $name, issue: $"schema_version must be 1, got ($parsed.schema_version?)"})
        }

        let gen_at = ($parsed.generated_at? | default "")
        if (($gen_at | describe) != "string") or (not ($gen_at =~ $GENERATED_AT_PATTERN)) {
            $violations = ($violations | append {file: $name, issue: $"generated_at format invalid \(expected YYYY-MM-DDThh:mm:ss.nnnnnnnnnZ\), got \"($gen_at)\""})
        }

        let gen = ($parsed.generator? | default "")
        if (($gen | describe) != "string") or (not ($gen =~ $GENERATOR_PATTERN)) {
            $violations = ($violations | append {file: $name, issue: $"generator must match scripts/lib/...#FunctionName, got \"($gen)\""})
        }

        let producer = ($parsed.producer? | default null)
        if $producer == null or (not (($producer | describe) | str starts-with "record")) {
            $violations = ($violations | append {file: $name, issue: $"producer must be {name:\"ocmts\",version:\"0.1.0\"}, got ($producer)"})
        } else {
            let pkeys = ($producer | columns)
            let extras = ($pkeys | where {|k| ($k != "name") and ($k != "version")})
            if ($extras | length) > 0 {
                $violations = ($violations | append {file: $name, issue: $"producer has unexpected fields: (($extras | str join ', '))"})
            }
            if (($producer.name? | default "") != "ocmts") or (($producer.version? | default "") != "0.1.0") {
                $violations = ($violations | append {file: $name, issue: $"producer must be {name:\"ocmts\",version:\"0.1.0\"}, got ($producer)"})
            }
        }

        let sources = ($parsed.sources? | default null)
        let src_desc = (if $sources != null { $sources | describe } else { "null" })
        let src_is_seq = (($src_desc | str starts-with "list") or ($src_desc | str starts-with "table"))
        if $sources == null or (not $src_is_seq) {
            $violations = ($violations | append {file: $name, issue: "\"sources\" must be an array"})
        } else {
            mut src_idx = 0
            for $entry in $sources {
                let i = $src_idx
                if not (($entry | describe) | str starts-with "record") {
                    $violations = ($violations | append {file: $name, issue: $"sources[($i)] must be an object"})
                    $src_idx = $src_idx + 1
                    continue
                }
                let ekeys = ($entry | columns)
                let extras = ($ekeys | where {|k| ($k != "path") and ($k != "sha256")})
                if ($extras | length) > 0 {
                    $violations = ($violations | append {file: $name, issue: $"sources[($i)] has unexpected fields: (($extras | str join ', '))"})
                }
                let src_path = ($entry.path? | default "")
                if (($src_path | describe) != "string") or ($src_path | str starts-with "/") {
                    $violations = ($violations | append {file: $name, issue: $"sources[($i)].path must be repo-relative \(no leading /\), got \"($src_path)\""})
                }
                let sha = ($entry.sha256? | default "")
                # Check: 64 lowercase hex characters.
                let sha_valid = (
                    (($sha | describe) == "string")
                    and (($sha | str length) == 64)
                    and ($sha =~ '^[0-9a-f]{64}$')
                )
                if not $sha_valid {
                    $violations = ($violations | append {file: $name, issue: $"sources[($i)].sha256 must be 64 lowercase hex chars, got \"($sha)\""})
                }
                $src_idx = $src_idx + 1
            }
        }
    }

    {skipped: false, violations: $violations}
}
