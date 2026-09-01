# SPDX-FileCopyrightText: 2026 BreachSAFE <https://www.breachsafe.io>
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
#
# breachsafe-workbench — the scan-fleet image: base toolchain + an OSS security
# scan fleet, so a person/agent can "open it and run any scan."
#
#   workbench = breachsafe-container (base) + { SAST/secrets, SCA/SBOM/vuln,
#               crypto/TLS, recon } scanners.
#
# Layering: this image is FROM the pinned base toolchain image. It inherits
# Python 3.14, OpenSSL 3.5.7 LTS (/opt/openssl), uv/ruff/mypy/reuse, and the
# base release binaries (gitleaks, cyclonedx, cosign, just). It ADDS the
# scan fleet below. Tool choices are grounded in
# breachsafe-common/reference/CATALOG.md (AppSec/SCA/DAST fleet + crypto/TLS +
# recon lanes).
#
# ===========================================================================
# Pinned versions (documented; bump here + refresh the per-arch SHA256 sums)
# ---------------------------------------------------------------------------
#   Release binaries (SHA256-verified per arch in stage `fleet-fetch`):
#     trufflehog   3.97.0    SAST/secrets   (Go, tar.gz)
#     grype        0.117.0   SCA/vuln       (Go, tar.gz)
#     syft         1.51.0    SBOM           (Go, tar.gz)
#     osv-scanner  2.5.1     SCA/vuln       (Go, raw binary — upstream ships no
#                                            checksums file; SHA256 computed
#                                            from the pinned release asset)
#     nuclei       3.11.1    recon/DAST     (Go, zip)
#   Git-cloned, pinned tag:
#     testssl.sh   3.2.4     crypto/TLS     (bash; clone --branch v3.2.4)
#   pip (PyPI), version-pinned in the final stage:
#     semgrep      1.174.0   SAST
#     bandit       1.9.4     SAST (python)
#     detect-secrets 1.5.0   secrets
#     sslyze       6.3.1     crypto/TLS
#     ssh-audit    3.9.0     crypto/SSH
#   apt (Debian bookworm; version tracks the distro repo, not independently
#   pinned — apt version pins are fragile across point releases):
#     nmap                   recon/network
#
#   NOT included by design:
#     masscan — needs raw-socket (CAP_NET_RAW) privileges; excluded to keep the
#               image usable unprivileged/non-root. Use nmap for host/port work.
#     gitleaks — already present in the base image (secrets); trufflehog +
#               detect-secrets added here complement it.
# ===========================================================================

# Base image to layer on. Declared in global scope (before the first FROM) so it
# is usable by the final `FROM ${BASE}`. Override at build time:
#   --build-arg BASE=breachsafe-container:test
ARG BASE=ghcr.io/paul007ex/breachsafe-container:3.14-openssl3.5.7

# ---------------------------------------------------------------------------
# Stage: fleet-fetch — download + SHA256-verify pinned release binaries for the
# build arch, and clone testssl.sh at a pinned tag. TARGETARCH is amd64|arm64.
# Same verify-then-install pattern as the base image's tool-fetch stage.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS fleet-fetch

ARG TARGETARCH

ARG TRUFFLEHOG_VERSION=3.97.0
ARG GRYPE_VERSION=0.117.0
ARG SYFT_VERSION=1.51.0
ARG OSV_SCANNER_VERSION=2.5.1
ARG NUCLEI_VERSION=3.11.1
ARG TESTSSL_VERSION=3.2.4

# Per-arch SHA256 sums (from each project's published checksums; osv-scanner has
# no checksums file, so its sums are computed from the pinned release assets).
ARG TRUFFLEHOG_SHA256_amd64=62224de2f9dd7cd418800feb953760a302ed2f82a7c547fe1146a4874fb179e4
ARG TRUFFLEHOG_SHA256_arm64=f48f57e3d4343377865b1b64653f96d381d61a7792d89d026e85524732039fde
ARG GRYPE_SHA256_amd64=38525dab1e06f162ebaa02f94d82d1f807076b011a44180cf2777edf1a7b9c26
ARG GRYPE_SHA256_arm64=935f628bdf9331ffdd946931ea5fdb50045d3970ba52670cbeb44a88f127291b
ARG SYFT_SHA256_amd64=2a2e837a2c8d59ec9af5472ee22d3b04ee463c4e44476ecf993fd1e5ab6ebc7f
ARG SYFT_SHA256_arm64=6c0466811541ea03add5213a60a1562f0851e4c0b0ecfdee1a694a9455285900
ARG OSV_SCANNER_SHA256_amd64=f9f25499a2c8cc367b3af45df2ea7eeca7fbccceab9c35079968f4b3652194be
ARG OSV_SCANNER_SHA256_arm64=3d0f5aa5a6baa8eb32bcef247388e149ef6030a6634ccae6fa0d62681fb27a6d
ARG NUCLEI_SHA256_amd64=ea63d4ae232808cd7c6bc00d0142428e231fab59dae01042246097d195835ab6
ARG NUCLEI_SHA256_arm64=8044e3d9768ba0a744b2872c1a87e813006f013da97ca9f50f7661a4203bec07

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar unzip git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
RUN mkdir -p /out/bin

# trufflehog: linux_amd64|linux_arm64 tar.gz, contains `trufflehog`.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) sha="${TRUFFLEHOG_SHA256_amd64}" ;; \
      arm64) sha="${TRUFFLEHOG_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}/trufflehog_${TRUFFLEHOG_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o th.tgz; \
    echo "${sha}  th.tgz" | sha256sum --check --strict; \
    tar -xzf th.tgz trufflehog; \
    install -m 0755 trufflehog /out/bin/trufflehog; \
    rm -f th.tgz trufflehog

# grype: linux_amd64|linux_arm64 tar.gz, contains `grype`.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) sha="${GRYPE_SHA256_amd64}" ;; \
      arm64) sha="${GRYPE_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o grype.tgz; \
    echo "${sha}  grype.tgz" | sha256sum --check --strict; \
    tar -xzf grype.tgz grype; \
    install -m 0755 grype /out/bin/grype; \
    rm -f grype.tgz grype

# syft: linux_amd64|linux_arm64 tar.gz, contains `syft`.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) sha="${SYFT_SHA256_amd64}" ;; \
      arm64) sha="${SYFT_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o syft.tgz; \
    echo "${sha}  syft.tgz" | sha256sum --check --strict; \
    tar -xzf syft.tgz syft; \
    install -m 0755 syft /out/bin/syft; \
    rm -f syft.tgz syft

# osv-scanner: raw per-arch binary (no archive, no upstream checksums file).
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) sha="${OSV_SCANNER_SHA256_amd64}" ;; \
      arm64) sha="${OSV_SCANNER_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/google/osv-scanner/releases/download/v${OSV_SCANNER_VERSION}/osv-scanner_linux_${TARGETARCH}"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o osv-scanner; \
    echo "${sha}  osv-scanner" | sha256sum --check --strict; \
    install -m 0755 osv-scanner /out/bin/osv-scanner; \
    rm -f osv-scanner

# nuclei: linux_amd64|linux_arm64 zip, contains `nuclei`.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) sha="${NUCLEI_SHA256_amd64}" ;; \
      arm64) sha="${NUCLEI_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/projectdiscovery/nuclei/releases/download/v${NUCLEI_VERSION}/nuclei_${NUCLEI_VERSION}_linux_${TARGETARCH}.zip"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o nuclei.zip; \
    echo "${sha}  nuclei.zip" | sha256sum --check --strict; \
    unzip -o nuclei.zip nuclei; \
    install -m 0755 nuclei /out/bin/nuclei; \
    rm -f nuclei.zip nuclei

# testssl.sh: pinned tag, shallow clone. It is a self-contained bash script plus
# an etc/ data dir; ship the whole tree and symlink the entrypoint onto PATH.
RUN set -eux; \
    git clone --depth 1 --branch "v${TESTSSL_VERSION}" \
      https://github.com/testssl/testssl.sh.git /out/opt/testssl.sh; \
    rm -rf /out/opt/testssl.sh/.git

# ---------------------------------------------------------------------------
# Final stage: base toolchain image + the scan fleet. BASE is the global ARG
# declared at the top of this file.
# ---------------------------------------------------------------------------
FROM ${BASE}

# pip-installed fleet versions (PyPI). Verified to install on Python 3.14.
ARG SEMGREP_VERSION=1.174.0
ARG BANDIT_VERSION=1.9.4
ARG DETECT_SECRETS_VERSION=1.5.0
ARG SSLYZE_VERSION=6.3.1
ARG SSH_AUDIT_VERSION=3.9.0

# Restated for LABELs (ARGs above are consumed by RUN; these are for metadata).
ARG TRUFFLEHOG_VERSION=3.97.0
ARG GRYPE_VERSION=0.117.0
ARG SYFT_VERSION=1.51.0
ARG OSV_SCANNER_VERSION=2.5.1
ARG NUCLEI_VERSION=3.11.1
ARG TESTSSL_VERSION=3.2.4

LABEL org.opencontainers.image.title="breachsafe-workbench" \
      org.opencontainers.image.description="BreachSAFE scan-fleet image: base toolchain + OSS security scanners (semgrep, bandit, trufflehog, detect-secrets, grype, syft, osv-scanner, sslyze, testssl.sh, ssh-audit, nmap, nuclei). Built on breachsafe-container." \
      org.opencontainers.image.source="https://github.com/paul007ex/breachsafe-container" \
      org.opencontainers.image.vendor="BreachSAFE" \
      org.opencontainers.image.licenses="PolyForm-Noncommercial-1.0.0" \
      org.opencontainers.image.base.name="ghcr.io/paul007ex/breachsafe-container"

# The base image ends as USER breachsafe; go back to root to install the fleet.
USER root

# nmap (recon) + testssl.sh runtime helpers: procps (ps — required by
# testssl.sh), dnsutils (dig), bsdextrautils (hexdump/column). Kept lean; clean
# the apt lists in the same layer.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         nmap \
         procps \
         dnsutils \
         bsdextrautils \
    && rm -rf /var/lib/apt/lists/*

# Release binaries + testssl.sh tree from the fetch stage.
COPY --from=fleet-fetch /out/bin/ /usr/local/bin/
COPY --from=fleet-fetch /out/opt/testssl.sh /opt/testssl.sh
RUN ln -s /opt/testssl.sh/testssl.sh /usr/local/bin/testssl.sh

# Python fleet, version-pinned, installed system-wide through the base image's
# pinned uv. The base image intentionally removes pip from the runtime image.
RUN uv pip install --system --no-cache \
      "semgrep==${SEMGREP_VERSION}" \
      "bandit==${BANDIT_VERSION}" \
      "detect-secrets==${DETECT_SECRETS_VERSION}" \
      "sslyze==${SSLYZE_VERSION}" \
      "ssh-audit==${SSH_AUDIT_VERSION}"

# nuclei writes its template store + config under $HOME. Point it at the
# breachsafe user's home so an unprivileged runtime has a writable location.
# Templates are NOT baked in: run `nuclei -update-templates` at runtime to fetch
# / refresh them (keeps the image lean and the template set current).
ENV NUCLEI_CONFIG_DIR=/home/breachsafe/.config/nuclei \
    HOME=/home/breachsafe

# Back to the non-root user for runtime.
USER breachsafe
WORKDIR /home/breachsafe
CMD ["/bin/bash"]
