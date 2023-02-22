#!/usr/bin/env bash

SCENARIO_DIR=$1
TEST_DIR=./k8s/tests

scenarios=("$(find ${TEST_DIR} -name 'deploy.sh' -type f -exec dirname {} \;)")

# If no deploy.sh found, exit
if [ ${#scenarios[@]} -eq 0 ]; then
    echo "🤷🏽‍♂️  No test scenarios found."
    exit 1
fi

if [ -z "$SCENARIO_DIR" ]; then
    # Prompt user to select a directory
    echo "📝  Select a test scenario to deploy:"
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
echo '🚀  Deploying test scenario' $(basename "$SCENARIO_DIR")
cd "$SCENARIO_DIR" && ./deploy.sh && (
    echo '✅  Successfully Deployed!'
    test -f "${SCENARIO_DIR}/NOTES.txt" && cat "${SCENARIO_DIR}/NOTES.txt" || echo
) || echo '❌  Failed to deploy'
