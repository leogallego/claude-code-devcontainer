#!/bin/bash
cd $(dirname "$0")
source test-utils/test-utils.sh

check "node is available" node --version
check "claude code is installed" claude --version
check "gh cli is available" gh --version
check "zsh is available" zsh --version
check "git-delta is available" delta --version
check "devcontainer env is set" [ "$DEVCONTAINER" = "true" ]

reportResults
