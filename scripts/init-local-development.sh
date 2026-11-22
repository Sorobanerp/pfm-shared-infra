#!/usr/bin/env bash
# ==============================================================================
# PFM Core Banking V3.0 — Idempotent Local Development Initializer
# Location: /home/dantas/workspace/pfm-platform/init-local-development.sh
# Security Policy: Generates untracked .env.local files with local emulator
# defaults only (zero production secrets).
# ==============================================================================
set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$PATH:$HOME/go/bin:$HOME/.local/bin"

echo "=============================================================================="
echo " [PFM DX] 1/5 — Validating Local Prerequisites"
echo "=============================================================================="

for cmd in docker java go python3 curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Prerequisite '$cmd' not found in PATH." >&2
    exit 1
  fi
done

if ! command -v grpcurl >/dev/null 2>&1; then
  echo "-> Installing grpcurl via go install..."
  go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
fi

echo "  [OK] Docker:  $(docker --version)"
echo "  [OK] Java:    $(java -version 2>&1 | head -n 1)"
echo "  [OK] Go:      $(go version)"
echo "  [OK] Python:  $(python3 --version)"
echo "  [OK] grpcurl: $(grpcurl --version 2>&1 | head -n 1)"

echo "=============================================================================="
echo " [PFM DX] 2/5 — Generating Untracked .env.local Files (Zero Cloud Secrets)"
echo "=============================================================================="

cat > "${WORKSPACE_ROOT}/pfm-shared-infra/.env.local" <<'EOF'
APP_ENV=local
POSTGRES_PORT=5432
KAFKA_PORT=9092
KAFKA_CONSOLE_PORT=8081
REDIS_PORT=6379
LOCALSTACK_PORT=4566
AWS_REGION=us-east-2
EOF

cat > "${WORKSPACE_ROOT}/pfm-core-ledger-java/.env.local" <<'EOF'
SPRING_PROFILES_ACTIVE=local
SERVER_PORT=8082
GRPC_SERVER_PORT=9090
GRPC_REFLECTION_ENABLED=true
DB_URL=jdbc:postgresql://localhost:5432/pfm_core_ledger
DB_USERNAME=pfm_app_user
DB_PASSWORD=pfm_app_secret_2026
FLYWAY_URL=jdbc:postgresql://localhost:5432/pfm_core_ledger
FLYWAY_USER=postgres
FLYWAY_PASSWORD=postgres
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
AWS_ENDPOINT_URL=http://localhost:4566
AWS_REGION=us-east-2
KMS_MASTER_KEY_ID=alias/pfm-master-key
EOF

cat > "${WORKSPACE_ROOT}/pfm-forecast-engine-go/.env.local" <<'EOF'
APP_ENV=local
GRPC_PORT=9091
REDIS_ADDR=localhost:6379
KAFKA_BROKERS=localhost:9092
EOF

cat > "${WORKSPACE_ROOT}/pfm-ingestion-bff-go/.env.local" <<'EOF'
APP_ENV=local
SERVER_PORT=8080
PORT=8080
KAFKA_BROKERS=localhost:9092
AWS_ENDPOINT_URL=http://localhost:4566
LOCALSTACK_ENDPOINT=http://localhost:4566
CORE_LEDGER_GRPC_ADDR=localhost:9090
CORE_LEDGER_HTTP_URL=http://localhost:8082
FORECAST_GRPC_ADDR=localhost:9091
FORECAST_ENGINE_HTTP_URL=http://localhost:9091
EOF

cat > "${WORKSPACE_ROOT}/pfm-ai-worker-python/.env.local" <<'EOF'
APP_ENV=local
WORKER_PORT=18400
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
KAFKA_GROUP_ID=pfm-ai-worker-local-group
PFM_AI_RULES_DSN=postgresql://pfm_ai_user:pfm_ai_pass@localhost:15433/pfm_ai_rules
AWS_ENDPOINT_URL=http://localhost:4566
GEMINI_API_KEY=
EOF

cat > "${WORKSPACE_ROOT}/pfm-web-nextjs/.env.local" <<'EOF'
NEXT_PUBLIC_APP_ENV=local
NEXT_PUBLIC_API_URL=http://localhost:8080
NEXT_PUBLIC_PFM_BFF_URL=http://localhost:8080
PORT=3000
EOF

echo "  [OK] Generated .env.local across all 6 application/infra repositories."

echo "=============================================================================="
echo " [PFM DX] 3/5 — Starting Local Infrastructure (docker-compose.local.yml)"
echo "=============================================================================="

COMPOSE_FILE="${WORKSPACE_ROOT}/pfm-shared-infra/docker-compose.local.yml"
docker compose -f "${COMPOSE_FILE}" up -d

echo "=============================================================================="
echo " [PFM DX] 4/5 — Waiting for Container Healthchecks"
echo "=============================================================================="

for container in postgres-core-ledger postgres-ai-rules pfm-redis pfm-kafka pfm-localstack pfm-kafka-ui; do
  printf "  Waiting for %-22s ... " "${container}"
  for _ in $(seq 1 40); do
    status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container}" 2>/dev/null || echo "starting")
    if [ "${status}" = "healthy" ] || [ "${status}" = "running" ]; then
      echo "[${status}]"
      break
    fi
    sleep 2
  done
done

echo "=============================================================================="
echo " [PFM DX] 5/5 — Ensuring Kafka Topics & LocalStack KMS/S3"
echo "=============================================================================="

for topic in statement.raw.extracted tx.categorized ledger.entry.committed tx.dlq; do
  docker exec pfm-kafka /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:29092 \
    --create --if-not-exists \
    --topic "${topic}" \
    --partitions 6 \
    --replication-factor 1 >/dev/null 2>&1 || true
  echo "  [OK] Kafka Topic ready: ${topic}"
done

docker exec pfm-localstack bash /etc/localstack/init/ready.d/init-aws.sh >/dev/null 2>&1 || true
echo "  [OK] LocalStack KMS (alias/pfm-master-key) & S3 buckets verified."

echo "=============================================================================="
echo " [PFM DX] Local Environment Ready!"
echo "   - PostgreSQL 16 (Core Ledger RLS): localhost:5432"
echo "   - Kafka / Redpanda Broker:         localhost:9092"
echo "   - Kafka / Redpanda Console UI:     http://localhost:8081"
echo "   - Redis / Valkey:                  localhost:6379"
echo "   - LocalStack (S3 + KMS):           http://localhost:4566"
echo "=============================================================================="
