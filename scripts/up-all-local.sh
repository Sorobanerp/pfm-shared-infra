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

for port in 3000 8081 9090 9091; do
  fuser -k "${port}/tcp" >/dev/null 2>&1 || true
done

echo "[PFM-UP] Applying idempotent PostgreSQL 16 RLS schemas & Kafka topics..."
docker exec -i postgres-core-ledger psql -U postgres -d pfm_core_ledger < "$WORKSPACE/pfm-core-ledger-java/src/main/resources/db/migration/V1__init_multitenant_ledger.sql" >/dev/null
docker exec -i postgres-ai-rules psql -U postgres -d pfm_ai_rules < "$WORKSPACE/pfm-shared-infra/local-cloud/init-db/init-pgvector.sql" >/dev/null

for topic in statement.raw.extracted tx.categorized receipt.items.extracted ledger.entry.committed; do
  docker exec pfm-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists --topic "$topic" --partitions 6 --replication-factor 1 >/dev/null 2>&1 || true
done

curl -fsS -X PUT "http://localhost:4566/pfm-statements-encrypted-local" >/dev/null 2>&1 || true

echo "=================================================================="
echo " 2. Starting 4 Backend Microservices (Logs in $LOG_DIR)"
echo "=================================================================="

# 2.1 pfm-core-ledger-java (:9090)
echo "[PFM-UP] Starting pfm-core-ledger-java on :9090..."
cd "$WORKSPACE/pfm-core-ledger-java"
if [ ! -f "target/pfm-core-ledger-java-1.0.0-SNAPSHOT.jar" ]; then
  ./mvnw package -DskipTests >/dev/null
fi
setsid java -jar target/pfm-core-ledger-java-1.0.0-SNAPSHOT.jar --server.port=9090 \
  </dev/null > "$LOG_DIR/pfm-core-ledger-java.log" 2>&1 &
echo $! > "$LOG_DIR/pfm-core-ledger-java.pid"

# 2.2 pfm-forecast-engine-go (:9091)
echo "[PFM-UP] Starting pfm-forecast-engine-go on :9091..."
cd "$WORKSPACE/pfm-forecast-engine-go"
go build -o "$LOG_DIR/pfm-forecast-engine-bin" ./cmd/server
GRPC_PORT=":9091" REDIS_ADDR="localhost:6379" \
  setsid "$LOG_DIR/pfm-forecast-engine-bin" </dev/null > "$LOG_DIR/pfm-forecast-engine-go.log" 2>&1 &
echo $! > "$LOG_DIR/pfm-forecast-engine-go.pid"

# 2.3 pfm-ai-worker-python
echo "[PFM-UP] Starting pfm-ai-worker-python..."
cd "$WORKSPACE/pfm-ai-worker-python"
KAFKA_BOOTSTRAP_SERVERS="localhost:9092" PFM_AI_RULES_DSN="postgresql://pfm_ai_user:pfm_ai_pass@localhost:5433/pfm_ai_rules" \
  setsid .venv/bin/python -m src.main </dev/null > "$LOG_DIR/pfm-ai-worker-python.log" 2>&1 &
echo $! > "$LOG_DIR/pfm-ai-worker-python.pid"

# 2.4 pfm-ingestion-bff-go (:8081)
echo "[PFM-UP] Starting pfm-ingestion-bff-go on :8081..."
cd "$WORKSPACE/pfm-ingestion-bff-go"
go build -o "$LOG_DIR/pfm-ingestion-bff-bin" ./cmd/server
PORT="8081" LOCALSTACK_ENDPOINT="http://localhost:4566" KAFKA_BROKERS="localhost:9092" \
  CORE_LEDGER_GRPC_ADDR="localhost:9090" CORE_LEDGER_HTTP_URL="http://localhost:9090" FORECAST_ENGINE_HTTP_URL="http://localhost:9091" \
  setsid "$LOG_DIR/pfm-ingestion-bff-bin" </dev/null > "$LOG_DIR/pfm-ingestion-bff-go.log" 2>&1 &
echo $! > "$LOG_DIR/pfm-ingestion-bff-go.pid"

echo "=================================================================="
echo " 3. Starting pfm-web-nextjs (:3000 -> Envoy :8080)"
echo "=================================================================="
cd "$WORKSPACE/pfm-web-nextjs"
if [ ! -f ".next/standalone/server.js" ]; then
  NEXT_PUBLIC_PFM_BFF_URL="http://localhost:8080" npm run build >/dev/null
fi
cp -r .next/static .next/standalone/.next/ 2>/dev/null || true
PORT=3000 HOSTNAME="0.0.0.0" NEXT_PUBLIC_PFM_BFF_URL="http://localhost:8080" \
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

wait_for_url "Envoy Edge Gateway (:8080)" "http://localhost:8080/healthz" 30
wait_for_url "pfm-ingestion-bff-go (:8081)" "http://localhost:8081/health" 30
wait_for_url "pfm-forecast-engine-go (:9091)" "http://localhost:9091/health" 30
wait_for_url "pfm-web-nextjs (:3000)" "http://localhost:3000" 30
wait_for_url "pfm-core-ledger-java (:9090)" "http://localhost:9090/actuator/health" 60

echo "=================================================================="
echo " ALL FULL-STACK SERVICES UP AND HEALTHY!"
echo " Logs: $LOG_DIR"
echo "=================================================================="
