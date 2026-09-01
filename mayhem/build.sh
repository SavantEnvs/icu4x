#!/usr/bin/env bash
#
# mayhem/build.sh — build upstream's own cargo-fuzz targets from
# components/calendar/fuzz (construction, add, until) as sanitized libFuzzer
# binaries, then build the additive mayhem/kat/ known-answer-test probe that
# mayhem/test.sh uses as the behavioral oracle.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE. This
# first (online) build populates the cargo registry under $CARGO_HOME (pinned,
# $HOME-independent — see the Dockerfile). Do NOT pass --offline here; the rlenv
# runtime exports CARGO_NET_OFFLINE=true for the re-run.
#
# rust-toolchain.toml at the repo root pins stable "1.97.1" for any BARE cargo/rustc
# invocation in this tree — every cargo call below is explicit `+$RUST_TOOLCHAIN` so
# that file never silently hijacks our pinned nightly (docs/netnew-worker-prompt.md
# §6, "an upstream root rust-toolchain.toml hijacks EVERY bare cargo").
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

: "${RUST_TOOLCHAIN:=nightly-2025-09-05}"

cd "$SRC"

# --- 1. Fuzz targets: upstream's OWN components/calendar/fuzz, unmodified. -------
# It already has its own empty [workspace] table (excluded from the root workspace)
# and 3 pure, file-I/O-free targets that only exercise icu_calendar's Date API from
# Arbitrary-derived structured bytes (construction, add, until) — no upstream file
# is touched by this port.
FUZZ_DIR="components/calendar/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  name="$(basename "${f%.*}")"
  [ "$name" = "common" ] && continue   # shared helper module, not a [[bin]]
  FUZZ_TARGETS+=("$name")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

# ASan on by default; an explicitly EMPTY $SANITIZER_FLAGS disables it ($SANITIZER_FLAGS
# itself is a set of clang flags rustc can't consume directly, so translate its on/off
# intent instead of passing it through verbatim).
RUST_SAN="-Zsanitizer=address"
[ -z "${SANITIZER_FLAGS+x}" ] || [ -n "${SANITIZER_FLAGS}" ] || RUST_SAN=""

# DWARF <= 3 debug info for triage (SPEC §6.2 item 10).
RUST_DEBUG_FLAGS="${RUST_DEBUG_FLAGS:--Cdebuginfo=1 -Zdwarf-version=3}"
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing $RUST_SAN $RUST_DEBUG_FLAGS -Cforce-frame-pointers"

# libfuzzer-sys's build.rs, by default, compiles libFuzzer's own C++ sources from
# source via the `cc` crate — that build ignores CFLAGS/CXXFLAGS and links in
# DWARF-5 CUs from the base image's clang, which -Zdwarf-version=3 (a rustc-only
# flag) never touches. Point it at the base's prebuilt libFuzzer runtime instead
# (ships with no debug info) so libfuzzer-sys skips its own from-source compile.
export CUSTOM_LIBFUZZER_PATH=/usr/lib/llvm-19/lib/clang/19/lib/linux/libclang_rt.fuzzer-x86_64.a

# rustc's prebuilt sanitizer runtimes (compiler-rt) ship DWARF-5 CUs. The linker
# copies their debug sections into the final binary at LINK time, so they must be
# stripped BEFORE linking (stripping the binary afterward does nothing). Idempotent.
find "$RUSTUP_HOME"/toolchains/*/lib/rustlib/"$TRIPLE"/lib \
  -name 'librustc-*_rt.*.a' -exec objcopy --strip-debug {} \; 2>/dev/null || true

echo "=== cargo +$RUST_TOOLCHAIN fuzz build ($FUZZ_DIR, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo "+$RUST_TOOLCHAIN" fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

echo "build.sh: fuzz binaries:"
ls -la /mayhem/construction /mayhem/add /mayhem/until

# --- 2. mayhem/kat: additive known-answer-test probe (the test.sh oracle). -------
# Plain (non-sanitized, non-nightly-specific) build — a normal dynamically linked
# Rust binary, which is what makes it interceptable by verify-repo's sabotage
# LD_PRELOAD shim (docs/netnew-worker-prompt.md §4).
echo "=== cargo +$RUST_TOOLCHAIN build --release ($SRC/mayhem/kat) ==="
( cd mayhem/kat && RUSTFLAGS="" cargo "+$RUST_TOOLCHAIN" build --release --jobs "$MAYHEM_JOBS" )
kat_bin="$SRC/mayhem/kat/target/release/icu4x-mayhem-kat"
[ -x "$kat_bin" ] || { echo "ERROR: expected KAT binary not found at $kat_bin" >&2; exit 1; }
cp "$kat_bin" /mayhem/kat-probe
echo "built /mayhem/kat-probe"

# Regression guard: the probe MUST be dynamically linked (Rust's default on this
# glibc target) — a statically linked probe would silently defeat the sabotage
# check the way a `cargo test` runner does.
file /mayhem/kat-probe | tee /tmp/kat-probe-file.txt
grep -q 'dynamically linked' /tmp/kat-probe-file.txt || {
  echo "ERROR: /mayhem/kat-probe is not dynamically linked — oracle would survive sabotage" >&2
  exit 1
}

echo "build.sh complete"
