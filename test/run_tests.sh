#!/bin/sh
set -eu

FAILED=0
PASSED=0

assert_equals() {
    expected="$1"
    actual="$2"
    name="$3"
    if [ "$expected" = "$actual" ]; then
        echo "[PASS] $name"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $name: Expected '$expected', got '$actual'"
        FAILED=$((FAILED + 1))
    fi
}

echo "Running test suite..."

# Test 1: Verify ddns.sh exists and is executable
if [ -x "./ddns.sh" ]; then
    echo "[PASS] ddns.sh exists and is executable"
    PASSED=$((PASSED + 1))
else
    echo "[FAIL] ddns.sh exists and is executable"
    FAILED=$((FAILED + 1))
fi

# Test 2: Help output
output=$(./ddns.sh --help 2>&1 || true)
case "$output" in
    *"Usage:"*) assert_equals "1" "1" "Help flag output" ;;
    *) assert_equals "Usage: ..." "$output" "Help flag output" ;;
esac

# Test 3: Parameter parsing via environment
env_output=$(DDNS_DOMAIN="test.com" DDNS_PROVIDER="duckdns" ./ddns.sh --dry-run 2>&1 || true)
case "$env_output" in
    *"domain=test.com"*provider=duckdns*) assert_equals "1" "1" "ENV parameter parsing" ;;
    *) assert_equals "domain=test.com provider=duckdns" "$env_output" "ENV parameter parsing" ;;
esac

# Test 4: CLI flag overrides ENV
cli_output=$(DDNS_DOMAIN="env.com" ./ddns.sh -d "cli.com" -p duckdns --dry-run 2>&1 || true)
case "$cli_output" in
    *"domain=cli.com"*provider=duckdns*) assert_equals "1" "1" "CLI parameter override" ;;
    *) assert_equals "domain=cli.com provider=duckdns" "$cli_output" "CLI parameter override" ;;
esac

# Test 5: Cache file creation and check
CACHE_TEST_DOMAIN="cache-test.org"
CACHE_FILE="/tmp/ddns_${CACHE_TEST_DOMAIN}_A.cache"
rm -f "$CACHE_FILE"

# Mock IP test run
./ddns.sh -d "$CACHE_TEST_DOMAIN" -p duckdns -t mocktoken --test-ip "1.2.3.4" --dry-run-update > /dev/null 2>&1 || true

if [ -f "$CACHE_FILE" ]; then
    cached_val=$(cat "$CACHE_FILE")
    assert_equals "1.2.3.4" "$cached_val" "IP cache written correctly"
else
    assert_equals "file exists" "file missing" "IP cache written correctly"
fi

rm -f "$CACHE_FILE"

# Test 6: POSIX JSON Record ID Extraction test
sample_json='{"success":true,"result":[{"id":"rec_123456789","name":"home.example.com","type":"A","content":"1.1.1.1"}]}'
extracted_id=$(echo "$sample_json" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
assert_equals "rec_123456789" "$extracted_id" "Regex JSON ID extraction"

# Test 7: Installation test to local temporary directory
TMP_INSTALL_DIR="/tmp/ddns_test_install"
rm -rf "$TMP_INSTALL_DIR"
INSTALL_DIR="$TMP_INSTALL_DIR" ./install.sh > /dev/null 2>&1

if [ -x "${TMP_INSTALL_DIR}/nodex" ]; then
    assert_equals "1" "1" "Installer deploys executable"
else
    assert_equals "installed" "missing" "Installer deploys executable"
fi
rm -rf "$TMP_INSTALL_DIR"

echo "Summary: $PASSED passed, $FAILED failed"
if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
