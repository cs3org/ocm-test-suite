#!/usr/bin/env bash

SCENARIO_DIR=$1
TEST_DIR=./k8s/tests

scenarios=("$(find ${TEST_DIR} -name 'deploy.sh' -type f -exec dirname {} \;)")

# If no deploy.sh found, exit
if [ ${#scenarios[@]} -eq 0 ]; then
    echo "🤷🏽‍♂️  No test scenarios found."
    exit 1
fi

options=()
for d in $scenarios; do
    options+=("$d ($(head -n 2 "$d/NOTES.txt" | tail -1))")
done

if [ -z "$SCENARIO_DIR" ]; then
    # Prompt user to select a directory
    echo "📝  Select a test scenario to deploy:"
    select opt in "${options[@]}"; do
        if [[ "$REPLY" =~ ^[0-9]+$ ]]; then
            dir=$(echo "$opt" | cut -d " " -f1)

            echo
            echo "🚀  Deploying test scenario" $(echo "$opt" | cut -d ' ' -f1)
            echo
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done

    SCENARIO_DIR=$dir
fi

echo
cd "$SCENARIO_DIR" && ./deploy.sh && (
    echo '✅  Scenario successfully Deployed!' && (
        test -f NOTES.txt && cat NOTES.txt || echo
    )
) || echo '❌  Failed to deploy'
