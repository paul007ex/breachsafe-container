<!-- SPDX-FileCopyrightText: 2026 BreachSAFE <https://www.breachsafe.io> -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# breachsafe-container

The pinned BreachSAFE toolchain image: one reproducible environment for **CI runtime**
and **local dev (devcontainer)**. CI stops rebuilding OpenSSL 3.5 from source on every
run, and tool versions stop drifting per repo. Implements §4.2 of the scaffold design
spec, `docs/specs/2026-08-22-breachsafe-repo-design.md` in
[`breachsafe-common`](https://github.com/paul007ex/breachsafe-common).

> The standalone `breachsafe-repo` repository this originally referenced was archived on
> 2026-08-22; its copier template now lives at `breachsafe-common/scaffold/`.

> License: **PolyForm-Noncommercial-1.0.0** (source-available, non-commercial). This is
> BreachSAFE first-party infrastructure, not OSI open source.

## What's pinned

| Component | Version | How it's installed | Verification |
|---|---|---|---|
| Python | **3.14** (3.14.7 at build) | base image `python:3.14-slim-bookworm` | base image digest-pinned |
| OpenSSL | **3.5.7 LTS** | built from source, `--prefix=/opt/openssl` | source tarball SHA256-checked |
| uv | 0.12.5 | pip (PyPI) | version-pinned |
| ruff | 0.16.4 | pip (PyPI) | version-pinned |
| mypy | 2.3.1 | pip (PyPI) | version-pinned |
| reuse | 6.2.0 (`[charset-normalizer]`) | pip (PyPI) | version-pinned |
| gitleaks | 8.30.1 | release tarball | per-arch SHA256-checked |
| cyclonedx-cli | 0.33.1 (binary: `cyclonedx`) | release binary | per-arch SHA256-checked |
| cosign | 3.1.3 | release binary | per-arch SHA256-checked |
| just | 1.58.0 | release tarball (musl) | per-arch SHA256-checked |

Notes:
- **Python 3.14 only** — no 3.12 fallback (design §4.2). **NOT** free-threaded (no-GIL).
- OpenSSL is built from source with a SHA256-verified tarball (same multi-stage pattern
  as `breachsafe/qureddy`). Base images and release binaries are pinned; base images by
  digest, binaries by per-architecture SHA256 checked at build time.
- `cyclonedx-cli` installs its self-contained .NET binary as `cyclonedx`. The image sets
  `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` so it runs on slim without libicu.

## OpenSSL environment

The from-source OpenSSL is exposed via env so consumers find it without guessing:

```
QUREDDY_OPENSSL=/opt/openssl/bin/openssl     # QuReddy convention
OPENSSL_DIR=/opt/openssl                      # Rust crates (crypto-rs/pki-rs) convention
OPENSSL_ROOT_DIR=/opt/openssl                 # CMake convention
LD_LIBRARY_PATH=/opt/openssl/lib64:/opt/openssl/lib
PATH=/opt/openssl/bin:/usr/local/bin:$PATH
```

Runs as the non-root user `breachsafe` (uid/gid 1000).

## Tag scheme

```
ghcr.io/paul007ex/breachsafe-container:<python>-openssl<openssl>
ghcr.io/paul007ex/breachsafe-container:3.14-openssl3.5.7   # primary
ghcr.io/paul007ex/breachsafe-container:latest              # moving alias
```

Multi-arch: `linux/amd64` + `linux/arm64`. Consumers should **digest-pin** in CI.

## How repos consume it

### CI (`container:`)

Run every job inside the toolchain so OpenSSL/uv/gitleaks are already present:

```yaml
jobs:
  gates:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/paul007ex/breachsafe-container:3.14-openssl3.5.7
    steps:
      - uses: actions/checkout@<sha> # v5
      - run: uv sync --locked --extra dev
      - run: just gates
```

Digest-pin for reproducibility once published:
`image: ghcr.io/paul007ex/breachsafe-container@sha256:<digest>`.

### Local dev (devcontainer)

`.devcontainer/devcontainer.json` points at the same tag, so local dev matches CI
byte-for-byte. Open the folder in a devcontainer-aware editor and it pulls the image.

## Build and publish

`.github/workflows/build-and-push.yml` builds multi-arch and pushes to GHCR with
`--provenance=true --sbom=true`, SHA-pinned actions, and
`permissions: { packages: write, contents: read, id-token: write }`. Triggered on
`main` (Dockerfile/workflow changes) or manually via `workflow_dispatch`.

Build locally for the host arch:

```
docker build -t breachsafe-container:test .
docker run --rm breachsafe-container:test python3 --version
```

## Bumping versions

Edit the pinned `ARG` values in the `Dockerfile` (and the per-arch SHA256 sums for
release binaries), bump `PRIMARY_TAG` in the workflow and the tag references above, then
rebuild. Downstream repos pick up the change by updating their `container_tag`.

## License

PolyForm-Noncommercial-1.0.0. Full text in [`LICENSE`](./LICENSE) /
[`LICENSES/`](./LICENSES/). REUSE metadata in [`REUSE.toml`](./REUSE.toml).
