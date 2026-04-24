#!/bin/bash

FAILED=()

check() {
    LABEL=$1
    shift
    echo -e "\n🔍 Testing: ${LABEL}"
    if "$@"; then
        echo "✅ Passed: ${LABEL}"
        return 0
    else
        echo "❌ Failed: ${LABEL}"
        FAILED+=("${LABEL}")
        return 1
    fi
}

reportResults() {
    echo ""
    if [ ${#FAILED[@]} -ne 0 ]; then
        echo "❌ ${#FAILED[@]} test(s) failed:"
        for f in "${FAILED[@]}"; do
            echo "  - $f"
        done
        exit 1
    else
        echo "✅ All tests passed!"
        exit 0
    fi
}
