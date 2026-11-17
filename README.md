# `pfm-shared-infra` — Cloud Landing Zone & Local Cloud Emulator (Predator Helios 300 — 64GB RAM)

Repositório de **Infraestrutura Compartilhada (Landing Zone Multicloud AWS/Azure/GCP)** e **Simulação 100% Local de Nuvem (`local-cloud/`)** da plataforma **PFM Core Banking**.

---

## 1. Arquitetura Local Cloud (`local-cloud/docker-compose.yml`)

Projetado para rodar com folga na estação **Predator Helios 300 (64GB RAM)** sob a rede isolada `pfm-cloud-net`, emulando serviços reais de nuvem com **Database-per-Service** e **Envelope Encryption KMS**:

| Container / Serviço | Imagem Oficial | Porta Host | Papel Arquitetural |
| :--- | :--- | :---: | :--- |
| **`pfm-localstack`** | `localstack/localstack:latest` | `14566` → 4566 | Emulador AWS (`s3`, `kms`, `secretsmanager`, `sts`) inicializado via `local-cloud/init-aws.sh`. |
| **`postgres-core-ledger`** | `pgvector/pgvector:pg16` | `15432` → 5432 | Banco exclusivo do `pfm-core-ledger-java` (`DB: pfm_core_ledger`, RLS + `NUMERIC(19,4)`). |
| **`postgres-ai-rules`** | `pgvector/pgvector:pg16` | `15433` → 5432 | Banco exclusivo do `pfm-ai-worker-python` (`DB: pfm_ai_rules`, embeddings `pgvector` e regras). |
| **`pfm-kafka`** | `apache/kafka:3.8.0` | `19092` → 9092 | Barramento de eventos KRaft (sem ZooKeeper), 6 partições padrão por tópico. |
| **`pfm-kafka-ui`** | `provectuslabs/kafka-ui:latest` | `18085` → 8080 | Interface visual de inspeção de tópicos, partições, schemas e consumer groups. |
| **`pfm-redis`** | `valkey/valkey:8.0-alpine` | `16379` → 6379 | Read-Models de projeção CQRS, chaves de idempotência (72h) e *Rate Limiting*. |
| **`pfm-envoy-gateway`** | `envoyproxy/envoy:v1.31-latest` | `18080` → 8080 | API Gateway de borda roteando `/api/v1/*` para o BFF Go e injetando `x-correlation-id`. |

### Recursos AWS Criados Automaticamente pelo `local-cloud/init-aws.sh`

1. **S3 Buckets (Criptografados com SSE-KMS)**:
   - `s3://pfm-statements-encrypted-local`
   - `s3://pfm-receipts-images-local`
2. **AWS KMS Symmetric Master Key (Envelope Encryption - ADR-006)**:
   - Alias: `alias/pfm-tenant-master-key` (`ENCRYPT_DECRYPT`, `SYMMETRIC_DEFAULT`)
3. **AWS Secrets Manager**:
   - Secret ID: `pfm/dev/gemini-api-key` (protegido pela chave KMS `alias/pfm-tenant-master-key`)

---

## 2. Acoplamento 1:1 com os Repositórios `-infra` dos Microsserviços (ADR-002 & ADR-007)

Em conformidade com o **ADR-002 (Topologia Multi-Repo & Mapeamento 1:1 IaC)**, a infraestrutura da plataforma é segregada em **duas camadas**:

```text
pfm-shared-infra/ (Camada 0 — Landing Zone & Recursos Base)
├── local-cloud/
│   ├── docker-compose.yml        # Nuvem local (LocalStack, 2x Postgres 16, Kafka KRaft, Valkey, Envoy)
│   ├── init-aws.sh               # Bootstrap automático S3 + KMS + SecretsManager
│   └── envoy/envoy.yaml          # Roteamento L7 /api/v1/* + Correlation Headers
└── terraform/
    ├── modules/                  # Módulos base reutilizáveis (OpenTofu / Terraform >= 1.8)
    │   ├── network/              # VPC, Subnets privadas/públicas, Service Mesh
    │   ├── database-per-service/ # Template de banco isolado com RLS e KMS
    │   ├── security-kms/         # KEK Master Key e rotação automática
    │   └── event-backbone/       # Cluster Kafka (MSK / Event Hubs / GCP Kafka) + Valkey
    └── environments/
        ├── aws/                  # Landing Zone AWS (EKS + Aurora PG16 + MSK + KMS)
        ├── azure/                # Landing Zone Azure (AKS + Flexible PG16 + Event Hubs + Key Vault)
        └── gcp/                  # Landing Zone GCP (GKE + Cloud SQL PG16 + Managed Kafka + Cloud KMS)
```

### Como os Repositórios `-infra` Consomem o `pfm-shared-infra`

1. **`pfm-shared-infra` exporta *Outputs* Imutáveis via Remote State**:
   - IDs de VPC/Subnets, ARN da chave KMS (`alias/pfm-tenant-master-key`), endpoints do cluster Kafka/Valkey e instâncias isoladas de PostgreSQL (`postgres-core-ledger` na 15432 e `postgres-ai-rules` na 15433).
2. **Cada Microsserviço possui seu acoplamento 1:1 IaC (`<service>-infra`)**:
   - Consome os módulos e *data sources* do `pfm-shared-infra` via `terraform_remote_state`.
   - Provisiona **apenas os recursos exclusivos daquele microsserviço**: IAM Role (IRSA / Workload Identity) de privilégio mínimo, seus tópicos Kafka específicos, seu schema/credenciais RLS e seu manifesto Helm/Deployment.
   - Um `terraform apply` em um microsserviço jamais afeta o estado (*statefile*) de outro microsserviço ou da Landing Zone compartilhada.

---

## 3. Como Operar e Validar Localmente

### Subir a Nuvem Local

```bash
docker compose -f local-cloud/docker-compose.yml up -d
```

### Validar os Recursos AWS no LocalStack (Porta 14566)

```bash
# Listar os buckets S3 criados
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --region sa-east-1 --endpoint-url=http://localhost:14566 s3 ls

# Validar o alias da chave KMS de Envelope Encryption
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --region sa-east-1 --endpoint-url=http://localhost:14566 kms describe-key --key-id alias/pfm-tenant-master-key

# Validar o segredo no Secrets Manager
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --region sa-east-1 --endpoint-url=http://localhost:14566 secretsmanager get-secret-value --secret-id pfm/dev/gemini-api-key
```


## Mapa Canônico de Portas Locais (Isolamento 12-Factor App)

Todas as portas de host utilizam as faixas `1xxxx` (aplicações e gateways) e `14xxx`/`15xxx`/`16xxx`/`19xxx` (infraestrutura e bancos) para eliminar 100% de colisão com o **Portainer** (`8000`, `9000`, `9443`) ou bancos pré-existentes no sistema operacional. Nos contêineres e no Kubernetes permanecem as portas internas canônicas (`8080`, `9090`, `5432`, `6379`, `9092`, `4566`).

Consulte [`.env.local.example`](.env.local.example) e a topologia detalhada em `pfm-docs/docs/operations/sre-finops.md`.

| Componente | Porta Host Local | Container / K8s | Variável de Ambiente |
| :--- | :---: | :---: | :--- |
| `pfm-docs` (MkDocs) | `18000` | `8000` | `PORT=18000` |
| `pfm-web-nextjs` | `18300` | `3000` | `PORT=18300`, `NEXT_PUBLIC_API_URL` |
| `pfm-envoy-gateway` | `18080` | `8080` | — (Docker mapping) |
| `pfm-ingestion-bff-go` | `18100` | `8080` | `SERVER_PORT=18100` |
| `pfm-forecast-engine-go` | `18110` | `9090` | `GRPC_PORT=18110` |
| `pfm-core-ledger-java` HTTP | `18200` | `8080` | `SERVER_PORT=18200` |
| `pfm-core-ledger-java` gRPC | `18210` | `9090` | `GRPC_SERVER_PORT=18210` |
| `pfm-ai-worker-python` | `18400` | `8080` | `WORKER_PORT=18400` |
| `postgres-core-ledger` | `15432` | `5432` | `DB_URL` |
| `postgres-ai-rules` | `15433` | `5432` | `PFM_AI_RULES_DSN` |
| `pfm-redis` (Valkey) | `16379` | `6379` | `REDIS_ADDR` |
| `pfm-kafka` (KRaft) | `19092` | `9092` | `KAFKA_BROKERS` / `KAFKA_BOOTSTRAP_SERVERS` |
| `pfm-kafka-ui` | `18085` | `8080` | — (Docker mapping) |
| `pfm-localstack` | `14566` | `4566` | `AWS_ENDPOINT_URL` |
| Android Emulator -> Envoy | `10.0.2.2:18080` | — | `BuildConfig.API_BASE_URL` |
