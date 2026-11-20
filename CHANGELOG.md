# Changelog — `pfm-shared-infra`

Todas as alterações notáveis neste repositório são documentadas neste arquivo seguindo o padrão [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e versionamento semântico [SemVer 2.0.0](https://semver.org/lang/pt-BR/).

---

## [Unreleased]

### Added
- Configuração oficial do **OpenTelemetry Collector Gateway** (`observability/otel-collector-config.yaml`) com `tail_sampling` (100% erros/latência > 500ms, 10% OK), `redaction/lgpd` e remoção de `tenant_id` em métricas para Datadog (`us3.datadoghq.com`).
- Dashboard unificado **PFM Unified Product Health** (`datadog_dashboard`) e monitores críticos (`datadog_monitor` para RLS/429, DLQs `*.dlq` e latência P99) em `terraform/modules/observability-datadog/dashboards.tf`, controlados por `var.enable_datadog_monitors`.
- Padronização de governança DevEx (`README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`) e workflow de validação de **Conventional Commits** em Pull Requests para `develop` e `main`.

---

## [0.2.0] - 2026-11-20

### Added
- Módulo `aws-ecs-pilot` (ECS Fargate Spot Arm64 + Cloud Map `pfm.internal`), S3 SSE-KMS e Secrets Upstash Kafka/Redis; EKS tornado condicional via `var.compute_engine`.

### Changed
- Alinhamento com a arquitetura **PFM Core Banking V3.0 (Production-Ready FinOps & Multi-Cloud)**.

### Security
- Aplicação estrita de políticas Zero-Trust (OIDC sem chaves estáticas, Trivy/Semgrep/Gitleaks gates e isolamento por tenant).

### Infrastructure
- Rollback automático de state S3 (`last-good`) e `workflow_dispatch` com suporte a `apply` e `destroy`.

---

## [0.1.0] - 2026-11-15

### Added
- Estrutura inicial do repositório `pfm-shared-infra`, pipelines GitHub Actions e integração ao ecossistema Gitflow `Sorobanerp`.
