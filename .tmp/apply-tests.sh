#!/bin/bash
# Apply incremental test files to the current commit
# Usage: apply-tests.sh <version>
# Where version is 04, 05, 06, ..., 11

set -e
VERSION="$1"
TMPDIR=".tmp"
TESTS_DIR="contracts/src/tests"

# Ensure tests directory exists
mkdir -p "$TESTS_DIR"

# Ensure lib.cairo has the tests module declaration
if ! grep -q 'mod tests;' contracts/src/lib.cairo; then
    echo "" >> contracts/src/lib.cairo
    echo "#[cfg(test)]" >> contracts/src/lib.cairo
    echo "mod tests;" >> contracts/src/lib.cairo
fi

# Copy test files based on version
case "$VERSION" in
    04)
        cp "$TMPDIR/04-test_token.cairo" "$TESTS_DIR/test_token.cairo"
        cp "$TMPDIR/04-tests.cairo" "$TESTS_DIR.cairo"
        ;;
    05)
        cp "$TMPDIR/05-test_token.cairo" "$TESTS_DIR/test_token.cairo"
        # tests.cairo stays same (just mod test_token;)
        ;;
    06)
        cp "$TMPDIR/06-test_bridge_core.cairo" "$TESTS_DIR/test_bridge_core.cairo"
        cp "$TMPDIR/06-tests.cairo" "$TESTS_DIR.cairo"
        ;;
    07)
        cp "$TMPDIR/07-test_bridge_core.cairo" "$TESTS_DIR/test_bridge_core.cairo"
        ;;
    08)
        cp "$TMPDIR/08-test_bridge_core.cairo" "$TESTS_DIR/test_bridge_core.cairo"
        ;;
    09)
        cp "$TMPDIR/09-test_bridge_core.cairo" "$TESTS_DIR/test_bridge_core.cairo"
        ;;
    10)
        cp "$TMPDIR/10-test_bridge_core.cairo" "$TESTS_DIR/test_bridge_core.cairo"
        ;;
    11)
        cp "$TMPDIR/11-test_bridge_registry.cairo" "$TESTS_DIR/test_bridge_registry.cairo"
        cp "$TMPDIR/11-tests.cairo" "$TESTS_DIR.cairo"
        ;;
    *)
        echo "Unknown version: $VERSION"
        exit 1
        ;;
esac

# Stage and amend
git add contracts/src/lib.cairo contracts/src/tests.cairo "$TESTS_DIR/" 2>/dev/null || true
git add contracts/src/tests/ 2>/dev/null || true
git commit --amend --no-edit
