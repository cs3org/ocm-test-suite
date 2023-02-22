#!/usr/bin/env bash

SCENARIO_DIR=$1
TEST_DIR=./k8s/tests

scenarios=("$(find ${TEST_DIR} -name 'cleanup.sh' -type f -exec dirname {} \;)")

# If no cleanup.sh found, exit
if [ ${#scenarios[@]} -eq 0 ]; then
    echo "🤷🏽‍♂️  No test scenarios found."
    exit 1
fi

options=()
for d in $scenarios; do
    options+=("$d ($(head -n 2 "$d/NOTES.txt" | tail -1))")
done

# Prompt user to select a directory
if [ -z "$SCENARIO_DIR" ]; then
    echo "📝  Select a test scenario to uninstall:"
    select opt in "${options[@]}"; do
        if [[ "$REPLY" =~ ^[0-9]+$ ]]; then
            dir=$(echo "$opt" | cut -d " " -f1)

            echo
            echo "🚀  Uninstalling test scenario" $(echo "$opt" | cut -d ' ' -f1)
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
    SCENARIO_DIR=$dir
fi

cd "$SCENARIO_DIR" && ./cleanup.sh && (
    echo '✅  Unistalled successfully!'
) || echo '❌  Failed to uninstall'
