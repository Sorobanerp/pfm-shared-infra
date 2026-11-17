#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/dantas/.nvm/versions/node/v24.13.0/bin:/home/dantas/.local/bin:$PATH"
WORKSPACE="/home/dantas/workspace/pfm-platform"
LOG_DIR="/tmp/pfm-logs"
mkdir -p "$LOG_DIR"

echo "=================================================================="
echo " 1. Starting pfm-shared-infra/local-cloud Docker Compose Stack"
echo "=================================================================="
cd "$WORKSPACE/pfm-shared-infra/local-cloud"
docker compose up -d

for port in 18300 18100 18200 18210 18110 18400; do
  fuser -k "${port}/tcp" >/dev/null 2>&1 || true
done

echo "[PFM-UP] Applying idempotent PostgreSQL 16 RLS schemas & Kafka topics..."
docker exec -i postgres-core-ledger psql -U postgres -d pfm_core_ledger < "$WORKSPACE/pfm-core-ledger-java/src/main/resources/db/migration/V1__init_multitenant_ledger.sql" >/dev/null
docker exec -i postgres-ai-rules psql -U postgres -d pfm_ai_rules < "$WORKSPACE/pfm-shared-infra/local-cloud/init-db/init-pgvector.sql" >/dev/null

for topic in statement.raw.extracted tx.categorized receipt.items.extracted ledger.entry.committed; do
  docker exec pfm-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists --topic "$topic" --partitions 6 --replication-factor 1 >/dev/null 2>&1 || true
done

curl -fsS -X PUT "http://localhost:14566/pfm-statements-encrypted-local" >/dev/null 2>&1 || true

echo "=================================================================="
echo " 2. Starting 4 Backend Microservices (Logs in $LOG_DIR)"
echo "=================================================================="

# 2.1 pfm-core-ledger-java (:18200)
echo "[PFM-UP] Starting pfm-core-ledger-java on :18200..."
cd "$WORKSPACE/pfm-core-ledger-java"
if [ ! -f "target/pfm-core-ledger-java-1.0.0-SNAPSHOT.jar" ]; then
  ./mvnw package -DskipTests >/dev/null
fi
SERVER_PORT=18200 GRPC_SERVER_PORT=18210 DB_URL="jdbc:postgresql://localhost:15432/pfm_core_ledger" KAFKA_BOOTSTRAP_SERVERS="localhost:19092" \
  setsid java -jar target/pfm-core-ledger-java-1.0.0-SNAPSHOT.jar \
  </dev/null > "$LOG_DIR/pfm-core-ledger-java.log" 2>&1 &
echo $! > "$LOG_DIR/pfm-core-ledger-java.pid"

# 2.2 pfm-forecast-engine-go (:18110)
echo "[PFM-UP] Starting pfm-forecast-engine-go on :18110..."
cd "$WORKSPACE/pfm-forecast-engine-go"
go build -o "$LOG_DIR/pfm-forecast-engine-bin" ./cmd/server
GRPC_PORT="18110" REDIS_ADDR="localhost:16379" \
  setsid "$LOG_DIR/pfm-forecast-engine-bin" </dev/null > "$LOG_DIR/pfm-forecast-engine-go.log" 2>&1 &
echo $! > "$LOG_DIR/pfm-forecast-engine-go.pid"

# 2.3 pfm-ai-worker-python
echo "[PFM-UP] Starting pfm-ai-worker-python..."
cd "$WORKSPACE/pfm-ai-worker-python"
WORKER_PORT=18400 AWS_ENDPOINT_URL="http://localhost:14566" KAFKA_BOOTSTRAP_SERVERS="localhost:19092" PFM_AI_RULES_DSN="postgresql://pfm_ai_user:pfm_ai_pass@localhost:15433/pfm_ai_rules" \
  setsid .venv/bin/python -m src.main </dev/null > "$LOG_DIR/pfm-ai-worker-python.log" 2>&1 &
echo $! > "$LOG_DIR/pfm-ai-worker-python.pid"

# 2.4 pfm-ingestion-bff-go (:18100)
echo "[PFM-UP] Starting pfm-ingestion-bff-go on :18100..."
cd "$WORKSPACE/pfm-ingestion-bff-go"
go build -o "$LOG_DIR/pfm-ingestion-bff-bin" ./cmd/server
SERVER_PORT="18100" AWS_ENDPOINT_URL="http://localhost:14566" KAFKA_BROKERS="localhost:19092" \
  CORE_LEDGER_GRPC_ADDR="localhost:18200" CORE_LEDGER_HTTP_URL="http://localhost:18200" FORECAST_GRPC_ADDR="localhost:18110" \
  setsid "$LOG_DIR/pfm-ingestion-bff-bin" </dev/null > "$LOG_DIR/pfm-ingestion-bff-go.log" 2>&1 &
echo $! > "$LOG_DIR/pfm-ingestion-bff-go.pid"

echo "=================================================================="
echo " 3. Starting pfm-web-nextjs (:18300 -> Envoy :18080)"
echo "=================================================================="
cd "$WORKSPACE/pfm-web-nextjs"
NEXT_PUBLIC_API_URL="http://localhost:18080" npm run build >/dev/null
cp -r .next/static .next/standalone/.next/ 2>/dev/null || true
PORT=18300 HOSTNAME="0.0.0.0" NEXT_PUBLIC_API_URL="http://localhost:18080" \
  setsid node .next/standalone/server.js </dev/null > "$LOG_DIR/pfm-web-nextjs.log" 2>&1 &
echo $! > "$LOG_DIR/pfm-web-nextjs.pid"

echo "=================================================================="
echo " 4. Waiting for Health Checks (200 OK)"
echo "=================================================================="
wait_for_url() {
  local name="$1"
  local url="$2"
  local max_wait="${3:-60}"
  for ((i=1; i<=max_wait; i++)); do
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url" || true)
    if [ "$status" = "200" ]; then
      echo "  [OK] $name ($url) -> HTTP 200"
      return 0
    fi
    sleep 1
  done
  echo "  [FAIL] $name ($url) did not return 200 within ${max_wait}s (last=$status)"
  return 1
}

wait_for_url "Envoy Edge Gateway (:18080)" "http://localhost:18080/healthz" 30
wait_for_url "pfm-ingestion-bff-go (:18100)" "http://localhost:18100/health" 30
wait_for_url "pfm-forecast-engine-go (:18110)" "http://localhost:18110/health" 30
wait_for_url "pfm-ai-worker-python (:18400)" "http://localhost:18400/health" 30
wait_for_url "pfm-web-nextjs (:18300)" "http://localhost:18300" 30
wait_for_url "pfm-core-ledger-java (:18200)" "http://localhost:18200/actuator/health" 60

echo "=================================================================="
echo " ALL FULL-STACK SERVICES UP AND HEALTHY!"
echo " Logs: $LOG_DIR"
echo "=================================================================="
