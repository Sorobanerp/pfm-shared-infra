CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

-- Restricted application role for pfm-core-ledger-java (NOBYPASSRLS)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pfm_app_user') THEN
        CREATE ROLE pfm_app_user WITH LOGIN PASSWORD 'pfm_app_secret_2026' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
    END IF;
END
$$;

-- Restricted application role for pfm-ai-worker-python (NOBYPASSRLS)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pfm_ai_user') THEN
        CREATE ROLE pfm_ai_user WITH LOGIN PASSWORD 'pfm_ai_pass' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
    END IF;
END
$$;

-- Tenant Learned Rules Table with PostgreSQL 16 Row-Level Security (ADR-002 / ADR-006)
CREATE TABLE IF NOT EXISTS learned_merchant_rules (
    tenant_id        VARCHAR(64)   NOT NULL,
    merchant_pattern VARCHAR(255)  NOT NULL,
    category_code    VARCHAR(64)   NOT NULL,
    category_group   VARCHAR(64)   NOT NULL,
    confidence       NUMERIC(19,4) NOT NULL DEFAULT 1.0000,
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, merchant_pattern)
);

ALTER TABLE learned_merchant_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE learned_merchant_rules FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_learned_merchant_rules_isolation ON learned_merchant_rules;
CREATE POLICY rls_learned_merchant_rules_isolation ON learned_merchant_rules
    FOR ALL
    TO PUBLIC
    USING (tenant_id = NULLIF(BTRIM(current_setting('app.current_tenant_id', true)), ''))
    WITH CHECK (tenant_id = NULLIF(BTRIM(current_setting('app.current_tenant_id', true)), ''));

GRANT USAGE ON SCHEMA public TO pfm_ai_user;
GRANT USAGE ON SCHEMA public TO pfm_app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON learned_merchant_rules TO pfm_ai_user;
