<!-- SPDX-FileCopyrightText: 2026 BreachSAFE <https://www.breachsafe.io> -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# breachsafe-container: agent guidance

Repository card for coding agents. Answer-first; the README (`README.md`) holds the full
detail this file points into.

## Contents

1. [What this repo is](#1-what-this-repo-is)
2. [The two pins live here](#2-the-two-pins-live-here)
3. [Tag scheme](#3-tag-scheme)
4. [Bumping a pinned version](#4-bumping-a-pinned-version)
5. [Build and smoke locally](#5-build-and-smoke-locally)
6. [Licence](#6-licence)
7. [Change procedure](#7-change-procedure)

## 1. What this repo is

The pinned BreachSAFE toolchain image: one reproducible environment for CI runtime and
local dev (devcontainer). It is what platform `~/claude/CLAUDE.md` §5 step 5 and §7 point
at. Remote is `paul007ex/breachsafe-container` (public). A bespoke Dockerfile in a
consumer repo that rebuilds OpenSSL or pins its own Python breaks the guarantee this image
exists to provide; fix the pin here instead.

The `Dockerfile` is multi-stage. Its last stage is `python`, so a bare `docker build .`
produces the Python image; the Rust image needs `--target rust`.

## 2. The two pins live here

| Component | Value | `Dockerfile` ARG |
|---|---|---|
| Python | 3.14 | `PYTHON_VERSION=3.14`, base `python:3.14-slim-bookworm` |
| OpenSSL | 3.5.7 LTS, built from source | `OPENSSL_VERSION=3.5.7` + `OPENSSL_SHA256=…` |
| Rust (rust lane only) | 1.98.0 | `RUST_VERSION=1.98.0`, base `rust:1.98.0-slim-bookworm` |

`OPENSSL_VERSION` is redeclared per stage (lines 25, 186, 266) and gated to `>=3.5.7,<3.6`
by an in-Dockerfile check that fails the build outside that range. The Rust base is
bookworm, not Alpine, and that is load-bearing: musl libcrypto cannot link a glibc `cargo`
build.

## 3. Tag scheme

Series tag, not a bare patch, so a patch bump needs no downstream edit:

```
ghcr.io/paul007ex/breachsafe-container:3.14-openssl3.5        # Python, primary
ghcr.io/paul007ex/breachsafe-container:rust1.98-openssl3.5    # Rust, primary
ghcr.io/paul007ex/breachsafe-container:latest                 # Python alias
```

`PRIMARY_TAG` (`3.14-openssl3.5`) and `RUST_PRIMARY_TAG` live in
`.github/workflows/build-and-push.yml`. Consumers should digest-pin in CI.

## 4. Bumping a pinned version

1. Edit the `ARG` in `Dockerfile` (every stage that redeclares it) and, for release
   binaries, the matching per-arch `*_SHA256_{amd64,arm64}`.
2. For OpenSSL, update both `OPENSSL_VERSION` and `OPENSSL_SHA256` against the release
   tarball's real digest.
3. Bump `PRIMARY_TAG` / `RUST_PRIMARY_TAG` in `build-and-push.yml` and the tag references
   in `README.md`.
4. Rebuild and smoke (§5). Downstream repos pick up the change via their `container_tag`.

Doc-only agents change nothing under §2 or §4 without a reviewed pin decision; both pins
are governed by platform `~/claude/CLAUDE.md` §7 (OpenSSL owner: Paul).

## 5. Build and smoke locally

No `Justfile` here; the gate is the image build itself.

```
docker build -t breachsafe-container:test .
docker run --rm breachsafe-container:test python3 --version
docker run --rm breachsafe-container:test openssl version
```

Expect Python 3.14.x and OpenSSL 3.5.7. The build already fails, rather than publishing,
if `openssl version` or `pkg-config --modversion libcrypto` disagrees with the pin.
Multi-arch publish is `.github/workflows/build-and-push.yml`; `build-workbench.yml` builds
the workbench image.

## 6. Licence

PolyForm-Noncommercial-1.0.0 on every first-party file (source-available, non-commercial,
not OSI open source). This repo is not an Apache carve-out. REUSE metadata in `REUSE.toml`
sets the default by `precedence = "aggregate"`; run `reuse lint` after touching headers.

## 7. Change procedure

Follow the platform ten-step loop in `~/claude/CLAUDE.md` §1: isolated worktree,
pressure-test, real build smoke, focused PR, merge only after hosted checks and artifact
identity pass. Report each step or mark it `NOT RUN` with a reason.
