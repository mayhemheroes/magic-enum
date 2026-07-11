#!/usr/bin/env bash
#
# magic-enum/mayhem/build.sh — build Neargye/magic_enum's OSS-Fuzz harness as a sanitized
# libFuzzer target (+ a standalone run-once reproducer), AND magic_enum's OWN meson test
# suite (doctest) so mayhem/test.sh only has to RUN it.
#
# magic_enum is a HEADER-ONLY, compile-time enum-reflection library (include/magic_enum/*.hpp).
# There is no library object to instrument — the fuzzed surface is the RUNTIME path of the
# reflection API exercised by the harness:
#   magic_enum_fuzzer — feeds attacker bytes (via FuzzedDataProvider) to the string/integer
#                       enum-lookup API: enum_cast<E>(string), enum_cast<E>(int),
#                       enum_contains, enum_names/enum_values/enum_entries, and the
#                       magic_enum::containers set/bitset built over a FuzzEnum.
# The input is NOT a file format — it is the raw byte stream FuzzedDataProvider slices into
# the lookup keys. So we compile the harness itself with $SANITIZER_FLAGS (ASan+UBSan,
# halting); since the library is header-only it is instrumented along with the harness TU.
#
# Build contract comes from the org base ENV (CC/CXX/SANITIZER_FLAGS/LIB_FUZZING_ENGINE/SRC).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) for SANITIZER_FLAGS so an explicit empty --build-arg builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS: DWARF ≤ 3 so Mayhem's triage can read symbols (clang-19 plain -g emits DWARF-5).
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

cd "$SRC"

HARNESS_DIR="$SRC/mayhem/harnesses"
# Headers live in include/magic_enum/ ; the harness #includes <magic_enum.hpp> + <magic_enum_containers.hpp>.
# Bundle a copy of FuzzedDataProvider.h in mayhem/harnesses so the build never depends on it
# being on the default clang include path.
INC="-I$SRC/include/magic_enum -I$HARNESS_DIR"
STD="-std=c++17"

# ── 1) libFuzzer target -> /mayhem/magic_enum_fuzzer ───────────────────────────────────────────
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $STD $INC \
    "$HARNESS_DIR/magic_enum_fuzzer.cc" $LIB_FUZZING_ENGINE -lpthread \
    -o "/mayhem/magic_enum_fuzzer"

# ── 2) standalone run-once reproducer (no libFuzzer runtime) -> /mayhem/magic_enum_fuzzer-standalone ─
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$HARNESS_DIR/standalone_main.c" -o "$SRC/mayhem-build-standalone_main.o" 2>/dev/null \
  || { mkdir -p "$SRC/mayhem-build"; $CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$HARNESS_DIR/standalone_main.c" -o "$SRC/mayhem-build/standalone_main.o"; }
SMAIN="$SRC/mayhem-build-standalone_main.o"; [ -f "$SMAIN" ] || SMAIN="$SRC/mayhem-build/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $STD $INC \
    "$HARNESS_DIR/magic_enum_fuzzer.cc" "$SMAIN" -lpthread \
    -o "/mayhem/magic_enum_fuzzer-standalone"

echo "built magic_enum_fuzzer (+ standalone)"

# ── 3) Behavioral oracle binary -> /mayhem/oracle_check ────────────────────────────────────────
# A standalone program that calls the reflection API with KNOWN enum values and PRINTS the results.
# test.sh runs it and greps for expected strings; a no-op/exit(0) patch yields empty output → FAIL.
$CXX $DEBUG_FLAGS $STD $INC \
    "$HARNESS_DIR/oracle_check.cc" \
    -o "/mayhem/oracle_check"
echo "built oracle_check"

# ── 5) Build magic_enum's OWN meson test suite (doctest) with NORMAL flags in a clean tree so
#       mayhem/test.sh only RUNS it. The suite asserts the reflection results against the doctest
#       expectations — a no-op/exit(0) patch cannot pass. (meson default cpp_std=c++17.) ─────────
if command -v meson >/dev/null 2>&1; then
  env -u CFLAGS -u CXXFLAGS -u SANITIZER_FLAGS \
    meson setup --reconfigure "$SRC/mayhem-tests" "$SRC" \
    || env -u CFLAGS -u CXXFLAGS -u SANITIZER_FLAGS \
       meson setup "$SRC/mayhem-tests" "$SRC"
  # The test executables are build_by_default:false in test/meson.build (names underscorified from
  # 'basic test'/'flags test'). Build them explicitly now so test.sh can run them; fall back to a
  # plain compile if the target names ever change.
  env -u CFLAGS -u CXXFLAGS -u SANITIZER_FLAGS \
    meson compile -C "$SRC/mayhem-tests" -j"$MAYHEM_JOBS" basic_test flags_test \
    || env -u CFLAGS -u CXXFLAGS -u SANITIZER_FLAGS \
       meson compile -C "$SRC/mayhem-tests" -j"$MAYHEM_JOBS"
  echo "built magic_enum meson test suite in mayhem-tests/"
else
  echo "WARNING: meson not found — test suite not built (mayhem/test.sh will fail loudly)" >&2
fi

echo "build.sh complete:"
ls -la /mayhem/magic_enum_fuzzer /mayhem/magic_enum_fuzzer-standalone 2>&1 || true
