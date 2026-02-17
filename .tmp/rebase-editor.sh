#!/bin/bash
# GIT_SEQUENCE_EDITOR script for rebase
# Drops standalone test commits and adds exec steps after code commits

FILE="$1"

# Drop the standalone test commits
sed -i '/^pick 40280f7/d' "$FILE"
sed -i '/^pick ecc16a5/d' "$FILE"

# After commit 4 (4a488b7 - strkBTC token): add test_token + tests module
sed -i '/^pick 4a488b7/a exec .tmp/apply-tests.sh 04' "$FILE"

# After commit 5 (d83822b - zero-address/burn fix): update test_token
sed -i '/^pick d83822b/a exec .tmp/apply-tests.sh 05' "$FILE"

# After commit 6 (069666c - bridge core storage): add test_bridge_core
sed -i '/^pick 069666c/a exec .tmp/apply-tests.sh 06' "$FILE"

# After commit 7 (9d6299b - admin functions): update test_bridge_core
sed -i '/^pick 9d6299b/a exec .tmp/apply-tests.sh 07' "$FILE"

# After commit 8 (dde9712 - min withdrawal event): update test_bridge_core
sed -i '/^pick dde9712/a exec .tmp/apply-tests.sh 08' "$FILE"

# After commit 9 (3b2042f - deposit request): update test_bridge_core
sed -i '/^pick 3b2042f/a exec .tmp/apply-tests.sh 09' "$FILE"

# After commit 10 (65f722b - withdrawal/views): update test_bridge_core
sed -i '/^pick 65f722b/a exec .tmp/apply-tests.sh 10' "$FILE"

# After commit 11 (0e33ef1 - bridge registry): add test_bridge_registry
sed -i '/^pick 0e33ef1/a exec .tmp/apply-tests.sh 11' "$FILE"
