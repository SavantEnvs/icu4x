# syntax=docker/dockerfile:1.7
#
# icu4x commit-image Dockerfile — Rust cargo-fuzz on the org base (ghcr.io/savantenvs/base).
# Installs a pinned nightly + cargo-fuzz into a fixed, $HOME-independent prefix
# (/opt/toolchains/rust — SPEC §6.2 item 8). We fuzz upstream's OWN
# components/calendar/fuzz crate unmodified (it already ships 3 pure, file-I/O-free
# targets: construction, add, until — see mayhem/build.sh), plus an additive
# mayhem/kat/ probe crate that gives mayhem/test.sh a dynamically linked binary to
# assert known-answer values against (docs/netnew-worker-prompt.md §4: `cargo test`
# alone is a forbidden oracle shape here).
#
# NOTE: the repo root ships rust-toolchain.toml pinning stable "1.97.1" — every
# `cargo`/`rustc` invocation in mayhem/build.sh and mayhem/test.sh uses an explicit
# `+$RUST_TOOLCHAIN` so that file never silently hijacks our pinned nightly.

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH

ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

ARG RUST_TOOLCHAIN=nightly-2025-09-05
ARG CARGO_FUZZ_VERSION=0.12.0

ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:$PATH \
    RUST_TOOLCHAIN=${RUST_TOOLCHAIN}

USER root
RUN set -eux; \
    install -d /opt/toolchains/rust; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "$RUST_TOOLCHAIN"; \
    rustup component add rust-src --toolchain "$RUST_TOOLCHAIN"; \
    cargo install cargo-fuzz --version "$CARGO_FUZZ_VERSION" --locked; \
    chown -R 2000:2000 /opt/toolchains/rust; \
    rustc --version; cargo --version; cargo fuzz --version
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
