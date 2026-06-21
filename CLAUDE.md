# Zilch Wiki Maintenance Schema

This document defines the operational rules, frontmatter standards, and workflows for maintaining the Zilch GCP wiki at `docs/wiki/`.

## Directory Layout Rules

The wiki is organized into two primary categories:

```
docs/wiki/
├── INDEX.md                    # Entry point; lists all pages with summaries
├── log.md                      # Changelog; tracks all modifications with timestamps
├── entities/                   # Components, modules, GCP services (nouns)
│   ├── always-free-tier.md
│   ├── cloud-run.md
│   ├── configuration.md
│   ├── deployment-reliability.md
│   ├── deployment-workflow.md
│   ├── environment-variables.md
│   ├── remote-state.md
│   ├── service-accounts.md
│   └── terraform.md
└── topics/                     # Guides, runbooks, processes (verbs/actions)
    ├── first-deployment.md
    ├── development/
    │   ├── application-default-credentials.md
    │   ├── extending-zilch.md
    │   └── service-patterns.md
    └── troubleshooting/
        ├── common.md
        └── health-checks.md
```

**Rules:**
- `entities/` contains descriptions of **things** (Cloud Run, Terraform, configuration, etc.)
- `topics/` contains **actions** (how to deploy, how to troubleshoot, how to extend)
- All markdown files must reside in `entities/`, `topics/`, or subdirectories thereof
- INDEX.md and log.md are the only root-level wiki files
- File names are lowercase with hyphens (no underscores, no spaces)

## Frontmatter Requirements

Every markdown file in `docs/wiki/` **must** include YAML frontmatter in this format:

```yaml
---
tags: [tag1, tag2, tag3]
last_updated: 2026-06-20
---
```

**Rules:**
- Frontmatter is enclosed by `---` delimiters (opening and closing)
- `tags` is an array of lowercase, hyphenated strings (e.g., `deployment`, `gcp-services`, `python`)
- `last_updated` is an ISO 8601 date string (YYYY-MM-DD)
- Frontmatter is required for all .md files
- Exception: Internal temporary or auto-generated files may omit frontmatter if documented in this schema

**Tag Guidelines:**
- Use consistent tags across related pages
- Examples: `deployment`, `configuration`, `gcp-services`, `troubleshooting`, `python`, `terraform`, `authentication`

## Changelog Format (log.md)

The file `docs/wiki/log.md` tracks all modifications to the wiki using this format:

```markdown
## [YYYY-MM-DD] [operation] | Description

Brief explanation of what was changed and why. List affected pages if more than one.

---
```

**Operations:**
- `lint` – Corrected formatting, frontmatter, or minor corrections
- `ingest` – Integrated new content (e.g., from migration docs)
- `update` – Modified existing page content
- `add` – Created a new page
- `remove` – Deleted a page
- `rebuild` – Rewrote or restructured a page significantly

**Examples:**
```markdown
## [2026-06-20] lint | Initialized LLM Wiki architecture and schema.

Set up root CLAUDE.md with directory rules, frontmatter standards, and operational workflows.

---

## [2026-06-20] ingest | Migrated Python architecture from IMPLEMENTATION_SUMMARY.md.

Updated pages: deployment-workflow.md, configuration.md, deployment-reliability.md, first-deployment.md, troubleshooting/common.md. Removed all Bash script references and documented Python architecture and zilch.py commands.

---
```

## Operational Workflows

### 1. INGEST Workflow

**Purpose:** Integrate new information (migration docs, implementation summaries) into the wiki.

**Process:**
1. Read source document (e.g., IMPLEMENTATION_SUMMARY.md, PYTHON_MIGRATION_PLAN.md)
2. Identify which wiki pages should receive updates
3. For each page:
   a. Read the current page and its frontmatter
   b. Update content to remove outdated references (e.g., Bash scripts, old architecture)
   c. Add new information aligned with source document
   d. Ensure frontmatter is present and updated (`last_updated` to current date)
   e. Preserve existing structure and cross-links
4. Append entry to `log.md` with operation `ingest`
5. Commit with message: `docs(wiki): ingest [summary of changes]`

**Guard Rails:**
- Never delete pages without explicit approval
- Always preserve cross-references and link integrity
- Update INDEX.md if new pages are added

### 2. QUERY Workflow

**Purpose:** Find information in the wiki using tags and content search.

**Process:**
1. Determine what information is needed (e.g., "deployment configuration", "troubleshooting")
2. Use tags in frontmatter to locate relevant pages
3. Read relevant pages in order (usually: topics/ first, then entities/)
4. Cross-reference via links and INDEX.md
5. Synthesize answer from multiple pages if needed

**Tag Search Examples:**
- `deployment` → all pages tagged `deployment`
- `python` → pages related to Python architecture
- `gcp-services` → pages about GCP service integrations
- `troubleshooting` → debugging and issue resolution

### 3. LINT Workflow

**Purpose:** Maintain wiki quality: correct frontmatter, verify links, update timestamps.

**Process:**
1. Scan all .md files in `docs/wiki/`
2. For each file:
   a. Verify YAML frontmatter is present and valid
   b. Check that `last_updated` is a valid ISO 8601 date
   c. Verify `tags` array contains only lowercase, hyphenated strings
   d. Check for broken links (references to pages that don't exist)
   e. Ensure file name follows naming convention (lowercase, hyphens)
   f. Correct any issues found
3. Verify INDEX.md lists all pages (except log.md and itself)
4. Verify log.md follows changelog format
5. Append entry to `log.md` with operation `lint` if changes made
6. Commit with message: `docs(wiki): lint [summary of fixes]`

**Lint Checks (Priority Order):**
1. Frontmatter validity (YAML syntax)
2. Required fields present (tags, last_updated)
3. File naming conventions
4. Broken links
5. Tag consistency
6. Markdown formatting

## Verification Checklist

Use this checklist after any wiki maintenance operation:

- [ ] All .md files in `docs/wiki/` have valid YAML frontmatter
- [ ] Each file has `tags: [...]` array with valid tag strings
- [ ] Each file has `last_updated: YYYY-MM-DD` with today's date (if modified)
- [ ] INDEX.md lists every .md file in `docs/wiki/` (except log.md itself)
- [ ] All internal links in wiki pages are correct and reference existing files
- [ ] No file names contain spaces, underscores, or uppercase letters (except in frontmatter)
- [ ] log.md has entries for all operations performed, in reverse chronological order
- [ ] No references to Bash scripts (deploy.sh, teardown.sh, common.sh) remain in entity or topic pages
- [ ] All Python architecture references are documented (zilch.py commands, modules, classes)
- [ ] Markdown formatting is consistent (headings, lists, code blocks)
- [ ] No orphaned pages (pages not referenced in INDEX.md or cross-links)

## Related Documentation

- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** — Python architecture and migration details
- **[PYTHON_MIGRATION_PLAN.md](PYTHON_MIGRATION_PLAN.md)** — Python migration roadmap
- **[docs/wiki/INDEX.md](docs/wiki/INDEX.md)** — Wiki entry point and page listing
- **[docs/wiki/log.md](docs/wiki/log.md)** — Changelog and operation history
