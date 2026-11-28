resource "helm_release" "datadog_agent" {
  count            = var.enable_helm_agent ? 1 : 0
  name             = "datadog-agent"
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog"
  version          = "3.74.0"
  namespace        = var.namespace
  create_namespace = true
  wait             = false

  set {
    name  = "datadog.site"
    value = var.datadog_site
  }

  set {
    name  = "datadog.apiKeyExistingSecret"
    value = var.api_key_existing_secret
  }

  set {
    name  = "datadog.apm.portEnabled"
    value = "true"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.grpc.enabled"
    value = "true"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.http.enabled"
    value = "true"
  }

  set {
    name  = "datadog.logs.enabled"
    value = "true"
  }

  set {
    name  = "datadog.logs.containerCollectAll"
    value = "true"
  }
}

resource "datadog_dashboard" "pfm_unified_product_health" {
  count       = var.enable_datadog_monitors ? 1 : 0
  title       = "PFM Unified Product Health (${var.environment})"
  description = "Painel executivo multi-cloud agrupado por jornada de negócio (ADR-010)"
  layout_type = "ordered"

  widget {
    group_definition {
      title       = "Jornada 1: Ingestão PDF (Zero-Disk RAM — pfm-ingestion-bff-go)"
      layout_type = "ordered"
      widget {
        timeseries_definition {
          title = "Latência P95/P99 Ingestão PDF (ms)"
          request {
            q            = "p95:trace.http.request.duration{service:pfm-ingestion-bff-go,env:${var.environment}}"
            display_type = "line"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Jornada 2: Conciliação NFC-e & Categorização IA (Lambda Arm64)"
      layout_type = "ordered"
      widget {
        timeseries_definition {
          title = "Throughput & Erros Pipeline IA (L1/L2/L3)"
          request {
            q            = "sum:trace.aws.lambda.hits{service:pfm-ai-worker-python,env:${var.environment}}.as_rate()"
            display_type = "bars"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Jornada 3: Core Ledger (Partidas Dobradas, RLS & Audit Log)"
      layout_type = "ordered"
      widget {
        timeseries_definition {
          title = "Latência P99 Core Ledger (SLO < 180ms)"
          request {
            q            = "p99:trace.grpc.server.duration{service:pfm-core-ledger-java,env:${var.environment}}"
            display_type = "line"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Jornada 4: Simulador SAC/Price & Forecast Engine"
      layout_type = "ordered"
      widget {
        timeseries_definition {
          title = "Simulações & Cache Hit Ratio (Upstash Redis RESP3)"
          request {
            q            = "p95:trace.grpc.server.duration{service:pfm-forecast-engine-go,env:${var.environment}}"
            display_type = "line"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Jornada 5: Admin Tenants (US-12) & Segurança Zero-Trust"
      layout_type = "ordered"
      widget {
        timeseries_definition {
          title = "Eventos 429 Rate Limit & Bloqueios Cross-Tenant RLS"
          request {
            q            = "sum:trace.http.request.errors{http.status_code:429,env:${var.environment}}.as_count()"
            display_type = "bars"
          }
        }
      }
    }
  }
}

resource "datadog_monitor" "rls_or_rate_limit_spike" {
  count   = var.enable_datadog_monitors ? 1 : 0
  name    = "[PFM][SEV-0] Violação RLS Cross-Tenant ou Pico 429 Rate Limit (${var.environment})"
  type    = "metric alert"
  message = "Alerta crítico ADR-010: tentativa de violação RLS ou pico anormal de HTTP 429 detectado. Acionar Runbook RB-02."
  query   = "sum(last_5m):sum:trace.http.request.errors{http.status_code:429,env:${var.environment}}.as_count() > 25"

  monitor_thresholds {
    critical = 25
    warning  = 10
  }
}

resource "datadog_monitor" "dlq_accumulation" {
  count   = var.enable_datadog_monitors ? 1 : 0
  name    = "[PFM][P1] Acúmulo de Mensagens em Dead Letter Queue (*.dlq) (${var.environment})"
  type    = "metric alert"
  message = "Alerta P1 ADR-010: mensagens acumuladas em DLQ cifrada. Acionar Runbook RB-01."
  query   = "max(last_5m):max:aws.sqs.approximate_number_of_messages_visible{queuename:pfm-*,env:${var.environment}} > 0"

  monitor_thresholds {
    critical = 1
  }
}

resource "datadog_monitor" "slo_p99_latency" {
  count   = var.enable_datadog_monitors ? 1 : 0
  name    = "[PFM][P1] Latência P99 Acima do SLO (Artefato 07) (${var.environment})"
  type    = "metric alert"
  message = "Latência P99 do Core Ledger ultrapassou 250ms por 5 minutos consecutivos (SLO < 180ms)."
  query   = "avg(last_5m):p99:trace.grpc.server.duration{service:pfm-core-ledger-java,env:${var.environment}} > 250"

  monitor_thresholds {
    critical = 250
    warning  = 180
  }
}
