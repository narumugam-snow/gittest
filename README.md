# Git Process for Snowflake Objects with GitHub

A comprehensive guide for DevOps engineers to implement version control and CI/CD for Snowflake database objects using DCM (Database Change Management).

## Overview

This repository demonstrates how to:
- Version control Snowflake objects (tables, views, dynamic tables, roles, grants)
- Implement GitOps workflow with feature branches and pull requests
- Automate deployments with GitHub Actions
- Manage multiple environments (DEV, PROD)

## Prerequisites

- Snowflake account with appropriate privileges
- GitHub repository
- `snow` CLI installed (Snowflake CLI)
- Service account for CI/CD deployments

---

## Step 1: Repository Structure

```
snowflake-dcm-project/
├── .github/
│   └── workflows/
│       ├── ci.yml              # PR validation
│       └── deploy.yml          # Production deployment
├── definitions/
│   ├── infrastructure.sql      # Databases, schemas, warehouses
│   ├── tables.sql              # Table definitions
│   ├── dynamic_tables.sql      # Dynamic tables
│   ├── views.sql               # Views
│   └── access.sql              # Roles and grants
├── manifest.yml                # DCM project configuration
├── .gitignore
└── README.md
```

---

## Step 2: Create DCM Project Configuration

### manifest.yml

```yaml
manifest_version: 1

include_definitions:
  - definitions/.*

type: DCM_PROJECT

configurations:
  DEV:
    env: "DEV"
    db_suffix: "_DEV"
    wh_size: "X-SMALL"
    
  PROD:
    env: "PROD"
    db_suffix: ""
    wh_size: "MEDIUM"
```

---

## Step 3: Define Snowflake Objects

### definitions/infrastructure.sql

```sql
-- Database
DEFINE DATABASE ANALYTICS{{db_suffix}};

-- Schemas
DEFINE SCHEMA ANALYTICS{{db_suffix}}.RAW;
DEFINE SCHEMA ANALYTICS{{db_suffix}}.STAGING;
DEFINE SCHEMA ANALYTICS{{db_suffix}}.MARTS;

-- Warehouse
DEFINE WAREHOUSE ANALYTICS_WH_{{env}}
WITH
    WAREHOUSE_SIZE = '{{wh_size}}'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

### definitions/tables.sql

```sql
-- Raw layer tables
DEFINE TABLE ANALYTICS{{db_suffix}}.RAW.CUSTOMERS (
    CUSTOMER_ID NUMBER PRIMARY KEY,
    CUSTOMER_NAME VARCHAR(255),
    EMAIL VARCHAR(255),
    REGION VARCHAR(50),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE;

DEFINE TABLE ANALYTICS{{db_suffix}}.RAW.ORDERS (
    ORDER_ID NUMBER PRIMARY KEY,
    CUSTOMER_ID NUMBER,
    ORDER_DATE DATE,
    ORDER_AMOUNT DECIMAL(18,2),
    STATUS VARCHAR(50),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE;
```

### definitions/dynamic_tables.sql

```sql
-- Staging layer - cleaned data
DEFINE DYNAMIC TABLE ANALYTICS{{db_suffix}}.STAGING.CUSTOMERS_CLEAN
    TARGET_LAG = '5 minutes'
    WAREHOUSE = ANALYTICS_WH_{{env}}
AS
SELECT 
    CUSTOMER_ID,
    TRIM(UPPER(CUSTOMER_NAME)) AS CUSTOMER_NAME,
    LOWER(TRIM(EMAIL)) AS EMAIL,
    UPPER(REGION) AS REGION,
    CREATED_AT,
    UPDATED_AT
FROM ANALYTICS{{db_suffix}}.RAW.CUSTOMERS
WHERE CUSTOMER_ID IS NOT NULL;

-- Marts layer - aggregated data
DEFINE DYNAMIC TABLE ANALYTICS{{db_suffix}}.MARTS.CUSTOMER_ORDERS_SUMMARY
    TARGET_LAG = '1 hour'
    WAREHOUSE = ANALYTICS_WH_{{env}}
AS
SELECT 
    c.CUSTOMER_ID,
    c.CUSTOMER_NAME,
    c.REGION,
    COUNT(o.ORDER_ID) AS TOTAL_ORDERS,
    SUM(o.ORDER_AMOUNT) AS TOTAL_REVENUE,
    AVG(o.ORDER_AMOUNT) AS AVG_ORDER_VALUE,
    MAX(o.ORDER_DATE) AS LAST_ORDER_DATE
FROM ANALYTICS{{db_suffix}}.STAGING.CUSTOMERS_CLEAN c
LEFT JOIN ANALYTICS{{db_suffix}}.RAW.ORDERS o 
    ON c.CUSTOMER_ID = o.CUSTOMER_ID
GROUP BY c.CUSTOMER_ID, c.CUSTOMER_NAME, c.REGION;
```

### definitions/access.sql

```sql
-- Roles
DEFINE ROLE ANALYTICS_{{env}}_ADMIN;
DEFINE ROLE ANALYTICS_{{env}}_READ;
DEFINE ROLE ANALYTICS_{{env}}_WRITE;

-- Grants for READ role
GRANT USAGE ON DATABASE ANALYTICS{{db_suffix}} TO ROLE ANALYTICS_{{env}}_READ;
GRANT USAGE ON ALL SCHEMAS IN DATABASE ANALYTICS{{db_suffix}} TO ROLE ANALYTICS_{{env}}_READ;
GRANT SELECT ON ALL TABLES IN DATABASE ANALYTICS{{db_suffix}} TO ROLE ANALYTICS_{{env}}_READ;
GRANT SELECT ON ALL VIEWS IN DATABASE ANALYTICS{{db_suffix}} TO ROLE ANALYTICS_{{env}}_READ;
GRANT SELECT ON ALL DYNAMIC TABLES IN DATABASE ANALYTICS{{db_suffix}} TO ROLE ANALYTICS_{{env}}_READ;

-- Grants for WRITE role
GRANT ROLE ANALYTICS_{{env}}_READ TO ROLE ANALYTICS_{{env}}_WRITE;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ANALYTICS{{db_suffix}}.RAW TO ROLE ANALYTICS_{{env}}_WRITE;

-- Grants for ADMIN role
GRANT ROLE ANALYTICS_{{env}}_WRITE TO ROLE ANALYTICS_{{env}}_ADMIN;
GRANT ALL PRIVILEGES ON DATABASE ANALYTICS{{db_suffix}} TO ROLE ANALYTICS_{{env}}_ADMIN;
```

---

## Step 4: Initialize DCM Project in Snowflake

```bash
# Create the DCM project in Snowflake (one-time setup)
snow dcm create ADMIN_DB.DCM.ANALYTICS_PROJECT -c <your-connection>
```

---

## Step 5: Git Workflow

### Branching Strategy

```
main (production)
  │
  ├── develop (integration)
  │     │
  │     ├── feature/add-products-table
  │     ├── feature/update-customer-schema
  │     └── fix/column-type-mismatch
```

### Development Workflow

```bash
# 1. Create feature branch
git checkout -b feature/add-products-table

# 2. Make changes to definition files
# Edit definitions/tables.sql

# 3. Validate locally
snow dcm analyze ADMIN_DB.DCM.ANALYTICS_PROJECT -c dev-connection \
    --configuration DEV \
    --output-path ./out/analyze

# 4. Review plan (what will change)
snow dcm plan ADMIN_DB.DCM.ANALYTICS_PROJECT -c dev-connection \
    --configuration DEV \
    --output-path ./out/plan

# 5. Deploy to DEV for testing
snow dcm deploy ADMIN_DB.DCM.ANALYTICS_PROJECT -c dev-connection \
    --configuration DEV \
    --alias "feature-products-table"

# 6. Commit and push
git add .
git commit -m "feat: add products table to raw schema"
git push origin feature/add-products-table

# 7. Create Pull Request
gh pr create --title "Add products table" --body "Adds PRODUCTS table to RAW schema"
```

---

## Step 6: GitHub Actions CI/CD

### .github/workflows/ci.yml (Pull Request Validation)

```yaml
name: DCM Validate

on:
  pull_request:
    branches: [main, develop]
    paths:
      - 'definitions/**'
      - 'manifest.yml'

env:
  SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
  SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
  SNOWFLAKE_PASSWORD: ${{ secrets.SNOWFLAKE_PASSWORD }}
  SNOWFLAKE_ROLE: ${{ secrets.SNOWFLAKE_ROLE }}
  SNOWFLAKE_WAREHOUSE: ${{ secrets.SNOWFLAKE_WAREHOUSE }}

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Snowflake CLI
        run: |
          pip install snowflake-cli-labs

      - name: Configure Snowflake connection
        run: |
          mkdir -p ~/.snowflake
          cat > ~/.snowflake/connections.toml << EOF
          [ci]
          account = "$SNOWFLAKE_ACCOUNT"
          user = "$SNOWFLAKE_USER"
          password = "$SNOWFLAKE_PASSWORD"
          role = "$SNOWFLAKE_ROLE"
          warehouse = "$SNOWFLAKE_WAREHOUSE"
          EOF

      - name: Clean output directory
        run: rm -rf ./out

      - name: DCM Analyze
        run: |
          snow dcm analyze ADMIN_DB.DCM.ANALYTICS_PROJECT \
            -c ci \
            --configuration DEV \
            --output-path ./out/analyze

      - name: Check analyze results
        run: |
          if [ -f ./out/analyze/analyze_output.json ]; then
            echo "=== Analyze Output ==="
            cat ./out/analyze/analyze_output.json | jq '.'
            
            # Check for errors
            ERRORS=$(cat ./out/analyze/analyze_output.json | jq '[.. | objects | select(has("errors")) | .errors[]] | length')
            if [ "$ERRORS" -gt 0 ]; then
              echo "::error::Found $ERRORS errors in analysis"
              exit 1
            fi
          fi

      - name: DCM Plan
        run: |
          rm -rf ./out/plan
          snow dcm plan ADMIN_DB.DCM.ANALYTICS_PROJECT \
            -c ci \
            --configuration DEV \
            --output-path ./out/plan

      - name: Generate Plan Summary
        id: plan
        run: |
          if [ -f ./out/plan/plan_output.json ]; then
            echo "=== Plan Output ==="
            
            # Check status
            STATUS=$(cat ./out/plan/plan_output.json | jq -r '.status')
            if [ "$STATUS" = "PLAN_FAILED" ]; then
              ERROR=$(cat ./out/plan/plan_output.json | jq -r '.error')
              echo "::error::Plan failed: $ERROR"
              exit 1
            fi
            
            # Count operations
            CREATES=$(cat ./out/plan/plan_output.json | jq '[.ddlChangeLog.operations[]? | select(.operationType == "CREATE")] | length')
            ALTERS=$(cat ./out/plan/plan_output.json | jq '[.ddlChangeLog.operations[]? | select(.operationType == "ALTER")] | length')
            DROPS=$(cat ./out/plan/plan_output.json | jq '[.ddlChangeLog.operations[]? | select(.operationType == "DROP")] | length')
            
            echo "## DCM Plan Summary" >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "| Operation | Count |" >> $GITHUB_STEP_SUMMARY
            echo "|-----------|-------|" >> $GITHUB_STEP_SUMMARY
            echo "| CREATE | $CREATES |" >> $GITHUB_STEP_SUMMARY
            echo "| ALTER | $ALTERS |" >> $GITHUB_STEP_SUMMARY
            echo "| DROP | $DROPS |" >> $GITHUB_STEP_SUMMARY
            
            if [ "$DROPS" -gt 0 ]; then
              echo "" >> $GITHUB_STEP_SUMMARY
              echo "::warning::This PR includes $DROPS DROP operations. Please review carefully."
            fi
          fi

      - name: Upload plan artifacts
        uses: actions/upload-artifact@v4
        with:
          name: dcm-plan
          path: ./out/
```

### .github/workflows/deploy.yml (Production Deployment)

```yaml
name: DCM Deploy

on:
  push:
    branches: [main]
    paths:
      - 'definitions/**'
      - 'manifest.yml'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        default: 'PROD'
        type: choice
        options:
          - DEV
          - PROD

env:
  SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
  SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_DEPLOY_USER }}
  SNOWFLAKE_PASSWORD: ${{ secrets.SNOWFLAKE_DEPLOY_PASSWORD }}
  SNOWFLAKE_ROLE: ${{ secrets.SNOWFLAKE_DEPLOY_ROLE }}
  SNOWFLAKE_WAREHOUSE: ${{ secrets.SNOWFLAKE_WAREHOUSE }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment || 'PROD' }}
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Snowflake CLI
        run: pip install snowflake-cli-labs

      - name: Configure Snowflake connection
        run: |
          mkdir -p ~/.snowflake
          cat > ~/.snowflake/connections.toml << EOF
          [deploy]
          account = "$SNOWFLAKE_ACCOUNT"
          user = "$SNOWFLAKE_USER"
          password = "$SNOWFLAKE_PASSWORD"
          role = "$SNOWFLAKE_ROLE"
          warehouse = "$SNOWFLAKE_WAREHOUSE"
          EOF

      - name: Set environment
        id: env
        run: |
          ENV="${{ github.event.inputs.environment || 'PROD' }}"
          echo "environment=$ENV" >> $GITHUB_OUTPUT

      - name: Clean and Analyze
        run: |
          rm -rf ./out
          snow dcm analyze ADMIN_DB.DCM.ANALYTICS_PROJECT \
            -c deploy \
            --configuration ${{ steps.env.outputs.environment }} \
            --output-path ./out/analyze

      - name: Plan
        run: |
          snow dcm plan ADMIN_DB.DCM.ANALYTICS_PROJECT \
            -c deploy \
            --configuration ${{ steps.env.outputs.environment }} \
            --output-path ./out/plan

      - name: Validate Plan
        run: |
          STATUS=$(cat ./out/plan/plan_output.json | jq -r '.status')
          if [ "$STATUS" = "PLAN_FAILED" ]; then
            echo "::error::Plan failed"
            exit 1
          fi

      - name: Deploy
        run: |
          ALIAS="github-${{ github.run_number }}-${{ github.sha }}"
          snow dcm deploy ADMIN_DB.DCM.ANALYTICS_PROJECT \
            -c deploy \
            --configuration ${{ steps.env.outputs.environment }} \
            --alias "$ALIAS"

      - name: Refresh Dynamic Tables
        run: |
          snow dcm refresh ADMIN_DB.DCM.ANALYTICS_PROJECT -c deploy

      - name: Run Tests
        run: |
          snow dcm test ADMIN_DB.DCM.ANALYTICS_PROJECT \
            -c deploy \
            --output-path ./out/test || true

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: deployment-artifacts
          path: ./out/
```

---

## Step 7: .gitignore Configuration

```gitignore
# DCM output directories
out/

# Snowflake CLI config (contains secrets)
.snowflake/

# OS files
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/

# Logs
*.log
```

---

## Step 8: GitHub Repository Setup

### Required Secrets

Configure these secrets in GitHub repository settings:

| Secret | Description |
|--------|-------------|
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier |
| `SNOWFLAKE_USER` | CI user for PR validation |
| `SNOWFLAKE_PASSWORD` | CI user password |
| `SNOWFLAKE_DEPLOY_USER` | Deployment service account |
| `SNOWFLAKE_DEPLOY_PASSWORD` | Deployment account password |
| `SNOWFLAKE_ROLE` | Role for DCM operations |
| `SNOWFLAKE_DEPLOY_ROLE` | Role for production deployments |
| `SNOWFLAKE_WAREHOUSE` | Warehouse for DCM operations |

### Branch Protection Rules

Configure for `main` branch:
- Require pull request reviews (1+ approvals)
- Require status checks to pass (DCM Validate)
- Require branches to be up to date
- Restrict who can push (protect from direct commits)

---

## Step 9: Complete Workflow Example

```bash
# 1. Clone repository
git clone https://github.com/your-org/snowflake-dcm-project.git
cd snowflake-dcm-project

# 2. Create feature branch
git checkout -b feature/add-inventory-table

# 3. Add new table definition
cat >> definitions/tables.sql << 'EOF'

DEFINE TABLE ANALYTICS{{db_suffix}}.RAW.INVENTORY (
    INVENTORY_ID NUMBER PRIMARY KEY,
    PRODUCT_ID NUMBER,
    WAREHOUSE_LOCATION VARCHAR(100),
    QUANTITY NUMBER,
    LAST_UPDATED TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE;
EOF

# 4. Validate locally
snow dcm analyze ADMIN_DB.DCM.ANALYTICS_PROJECT -c dev \
    --configuration DEV --output-path ./out/analyze

# 5. Check plan
snow dcm plan ADMIN_DB.DCM.ANALYTICS_PROJECT -c dev \
    --configuration DEV --output-path ./out/plan

# View plan summary
cat ./out/plan/plan_output.json | jq '.ddlChangeLog.operations[] | {type: .operationType, object: .objectName}'

# 6. Test in DEV
snow dcm deploy ADMIN_DB.DCM.ANALYTICS_PROJECT -c dev \
    --configuration DEV --alias "feature-inventory"

# 7. Commit and push
git add definitions/tables.sql
git commit -m "feat: add inventory table for warehouse tracking"
git push origin feature/add-inventory-table

# 8. Create PR (triggers CI validation)
gh pr create \
    --title "Add inventory table" \
    --body "## Summary
- Adds INVENTORY table to RAW schema
- Enables warehouse inventory tracking

## Testing
- Validated in DEV environment
- Plan shows 1 CREATE operation"

# 9. After PR approval and merge, GitHub Actions deploys to PROD
```

---

## Best Practices

### 1. Always Validate Before Committing
```bash
snow dcm analyze ... --output-path ./out/analyze
snow dcm plan ... --output-path ./out/plan
```

### 2. Use Meaningful Commit Messages
```
feat: add new customer dimension table
fix: correct column type in orders table  
refactor: reorganize schema structure
docs: update access control documentation
```

### 3. Review DROP Operations Carefully
- PRs with DROP operations should require additional review
- Consider using `--alias` to track deployment versions

### 4. Test in DEV First
- Always deploy to DEV and validate before merging to main
- Use preview command to spot-check data

### 5. Use Deployment Aliases
```bash
snow dcm deploy ... --alias "release-v2.1.0"
```

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `Plan shows unexpected changes` | Compare DCM definition with `GET_DDL()` output |
| `Permission denied` | Verify role has required privileges |
| `Object not found` | Ensure database/schema exists before objects |
| `CI fails on analyze` | Check for syntax errors in definition files |

### Useful Commands

```bash
# List all DCM projects
snow dcm list -c <connection> --database ""

# View deployment history
snow dcm list-deployments ADMIN_DB.DCM.ANALYTICS_PROJECT -c <connection>

# Preview data after deployment
snow dcm preview ADMIN_DB.DCM.ANALYTICS_PROJECT -c <connection> \
    --object ANALYTICS.RAW.CUSTOMERS --limit 10

# Rollback (drop deployment)
snow dcm drop-deployment ADMIN_DB.DCM.ANALYTICS_PROJECT 'DEPLOYMENT$1' -c <connection>
```

---

## Summary

| Step | Description | Commands/Files |
|------|-------------|----------------|
| 1 | Setup repository structure | Create directories |
| 2 | Configure DCM manifest | `manifest.yml` |
| 3 | Define Snowflake objects | `definitions/*.sql` |
| 4 | Initialize DCM project | `snow dcm create` |
| 5 | Implement Git workflow | Feature branches, PRs |
| 6 | Setup GitHub Actions | CI/CD workflows |
| 7 | Configure secrets | GitHub Settings |
| 8 | Protect branches | Branch rules |
| 9 | Deploy changes | Merge to main |

This process ensures:
- All Snowflake changes are version controlled
- Changes are validated before deployment
- Production deployments are automated and auditable
- Rollback capability through deployment tracking
