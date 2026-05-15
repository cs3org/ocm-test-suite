# Print a suite ID. If --override is a non-empty string, prints it unchanged.
# Otherwise generates a new unique suite ID.

use ../../lib/suite/index.nu [new-suite-id]

def main [
    --override: string = "",    # pass-through a non-empty suite_id unchanged
] {
    let id = if not ($override | is-empty) {
        $override
    } else {
        new-suite-id
    }
    print $id
}
