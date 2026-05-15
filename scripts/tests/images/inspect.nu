# inspect-one-image unit tests.
# Run: nu scripts/tests/images/inspect.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/images/inspect.nu [inspect-one-image]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def test-inspect-handles-empty-ref [] {
    test-log "\n[test-inspect-handles-empty-ref]"
    let r = (inspect-one-image "")
    [(assert-null $r "empty ref returns null")]
}

def test-inspect-handles-missing-image [] {
    test-log "\n[test-inspect-handles-missing-image]"
    let r = (inspect-one-image "definitely-does-not-exist-12345:nope")
    [(assert-null $r "missing image returns null")]
}

# Skips gracefully when docker is absent or hello-world not pulled.
def test-inspect-fields-present-when-docker-available [] {
    test-log "\n[test-inspect-fields-present-when-docker-available]"
    let docker_check = (try {
        ^docker version | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: ""}
    })
    if $docker_check.exit_code != 0 {
        test-log "  skip: no docker daemon available"
        return [PASS]
    }
    let img_check = (try {
        ^docker image inspect hello-world:latest | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $img_check.exit_code != 0 {
        test-log "  skip: hello-world:latest not present locally"
        return [PASS]
    }
    let r = (inspect-one-image "hello-world:latest")
    let cols = ($r | columns)
    [
        (assert-list-contains $cols "local_image_id" "has local_image_id column")
        (assert-list-contains $cols "repo_digests" "has repo_digests column")
    ]
}

def main [] {
    test-log "=== images/inspect Tests ==="
    let results = (
        (test-inspect-handles-empty-ref)
        | append (test-inspect-handles-missing-image)
        | append (test-inspect-fields-present-when-docker-available)
    ) | flatten
    run-suite "images/inspect" $SUITE_PATH $results
}
