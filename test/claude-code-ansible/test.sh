#!/bin/bash
cd $(dirname "$0")
source ../test-utils/test-utils.sh

check "ansible is available" ansible --version
check "ansible-lint is available" ansible-lint --version
check "claude code is installed" claude --version
check "gh cli is available" gh --version
check "node is available" node --version
check "devcontainer env is set" [ "$DEVCONTAINER" = "true" ]

reportResults
