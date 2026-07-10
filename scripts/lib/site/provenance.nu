# Provenance block helpers used by the site-publish pipeline to stamp generated artifacts.

use ../time/utc.nu [utc-now]

# Input files hashed into the provenance block of every site output that derives from the matrix config + adapter capabilities.
export const SITE_PROVENANCE_SOURCES = [
    "config/matrix/defaults.nuon",
    "config/matrix/platforms.nuon",
    "config/matrix/capabilities.v1.nuon",
    "config/matrix/flows/contact-token.nuon",
    "config/matrix/flows/contact-wayf.nuon",
    "config/matrix/flows/login.nuon",
    "config/matrix/flows/share-with.nuon",
    "config/matrix/flows/webapp-share.nuon",
    "config/adapters/capabilities.v1.nuon",
]

# Hash a repo-relative source file and return a {path, sha256} record.
export def hash-source [path: string, ocmts_root: string] {
    if ($path | str starts-with "/") {
        error make {msg: $"hash-source: path must be repo-relative, got absolute path: ($path)"}
    }
    let abs = ($ocmts_root | path join $path)
    let sha = (open --raw $abs | hash sha256)
    {path: $path, sha256: $sha}
}

# Build a provenance block for one machine-written site output file.
# args keys: generator (string, repo-relative <path>#<func>),
#   producer ({name, version}), sources (list of repo-relative paths),
#   ocmts_root (absolute path to the OCMTS repo root).
export def build-provenance-block [args: record] {
    if ($args.generator | str starts-with "/") {
        error make {msg: $"build-provenance-block: generator must be repo-relative, got absolute path: ($args.generator)"}
    }
    for src in $args.sources {
        if ($src | str starts-with "/") {
            error make {msg: $"build-provenance-block: sources[] must be repo-relative, got absolute path: ($src)"}
        }
    }
    let generated_at = (utc-now)
    let hashed_sources = ($args.sources | each {|s| hash-source $s $args.ocmts_root})
    {
        schema_version: 1,
        generated_at: $generated_at,
        generator: $args.generator,
        producer: $args.producer,
        sources: $hashed_sources,
    }
}
