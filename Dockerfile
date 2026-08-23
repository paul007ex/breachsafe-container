# SPDX-FileCopyrightText: 2026 BreachSAFE <https://www.breachsafe.io>
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
#
# breachsafe-container — pinned BreachSAFE toolchain image (CI runtime + devcontainer).
# Multi-stage:
#   (a) openssl-build : OpenSSL 3.5.7 LTS from source, SHA256-verified, --prefix=/opt/openssl
#   (b) tool-fetch    : pinned release binaries (gitleaks, trivy, cyclonedx-cli, cosign, just),
#                       SHA256-verified per arch
#   (c) final         : python:3.14-slim-bookworm + OpenSSL + pinned python + release tools
#
# Python 3.14 ONLY (no 3.12 fallback), NOT free-threaded.

# ---------------------------------------------------------------------------
# Stage (a): OpenSSL 3.5.7 LTS from source (pattern reused verbatim from
# breachsafe/qureddy's Dockerfile — SHA256-verified source build).
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818 AS openssl-build

ARG OPENSSL_VERSION=3.5.7
ARG OPENSSL_SHA256=a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates curl perl \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --proto '=https' --connect-timeout 30 --max-time 600 \
      "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
      --output /tmp/openssl.tar.gz \
    && echo "${OPENSSL_SHA256}  /tmp/openssl.tar.gz" | sha256sum --check --strict \
    && mkdir /tmp/openssl-src \
    && tar --extract --gzip --strip-components=1 --file /tmp/openssl.tar.gz --directory /tmp/openssl-src \
    && cd /tmp/openssl-src \
    && ./Configure --prefix=/opt/openssl --openssldir=/opt/openssl/ssl shared no-tests \
    && make -j"$(nproc)" build_libs \
    && make -j"$(nproc)" apps/openssl \
    && make install_sw \
    && rm -rf /tmp/openssl.tar.gz /tmp/openssl-src

# ---------------------------------------------------------------------------
# Stage (b): fetch + SHA256-verify pinned release binaries for the build arch.
# TARGETARCH is provided by BuildKit (amd64 | arm64).
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818 AS tool-fetch

ARG TARGETARCH

# Pinned tool versions (see README "Pinned versions").
ARG GITLEAKS_VERSION=8.30.1
ARG TRIVY_VERSION=0.74.0
ARG CYCLONEDX_CLI_VERSION=0.33.1
ARG COSIGN_VERSION=3.1.3
ARG JUST_VERSION=1.58.0

# Per-arch SHA256 sums (verified upstream at author time).
ARG GITLEAKS_SHA256_amd64=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG GITLEAKS_SHA256_arm64=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080
ARG TRIVY_SHA256_amd64=2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a
ARG TRIVY_SHA256_arm64=b94ce1976bbf3c15b514b605ee88be7c6d94a29be2302847ff01cb794d47aad5
ARG CYCLONEDX_SHA256_amd64=bfc8b2538da86fe239bc53658bbb63c1c8c510a293c1e6891aa5bea5d3c58746
ARG CYCLONEDX_SHA256_arm64=b2e9fdf9665ef49868a2ec012171c6e785dcd69745bc5869e53e4f4bfb096a5f
ARG COSIGN_SHA256_amd64=4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71
ARG COSIGN_SHA256_arm64=c5d324e091826b0d7a78eb16fef316450b4eb9aaec045611c08ba06f5e73220a
ARG JUST_SHA256_amd64=4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d
ARG JUST_SHA256_arm64=748237128c4c40cbdabc65e841d05ceba13cc23a91eaba395495894c1d9764df
ARG NODE_VERSION=22.23.2
ARG NODE_SHA256_amd64=d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307
ARG NODE_SHA256_arm64=fff4078c5def658577f92c88db7db3bc0072924bfb93fe52c1e744a54e94abb8

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
RUN mkdir -p /out/bin

# gitleaks: assets use x64|arm64 in the archive name.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) gl_arch=x64;  gl_sha="${GITLEAKS_SHA256_amd64}" ;; \
      arm64) gl_arch=arm64; gl_sha="${GITLEAKS_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o gitleaks.tgz; \
    echo "${gl_sha}  gitleaks.tgz" | sha256sum --check --strict; \
    tar -xzf gitleaks.tgz gitleaks; \
    install -m 0755 gitleaks /out/bin/gitleaks; \
    rm -f gitleaks.tgz gitleaks

# trivy: assets use Linux-64bit|Linux-ARM64.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) tv_arch=Linux-64bit; tv_sha="${TRIVY_SHA256_amd64}" ;; \
      arm64) tv_arch=Linux-ARM64; tv_sha="${TRIVY_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_${tv_arch}.tar.gz"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o trivy.tgz; \
    echo "${tv_sha}  trivy.tgz" | sha256sum --check --strict; \
    tar -xzf trivy.tgz trivy; \
    install -m 0755 trivy /out/bin/trivy; \
    rm -f trivy.tgz trivy

# cyclonedx-cli: single self-contained binary, installed as `cyclonedx`.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) cx_arch=x64;   cx_sha="${CYCLONEDX_SHA256_amd64}" ;; \
      arm64) cx_arch=arm64; cx_sha="${CYCLONEDX_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/CycloneDX/cyclonedx-cli/releases/download/v${CYCLONEDX_CLI_VERSION}/cyclonedx-linux-${cx_arch}"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o cyclonedx; \
    echo "${cx_sha}  cyclonedx" | sha256sum --check --strict; \
    install -m 0755 cyclonedx /out/bin/cyclonedx; \
    rm -f cyclonedx

# cosign: single binary.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) co_sha="${COSIGN_SHA256_amd64}" ;; \
      arm64) co_sha="${COSIGN_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${TARGETARCH}"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o cosign; \
    echo "${co_sha}  cosign" | sha256sum --check --strict; \
    install -m 0755 cosign /out/bin/cosign; \
    rm -f cosign

# just: musl static build (arch triple differs from Docker arch).
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) ju_triple=x86_64-unknown-linux-musl;  ju_sha="${JUST_SHA256_amd64}" ;; \
      arm64) ju_triple=aarch64-unknown-linux-musl; ju_sha="${JUST_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${ju_triple}.tar.gz"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o just.tgz; \
    echo "${ju_sha}  just.tgz" | sha256sum --check --strict; \
    tar -xzf just.tgz just; \
    install -m 0755 just /out/bin/just; \
    rm -f just.tgz just

# Node: needed by jscpd. Debian bookworm ships Node 18, which cannot load jscpd 4.x at all —
# its CJS entry require()s an ES-only dependency and dies with ERR_REQUIRE_ESM. Verified on
# arm64: node18+jscpd4.3.0 FAILS, node22+jscpd4.3.0 WORKS, node18+jscpd3.5.10 WORKS. Taking
# Node 22 rather than downgrading jscpd, because breachsafe-common's .jscpd.json targets 4.x.
# Checksum-pinned tarball like every other tool here, not apt. (#2)
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) nd_arch=linux-x64;   nd_sha="${NODE_SHA256_amd64}" ;; \
      arm64) nd_arch=linux-arm64; nd_sha="${NODE_SHA256_arm64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${nd_arch}.tar.xz"; \
    curl --fail --location --proto '=https' --connect-timeout 30 --max-time 300 "$url" -o node.tar.xz; \
    echo "${nd_sha}  node.tar.xz" | sha256sum --check --strict; \
    mkdir -p /out/node; \
    tar --extract --xz --file node.tar.xz --directory /out/node --strip-components=1; \
    rm -f node.tar.xz; \
    rm -rf /out/node/CHANGELOG.md /out/node/LICENSE /out/node/README.md

# ---------------------------------------------------------------------------
# Stage (c): final image. Python 3.14 slim + OpenSSL + pinned python + tools.
# ---------------------------------------------------------------------------
FROM python:3.14-slim-bookworm@sha256:23c59390fc717bf09f9336908199a0ae75d9c4264bf296123f94ad772fea3b52

# Pinned python-tool versions (PyPI).
ARG UV_VERSION=0.12.5
ARG RUFF_VERSION=0.16.4
ARG MYPY_VERSION=2.3.1
ARG REUSE_VERSION=6.2.0

ARG OPENSSL_VERSION=3.5.7
ARG PYTHON_VERSION=3.14

LABEL org.opencontainers.image.title="breachsafe-container" \
      org.opencontainers.image.description="Pinned BreachSAFE toolchain image (CI runtime + devcontainer): Python 3.14, OpenSSL 3.5.7 LTS from source, uv/ruff/mypy/gitleaks/trivy/cyclonedx-cli/cosign/just/reuse." \
      org.opencontainers.image.source="https://github.com/paul007ex/breachsafe-container" \
      org.opencontainers.image.vendor="BreachSAFE" \
      org.opencontainers.image.licenses="PolyForm-Noncommercial-1.0.0" \
      org.opencontainers.image.base.name="docker.io/library/python:3.14-slim-bookworm"

# OpenSSL 3.5.7 LTS from stage (a).
COPY --from=openssl-build /opt/openssl /opt/openssl

# Pinned release binaries from stage (b).
COPY --from=tool-fetch /out/bin/ /usr/local/bin/

# OpenSSL env: expose the from-source build to consumers (QUREDDY_OPENSSL is the
# convention QuReddy reads; OPENSSL_DIR is the convention the Rust crates read).
ENV QUREDDY_OPENSSL=/opt/openssl/bin/openssl \
    OPENSSL_DIR=/opt/openssl \
    OPENSSL_ROOT_DIR=/opt/openssl \
    LD_LIBRARY_PATH=/opt/openssl/lib64:/opt/openssl/lib \
    PATH=/opt/openssl/bin:/usr/local/bin:$PATH \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

ARG DEFUSEDXML_VERSION=0.7.1
# Pinned python toolchain (uv, ruff, mypy, reuse, defusedxml) installed system-wide.
RUN python3 -m pip install --no-cache-dir \
      "uv==${UV_VERSION}" \
      "ruff==${RUFF_VERSION}" \
      "mypy==${MYPY_VERSION}" \
      "reuse[charset-normalizer]==${REUSE_VERSION}" \
      # check_no_skipped_tests.py parses JUnit XML and imports defusedxml rather
      # than stdlib ElementTree, because the XML it reads is a build artifact.
      # Without it the no-skipped-tests gate dies with ModuleNotFoundError.
      "defusedxml==${DEFUSEDXML_VERSION}" \
    # Remove the installer once the toolchain is in. Nothing downstream needs bare pip:
    # breachsafe-common's reusable workflows drive everything through `uv run/sync/tool run`
    # (verified: zero bare-pip invocations across .github/workflows/ and quality-gates/).
    # pip's vendored tree is where Trivy finds msgpack GHSA-6v7p-g79w-8964 and setuptools
    # CVE-2025-47273, both inherited from python:3.14-slim-bookworm rather than declared here.
    # Deleting unused code beats suppressing a finding about it. (#3)
    && python3 -m pip uninstall -y pip setuptools \
    && rm -rf /usr/local/lib/python3.14/site-packages/pip \
              /usr/local/lib/python3.14/site-packages/pip-*.dist-info \
              /usr/local/lib/python3.14/site-packages/setuptools \
              /usr/local/lib/python3.14/site-packages/setuptools-*.dist-info \
              /usr/local/lib/python3.14/site-packages/pkg_resources \
              /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.14 \
    && uv --version && ruff --version && mypy --version && reuse --version \
    && python3 -c 'import defusedxml; print("defusedxml", defusedxml.__version__)'

# Node + jscpd: the duplicate-code gate in breachsafe-common's reusable
# quality-gates-python.yml runs jscpd inside this image. bookworm ships Node 18
# (jscpd 4 needs >=14). jscpd is installed globally so CI needs no npx fetch.
# Node 22 + jscpd. Node comes from the tool-fetch stage (the final image has no curl/xz);
# jscpd is installed here because npm needs to resolve its dependency tree at build time.
# `jscpd --version` is asserted so a silent install failure cannot ship an image whose
# duplicate-code gate crashes on first use — which is exactly what ERR_REQUIRE_ESM did. (#2)
ARG JSCPD_VERSION=4.3.0
COPY --from=tool-fetch /out/node/ /usr/local/
RUN set -eux; \
    node --version; \
    npm install -g --fetch-retries=5 "jscpd@${JSCPD_VERSION}"; \
    jscpd --version; \
    npm cache clean --force

# git: required, not optional. Two independent reasons, both verified in CI:
#   1. The diff-scoped gates shell out to it. quality-gates-python.yml computes
#      BASE_SHA/HEAD_SHA with `git rev-parse` and feeds them to
#      check_antipattern_diff.py. Without git every such step exits 127.
#   2. actions/checkout SILENTLY falls back to a REST tarball when git is absent.
#      The files land but there is no .git directory, so any diff-based gate is
#      impossible and gitleaks has no history to scan. The failure is quiet: the
#      checkout step goes green.
# This image is also documented as the local devcontainer, which needs git regardless.
# Asserted below so a silent install failure cannot ship a git-less image. (#2 pattern)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends git; \
    rm -rf /var/lib/apt/lists/*; \
    git --version

# Non-root user.
RUN groupadd --gid 1000 breachsafe \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash breachsafe

USER breachsafe
WORKDIR /home/breachsafe
CMD ["python3"]
