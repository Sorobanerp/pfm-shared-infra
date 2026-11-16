# `pfm-shared-infra` — Cloud Landing Zone & Local Cloud Emulator (Predator Helios 300 — 64GB RAM)

Repositório de **Infraestrutura Compartilhada (Landing Zone Multicloud AWS/Azure/GCP)** e **Simulação 100% Local de Nuvem (`local-cloud/`)** da plataforma **PFM Core Banking**.

---

## 1. Arquitetura Local Cloud (`local-cloud/docker-compose.yml`)

Projetado para rodar com folga na estação **Predator Helios 300 (64GB RAM)** sob a rede isolada `pfm-cloud-net`, emulando serviços reais de nuvem com **Database-per-Service** e **Envelope Encryption KMS**:

| Container / Serviço | Imagem Oficial | Porta Host | Papel Arquitetural |
| :--- | :--- | :---: | :--- |
| **`pfm-localstack`** | `localstack/localstack:latest` | `4566` | Emulador AWS (`s3`, `kms`, `secretsmanager`, `sts`) inicializado via `local-cloud/init-aws.sh`. |
| **`postgres-core-ledger`** | `pgvector/pgvector:pg16` | `5432` | Banco exclusivo do `pfm-core-ledger-java` (`DB: pfm_core_ledger`, RLS + `NUMERIC(19,4)`). |
| **`postgres-ai-rules`** | `pgvector/pgvector:pg16` | `5433` | Banco exclusivo do `pfm-ai-worker-python` (`DB: pfm_ai_rules`, embeddings `pgvector` e regras). |
| **`pfm-kafka`** | `apache/kafka:3.8.0` | `9092` | Barramento de eventos KRaft (sem ZooKeeper), 6 partições padrão por tópico. |
| **`pfm-kafka-ui`** | `provectuslabs/kafka-ui:latest` | `8085` | Interface visual de inspeção de tópicos, partições, schemas e consumer groups. |
| **`pfm-redis`** | `valkey/valkey:8.0-alpine` | `6379` | Read-Models de projeção CQRS, chaves de idempotência (72h) e *Rate Limiting*. |
| **`pfm-envoy-gateway`** | `envoyproxy/envoy:v1.31-latest` | `8080` | API Gateway de borda roteando `/api/v1/*` para o BFF Go e injetando `x-correlation-id`. |

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
   - IDs de VPC/Subnets, ARN da chave KMS (`alias/pfm-tenant-master-key`), endpoints do cluster Kafka/Valkey e instâncias isoladas de PostgreSQL (`postgres-core-ledger` na 5432 e `postgres-ai-rules` na 5433).
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

### Validar os Recursos AWS no LocalStack (Porta 4566)

```bash
# Listar os buckets S3 criados
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --region sa-east-1 --endpoint-url=http://localhost:4566 s3 ls

# Validar o alias da chave KMS de Envelope Encryption
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --region sa-east-1 --endpoint-url=http://localhost:4566 kms describe-key --key-id alias/pfm-tenant-master-key

# Validar o segredo no Secrets Manager
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --region sa-east-1 --endpoint-url=http://localhost:4566 secretsmanager get-secret-value --secret-id pfm/dev/gemini-api-key
```
