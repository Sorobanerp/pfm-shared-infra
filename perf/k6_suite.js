import http from "k6/http";
import { check, sleep } from "k6";
import { Counter, Rate, Trend } from "k6/metrics";

/**
 * PFM Core Banking V2 — Official k6 Performance & Stress Suite (Artifact 07 V2)
 *
 * Profiles (`-e PROFILE=pilot_5_users` or `-e PROFILE=tier1_bank_stress`):
 * 1. `pilot_5_users`: 5 concurrent family/pilot users over 2m with realistic think-time.
 * 2. `tier1_bank_stress`: Progressive ramp 50 -> 250 -> 500 -> 1000 VUs over 3m
 *    simulating Tier-1 Bank invoice closing peak (Itaú / Nubank / BB).
 *
 * Traffic Mix:
 * - 60% Read Dashboard & Multi-Card Matrix with ETag (`If-None-Match` -> 304 Not Modified)
 * - 20% Transaction & SEFAZ NFC-e Receipt Ingestion (`POST /api/v1/receipts/nfce`)
 * - 15% gRPC Contract Amortization Simulation (`POST /api/v1/contracts/simulate`)
 * -  5% Credit Card Statement PDF Upload in RAM (`POST /api/v1/statements/upload`)
 */

const profile = __ENV.PROFILE || "pilot_5_users";
const baseUrl = __ENV.BASE_URL || "http://localhost:18080";

export const dashboardLatency = new Trend("pfm_dashboard_latency_ms", true);
export const forecastGrpcLatency = new Trend("pfm_forecast_grpc_latency_ms", true);
export const nfceIngestLatency = new Trend("pfm_nfce_ingest_latency_ms", true);
export const statementUploadLatency = new Trend("pfm_statement_upload_latency_ms", true);
export const rateLimitedCounter = new Counter("pfm_rate_limited_429_total");
export const etag304HitCounter = new Counter("pfm_etag_304_hits_total");
export const businessSuccessRate = new Rate("pfm_business_success_rate");

const pilotScenarios = {
  pilot_5_users: {
    executor: "constant-vus",
    vus: 5,
    duration: __ENV.DURATION_OVERRIDE || "2m",
  },
};

const tier1StressScenarios = {
  tier1_bank_stress: {
    executor: "ramping-vus",
    startVUs: 10,
    stages: [
      { duration: "30s", target: 50 },
      { duration: "45s", target: 250 },
      { duration: "45s", target: 500 },
      { duration: "45s", target: 1000 },
      { duration: "15s", target: 0 },
    ],
    gracefulRampDown: "10s",
  },
};

export const options = {
  scenarios: profile === "tier1_bank_stress" ? tier1StressScenarios : pilotScenarios,
  thresholds: {
    pfm_dashboard_latency_ms: ["p(99)<150"],
    pfm_forecast_grpc_latency_ms: ["p(99)<25"],
    pfm_business_success_rate: ["rate>0.9995"],
  },
};

const TENANT_POOL = [
  "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
  "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
];

let cachedEtagByTenant = {};

function deterministicTenantForVu(vuId, iter) {
  if (profile === "pilot_5_users") {
    return TENANT_POOL[(vuId - 1) % TENANT_POOL.length];
  }
  // Generate valid deterministic UUID per virtual user to test multi-tenant RLS & per-tenant rate limiter
  const hexVu = (vuId % 65535).toString(16).padStart(4, "0");
  const hexBucket = (iter % 255).toString(16).padStart(2, "0");
  return `aaaaaaaa-${hexVu}-4aaa-8aaa-0000000000${hexBucket}`;
}

export default function () {
  const tenantId = deterministicTenantForVu(__VU, __ITER);
  const roll = Math.random() * 100;

  if (roll < 60) {
    // 60%: Read Consolidated Dashboard & Multi-Card Matrix with ETag / If-None-Match
    const headers = {
      "X-Tenant-ID": tenantId,
      "Accept-Encoding": "br, gzip",
    };
    if (cachedEtagByTenant[tenantId]) {
      headers["If-None-Match"] = cachedEtagByTenant[tenantId];
    }

    const res = http.get(`${baseUrl}/api/v1/dashboard?scope=FAMILY`, { headers });
    dashboardLatency.add(res.timings.duration);

    if (res.status === 200 && res.headers["ETag"]) {
      cachedEtagByTenant[tenantId] = res.headers["ETag"];
    } else if (res.status === 304) {
      etag304HitCounter.add(1);
    } else if (res.status === 429) {
      rateLimitedCounter.add(1);
    }

    const ok = check(res, {
      "dashboard status is 200, 304, or 429 (rate-limit)": (r) =>
        r.status === 200 || r.status === 304 || r.status === 429,
    });
    businessSuccessRate.add(ok);
  } else if (roll < 80) {
    // 20%: NFC-e Receipt Ingestion (POST /api/v1/receipts/nfce)
    const payload = JSON.stringify({
      qrCodeUrl:
        "https://nfce.set.rn.gov.br/consultarNFCe.aspx?p=24261175315333000109650010000987651000987654|2|1|1",
      cardId: "33333333-aaaa-4aaa-8aaa-333333333333",
      paymentMethod: "CREDIT_CARD",
      idempotencyKey: `sha256-k6-${tenantId}-${__ITER}`,
    });

    const res = http.post(`${baseUrl}/api/v1/receipts/nfce`, payload, {
      headers: {
        "Content-Type": "application/json",
        "X-Tenant-ID": tenantId,
      },
    });
    nfceIngestLatency.add(res.timings.duration);
    if (res.status === 429) {
      rateLimitedCounter.add(1);
    }
    const ok = check(res, {
      "nfce status is 200 or 429": (r) => r.status === 200 || r.status === 429,
    });
    businessSuccessRate.add(ok);
  } else if (roll < 95) {
    // 15%: Contract Amortization Simulation via gRPC Bridge (POST /api/v1/contracts/simulate)
    const payload = JSON.stringify({
      contract_id: "contract-sac-k6",
      amortization_system: "SAC",
      prepayment_strategy: "REDUCE_TERM",
      outstanding_balance: "300000.0000",
      remaining_installments: 120,
      monthly_interest_rate: "0.0080",
      extra_amortization_amount: "60000.0000",
    });

    const res = http.post(`${baseUrl}/api/v1/contracts/simulate`, payload, {
      headers: {
        "Content-Type": "application/json",
        "X-Tenant-ID": tenantId,
      },
    });
    forecastGrpcLatency.add(res.timings.duration);
    if (res.status === 429) {
      rateLimitedCounter.add(1);
    }
    const ok = check(res, {
      "simulate contract status is 200 or 429": (r) =>
        r.status === 200 || r.status === 429,
    });
    businessSuccessRate.add(ok);
  } else {
    // 5%: Credit Card Statement Upload in RAM (POST /api/v1/statements/upload)
    const statementBody = [
      "REF: 2026-11",
      "VENCIMENTO: 2026-11-25",
      "TOTAL_FATURA: 6311.14",
      "2026-11-14 | ATACADAO SA | 313.01",
      "2026-11-15 | MOBILIA DESIGN 01/10 | 6159.08",
      "2026-11-16 | MENSALIDADE ITAU AVISA | 7.99",
      "2026-11-16 | ESTORNO LOJA RENNER | -168.94",
    ].join("\n");

    const res = http.post(`${baseUrl}/api/v1/statements/upload`, statementBody, {
      headers: {
        "X-Tenant-ID": tenantId,
        "X-Statement-Issuer": "ITAU",
        "X-Card-Last4": "5285",
        "X-File-Name": "fatura-itau-5285-k6.pdf",
      },
    });
    statementUploadLatency.add(res.timings.duration);
    if (res.status === 429) {
      rateLimitedCounter.add(1);
    }
    const ok = check(res, {
      "statement upload status is 200 or 429": (r) =>
        r.status === 200 || r.status === 429,
    });
    businessSuccessRate.add(ok);
  }

  if (profile === "pilot_5_users") {
    sleep(0.25);
  } else {
    sleep(0.02);
  }
}
