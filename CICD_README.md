# Serverless Migration CI/CD Pipeline

Automated deployment pipeline for Snowflake serverless features using GitHub Actions.

## Components

| Component | File | Description |
|-----------|------|-------------|
| **Snowpipe** | `definitions/snowpipe.sql` | Continuous data loading from cloud storage |
| **Dynamic Tables** | `definitions/dynamic_tables.sql` | Bronze → Silver → Gold medallion pipeline |
| **Streams** | `definitions/streams.sql` | Change Data Capture (CDC) |
| **Tasks** | `definitions/tasks.sql` | Serverless and scheduled processing |

## Pipeline Workflows

### CI Workflow (`ci.yml`)
- **Triggers**: Pull requests to `main` or `develop`
- **Actions**: Validates SQL syntax with `--dry-run`

### Deploy Workflow (`deploy.yml`)
- **Triggers**: Push to `main` or manual dispatch
- **Actions**: Deploys all serverless objects to Snowflake

## Setup Instructions

### 1. Configure GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description | Example |
|--------|-------------|---------|
| `SNOWFLAKE_ACCOUNT` | Account identifier | `abc12345.us-east-1` |
| `SNOWFLAKE_USER` | Service account username | `CICD_USER` |
| `SNOWFLAKE_PASSWORD` | Service account password | `***` |
| `SNOWFLAKE_ROLE` | Deployment role | `SYSADMIN` |
| `SNOWFLAKE_WAREHOUSE` | Compute warehouse | `COMPUTE_WH` |
| `SNOWFLAKE_DATABASE` | Target database | `DEMO_INGEST_DB` |

### 2. Create Service Account (Recommended)

```sql
-- Create dedicated CI/CD user
CREATE USER CICD_USER
    PASSWORD = '<strong-password>'
    DEFAULT_ROLE = SYSADMIN
    MUST_CHANGE_PASSWORD = FALSE;

-- Grant necessary privileges
GRANT ROLE SYSADMIN TO USER CICD_USER;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE SYSADMIN;
```

### 3. Test the Pipeline

```bash
# Create a feature branch
git checkout -b feature/update-dynamic-tables

# Make changes to SQL files
# ...

# Push and create PR (triggers CI)
git push -u origin feature/update-dynamic-tables

# Merge to main (triggers deploy)
```

## Manual Deployment

Use workflow dispatch to deploy specific components:

1. Go to **Actions → Deploy Serverless Objects**
2. Click **Run workflow**
3. Select environment and component
4. Click **Run workflow**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Repository                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ snowpipe.sql│  │dynamic_     │  │ tasks.sql   │          │
│  │             │  │tables.sql   │  │             │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
└─────────┼────────────────┼────────────────┼─────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────┐
│                   GitHub Actions CI/CD                       │
│  ┌─────────────────────┐  ┌─────────────────────┐           │
│  │   CI: Validate      │  │   Deploy: Execute   │           │
│  │   (--dry-run)       │  │   (snow sql)        │           │
│  └─────────────────────┘  └─────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       Snowflake                              │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐│
│  │ Snowpipe  │  │  Dynamic  │  │  Streams  │  │   Tasks   ││
│  │           │  │  Tables   │  │           │  │           ││
│  └───────────┘  └───────────┘  └───────────┘  └───────────┘│
│        │              │              │              │        │
│        ▼              ▼              ▼              ▼        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                  DEMO_INGEST_DB                          ││
│  │  RAW → BRONZE → SILVER → GOLD                           ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Cost Optimization

| Pattern | Before | After | Savings |
|---------|--------|-------|---------|
| Frequent COPY INTO | Warehouse | Snowpipe | 40-70% |
| Scheduled CTAS | Tasks | Dynamic Tables | 20-40% |
| Short tasks | Warehouse | Serverless Tasks | 10-30% |
