#!/usr/bin/env bash

SCENARIO_DIR=$1
TEST_DIR=./k8s/tests

scenarios=("$(find ${TEST_DIR} -name 'cleanup.sh' -type f -exec dirname {} \;)")

# If no cleanup.sh found, exit
if [ ${#scenarios[@]} -eq 0 ]; then
    echo "🤷🏽‍♂️  No test scenarios found."
    exit 1
fi

# Prompt user to select a directory
if [ -z "$SCENARIO_DIR" ]; then
    echo "📝  Select a test scenario to uninstall:"
    select dir in "${scenarios[@]}"; do
        if [[ "$REPLY" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
    SCENARIO_DIR=$dir
fi

echo
echo '🚀  Uninstalling test scenario' $(basename "$SCENARIO_DIR")
cd "$SCENARIO_DIR" && ./cleanup.sh && (
    echo '✅  Unistalled successfully!'
) || echo '❌  Failed to uninstall'
