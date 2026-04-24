# Reusable test fixtures. Most suites need a temp directory with
# guaranteed cleanup; `with-tmp-dir` runs the closure with the temp
# path and removes it afterwards even on error.

export def with-tmp-dir [closure: closure]: nothing -> any {
    let tmp = (^mktemp -d | str trim)
    try {
        let result = (do $closure $tmp)
        ^rm -rf $tmp
        $result
    } catch {|err|
        ^rm -rf $tmp
        error make {msg: $err.msg}
    }
}
