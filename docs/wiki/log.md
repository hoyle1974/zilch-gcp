## [2026-06-20] lint | Initialized LLM Wiki architecture and schema.

Set up root CLAUDE.md with directory rules, frontmatter standards, and operational workflows. This establishes the foundational architecture for maintaining the Zilch GCP wiki, including directory layout conventions, YAML frontmatter requirements for all wiki pages, changelog format for log.md, and three operational workflows: INGEST (integrating new content), QUERY (finding information via tags), and LINT (maintaining wiki quality).

---

## [2026-06-20] ingest | Recompilation pass: Python migration

Recompiled 5 wiki pages to reflect the Python orchestration migration and updated deployment architecture. Modified pages: docs/wiki/entities/configuration.md, docs/wiki/entities/deployment-reliability.md, docs/wiki/entities/deployment-workflow.md, docs/wiki/topics/first-deployment.md, and docs/wiki/topics/troubleshooting/common.md. Changes focused on removing obsolete Bash-centric references and integrating Python-based architecture documentation. Additionally rebuilt docs/wiki/INDEX.md with a comprehensive catalog of all wiki entities and topics.

---

---

## [2026-09-20] update | Cloud Run env is no longer reverted; storage bucket is private by construction

main.tf: the Cloud Run service now ignores changes to its container env as well as its image, so variables and secret references added by the app's own deploys are not stripped by `terraform apply` (trade-off documented in docs/wiki/entities/environment-variables.md). The optional `google_storage_bucket.app` now sets uniform bucket-level access and public access prevention. `terraform validate` passes; not applied to any project. Motivated by the `now` app (fork-friendliness work).
