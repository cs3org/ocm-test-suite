# Shared value predicates.

export def is-record [value: any] {
    ($value | describe | str starts-with "record")
}
