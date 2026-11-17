#!/usr/bin/env bash
set -euo pipefail

DEMO_TENANT_ID="dddddddd-dddd-4ddd-8ddd-dddddddddddd"
MEMBER_OWNER_ID="dddd0001-dddd-4ddd-8ddd-000000000001"
MEMBER_SPOUSE_ID="dddd0002-dddd-4ddd-8ddd-000000000002"
ACCOUNT_MAIN_ID="dddd1001-dddd-4ddd-8ddd-000000000001"

CARD_ITAU_5285="dddd2001-dddd-4ddd-8ddd-000000005285"
CARD_ITAU_1360="dddd2002-dddd-4ddd-8ddd-000000001360"
CARD_BB_7741="dddd2003-dddd-4ddd-8ddd-000000007741"
CARD_MARISA_0912="dddd2004-dddd-4ddd-8ddd-000000000912"

CONTRACT_SAC_ID="dddd3001-dddd-4ddd-8ddd-000000000360"
CONTRACT_CONSORCIO_ID="dddd3002-dddd-4ddd-8ddd-000000000072"

PARENT_10X_ENTRY_ID="dddd4001-dddd-4ddd-8ddd-000000000010"
SUPERMARKET_ENTRY_ID="dddd4002-dddd-4ddd-8ddd-000000000313"

echo "[DEMO-SEED] Populating Tenant Demo 'Família Silva - Piloto MVP' ($DEMO_TENANT_ID)..."

docker exec -i postgres-core-ledger psql -v ON_ERROR_STOP=1 -U postgres -d pfm_core_ledger <<SQL
BEGIN;
SET LOCAL app.current_tenant_id = '${DEMO_TENANT_ID}';

-- Clean previous demo data for idempotency
DELETE FROM receipt_items WHERE tenant_id = '${DEMO_TENANT_ID}';
DELETE FROM installment_schedules WHERE tenant_id = '${DEMO_TENANT_ID}';
DELETE FROM outbox_events WHERE tenant_id = '${DEMO_TENANT_ID}';
DELETE FROM ledger_entries WHERE tenant_id = '${DEMO_TENANT_ID}';
DELETE FROM financial_contracts WHERE tenant_id = '${DEMO_TENANT_ID}';
DELETE FROM credit_cards WHERE tenant_id = '${DEMO_TENANT_ID}';
DELETE FROM tenant_members WHERE tenant_id = '${DEMO_TENANT_ID}';

-- 1. Tenant: Família Silva - Piloto MVP
INSERT INTO tenants (id, tenant_id, name, base_currency, monthly_net_income, status)
VALUES ('${DEMO_TENANT_ID}', '${DEMO_TENANT_ID}', 'Família Silva - Piloto MVP', 'BRL', 18200.0000, 'ACTIVE')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    monthly_net_income = EXCLUDED.monthly_net_income;

-- 2. Two Holders (OWNER & MEMBER)
INSERT INTO tenant_members (id, tenant_id, user_subject, email, role, spending_allowance) VALUES
('${MEMBER_OWNER_ID}', '${DEMO_TENANT_ID}', 'carlos.silva', 'carlos.silva@familiasilva.com.br', 'OWNER', 12000.0000),
('${MEMBER_SPOUSE_ID}', '${DEMO_TENANT_ID}', 'mariana.silva', 'mariana.silva@familiasilva.com.br', 'MEMBER', 6200.0000);

-- 3. Checking Account
INSERT INTO financial_accounts (id, tenant_id, account_name, institution_code, account_type, currency, current_balance)
VALUES ('${ACCOUNT_MAIN_ID}', '${DEMO_TENANT_ID}', 'Conta Conjunta Família Silva - Itaú', 'ITAU_341', 'CHECKING', 'BRL', 24500.0000)
ON CONFLICT (id) DO UPDATE SET current_balance = EXCLUDED.current_balance;

-- 4. Four Credit Cards (Itaú Black 5285, Itaú Platinum 1360, BB Ourocard, Marisa)
INSERT INTO credit_cards (id, tenant_id, financial_account_id, card_name, card_last_four, credit_limit, available_limit, closing_day, due_day) VALUES
('${CARD_ITAU_5285}', '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', 'Itaú Black 5285', '5285', 32000.0000, 16827.0500, 25, 5),
('${CARD_ITAU_1360}', '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', 'Itaú Platinum 1360', '1360', 15000.0000, 8749.2000, 20, 1),
('${CARD_BB_7741}',   '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', 'BB Ourocard', '7741', 14000.0000, 10455.0000, 18, 28),
('${CARD_MARISA_0912}', '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', 'Marisa Mastercard', '0912', 3500.0000, 2128.0000, 10, 20);

-- 5. Two Financial Contracts: 1 SAC Mortgage (360 months) + 1 Vehicle Consorcio (72 months)
INSERT INTO financial_contracts (id, tenant_id, contract_name, modality, principal_balance, monthly_interest_rate, consorcio_admin_fee_rate, monthly_insurance_fees, total_installments, remaining_installments, start_date) VALUES
('${CONTRACT_SAC_ID}', '${DEMO_TENANT_ID}', 'Financiamento Imobiliário SAC (360m)', 'SAC', 320000.0000, 0.0085, 0.0000, 85.0000, 360, 312, '2022-11-01'),
('${CONTRACT_CONSORCIO_ID}', '${DEMO_TENANT_ID}', 'Consórcio Veicular SUV (72m)', 'CONSORCIO', 115000.0000, 0.0000, 0.1600, 25.0000, 72, 54, '2025-05-01');

-- 6. 3-Month Historical Categorized Transactions (2026-09, 2026-10, 2026-11)
INSERT INTO ledger_entries (id, tenant_id, account_id, credit_card_id, category_code, subcategory_code, direction, entry_type, amount, currency, competence_date, cash_date, description, idempotency_key, reconciliation_status) VALUES
-- Month 1: 2026-09
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', NULL, 'MORADIA', 'ALUGUEL_CONDOMINIO', 'DEBIT', 'STANDARD_EXPENSE', 2850.0000, 'BRL', '2026-09-05', '2026-09-05', 'CONDOMINIO RESIDENCIAL SOLAR', 'demo-hist-202609-01', 'CONCILED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_ITAU_5285}', 'ALIMENTACAO', 'SUPERMERCADO_MERCEARIA', 'DEBIT', 'STANDARD_EXPENSE', 1420.5000, 'BRL', '2026-09-12', NULL, 'SUPERMERCADO PAO DE ACUCAR', 'demo-hist-202609-02', 'CONCILED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_ITAU_1360}', 'SAUDE', 'PLANO_SAUDE', 'DEBIT', 'STANDARD_EXPENSE', 1680.0000, 'BRL', '2026-09-15', NULL, 'UNIMED PLANO FAMILIAR', 'demo-hist-202609-03', 'CONCILED'),

-- Month 2: 2026-10
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', NULL, 'MORADIA', 'ALUGUEL_CONDOMINIO', 'DEBIT', 'STANDARD_EXPENSE', 2850.0000, 'BRL', '2026-10-05', '2026-10-05', 'CONDOMINIO RESIDENCIAL SOLAR', 'demo-hist-202610-01', 'CONCILED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_ITAU_5285}', 'ALIMENTACAO', 'RESTAURANTES_GASTRONOMIA', 'DEBIT', 'STANDARD_EXPENSE', 245.9000, 'BRL', '2026-10-14', NULL, 'CHURRASCARIA GAUCHA', 'demo-hist-202610-02', 'CONCILED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_BB_7741}', 'TRANSPORTE', 'COMBUSTIVEL_ETANOL_GASOLINA', 'DEBIT', 'STANDARD_EXPENSE', 280.0000, 'BRL', '2026-10-19', NULL, 'POSTO FREI DAMIAO', 'demo-hist-202610-03', 'CONCILED'),

-- Month 3 (Current): 2026-11 — Includes 10x Parcelled Purchase, Supermarket NFC-e target, Bank Fee & Refund
('${PARENT_10X_ENTRY_ID}', '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_ITAU_5285}', 'LAZER', 'VESTUARIO_CALCADOS', 'DEBIT', 'INSTALLMENT_ACCRUAL', 1000.0300, 'BRL', '2026-11-10', NULL, 'LOJAS RENNER PARC 01/10', 'demo-curr-202611-10x', 'CONCILED'),
('${SUPERMARKET_ENTRY_ID}', '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_ITAU_5285}', 'ALIMENTACAO', 'SUPERMERCADO_MERCEARIA', 'DEBIT', 'STANDARD_EXPENSE', 313.0100, 'BRL', '2026-11-14', NULL, 'ATACADAO S.A. - LOJA ACU', 'demo-curr-202611-atacadao', 'CONCILED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_ITAU_5285}', 'FINANCEIRO', 'ANUIDADE_TARIFAS_BANCARIAS', 'DEBIT', 'STANDARD_EXPENSE', 7.9900, 'BRL', '2026-11-15', NULL, 'MENSALIDADE ITAU AVISA', 'demo-curr-202611-fee', 'CONCILED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_ITAU_5285}', 'LAZER', 'VESTUARIO_CALCADOS', 'CREDIT', 'REFUND_CREDIT', 168.9400, 'BRL', '2026-11-16', NULL, 'ESTORNO LOJAS RENNER -R$ 168,94', 'demo-curr-202611-refund', 'CONCILED'),

-- 7. 3 Pending Items in "OUTROS" (NAO_CATEGORIZADO) for Live Inbox Learning Demo
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_ITAU_5285}', 'OUTROS', 'NAO_CATEGORIZADO', 'DEBIT', 'STANDARD_EXPENSE', 148.9000, 'BRL', '2026-11-12', NULL, 'JIM.COM* COMERCIO SERTAO LTDAACUBRA', 'demo-inbox-pending-01', 'MANUAL_REVIEW'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_BB_7741}',   'OUTROS', 'NAO_CATEGORIZADO', 'DEBIT', 'STANDARD_EXPENSE', 92.0000,  'BRL', '2026-11-15', NULL, 'BMB*DISTRIBUIDORA VALE DO ASSU', 'demo-inbox-pending-02', 'MANUAL_REVIEW'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${ACCOUNT_MAIN_ID}', '${CARD_MARISA_0912}', 'OUTROS', 'NAO_CATEGORIZADO', 'DEBIT', 'STANDARD_EXPENSE', 215.0000, 'BRL', '2026-11-16', NULL, 'PG *STUDIO BELA VIDA NATALBRA', 'demo-inbox-pending-03', 'MANUAL_REVIEW');

-- 8. 10x Installment Schedule (1..9 = 100.0000, 10th = 100.0300 -> exact cent adjustment on last installment)
INSERT INTO installment_schedules (id, tenant_id, credit_card_id, parent_ledger_entry_id, installment_number, total_installments, competence_month, due_date, amount, status) VALUES
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 1,  10, '2026-11', '2026-11-05', 100.0000, 'BILLED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 2,  10, '2026-12', '2026-12-05', 100.0000, 'SCHEDULED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 3,  10, '2027-01', '2027-01-05', 100.0000, 'SCHEDULED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 4,  10, '2027-02', '2027-02-05', 100.0000, 'SCHEDULED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 5,  10, '2027-03', '2027-03-05', 100.0000, 'SCHEDULED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 6,  10, '2027-04', '2027-04-05', 100.0000, 'SCHEDULED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 7,  10, '2027-05', '2027-05-05', 100.0000, 'SCHEDULED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 8,  10, '2027-06', '2027-06-05', 100.0000, 'SCHEDULED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 9,  10, '2027-07', '2027-07-05', 100.0000, 'SCHEDULED'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${CARD_ITAU_5285}', '${PARENT_10X_ENTRY_ID}', 10, 10, '2027-08', '2027-08-05', 100.0300, 'SCHEDULED');

-- 9. Supermarket NFC-e Receipt Items with >10% EAN Personal Inflation (EAN 7891000100103: R$ 20.00 -> R$ 23.50 = +17.50%)
INSERT INTO receipt_items (id, tenant_id, ledger_entry_id, access_key, item_sequence, ean, description, quantity, unit_of_measure, unit_price, total_price, issued_at) VALUES
(gen_random_uuid(), '${DEMO_TENANT_ID}', NULL, '24261075315333000109650010000111111000111111', 1, '7891000100103', 'CAFE TORRADO E MOIDO 500G', 2.0000, 'UN', 20.0000, 40.0000, '2026-10-12T14:00:00Z'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${SUPERMARKET_ENTRY_ID}', '24261175315333000109650010000987651000987654', 1, '7891000100103', 'CAFE TORRADO E MOIDO 500G', 2.0000, 'UN', 23.5000, 47.0000, '2026-11-12T15:30:00Z'),
(gen_random_uuid(), '${DEMO_TENANT_ID}', '${SUPERMARKET_ENTRY_ID}', '24261175315333000109650010000987651000987654', 2, '7894900011517', 'COMPRAS SUPERMERCADO FAMILIAR', 1.0000, 'UN', 266.0100, 266.0100, '2026-11-12T15:30:00Z');

COMMIT;
SQL

echo "[DEMO-SEED] Populating Valkey/Redis Read-Model Snapshot for 'Família Silva - Piloto MVP'..."
docker exec pfm-redis valkey-cli SET "pfm:forecast:${DEMO_TENANT_ID}:2026-11" \
  '{"tenant_id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","tenant_name":"Família Silva - Piloto MVP","reference_month":"2026-11","regular_net_income":"18200.0000","total_projected_outflow":"18828.4500","projected_surplus_or_deficit":"-628.4500","traffic_light":"RED","limit_is_not_budget_alert":true}' >/dev/null

echo "[DEMO-SEED] Tenant 'Família Silva - Piloto MVP' successfully seeded!"
