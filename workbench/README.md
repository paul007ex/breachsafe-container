<!-- SPDX-FileCopyrightText: 2026 BreachSAFE <https://www.breachsafe.io> -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# breachsafe-workbench

The BreachSAFE **scan-fleet** image: the pinned base toolchain plus an OSS
security scanner fleet, so a person or agent can "open it and run any scan"
without installing anything.

```
workbench = breachsafe-container (base toolchain) + scan fleet
```

> License: **PolyForm-Noncommercial-1.0.0** (source-available, non-commercial).
> BreachSAFE first-party infrastructure, not OSI open source. The bundled
> scanners keep their own upstream licenses.

## Base -> workbench layering

This image is `FROM` the pinned base image
(`ghcr.io/paul007ex/breachsafe-container:3.14-openssl3.5.7`). From the base it
inherits, and does **not** re-install:

- Python **3.14** and **OpenSSL 3.5.7 LTS** built from source at `/opt/openssl`
  (exposed via `OPENSSL_DIR` / `QUREDDY_OPENSSL` / `LD_LIBRARY_PATH`).
- `uv`, `ruff`, `mypy`, `reuse` (PyPI, pinned).
- `gitleaks`, `trivy`, `cyclonedx`, `cosign`, `just` (release binaries, pinned).

On top of that it adds the scan fleet below and drops back to the non-root
`breachsafe` user (uid/gid 1000). `trivy` and `gitleaks` are **not** duplicated;
they already live in the base.

## What's in it (the scan fleet)

Tool choices track `breachsafe-common/reference/CATALOG.md` (the AppSec/SCA/DAST
fleet + crypto/TLS + recon lanes).

| Lane | Tool | Version | Installed via | Smoke check |
|---|---|---|---|---|
| SAST | semgrep | 1.174.0 | pip (PyPI) | `semgrep --version` |
| SAST (python) | bandit | 1.9.4 | pip (PyPI) | `bandit --version` |
| Secrets | trufflehog | 3.97.0 | release tarball, per-arch SHA256 | `trufflehog --version` |
| Secrets | detect-secrets | 1.5.0 | pip (PyPI) | `detect-secrets --version` |
| SCA / vuln | grype | 0.117.0 | release tarball, per-arch SHA256 | `grype version` |
| SBOM | syft | 1.51.0 | release tarball, per-arch SHA256 | `syft version` |
| SCA / vuln | osv-scanner | 2.5.1 | release binary, per-arch SHA256 | `osv-scanner --version` |
| Crypto / TLS | sslyze | 6.3.1 | pip (PyPI) | `sslyze --help` (see note) |
| Crypto / TLS | testssl.sh | 3.2.4 | git clone, pinned tag | `testssl.sh --version` |
| Crypto / SSH | ssh-audit | 3.9.0 | pip (PyPI) | `ssh-audit -h` |
| Recon / network | nmap | 7.93 (Debian) | apt (bookworm) | `nmap --version` |
| Recon / DAST | nuclei | 3.11.1 | release zip, per-arch SHA256 | `nuclei -version` |

Notes:

- **sslyze has no `--version` flag.** The version prints in the `sslyze --help`
  header (`SSLyze version 6.3.1`). Every other tool takes a real version flag.
- **testssl.sh uses the base's OpenSSL 3.5.7** (found on `PATH` via
  `/opt/openssl/bin`), so its cipher/protocol coverage matches the rest of BQP.
- **nuclei templates are NOT baked in.** Run `nuclei -update-templates` at
  runtime to fetch/refresh them; they are written under `$HOME/.config/nuclei`
  (writable by the non-root user). Baking them would stale the image and bloat
  it; updating at runtime keeps the template set current.
- **`nmap` is not independently version-pinned** — it comes from the Debian
  bookworm repo (apt version pins are fragile across point releases). Everything
  else is pinned by exact version, and release binaries are SHA256-verified per
  architecture at build time.

### Deliberately excluded

- **masscan** — needs raw-socket (`CAP_NET_RAW`) privileges; excluded so the
  image stays usable unprivileged / non-root. Use `nmap` for host/port work.
- **trivy**, **gitleaks** — already in the base image; not duplicated here.

## How to run

Mount your source read-only-ish and invoke any tool. The default `CMD` is
`/bin/bash`, so `docker run -it ... breachsafe-workbench` drops you into a shell
with the whole fleet on `PATH`.

```bash
# SAST over a checked-out repo
docker run --rm -v "$PWD:/src" breachsafe-workbench semgrep --config auto /src

# Secret scan
docker run --rm -v "$PWD:/src" breachsafe-workbench trufflehog filesystem /src

# SBOM then vuln scan
docker run --rm -v "$PWD:/src" breachsafe-workbench syft dir:/src -o cyclonedx-json
docker run --rm -v "$PWD:/src" breachsafe-workbench grype dir:/src

# Dependency vulns
docker run --rm -v "$PWD:/src" breachsafe-workbench osv-scanner scan --recursive /src

# TLS posture of a live endpoint
docker run --rm breachsafe-workbench sslyze example.com:443
docker run --rm breachsafe-workbench testssl.sh --quiet example.com

# SSH posture
docker run --rm breachsafe-workbench ssh-audit example.com

# Recon
docker run --rm breachsafe-workbench nmap -sV example.com
docker run --rm breachsafe-workbench sh -c 'nuclei -update-templates && nuclei -u https://example.com'

# Interactive shell with the full fleet
docker run --rm -it -v "$PWD:/src" breachsafe-workbench
```

## Tag scheme

```
ghcr.io/paul007ex/breachsafe-workbench:<ver>
ghcr.io/paul007ex/breachsafe-workbench:0.1.0                  # fleet version (primary)
ghcr.io/paul007ex/breachsafe-workbench:3.14-openssl3.5.7      # base-aligned alias
ghcr.io/paul007ex/breachsafe-workbench:latest                 # moving alias
```

`<ver>` is the workbench fleet version (its own line, independent of the base
toolchain version). The base-aligned tag records which base toolchain the image
was built on. Multi-arch: `linux/amd64` + `linux/arm64`. Consumers should
**digest-pin** in CI.

## Build

Build locally for the host arch, layering on a locally-built base:

```bash
docker build -t breachsafe-workbench:test \
  --build-arg BASE=breachsafe-container:test \
  ./workbench
```

Or against the published base (the `BASE` ARG default):

```bash
docker build -t breachsafe-workbench:test ./workbench
```

CI (`.github/workflows/build-workbench.yml`) builds multi-arch and pushes to
GHCR with `--provenance=true --sbom=true`, SHA-pinned actions, and least-privilege
permissions. It first verifies the base image is published, then builds on it.

## Bumping versions

Edit the pinned `ARG` values in the `Dockerfile`. For release binaries, refresh
the per-arch `*_SHA256_*` sums from each project's published checksums
(osv-scanner ships no checksums file, so compute its sum from the release asset).
The `Dockerfile` header carries a full "Pinned versions" block; keep it in sync.

## License

PolyForm-Noncommercial-1.0.0. See the repo root [`LICENSE`](../LICENSE) /
[`LICENSES/`](../LICENSES/); REUSE metadata in [`REUSE.toml`](../REUSE.toml).
