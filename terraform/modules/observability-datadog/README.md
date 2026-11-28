# Module `observability-datadog`

Provisiona o Dashboard Unificado de Saúde do Produto e Monitores Críticos SLO/RLS no Datadog (`us3.datadoghq.com`) conforme `ADR-010`.

## Inputs

| Name | Description | Type | Default |
| :--- | :--- | :---: | :---: |
| `environment` | Target deployment environment (`dev` or `prod`) | `string` | `"prod"` |
| `datadog_site` | Datadog intake site | `string` | `"us3.datadoghq.com"` |
| `api_key_existing_secret` | Kubernetes secret containing the Datadog API key | `string` | `"datadog-secret"` |
| `namespace` | Kubernetes namespace for observability agents | `string` | `"monitoring"` |
| `enable_helm_agent` | Enable Datadog Helm Agent inside EKS | `bool` | `false` |
| `enable_datadog_monitors` | Enable Datadog Dashboard and Critical Monitors | `bool` | `false` |

## Outputs

| Name | Description | Sensitive |
| :--- | :--- | :---: |
| `otlp_http_endpoint` | Internal OTLP HTTP collector endpoint | `false` |
| `otlp_grpc_endpoint` | Internal OTLP gRPC collector endpoint | `false` |
