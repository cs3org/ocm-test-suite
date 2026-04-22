# Local preview server for a built site directory.
# Prefers bun; falls back to npm. Blocks until Ctrl+C.

export def run-site-preview [
    site_dir: string,
    host: string,
    port: int,
] {
    if not ($site_dir | path exists) {
        error make {msg: $"site preview: site directory does not exist: ($site_dir)"}
    }
    let pkg_json = ($site_dir | path join "package.json")
    if not ($pkg_json | path exists) {
        error make {msg: $"site preview: no package.json in ($site_dir); is this a built site?"}
    }
    let bun_ok = (try {
        (^bun --version | complete).exit_code == 0
    } catch { false })
    let npm_ok = (try {
        (^npm --version | complete).exit_code == 0
    } catch { false })
    if not ($bun_ok or $npm_ok) {
        error make {msg: "site preview: neither bun nor npm is available on PATH"}
    }
    let runtime = if $bun_ok { "bun" } else { "npm" }
    let port_str = ($port | into string)
    print --stderr $"Starting site preview at http://($host):($port_str)/ from ($site_dir)"
    print --stderr $"Runtime: ($runtime). Press Ctrl+C to stop."
    cd $site_dir
    if $bun_ok {
        ^bun run preview --host $host --port $port_str
    } else {
        ^npm run preview -- --host $host --port $port_str
    }
    if $env.LAST_EXIT_CODE != 0 {
        error make {msg: "site preview: preview server exited non-zero"}
    }
}
