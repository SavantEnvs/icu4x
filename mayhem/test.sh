#!/usr/bin/env bash
#
# mayhem/test.sh — the BEHAVIORAL oracle for the icu4x integration. Runs the
# dynamically linked /mayhem/kat-probe (built by mayhem/build.sh) and asserts its
# exact stdout against known-answer values lifted from icu_calendar's own doctests
# (components/calendar/src/{lib,options,duration}.rs) — not exit-code-only, not a
# libFuzzer marker, not `cargo test` (whose harness binary is the forbidden
# statically-linked-runner oracle shape, see docs/netnew-worker-prompt.md §4).
#
# Every assertion below is UNCONDITIONAL: a missing binary or a missing/wrong line
# is a hard failure, never a skipped check — a neutered ("exit(0) before doing
# anything") binary produces NONE of these lines, so this fails loudly exactly as
# required by verify-repo's sabotage check.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

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

KAT_BIN="/mayhem/kat-probe"
if [ ! -x "$KAT_BIN" ]; then
  echo "test.sh: $KAT_BIN missing or not executable — hard failure (never a skip)" >&2
  emit_ctrf "icu4x-kat" 0 1
  exit 1
fi

out="$("$KAT_BIN" 2>&1)"
rc=$?
echo "$out"

# Each check is a (name, exact expected line) pair. `grep -qF` on the raw stdout —
# a sabotaged/neutered binary that _exit(0)s before main's body runs prints NONE of
# these, so every check fails, exactly as required.
declare -a NAMES=(
  "construction_weekday"
  "construction_era_year"
  "add_overflow_constrain"
  "until_days_default"
  "until_not_negative"
  "all_pass_marker"
)
declare -a EXPECT=(
  "KAT1_WEEKDAY=Wednesday"
  "KAT1_ERA_YEAR=1992"
  "KAT2_ADDED_YMD=2025-11-30"
  "KAT3_DIFF_DAYS=410"
  "KAT3_DIFF_IS_NEGATIVE=false"
  "KAT_ALL_PASS"
)

passed=0
failed=0
for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  expect="${EXPECT[$i]}"
  if printf '%s' "$out" | grep -qF -- "$expect"; then
    echo "PASS: $name ($expect)"
    passed=$((passed + 1))
  else
    echo "FAIL: $name — expected line '$expect' not found in kat-probe output" >&2
    failed=$((failed + 1))
  fi
done

# Belt-and-suspenders: a nonzero exit with no explicit FAIL line above (e.g. killed
# by a signal, or sabotage _exit(0) racing an unrelated partial write) must still
# count as a failure, not a silent pass.
if [ "$rc" -ne 0 ] && ! printf '%s' "$out" | grep -qF "KAT_SOME_FAIL"; then
  echo "test.sh: kat-probe exited $rc without a clean KAT_SOME_FAIL — treating as failure" >&2
  failed=$((failed + 1))
fi

emit_ctrf "icu4x-kat" "$passed" "$failed"
