## [2026-06-20] lint | Initialized LLM Wiki architecture and schema.

Set up root CLAUDE.md with directory rules, frontmatter standards, and operational workflows. This establishes the foundational architecture for maintaining the Zilch GCP wiki, including directory layout conventions, YAML frontmatter requirements for all wiki pages, changelog format for log.md, and three operational workflows: INGEST (integrating new content), QUERY (finding information via tags), and LINT (maintaining wiki quality).

---

## [2026-06-20] ingest | Recompilation pass: Python migration

Recompiled 5 wiki pages to reflect the Python orchestration migration and updated deployment architecture. Modified pages: docs/wiki/entities/configuration.md, docs/wiki/entities/deployment-reliability.md, docs/wiki/entities/deployment-workflow.md, docs/wiki/topics/first-deployment.md, and docs/wiki/topics/troubleshooting/common.md. Changes focused on removing obsolete Bash-centric references and integrating Python-based architecture documentation. Additionally rebuilt docs/wiki/INDEX.md with a comprehensive catalog of all wiki entities and topics.

---

---

## [2026-09-20] update | Cloud Run env is no longer reverted; storage bucket is private by construction

main.tf: the Cloud Run service now ignores changes to its container env as well as its image, so variables and secret references added by the app's own deploys are not stripped by `terraform apply` (trade-off documented in docs/wiki/entities/environment-variables.md). The optional `google_storage_bucket.app` now sets uniform bucket-level access and public access prevention. `terraform validate` passes; not applied to any project. Motivated by the `now` app (fork-friendliness work).

---

## [2026-09-20] update | Firestore PITR pinned; monitoring gets a real 5xx alert, an uptime check and optional email

main.tf: `google_firestore_database.default` now states `point_in_time_recovery_enablement = ENABLED`, because an apply would otherwise have switched off a hand-enabled PITR on the `now` project (found by `terraform plan`). cloud_monitoring.tf: `cloud_run_errors` now alerts on more than 3 5xx responses in 5 minutes (it used to alert on request count and never fired), plus a `<app>-health` uptime check on `/health` and a "health check failing" policy; new optional `alert_email` (config.py, variables.tf, template) adds an email notification channel. `terraform validate` passes; a plan against the `now` project shows 2 to add, 1 to change, 0 to destroy. Pre-existing: 11 tests in tests/ fail before and after this change.

---

## [2026-09-20] update | Ignore gcloud client fields on the Cloud Run service

main.tf: `client` and `client_version` (set by `gcloud run deploy`) are added to `ignore_changes`; after the `now` app was deployed into the zilch-managed service, a plan wanted to null them. Applied the monitoring changes from 1f76d72 to the `now` project; plan is clean.

---

## [2026-09-20] update | README: real-world reference (`now`), monitoring resources

README.md: added "A real app built on Zilch: now" under Reference Application (the infrastructure/app split and the lessons now built in) and described the uptime check, 5xx alert and `alert_email` under Monitoring & Logs.
