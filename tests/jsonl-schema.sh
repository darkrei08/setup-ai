#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-jsonl.XXXXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

extract_function() {
    local name="$1"
    awk -v name="${name}" '
        $0 ~ "^" name "\\(\\) \\{" { capture = 1 }
        capture {
            line = $0
            opens = gsub(/\{/, "", line)
            closes = gsub(/\}/, "", line)
            depth += opens - closes
            print
            if (depth == 0) exit
        }
    ' "${ROOT}/setup-ai.sh"
}

PRODUCT_FUNCTIONS="${TEST_DIR}/product-functions.sh"
extract_function json_escape > "${PRODUCT_FUNCTIONS}"
extract_function json_log >> "${PRODUCT_FUNCTIONS}"
extract_function log_event >> "${PRODUCT_FUNCTIONS}"
extract_function record_step >> "${PRODUCT_FUNCTIONS}"

RUN_ID="20260921T000000Z"
JSONL_LOG="${TEST_DIR}/events.jsonl"
HUMAN_LOG="${TEST_DIR}/events.log"
VERBOSE=0
DEBUG=0
LAST_ERROR_STEP=""
LAST_ERROR_RC=0
CURRENT_MODULE="test"
DRY_RUN=0
STEP_INSTALLED=0
STEP_VERIFIED=0
STEP_SKIPPED=0
STEP_PLANNED=0
STEP_FAILED=0
STEP_FAIL_STEP=""
STEP_FAIL_RC=0
TMP_DIR="${TEST_DIR}"
source "${PRODUCT_FUNCTIONS}"

json_log "2026-09-21T00:00:00Z" "INFO" "test" "plain" "Plain event"
json_log "2026-09-21T00:00:01Z" "INFO" "test" "meta" "Event with metadata" 0 "pkg=demo"
json_log "2026-09-21T00:00:02Z" "WARN" "test" "failed" "Optional failure" 7 "pkg=demo" '{"modules":[],"steps":{"installed":0}}' 1 "continue"
json_log "2026-09-21T00:00:03Z" "ERROR" "test" "direct_failed" "Direct failure" 9 "path=demo"
log_event "ERROR" "test" "forwarded_unclassified" "Forwarded failure" 11 "path=forwarded"
log_event "WARN" "test" "forwarded_classified" "Forwarded optional failure" 12 "path=forwarded" "" 1 "continue"
record_step "test" "skipped" 13 "optional-step"
record_step "test" "failed" 14 "mandatory-step"

node --input-type=module - "${JSONL_LOG}" <<'NODE'
import assert from "node:assert/strict";
import fs from "node:fs";

const lines = fs.readFileSync(process.argv[2], "utf8").trim().split("\n");
const expectedKeys = [
  ["ts", "lvl", "ph", "ev", "msg", "rc", "rid", "pid"],
  ["ts", "lvl", "ph", "ev", "msg", "rc", "rid", "pid", "meta"],
  ["ts", "lvl", "ph", "ev", "msg", "rc", "rid", "pid", "meta", "summary", "err"],
  ["ts", "lvl", "ph", "ev", "msg", "rc", "rid", "pid", "meta", "err"],
  ["ts", "lvl", "ph", "ev", "msg", "rc", "rid", "pid", "meta", "err"],
  ["ts", "lvl", "ph", "ev", "msg", "rc", "rid", "pid", "meta", "err"],
  ["ts", "lvl", "ph", "ev", "msg", "rc", "rid", "pid", "meta", "err"],
  ["ts", "lvl", "ph", "ev", "msg", "rc", "rid", "pid", "meta", "err"],
];
const records = lines.map((line, index) => {
  const record = JSON.parse(line);
  assert.equal(typeof record, "object");
  assert.ok(record !== null && !Array.isArray(record));
  assert.deepEqual(Object.keys(record), expectedKeys[index]);
  return record;
});
assert.deepEqual(records[2].err, { rc: 7, optional: true, behavior: "continue" });
assert.deepEqual(records[3].err, { rc: 9 });
assert.equal(records[3].err.optional, undefined);
assert.equal(records[3].err.behavior, undefined);
assert.deepEqual(records[4].err, { rc: 11 });
assert.deepEqual(records[5].err, { rc: 12, optional: true, behavior: "continue" });
assert.deepEqual(records[6].err, { rc: 13 });
assert.deepEqual(records[7].err, { rc: 14 });
console.log(`PASS: ${records.length} JSONL records have the documented key order`);
NODE
