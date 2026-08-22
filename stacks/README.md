<!-- SPDX-FileCopyrightText: 2026 BreachSAFE <https://www.breachsafe.io> -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# stacks — opt-in posture platforms

These are **posture dashboards you bring up yourself** with `docker compose up`.
They are **NOT baked into any image** and are **NOT built or run by CI** — they
are heavy, long-running, multi-container servers (databases, message queues, web
UIs). The `breachsafe-workbench` image produces the artifacts (SBOMs, findings,
attestations); these stacks are where you *land and triage* that output over
time.

```
workbench (run a scan)  ->  SBOM / findings / attestation  ->  posture stack (triage over time)
```

| Stack | Role (from CATALOG.md posture lane) | Priority | Dir |
|---|---|---|---|
| Dependency-Track | SBOM -> vuln: component->vuln matching + VEX/analysis triage lifecycle | primary | `dependency-track/` |
| GUAC | supply-chain graph fusion + SLSA/in-toto attestation model | primary | `guac/` |
| DefectDojo | findings aggregation: parser-package + import/reimport lifecycle + dedupe | **OPTIONAL** (lower priority) | `defectdojo/` |

## Bringing one up

```bash
cd stacks/dependency-track    # or guac / defectdojo
docker compose up -d
docker compose logs -f
# ... use it ...
docker compose down           # add -v to also drop the data volumes
```

Each stack `name:`s its compose project, so they don't collide if you run more
than one. Note the **port map** below — Dependency-Track and DefectDojo both
default their UI to host `8080`; run them one at a time or edit the port
mapping.

| Stack | UI | Also exposes |
|---|---|---|
| Dependency-Track | http://localhost:8080 (frontend) | API on `8081` |
| GUAC | http://localhost:8080 (GraphQL) | REST `8081`, NATS `4222`, collectsub `2782` |
| DefectDojo | http://localhost:8080 (nginx) | — |

## Feeding them from the workbench

```bash
# Dependency-Track: upload a CycloneDX SBOM (UI or API)
docker run --rm -v "$PWD:/src" breachsafe-workbench syft dir:/src -o cyclonedx-json > bom.json

# GUAC: ingest an SPDX SBOM / attestation into the graph
docker run --rm -v "$PWD:/src" breachsafe-workbench syft dir:/src -o spdx-json > sbom.spdx.json

# DefectDojo: import per-tool reports via its parsers (semgrep/bandit/grype/nuclei/...)
docker run --rm -v "$PWD:/src" breachsafe-workbench semgrep --config auto --json /src > semgrep.json
```

## Resource needs (heads-up)

These are servers, not CLIs — budget accordingly:

- **Dependency-Track** — the API server is the memory hog: give it **4 GB+ heap**
  (`EXTRA_JAVA_OPTIONS: -Xmx4g`, compose limit 6 GB). Plus postgres + frontend.
  Realistically wants ~6-8 GB RAM available to Docker.
- **GUAC** — several Go services + NATS (JetStream) + postgres. Lighter than DT
  per-service but many services; budget ~4 GB and a few CPU cores.
- **DefectDojo** — the heaviest: postgres + redis + uwsgi + two celery services +
  nginx + a one-shot initializer (migrations/seed). Budget ~4-6 GB; first boot is
  slow while the initializer migrates the DB and seeds the `admin` user.

All default credentials/secrets in these files are **local-dev placeholders**
(`admin/admin`, `change-me-...`). Change every password and secret before any
non-local use.

## Not here (by design)

No AI/eval or agent-framework services (no phoenix, no kagent) — out of scope for
the posture stacks. Cloud-posture and orchestration platforms from CATALOG.md
(prowler, osmedeus, ...) are separate tracks, not part of this workbench repo.

## License

PolyForm-Noncommercial-1.0.0 for these first-party compose files. See the repo
root [`LICENSE`](../LICENSE) / [`LICENSES/`](../LICENSES/); REUSE metadata in
[`REUSE.toml`](../REUSE.toml). The upstream container images each keep their own
license (Dependency-Track Apache-2.0, GUAC Apache-2.0, DefectDojo BSD-3-Clause).
