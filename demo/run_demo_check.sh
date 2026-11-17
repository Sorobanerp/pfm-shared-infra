#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/dantas/.nvm/versions/node/v24.13.0/bin:/home/dantas/.local/bin:$PATH"
WORKSPACE="/home/dantas/workspace/pfm-platform"
DEMO_TENANT_ID="dddddddd-dddd-4ddd-8ddd-dddddddddddd"

echo "=================================================================="
echo " 1. Ensuring Full-Stack Local Environment is Up & Seeded"
echo "=================================================================="
"$WORKSPACE/pfm-shared-infra/scripts/up-all-local.sh"
"$WORKSPACE/pfm-shared-infra/demo/seed_demo_tenant.sh"

echo "=================================================================="
echo " 2. Verifying Demo Tenant State across UC-01 through UC-06"
echo "=================================================================="

# UC-01 & UC-06: Verify Tenant, 2 Members, 4 Cards, 2 Contracts & 10x Installments in PostgreSQL under RLS
docker exec -i postgres-core-ledger psql -U pfm_app_user -d pfm_core_ledger -tA <<SQL
BEGIN;
SET LOCAL app.current_tenant_id = '${DEMO_TENANT_ID}';
SELECT 'TENANT=' || name || ' | INCOME=' || monthly_net_income FROM tenants;
SELECT 'MEMBERS=' || count(*) FROM tenant_members;
SELECT 'CARDS=' || count(*) FROM credit_cards;
SELECT 'CONTRACTS=' || count(*) FROM financial_contracts;
SELECT 'INSTALLMENTS_10X=' || count(*) || ' | LAST_PARC=' || max(amount) FROM installment_schedules;
SELECT 'INBOX_PENDING_OUTROS=' || count(*) FROM ledger_entries WHERE category_code = 'OUTROS';
COMMIT;
SQL

# Run automated E2E validator (UC-01..UC-06)
"$WORKSPACE/pfm-ai-worker-python/.venv/bin/python" "$WORKSPACE/pfm-shared-infra/e2e/e2e_validator.py" >/dev/null
echo "  [OK] E2E Validator (UC-01 through UC-06) -> 100% APROVADO"

# Re-seed demo tenant so interactive demo starts with fresh data
"$WORKSPACE/pfm-shared-infra/demo/seed_demo_tenant.sh" >/dev/null

echo "=================================================================="
echo " 3. Verifying All 4 Web App Routes on http://localhost:18300"
echo "=================================================================="
for route in "/" "/cards" "/inbox" "/contracts"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:18300${route}")
  if [ "$code" != "200" ]; then
    echo "  [FAIL] Route http://localhost:18300${route} returned HTTP $code"
    exit 1
  fi
  echo "  [OK] Web Route http://localhost:18300${route} -> HTTP 200 OK"
done

echo "=================================================================="
echo " 4. Running Headless Playwright Rehearsal on Live Demo Stack"
echo "=================================================================="
cd "$WORKSPACE/pfm-web-nextjs"
npx playwright test

echo "=================================================================="
echo " DEMO REHEARSAL 100% READY FOR LIVE PRESENTATION!"
echo "=================================================================="
