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
# Two variants ship, and between them they cover every cipher, protocol and PQC
# capability BQP measures. `latest` and `:4.0.2` are the same bytes, so an ordinary
# pull gets the weak-cipher build with no suffix and no special pin:
#
#   :4.0.2 / :latest  DEFAULT. 4.0.2 with the weak cipher suites compiled in and
#                     the legacy provider activated. Its default cipher list,
#                     KEM list, signature list and TLS group list are each byte
#                     identical to a stock 4.0.2, so the current-strength lane
#                     measures exactly what it measured before.
#   :1.0.2u           EOL. The only variant that reaches SSLv3, export suites and
#                     single DES, none of which any 3.x or 4.x build can offer.
#
# A 3.5 LTS variant used to ship here. Measured against the pair above it carried
# no capability they lack: stock 3.5.8 offers no weak suites and no SSLv3, and its
# PQC surface is a subset of 4.0.2's. openssl-sys 0.9.117 handles `(4, 0, _)`, so
# the Rust lane links against 4.0.2 directly and the LTS ABI argument goes with it.
#
# One target extracts; one compiles. Extraction copies binaries BreachSAFE already
# published, from a digest-pinned BreachSAFE image, so no third-party bytes enter.
# openssl40 compiles, because a weak-cipher build exists in no published image and
# there is nothing to extract it from.
#
# Rebuild only when a version pin changes. Producing a NEW OpenSSL version is a
# separate, deliberate act and is not part of any ordinary image build; the
# source-build recipe that produced the extracted binaries is in this repository's
# history at fb25214.
#
#   docker buildx build --target openssl40 \
#     -t ghcr.io/paul007ex/breachsafe-openssl:4.0.2 \
#     -t ghcr.io/paul007ex/breachsafe-openssl:latest \
#     -t ghcr.io/paul007ex/breachsafe-openssl-backup:4.0.2 openssl/
#   docker buildx build --target openssl102u \
#     -t ghcr.io/paul007ex/breachsafe-openssl:1.0.2u \
#     -t ghcr.io/paul007ex/breachsafe-openssl-backup:1.0.2u openssl/

# The BreachSAFE image that already carries the 1.0.2u prefix, pinned by digest.
ARG SOURCE_IMAGE=ghcr.io/paul007ex/breachsafe-container:3.14-openssl3.5@sha256:15eb1539a7a0045b6eaae18d636802c34d1ec8dde12f7814dd4d6dd6689fd285

FROM ${SOURCE_IMAGE} AS source

# ---------------------------------------------------------------------------
# Shared source stage for 4.0.2. Both the shipped build and the baseline it is
# compared against branch from here, so they are provably the same source bytes
# and the comparison isolates the Configure flags.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS ossl40-src

ARG OPENSSL_VERSION=4.0.2
ARG OPENSSL_SHA256=736b467530f916737b7031310ccb21d8218c6229e61e8e160cd1d3458cd543a8

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         build-essential ca-certificates curl perl make \
    && rm -rf /var/lib/apt/lists/*

# Series guard: a patch bump stays in range, a series bump has to be a reviewed
# edit here. 4.1 is deliberately out of range while it is prerelease only.
RUN set -eux; \
    case "${OPENSSL_VERSION}" in \
      4.0.*) ;; \
      *) echo "OPENSSL_VERSION=${OPENSSL_VERSION} is outside the 4.0 series" >&2; exit 1 ;; \
    esac; \
    patch="${OPENSSL_VERSION#4.0.}"; \
    case "$patch" in \
      ''|*[!0-9]*) echo "OPENSSL_VERSION=${OPENSSL_VERSION} has no numeric patch" >&2; exit 1 ;; \
    esac; \
    [ "$patch" -ge 2 ] || { echo "OPENSSL_VERSION=${OPENSSL_VERSION} is below the 4.0.2 floor" >&2; exit 1; }; \
    echo "OpenSSL ${OPENSSL_VERSION} is within >=4.0.2,<4.1"

RUN set -eux; \
    mkdir -p /src; \
    curl -fsSL -o /tmp/openssl.tar.gz \
      "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"; \
    echo "${OPENSSL_SHA256}  /tmp/openssl.tar.gz" | sha256sum --check --strict; \
    tar --extract --gzip --strip-components=1 --file /tmp/openssl.tar.gz --directory /src; \
    rm -f /tmp/openssl.tar.gz

WORKDIR /src

# ---------------------------------------------------------------------------
# Baseline: stock 4.0.2. Nothing ships from this stage. It exists so the gate in
# the next stage can diff against a build that differs only in Configure flags,
# which is the evidence that redirecting the default tag to the weak build leaves
# the current-strength lane measuring a modern client.
# ---------------------------------------------------------------------------
FROM ossl40-src AS ossl40-stock

RUN set -eux; \
    ./Configure --prefix=/opt/openssl-stock --openssldir=/opt/openssl-stock/ssl \
      shared no-tests; \
    make -j"$(nproc)" build_libs; \
    make -j"$(nproc)" apps/openssl; \
    make install_sw

# ---------------------------------------------------------------------------
# The shipped build: 4.0.2 with the weak cipher suites available.
#
# Stock 4.0.2 offers none of RC4, 3DES, IDEA or SEED, so an endpoint that accepts
# only those reports as "not observed" instead of weak. Two separate gates hide
# them, and both have to be opened:
#
#   compile   enable-weak-ssl-ciphers restores the suite definitions in libssl.
#             Without it 3DES is absent even at @SECLEVEL=0.
#   runtime   RC4, IDEA and SEED live in the legacy provider, which 3.x and 4.x
#             load only when openssl.cnf activates it. Opening the compile gate
#             alone leaves RC4 at zero suites, which reads exactly like a failed
#             build.
#
# SSLv3, export suites and single DES have no build flag here: 4.0 rejects
# enable-ssl3 and enable-ssl3-method as unsupported options, and the export and
# single-DES suites are gone from the sources. :1.0.2u remains the only variant
# that reaches those three.
# ---------------------------------------------------------------------------
FROM ossl40-src AS ossl40-weak

RUN set -eux; \
    ./Configure --prefix=/opt/openssl --openssldir=/opt/openssl/ssl \
      shared no-tests \
      enable-weak-ssl-ciphers enable-idea enable-seed; \
    make -j"$(nproc)" build_libs; \
    make -j"$(nproc)" apps/openssl; \
    make install_sw

# install_sw skips the config directory, so openssl.cnf is written here.
# Activating the legacy provider is what makes RC4, IDEA and SEED fetchable. The
# default provider is activated alongside it because naming any provider in the
# config replaces the implicit default rather than adding to it, and a config that
# names only legacy would take AES away.
RUN set -eux; \
    mkdir -p /opt/openssl/ssl; \
    printf '%s\n' \
      '# Activating any provider replaces the implicit default, so default is named' \
      '# explicitly here. Removing it removes AES.' \
      'openssl_conf = openssl_init' \
      '' \
      '[openssl_init]' \
      'providers = provider_sect' \
      '' \
      '[provider_sect]' \
      'default = default_sect' \
      'legacy  = legacy_sect' \
      '' \
      '[default_sect]' \
      'activate = 1' \
      '' \
      '[legacy_sect]' \
      'activate = 1' \
      > /opt/openssl/ssl/openssl.cnf

# The build gate. Every assertion below fails against a stock build, so a silently
# stock-equivalent result cannot pass. The four parity diffs are the reason the
# unsuffixed tag can carry the weak build: they fail if the weak flags reach the
# default negotiation surface.
COPY --from=ossl40-stock /opt/openssl-stock /opt/openssl-stock
RUN set -eux; \
    export LD_LIBRARY_PATH=/opt/openssl/lib64:/opt/openssl/lib; \
    O=/opt/openssl/bin/openssl; \
    "$O" version | grep -q "^OpenSSL ${OPENSSL_VERSION} "; \
    "$O" list -providers | grep -q 'OpenSSL Legacy Provider'; \
    for spec in RC4 3DES IDEA SEED; do \
      n="$("$O" ciphers "${spec}:@SECLEVEL=0" 2>/dev/null | tr ':' '\n' | grep -c .)"; \
      [ "$n" -gt 0 ] || { echo "${spec}: 0 suites, the weak build did not take" >&2; exit 1; }; \
      echo "${spec}: ${n} suites"; \
    done; \
    "$O" list -kem-algorithms | grep -q 'ML-KEM-768'; \
    "$O" list -signature-algorithms | grep -q 'ML-DSA-65'; \
    "$O" list -tls1_3 -tls-groups | grep -q 'X25519MLKEM768'; \
    echo 'PQC present: ML-KEM-768, ML-DSA-65, X25519MLKEM768'; \
    rm -f /tmp/weak.txt /tmp/stock.txt; \
    parity() { \
      "$O" "$@" | tr ':' '\n' | sort > /tmp/weak.txt; \
      LD_LIBRARY_PATH=/opt/openssl-stock/lib64:/opt/openssl-stock/lib \
        /opt/openssl-stock/bin/openssl "$@" | tr ':' '\n' | sort > /tmp/stock.txt; \
      [ -s /tmp/stock.txt ] || { echo "stock '$*' is empty, the comparison did not run" >&2; return 1; }; \
      diff /tmp/stock.txt /tmp/weak.txt \
        || { echo "'$*' differs from stock; the weak flags reached the default surface" >&2; return 1; }; \
      echo "matches stock: $* ($(wc -l < /tmp/weak.txt) entries)"; \
    }; \
    parity ciphers; \
    parity list -kem-algorithms; \
    parity list -signature-algorithms; \
    parity list -tls1_3 -tls-groups; \
    rm -rf /opt/openssl-stock /tmp/weak.txt /tmp/stock.txt

# ---------------------------------------------------------------------------
# OpenSSL 4.0.2, weak-cipher build. The default every image builds FROM.
# ---------------------------------------------------------------------------
FROM scratch AS openssl40
LABEL org.opencontainers.image.title="breachsafe-openssl" \
      org.opencontainers.image.description="OpenSSL 4.0.2 prefix with the weak cipher suites compiled in and the legacy provider activated. Default negotiation surface is identical to a stock 4.0.2." \
      org.opencontainers.image.vendor="BreachSAFE" \
      org.opencontainers.image.source="https://github.com/paul007ex/breachsafe-container" \
      org.opencontainers.image.url="https://www.breachsafe.io" \
      org.opencontainers.image.licenses="PolyForm-Noncommercial-1.0.0" \
      org.opencontainers.image.version="4.0.2" \
      io.breachsafe.openssl.version="4.0.2" \
      io.breachsafe.openssl.prefix="/opt/openssl" \
      io.breachsafe.openssl.weak="true"
COPY --from=ossl40-weak /opt/openssl /opt/openssl

# ---------------------------------------------------------------------------
# OpenSSL 1.0.2u. EOL by design: the compatibility lane measures what a weak
# client can still negotiate. Never link a product against this.
# ---------------------------------------------------------------------------
FROM scratch AS openssl102u
LABEL org.opencontainers.image.title="breachsafe-openssl" \
      org.opencontainers.image.description="OpenSSL 1.0.2u prefix for the BreachSAFE legacy compatibility lane. EOL by design, evidence collection only." \
      org.opencontainers.image.vendor="BreachSAFE" \
      org.opencontainers.image.source="https://github.com/paul007ex/breachsafe-container" \
      org.opencontainers.image.base.name="ghcr.io/paul007ex/breachsafe-container" \
      org.opencontainers.image.base.digest="sha256:15eb1539a7a0045b6eaae18d636802c34d1ec8dde12f7814dd4d6dd6689fd285" \
      org.opencontainers.image.url="https://www.breachsafe.io" \
      org.opencontainers.image.licenses="PolyForm-Noncommercial-1.0.0" \
      org.opencontainers.image.version="1.0.2u" \
      io.breachsafe.openssl.version="1.0.2u" \
      io.breachsafe.openssl.prefix="/opt/openssl-legacy" \
      io.breachsafe.openssl.eol="true"
COPY --from=source /opt/openssl-legacy /opt/openssl-legacy
