#!/usr/bin/env bash
#
# magic-enum/mayhem/test.sh — behavioral oracle for magic_enum.
#
# TWO-LAYER oracle (both layers must pass):
#
# Layer A — /mayhem/oracle_check (built by build.sh):
#   A small standalone program that calls enum_name/enum_cast/enum_count/enum_contains
#   with KNOWN enum values and PRINTS the results to stdout.  This script greps the
#   output for every expected value.  A no-op / exit(0) patch produces empty output,
#   so every grep fails and the oracle exits non-zero.
#
# Layer B — magic_enum's OWN meson/doctest suite (also built by build.sh):
#   The upstream test suite asserts compile-time reflection results (enum_name, enum_cast,
#   flags, ...) against expected values.  Neutering to exit(0) doesn't affect those
#   assertions; combined with Layer A they catch both: a patch that silently wrong-answers,
#   and a patch that suppresses output entirely.
#
# Emits CTRF; exits 0 iff no test failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

BUILDDIR="$SRC/mayhem-tests"
ORACLE="/mayhem/oracle_check"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASS=0
FAIL=0

# ── Layer A: behavioral output oracle ──────────────────────────────────────────────────────────
if [ ! -x "$ORACLE" ]; then
  echo "FAIL: $ORACLE missing or not executable — run mayhem/build.sh first" >&2
  emit_ctrf "magic-enum-oracle" 0 1 0; exit 2
fi

echo "=== Layer A: oracle_check behavioral output ==="
ORACLE_OUT="$("$ORACLE" 2>&1)"; oracle_rc=$?
echo "$ORACLE_OUT"

if [ "$oracle_rc" -ne 0 ]; then
  echo "FAIL: oracle_check exited $oracle_rc" >&2
  FAIL=$(( FAIL + 1 ))
fi

# Assert every expected key-value pair is present in the output.
# Format: "label=expected_value"
check_output() {
  local label="$1" expected="$2"
  if printf '%s\n' "$ORACLE_OUT" | grep -qF "$label=$expected"; then
    echo "PASS: $label=$expected"
    PASS=$(( PASS + 1 ))
  else
    echo "FAIL: expected '$label=$expected' in oracle output" >&2
    FAIL=$(( FAIL + 1 ))
  fi
}

check_output "name(RED)"    "RED"
check_output "name(GREEN)"  "GREEN"
check_output "name(BLUE)"   "BLUE"
check_output "cast(RED)"    "1"
check_output "cast(GREEN)"  "2"
check_output "cast(2)"      "GREEN"
check_output "count(Color)" "3"
check_output "count(Dir)"   "2"
check_output "contains(3)"  "yes"
check_output "contains(99)" "no"

# ── Layer B: meson/doctest upstream suite ──────────────────────────────────────────────────────
echo ""
echo "=== Layer B: meson test suite (doctest) ==="

if [ ! -d "$BUILDDIR" ]; then
  echo "FAIL: missing $BUILDDIR — run mayhem/build.sh first" >&2
  FAIL=$(( FAIL + 1 ))
elif ! command -v meson >/dev/null 2>&1; then
  echo "FAIL: meson not available — cannot run the test suite" >&2
  FAIL=$(( FAIL + 1 ))
else
  meson_out="$(env -u CFLAGS -u CXXFLAGS -u SANITIZER_FLAGS meson test -C "$BUILDDIR" --print-errorlogs 2>&1)"; mrc=$?
  echo "$meson_out"

  # meson summary block:  Ok: N / Expected Fail: N / Fail: N / Unexpected Pass: N / Skipped: N / Timeout: N
  MPASSED=$(printf '%s\n' "$meson_out" | sed -n 's/^Ok:[[:space:]]*\([0-9][0-9]*\).*/\1/p'             | tail -1)
  MEXPFAIL=$(printf '%s\n' "$meson_out" | sed -n 's/^Expected Fail:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | tail -1)
  MFAIL=$(printf '%s\n' "$meson_out" | sed -n 's/^Fail:[[:space:]]*\([0-9][0-9]*\).*/\1/p'             | tail -1)
  MUNEXP=$(printf '%s\n' "$meson_out" | sed -n 's/^Unexpected Pass:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | tail -1)
  MSKIP=$(printf '%s\n' "$meson_out" | sed -n 's/^Skipped:[[:space:]]*\([0-9][0-9]*\).*/\1/p'          | tail -1)
  MTIMEOUT=$(printf '%s\n' "$meson_out" | sed -n 's/^Timeout:[[:space:]]*\([0-9][0-9]*\).*/\1/p'       | tail -1)
  : "${MPASSED:=0}" "${MEXPFAIL:=0}" "${MFAIL:=0}" "${MUNEXP:=0}" "${MSKIP:=0}" "${MTIMEOUT:=0}"

  MPASS_TOTAL=$(( MPASSED + MEXPFAIL ))
  MFAIL_TOTAL=$(( MFAIL + MUNEXP + MTIMEOUT ))

  if [ "$(( MPASS_TOTAL + MFAIL_TOTAL + MSKIP ))" -eq 0 ]; then
    # No parseable summary — fall back to exit code
    if [ "$mrc" -eq 0 ]; then
      MPASS_TOTAL=1; MFAIL_TOTAL=0
    else
      MPASS_TOTAL=0; MFAIL_TOTAL=1
    fi
  fi

  PASS=$(( PASS + MPASS_TOTAL ))
  FAIL=$(( FAIL + MFAIL_TOTAL ))
  PASS=$(( PASS + MSKIP ))  # skipped go into other bucket below via emit_ctrf skipped arg
  PASS=$(( PASS - MSKIP ))  # undo — track skipped separately
fi

# ── Emit CTRF + final verdict ──────────────────────────────────────────────────────────────────
emit_ctrf "magic-enum-oracle" "$PASS" "$FAIL" "${MSKIP:-0}"
