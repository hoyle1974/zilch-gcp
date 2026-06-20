# MySQL Service for Zilch (Future Plan)

**Status:** Design in progress (2026-06-19)  
**Author:** Claude Code  
**Target Release:** TBD

---

## Overview

Add managed MySQL database support to Zilch, enabling indie developers and solo engineers to deploy production-grade relational SQL applications on GCP's Always Free tier (compute cost ~$0, storage cost ~$0.40/month).

This service provides an alternative to Firestore (NoSQL) for applications requiring transactional relational data, ACID compliance, and complex queries.

---

## Problem Statement

Current Zilch services include Firestore (NoSQL) but lack relational SQL database options:
- **Cloud SQL** (GCP's managed database): $7-15/month minimum (breaks Always Free philosophy)
- **SQLite + Cloud Storage**: Free but suffers from single-writer concurrency bottlenecks under load
- **No SQL option**: Forces users to Firestore or paid alternatives

Zilch's target audience (indie hackers, solo developers) often need relational data but cannot afford $7-15/month database costs.

---

## Solution: Compute Engine e2-micro + MySQL

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  GCP Project                                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────┐        ┌────────────────────────┐ │
│  │ Cloud Run (Apps)     │        │ Compute Engine e2-micro│ │
│  │                      │        │ (Always Free)          │ │
│  │ ┌────────────────┐   │        │                        │ │
│  │ │ App Code       │   │        │ ┌──────────────────┐  │ │
│  │ │ (Python/Node)  │   │        │ │ MySQL 8.0        │  │ │
│  │ └────────────────┘   │        │ │ (Docker)         │  │ │
│  │        ↓             │        │ │                  │  │ │
│  │ Cloud SQL Proxy ────────────→│ │ :3306            │  │ │
│  │ (encrypted tunnel)   │        │ │                  │  │ │
│  │                      │        │ │ /data (30GB PD)  │  │ │
│  │                      │        │ │                  │  │ │
│  │ Env vars:           │        │ └──────────────────┘  │ │
│  │ ZILCH_MYSQL_*       │        │                        │ │
│  └────────────────────┘        └────────────────────────┘ │
│                                           ↓                │
│                                    [Persistent Disk]       │
│                                     (~$0.40/month)         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Components

1. **Compute Engine e2-micro VM** (Always Free tier)
   - Location: us-central1 (Always Free region)
   - Compute cost: $0/month (Always Free)
   - Uptime: Always on (not auto-scaling)
   - Storage: 30GB persistent disk (~$0.40/month)

2. **MySQL 8.0 in Docker**
   - Container-based deployment for simplicity
   - Startup script handles initialization on first boot
   - Data stored on persistent disk

3. **Cloud SQL Proxy Sidecar** (in Cloud Run)
   - Encrypted tunnel from Cloud Run to e2-micro
   - IAM-authenticated (no credentials in environment)
   - Free (part of Cloud SQL Proxy)

4. **Migration Management**
   - Zilch provides `db/migrations/` directory for `.sql` files
   - `./migrate.sh` helper script to run migrations
   - Version-controlled schema evolution

### Developer Access Patterns

**Option 1: Cloud SQL Proxy (Local Development)**
```bash
# Install once: gcloud components install cloud-sql-proxy
cloud-sql-proxy compute/PROJECT/REGION/VM-NAME &
mysql -h 127.0.0.1 -u zilch_user -p
```
- IAM-authenticated, secure, encrypted
- Best for development and debugging

**Option 2: SSH Bastion (Direct VM Access)**
```bash
gcloud compute ssh zilch-mysql-vm --zone=us-central1-a
# Then connect to MySQL on localhost
mysql -u zilch_user -p
```
- Direct access for ops/troubleshooting
- SSH keys managed by gcloud

**Option 3: Migration Scripts (Automated Schema Management)**
```bash
# User commits SQL files to version control
db/migrations/
  001-initial-schema.sql
  002-add-users-table.sql
  003-add-indexes.sql

# Run migrations
./migrate.sh up
./migrate.sh rollback  # if needed
```
- Version-controlled schema evolution
- Repeatable, idempotent migrations
- Dry-run mode for safety

---

## Cost Model

| Component | Cost | Notes |
|-----------|------|-------|
| Compute Engine e2-micro | $0/month | Always Free tier |
| Persistent Disk (30GB) | ~$0.40/month | Standard HDD |
| Cloud SQL Proxy | $0/month | Included in Cloud SQL Proxy |
| **Total** | **~$0.40/month** | Within "nearly free" philosophy |

---

## Performance Limits & Constraints

### Why MySQL (not PostgreSQL)?

MySQL chosen over PostgreSQL for e2-micro (1GB RAM):
- **20-30% faster** on typical OLTP workloads
- **Smaller memory footprint** (critical on 1GB RAM)
- PostgreSQL would require PgBouncer connection pooler (adds complexity)

### Performance Ceiling

| Metric | Limit | Notes |
|--------|-------|-------|
| **Read throughput** | ~1000s/sec | Limited by CPU, not I/O |
| **Write throughput** | ~100-500/sec | Single-instance constraint |
| **Concurrent requests** | 1000s | Handled by Cloud Run, queued at MySQL |
| **Data size** | 1-10GB ideal | Persistent disk can hold 30GB |
| **Query latency** | 1-50ms | Depends on query complexity |

### Constraints & Limitations

1. **Single Instance Bottleneck**
   - Only one e2-micro runs the database
   - No automatic failover (unlike Cloud SQL)
   - VM maintenance requires downtime planning

2. **Concurrency Model**
   - MySQL handles concurrent requests correctly
   - Writes are queued by MySQL's lock protocol
   - No issues with eventual consistency (unlike SQLite)

3. **Memory Constraints**
   - 1GB RAM shared between OS, MySQL, Docker overhead
   - Buffer pool limited to ~400-500MB
   - Large result sets may spill to disk

4. **Backup & Recovery**
   - Persistent disk snapshotting: Manual (not automatic)
   - No built-in replication (user responsibility)
   - Data loss risk during VM reboot without snapshot

5. **Scaling Limitations**
   - Cannot horizontally scale a single MySQL instance
   - Read replicas require additional infrastructure cost
   - Not suitable for write-heavy workloads beyond ~500/sec

### Workload Suitability

**Good fit:**
- Transactional OLTP (user accounts, orders, relationships)
- Indie/hobby apps with <1000 concurrent users
- Small data sets (< 5GB)
- Moderate write rates (< 100/sec)

**Poor fit:**
- High-concurrency systems (> 5000/sec writes)
- Data warehouse/analytics (use BigQuery instead)
- Multi-region deployment
- Zero-downtime requirements

---

## Zilch Integration

### New Terraform Resources

- `google_compute_instance` — e2-micro VM
- `google_compute_disk` — Persistent disk
- `google_compute_instance_from_template` — VM template with startup script
- IAM bindings for Cloud Run service account → VM access
- Firewall rules (MySQL port restricted to Cloud Run subnet)

### Updated Deployment Flow

1. **New variable in `variables.tf`:**
   ```hcl
   variable "enable_mysql" {
     type        = bool
     description = "Enable managed MySQL database"
     default     = false
   }
   ```

2. **Updated `deploy.sh`:**
   - Prompt user: "Enable MySQL database? (y/n)"
   - If yes: Run additional Terraform for e2-micro setup
   - Validate Cloud SQL Proxy installation for Cloud Run

3. **New directory structure:**
   ```
   zilch-gcp/
   ├── db/
   │   ├── migrations/           # User's schema files
   │   ├── migrate.sh            # Migration runner script
   │   └── init-schema.sql       # Zilch-provided base schema
   └── terraform/
       ├── mysql.tf              # All MySQL resources
       └── mysql-outputs.tf      # Environment variable outputs
   ```

4. **Environment variables passed to Cloud Run:**
   ```
   ZILCH_MYSQL_HOST         → Internal IP of e2-micro
   ZILCH_MYSQL_PORT         → 3306
   ZILCH_MYSQL_DATABASE     → auto-created database name
   ZILCH_MYSQL_USER         → zilch_user
   ZILCH_MYSQL_PASSWORD     → Generated, stored in Secret Manager
   ```

### Deployment Reliability

- **Startup scripts**: Handle MySQL initialization, data directory setup
- **Health checks**: VM reachability validation before Cloud Run deployment
- **Error recovery**: Detect MySQL container failures, warn user
- **Idempotent**: Safe to re-run `deploy.sh` (doesn't recreate VM if exists)

---

## Implementation Roadmap

### Phase 1: MVP (Basic MySQL support)
- [ ] Terraform resources for e2-micro + MySQL + persistent disk
- [ ] Cloud SQL Proxy sidecar in Cloud Run
- [ ] Environment variable plumbing
- [ ] Basic `migrate.sh` script
- [ ] Documentation on developer access patterns

### Phase 2: Production Hardening
- [ ] Automated backups (Cloud Storage snapshots)
- [ ] Monitoring & alerting (Cloud Monitoring)
- [ ] Log aggregation (Cloud Logging)
- [ ] SSH key management improvements
- [ ] Connection pooling optimization

### Phase 3: Advanced Features
- [ ] Read replicas (optional, paid)
- [ ] Multi-region support
- [ ] PostgreSQL support (post-MySQL)
- [ ] Automated failover (expensive, likely out of scope)

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| **VM maintenance downtime** | App goes offline during GCP maintenance | Auto-restart enabled, user notified in docs |
| **Data loss on VM failure** | Corruption, unrecoverable data | Persistent disk redundancy, manual snapshots |
| **Single point of failure** | No automatic failover | Document backup strategy, recommend snapshots |
| **Out-of-memory crashes** | MySQL OOM kill | Monitor, document memory limits, tune buffer pool |
| **Networking misconfiguration** | Cloud Run can't reach MySQL | Automated VPC setup, health checks, clear errors |

---

## Comparison to Alternatives

| Option | Cost/month | Concurrency | Ops Burden | Durability |
|--------|-----------|------------|-----------|-----------|
| **MySQL on e2-micro** | ~$0.40 | Excellent | Moderate | Good |
| **Cloud SQL** | $7-15 | Excellent | None | Excellent |
| **SQLite + Cloud Storage** | $0 | Poor (single-writer) | Low | Fair |
| **Firestore** | $0 | Excellent | None | Excellent |
| **PostgreSQL on e2-micro** | ~$0.40 | Excellent | Higher | Good |

---

## Questions for Design Review

1. **Backup strategy**: Should Zilch auto-snapshot persistent disk, or document manual approach?
2. **Connection pooling**: Should we bundle PgBouncer or rely on MySQL's built-in pooling?
3. **Multi-instance**: If user scales Cloud Run horizontally, do all instances share one MySQL VM? (Yes, and that's the design)
4. **Monitoring**: Should Zilch provide pre-configured Cloud Monitoring dashboards?
5. **PostgreSQL support**: Should we plan this as Phase 2 or separate effort?

---

## See Also

- **[Cloud Run](../entities/cloud-run.md)** — How Cloud Run connects to services
- **[Service Accounts](../entities/service-accounts.md)** — IAM for Cloud SQL Proxy
- **[Extending Zilch](../development/extending-zilch.md)** — How to add new services
- **[GCP Cloud SQL Pricing](https://cloud.google.com/sql/pricing)** — Why we avoid managed Cloud SQL
