#!/bin/bash
#
# oc-mirror wrapper with retry logic for network failures
# Runs each version (418, 419, 420) with individual retry logic
# Returns 0 only if all mirrors succeed, 1 if any fail after 3 retries
#

set -o pipefail

MAX_RETRIES=3
RETRY_DELAY=300  # 5 minutes between retries
REGISTRY="$1"

# Function to run a single oc-mirror operation with retry logic
run_mirror_with_retry() {
    local version=$1
    local attempt=1
    local success=false

    while [ $attempt -le $MAX_RETRIES ] && [ "$success" = false ]; do
        echo "=== Mirroring OCP ${version} (attempt ${attempt}/${MAX_RETRIES}) ==="

        # Clear log for this version before each attempt
        if [ $attempt -gt 1 ]; then
            echo "Clearing previous attempt log for ${version}..."
            > /root/mirroring-${version}.log
        fi

        # Run oc-mirror
        oc-mirror --parallel-images=10 --v2 \
            --workspace file:///root/workspace-${version}/ \
            --config=/root/imageset-mirror-core-${version}.yaml \
            docker://${REGISTRY} \
            2>&1 | tee -a /root/mirroring-${version}.log

        # Check for errors (matches original async check pattern)
        if grep -q 'some errors occurred during the mirroring' /root/mirroring-${version}.log; then
            echo "ERROR: oc-mirror ${version} - some errors occurred during the mirroring"
            attempt=$((attempt + 1))
            if [ $attempt -le $MAX_RETRIES ]; then
                echo "RETRY: Waiting ${RETRY_DELAY} seconds before retrying ${version}..."
                sleep $RETRY_DELAY
            fi
        else
            echo "SUCCESS: oc-mirror ${version} completed without errors"
            success=true
        fi
    done

    if [ "$success" = false ]; then
        echo "FAILED: oc-mirror ${version} failed after ${MAX_RETRIES} attempts"
        return 1
    fi

    return 0
}

# Main execution - run each version with individual retry logic
all_success=true

run_mirror_with_retry "418" || all_success=false
run_mirror_with_retry "419" || all_success=false
run_mirror_with_retry "420" || all_success=false

if [ "$all_success" = true ]; then
    echo "=== SUCCESS: All oc-mirror operations completed without errors ==="
    exit 0
else
    echo "=== FAILED: One or more oc-mirror operations failed after retries ==="
    exit 1
fi
