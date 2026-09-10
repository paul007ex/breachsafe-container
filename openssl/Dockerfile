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
# Three variants ship. `latest` and `:3.5.8` are the same bytes, so an ordinary
# pull gets the weak-cipher build with no suffix and no special pin:
#
#   :3.5.8 / :latest  DEFAULT. The 3.5 LTS series with the weak cipher suites and
#                     SSLv3 compiled in and the legacy provider activated. Its
#                     default cipher list, KEM list, signature list and TLS group
#                     list are each byte identical to a stock 3.5.8, so the
#                     current-strength lane measures what it measured before.
#   :4.0.2            The 4.0 series, same weak configuration. Not the default.
#                     Adds curveSM2MLKEM768; loses SSLv3, which 4.0 rejects at
#                     Configure. Published so a move to 4.0 needs no rebuild.
#   :1.0.2u           EOL. The only variant that reaches export suites and single
#                     DES, which are gone from the 3.x and 4.x sources.
#
# The 3.5 LTS series is the default because it is the newest supported series that
# can still carry SSLv3. That keeps SSLv3 evidence on a supported runtime instead
# of resting it on the EOL 1.0.2u binary.
#
# One target extracts; two compile. Extraction copies binaries BreachSAFE already
# published, from a digest-pinned BreachSAFE image, so no third-party bytes enter.
# The weak builds compile, because a weak-cipher build exists in no published
# image and there is nothing to extract one from.
#
# Rebuild only when a version pin changes. Producing a NEW OpenSSL version is a
# separate, deliberate act and is not part of any ordinary image build; the
# source-build recipe that produced the extracted binaries is in this repository's
# history at fb25214.
#
#   docker buildx build --target openssl35weak \
#     -t ghcr.io/paul007ex/breachsafe-openssl:3.5.8 \
#     -t ghcr.io/paul007ex/breachsafe-openssl:latest \
#     -t ghcr.io/paul007ex/breachsafe-openssl-backup:3.5.8 openssl/
#   docker buildx build --target openssl40 \
#     -t ghcr.io/paul007ex/breachsafe-openssl:4.0.2 \
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
      shared no-tests "-Wl,-rpath,/opt/openssl-stock/lib64:/opt/openssl-stock/lib"; \
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
      enable-weak-ssl-ciphers enable-idea enable-seed \
      "-Wl,-rpath,/opt/openssl/lib64:/opt/openssl/lib"; \
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
# OpenSSL 4.0.2, weak-cipher build. Published, not the default.
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
# OpenSSL 3.5 LTS source, for the weak-cipher build that is the default.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS ossl35-src

ARG OPENSSL35_VERSION=3.5.8
ARG OPENSSL35_SHA256=a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         build-essential ca-certificates curl perl make \
    && rm -rf /var/lib/apt/lists/*

# Series guard: a patch bump stays in range, a series bump is a reviewed edit.
RUN set -eux; \
    case "${OPENSSL35_VERSION}" in \
      3.5.*) ;; \
      *) echo "OPENSSL35_VERSION=${OPENSSL35_VERSION} is outside the 3.5 LTS series" >&2; exit 1 ;; \
    esac; \
    patch="${OPENSSL35_VERSION#3.5.}"; \
    case "$patch" in \
      ''|*[!0-9]*) echo "OPENSSL35_VERSION=${OPENSSL35_VERSION} has no numeric patch" >&2; exit 1 ;; \
    esac; \
    [ "$patch" -ge 8 ] || { echo "OPENSSL35_VERSION=${OPENSSL35_VERSION} is below the 3.5.8 floor" >&2; exit 1; }; \
    echo "OpenSSL ${OPENSSL35_VERSION} is within >=3.5.8,<3.6"

RUN set -eux; \
    mkdir -p /src; \
    curl -fsSL -o /tmp/openssl.tar.gz \
      "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL35_VERSION}/openssl-${OPENSSL35_VERSION}.tar.gz"; \
    echo "${OPENSSL35_SHA256}  /tmp/openssl.tar.gz" | sha256sum --check --strict; \
    tar --extract --gzip --strip-components=1 --file /tmp/openssl.tar.gz --directory /src; \
    rm -f /tmp/openssl.tar.gz

WORKDIR /src

# ---------------------------------------------------------------------------
# The shipped default: 3.5 LTS with the weak cipher suites and SSLv3 available.
#
# Two gates hide the weak suites and both have to be opened. enable-weak-ssl-ciphers
# restores the suite definitions in libssl; without it 3DES is absent even at
# @SECLEVEL=0. RC4, IDEA and SEED then live in the legacy provider, which 3.x loads
# only when openssl.cnf activates it, so opening the compile gate alone leaves RC4
# at zero suites and reads exactly like a failed build.
#
# enable-ssl3 and enable-ssl3-method are the reason this series is the default
# rather than 4.0: OpenSSL 4.0 rejects both as unsupported options, so no 4.x build
# can measure a server that offers nothing above SSLv3. Carrying SSLv3 here moves
# that evidence off the EOL 1.0.2u binary and onto a supported one.
#
# Export suites and single DES have no flag in any 3.x build; they are gone from
# the sources. :1.0.2u remains the only variant that reaches those two.
#
# The RUNPATH names both libdirs because the install target differs by
# architecture: x86_64 lands in lib64, aarch64 in lib. Naming one silently loses
# to the base image's own libssl on the other arch, which is how the first attempt
# passed arm64 and failed amd64 (#50).
# ---------------------------------------------------------------------------
FROM ossl35-src AS ossl35-weak

RUN set -eux; \
    ./Configure --prefix=/opt/openssl --openssldir=/opt/openssl/ssl \
      shared no-tests \
      enable-weak-ssl-ciphers enable-ssl3 enable-ssl3-method enable-idea enable-seed \
      "-Wl,-rpath,/opt/openssl/lib64:/opt/openssl/lib"; \
    make -j"$(nproc)" build_libs; \
    make -j"$(nproc)" apps/openssl; \
    make install_sw

# install_sw skips the config directory, so openssl.cnf is written here.
# Activating the legacy provider is what makes RC4, IDEA and SEED fetchable. The
# default provider is named alongside it because activating any provider replaces
# the implicit default rather than adding to it; dropping it removes AES.
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

# The build gate. The baseline is the stock 3.5.8 already published in the source
# image, which is exactly the build this one replaces, so the diff answers the only
# question that matters: does the default negotiation surface move.
COPY --from=source /opt/openssl /opt/openssl-stock
RUN set -eux; \
    export LD_LIBRARY_PATH=/opt/openssl/lib64:/opt/openssl/lib; \
    O=/opt/openssl/bin/openssl; \
    "$O" version | grep -qF "OpenSSL ${OPENSSL35_VERSION} "; \
    "$O" list -providers | grep -q 'OpenSSL Legacy Provider'; \
    for spec in RC4 3DES IDEA SEED; do \
      n="$("$O" ciphers "${spec}:@SECLEVEL=0" 2>/dev/null | tr ':' '\n' | grep -c .)"; \
      [ "$n" -gt 0 ] || { echo "${spec}: 0 suites, the weak build did not take" >&2; exit 1; }; \
      echo "${spec}: ${n} suites"; \
    done; \
    "$O" s_client -help 2>&1 | grep -q -- '-ssl3'; \
    echo 'SSLv3 client method present'; \
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
# OpenSSL 3.5 LTS, weak-cipher build. The default every image builds FROM.
# ---------------------------------------------------------------------------
FROM scratch AS openssl35weak
LABEL org.opencontainers.image.title="breachsafe-openssl" \
      org.opencontainers.image.description="OpenSSL 3.5 LTS prefix with the weak cipher suites and SSLv3 compiled in and the legacy provider activated. Default negotiation surface is identical to a stock 3.5.8." \
      org.opencontainers.image.vendor="BreachSAFE" \
      org.opencontainers.image.source="https://github.com/paul007ex/breachsafe-container" \
      org.opencontainers.image.url="https://www.breachsafe.io" \
      org.opencontainers.image.licenses="PolyForm-Noncommercial-1.0.0" \
      org.opencontainers.image.version="3.5.8" \
      io.breachsafe.openssl.version="3.5.8" \
      io.breachsafe.openssl.prefix="/opt/openssl" \
      io.breachsafe.openssl.weak="true" \
      io.breachsafe.openssl.ssl3="true"
COPY --from=ossl35-weak /opt/openssl /opt/openssl

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
