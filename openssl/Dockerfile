# SPDX-FileCopyrightText: 2026 BreachSAFE <https://www.breachsafe.io>
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
#
# breachsafe-openssl — the OpenSSL binaries BreachSAFE builds, as standalone
# digest-addressable images, so no repository compiles OpenSSL in its own build.
#
# Publishes two names from the same bytes:
#   breachsafe-openssl         PRIMARY. What every image builds FROM.
#   breachsafe-openssl-backup  INSURANCE. Nothing builds from it. It exists so the
#                              binaries survive a retag or deletion of the primary.
#
# This file does not compile anything and does not copy from a third party. It
# extracts the binaries BreachSAFE already published, from a digest-pinned
# BreachSAFE image, and republishes them under their own name so consumers can
# pin the crypto independently of the toolchain image that carries it.
#
# Rebuild only when a version pin changes. Producing a NEW OpenSSL version is a
# separate, deliberate act and is not part of any ordinary image build; the
# source-build recipe that produced the current binaries is in this repository's
# history at fb25214.
#
#   docker buildx build --target openssl35 \
#     -t ghcr.io/paul007ex/breachsafe-openssl:3.5.8 \
#     -t ghcr.io/paul007ex/breachsafe-openssl-backup:3.5.8 openssl/
#   docker buildx build --target openssl102u \
#     -t ghcr.io/paul007ex/breachsafe-openssl:1.0.2u \
#     -t ghcr.io/paul007ex/breachsafe-openssl-backup:1.0.2u openssl/

# The BreachSAFE image that already carries both prefixes, pinned by digest.
ARG SOURCE_IMAGE=ghcr.io/paul007ex/breachsafe-container:3.14-openssl3.5@sha256:15eb1539a7a0045b6eaae18d636802c34d1ec8dde12f7814dd4d6dd6689fd285

FROM ${SOURCE_IMAGE} AS source

# ---------------------------------------------------------------------------
# OpenSSL 3.5 LTS. The current-strength lane.
# ---------------------------------------------------------------------------
FROM scratch AS openssl35
LABEL org.opencontainers.image.title="breachsafe-openssl" \
      org.opencontainers.image.description="OpenSSL 3.5 LTS prefix for BreachSAFE images. Extracted, never compiled here." \
      org.opencontainers.image.vendor="BreachSAFE" \
      org.opencontainers.image.url="https://www.breachsafe.io" \
      org.opencontainers.image.licenses="PolyForm-Noncommercial-1.0.0" \
      io.breachsafe.openssl.version="3.5.8" \
      io.breachsafe.openssl.prefix="/opt/openssl"
COPY --from=source /opt/openssl /opt/openssl

# ---------------------------------------------------------------------------
# OpenSSL 1.0.2u. EOL by design: the compatibility lane measures what a weak
# client can still negotiate. Never link a product against this.
# ---------------------------------------------------------------------------
FROM scratch AS openssl102u
LABEL org.opencontainers.image.title="breachsafe-openssl" \
      org.opencontainers.image.description="OpenSSL 1.0.2u prefix for the BreachSAFE legacy compatibility lane. EOL by design, evidence collection only." \
      org.opencontainers.image.vendor="BreachSAFE" \
      org.opencontainers.image.url="https://www.breachsafe.io" \
      org.opencontainers.image.licenses="PolyForm-Noncommercial-1.0.0" \
      io.breachsafe.openssl.version="1.0.2u" \
      io.breachsafe.openssl.prefix="/opt/openssl-legacy" \
      io.breachsafe.openssl.eol="true"
COPY --from=source /opt/openssl-legacy /opt/openssl-legacy
