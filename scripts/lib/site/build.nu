# Astro site build runner.

# Run the Astro site build command, preferring bun over npm.
# Streams build output to the terminal (no capture).
export def run-site-build [site_dir: string] {
    let bun_ok = (try {
        (^bun --version | complete).exit_code == 0
    } catch { false })
    let cmd = if $bun_ok { "bun" } else { "npm" }
    print --stderr $"Building with ($cmd) in ($site_dir)..."
    cd $site_dir
    if $bun_ok {
        ^bun run build
    } else {
        ^npm run build
    }
    if $env.LAST_EXIT_CODE != 0 {
        error make {msg: "Site build failed. See output above."}
    }
}
