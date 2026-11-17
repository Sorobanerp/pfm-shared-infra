package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/rand/v2"
	"net/http"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type StageResult struct {
	Profile              string            `json:"profile"`
	MaxVUs               int               `json:"max_vus"`
	DurationSeconds      float64           `json:"duration_seconds"`
	TotalRequests        int64             `json:"total_requests"`
	ThroughputRPS        float64           `json:"throughput_rps"`
	Status200            int64             `json:"status_200"`
	Status304ETag        int64             `json:"status_304_etag"`
	Status429RateLimited int64             `json:"status_429_rate_limited"`
	Status5xxErrors      int64             `json:"status_5xx_errors"`
	ErrorRatePct         float64           `json:"error_rate_pct"`
	DashboardP50Ms       float64           `json:"dashboard_p50_ms"`
	DashboardP95Ms       float64           `json:"dashboard_p95_ms"`
	DashboardP99Ms       float64           `json:"dashboard_p99_ms"`
	ForecastGrpcP50Ms    float64           `json:"forecast_grpc_p50_ms"`
	ForecastGrpcP95Ms    float64           `json:"forecast_grpc_p95_ms"`
	ForecastGrpcP99Ms    float64           `json:"forecast_grpc_p99_ms"`
	NfceIngestP95Ms      float64           `json:"nfce_ingest_p95_ms"`
	NfceIngestP99Ms      float64           `json:"nfce_ingest_p99_ms"`
	StatementUploadP95Ms float64           `json:"statement_upload_p95_ms"`
	StatementUploadP99Ms float64           `json:"statement_upload_p99_ms"`
	DockerStatsSnapshot  []string          `json:"docker_stats_snapshot"`
	ProcessRssSnapshot   map[string]string `json:"process_rss_snapshot"`
	PostgresConnections  string            `json:"postgres_connections"`
	RedisUsedMemory      string            `json:"redis_used_memory"`
}

func runProfile(baseURL string, profile string, maxVUs int, duration time.Duration, thinkTime time.Duration) StageResult {
	client := &http.Client{
		Timeout: 5 * time.Second,
		Transport: &http.Transport{
			MaxIdleConns:        2000,
			MaxIdleConnsPerHost: 2000,
			IdleConnTimeout:     30 * time.Second,
		},
	}

	var (
		totalReqs   atomic.Int64
		code200     atomic.Int64
		code304     atomic.Int64
		code429     atomic.Int64
		code5xx     atomic.Int64
		muLat       sync.Mutex
		dashLat     []float64
		forecastLat []float64
		nfceLat     []float64
		uploadLat   []float64
	)

	start := time.Now()
	deadline := start.Add(duration)
	var wg sync.WaitGroup

	for vu := 1; vu <= maxVUs; vu++ {
		wg.Add(1)
		go func(vuID int) {
			defer wg.Done()
			// Stagger ramp-up for tier1_bank_stress (50 -> 250 -> 500 -> 1000 VUs)
			if profile == "tier1_bank_stress" {
				if vuID > 500 {
					time.Sleep(3 * time.Second)
				} else if vuID > 250 {
					time.Sleep(2 * time.Second)
				} else if vuID > 50 {
					time.Sleep(1 * time.Second)
				}
			}

			pool := []string{
				"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
				"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
				"cccccccc-cccc-4ccc-8ccc-cccccccccccc",
				"dddddddd-dddd-4ddd-8ddd-dddddddddddd",
				"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
			}
			tenantID := pool[(vuID-1)%len(pool)]
			var lastETag string
			iter := 0
			for time.Now().Before(deadline) {
				iter++

				roll := rand.IntN(100)
				reqStart := time.Now()
				var resp *http.Response
				var err error

				if roll < 60 {
					// 60%: Read Dashboard / Multi-Card Matrix with ETag
					req, _ := http.NewRequest(http.MethodGet, baseURL+"/api/v1/dashboard?scope=FAMILY", nil)
					req.Header.Set("X-Tenant-ID", tenantID)
					req.Header.Set("Accept-Encoding", "br, gzip")
					if lastETag != "" {
						req.Header.Set("If-None-Match", lastETag)
					}
					resp, err = client.Do(req)
					elapsedMs := float64(time.Since(reqStart).Microseconds()) / 1000.0
					if err == nil && resp != nil {
						if et := resp.Header.Get("ETag"); et != "" {
							lastETag = et
						}
						_, _ = io.Copy(io.Discard, resp.Body)
						_ = resp.Body.Close()
						muLat.Lock()
						dashLat = append(dashLat, elapsedMs)
						muLat.Unlock()
					}
				} else if roll < 80 {
					// 20%: NFC-e Receipt Ingestion
					body := fmt.Sprintf(`{"qrCodeUrl":"https://nfce.set.rn.gov.br/consultarNFCe.aspx?p=24261175315333000109650010000987651000987654|2|1|1","cardId":"33333333-aaaa-4aaa-8aaa-333333333333","paymentMethod":"CREDIT_CARD","idempotencyKey":"sha256-%s-%d"}`, tenantID, iter)
					req, _ := http.NewRequest(http.MethodPost, baseURL+"/api/v1/receipts/nfce", strings.NewReader(body))
					req.Header.Set("Content-Type", "application/json")
					req.Header.Set("X-Tenant-ID", tenantID)
					resp, err = client.Do(req)
					elapsedMs := float64(time.Since(reqStart).Microseconds()) / 1000.0
					if err == nil && resp != nil {
						_, _ = io.Copy(io.Discard, resp.Body)
						_ = resp.Body.Close()
						muLat.Lock()
						nfceLat = append(nfceLat, elapsedMs)
						muLat.Unlock()
					}
				} else if roll < 95 {
					// 15%: Contract Amortization Simulation (gRPC Forecast Engine)
					body := `{"contract_id":"sac-k6","amortization_system":"SAC","prepayment_strategy":"REDUCE_TERM","outstanding_balance":"300000.0000","remaining_installments":120,"monthly_interest_rate":"0.0080","extra_amortization_amount":"60000.0000"}`
					req, _ := http.NewRequest(http.MethodPost, baseURL+"/api/v1/contracts/simulate", strings.NewReader(body))
					req.Header.Set("Content-Type", "application/json")
					req.Header.Set("X-Tenant-ID", tenantID)
					resp, err = client.Do(req)
					elapsedMs := float64(time.Since(reqStart).Microseconds()) / 1000.0
					if err == nil && resp != nil {
						_, _ = io.Copy(io.Discard, resp.Body)
						_ = resp.Body.Close()
						muLat.Lock()
						forecastLat = append(forecastLat, elapsedMs)
						muLat.Unlock()
					}
				} else {
					// 5%: Statement PDF Upload in RAM
					stmt := "REF: 2026-11\nVENCIMENTO: 2026-11-25\nTOTAL_FATURA: 6311.14\n2026-11-14 | ATACADAO SA | 313.01\n2026-11-15 | MOBILIA DESIGN 01/10 | 6159.08\n2026-11-16 | MENSALIDADE ITAU AVISA | 7.99\n2026-11-16 | ESTORNO LOJA RENNER | -168.94\n"
					req, _ := http.NewRequest(http.MethodPost, baseURL+"/api/v1/statements/upload", bytes.NewBufferString(stmt))
					req.Header.Set("X-Tenant-ID", tenantID)
					req.Header.Set("X-Statement-Issuer", "ITAU")
					req.Header.Set("X-Card-Last4", "5285")
					resp, err = client.Do(req)
					elapsedMs := float64(time.Since(reqStart).Microseconds()) / 1000.0
					if err == nil && resp != nil {
						_, _ = io.Copy(io.Discard, resp.Body)
						_ = resp.Body.Close()
						muLat.Lock()
						uploadLat = append(uploadLat, elapsedMs)
						muLat.Unlock()
					}
				}

				totalReqs.Add(1)
				if err != nil || resp == nil {
					code5xx.Add(1)
				} else {
					switch resp.StatusCode {
					case http.StatusOK:
						code200.Add(1)
					case http.StatusNotModified:
						code304.Add(1)
					case http.StatusTooManyRequests:
						code429.Add(1)
					default:
						if resp.StatusCode >= 500 {
							code5xx.Add(1)
						} else {
							code200.Add(1)
						}
					}
				}

				if thinkTime > 0 {
					time.Sleep(thinkTime)
				}
			}
		}(vu)
	}

	// Capture live infrastructure telemetry halfway through the run
	time.Sleep(duration / 2)
	dockerStats := captureDockerStats()
	procRss := captureProcessRss()
	pgConns := capturePostgresConnections()
	redisMem := captureRedisMemory()

	wg.Wait()
	actualSec := time.Since(start).Seconds()
	tot := totalReqs.Load()
	errPct := 0.0
	if tot > 0 {
		errPct = float64(code5xx.Load()) * 100.0 / float64(tot)
	}

	return StageResult{
		Profile:              profile,
		MaxVUs:               maxVUs,
		DurationSeconds:      round2(actualSec),
		TotalRequests:        tot,
		ThroughputRPS:        round2(float64(tot) / actualSec),
		Status200:            code200.Load(),
		Status304ETag:        code304.Load(),
		Status429RateLimited: code429.Load(),
		Status5xxErrors:      code5xx.Load(),
		ErrorRatePct:         round2(errPct),
		DashboardP50Ms:       percentile(dashLat, 0.50),
		DashboardP95Ms:       percentile(dashLat, 0.95),
		DashboardP99Ms:       percentile(dashLat, 0.99),
		ForecastGrpcP50Ms:    percentile(forecastLat, 0.50),
		ForecastGrpcP95Ms:    percentile(forecastLat, 0.95),
		ForecastGrpcP99Ms:    percentile(forecastLat, 0.99),
		NfceIngestP95Ms:      percentile(nfceLat, 0.95),
		NfceIngestP99Ms:      percentile(nfceLat, 0.99),
		StatementUploadP95Ms: percentile(uploadLat, 0.95),
		StatementUploadP99Ms: percentile(uploadLat, 0.99),
		DockerStatsSnapshot:  dockerStats,
		ProcessRssSnapshot:   procRss,
		PostgresConnections:  pgConns,
		RedisUsedMemory:      redisMem,
	}
}

func percentile(values []float64, p float64) float64 {
	if len(values) == 0 {
		return 0
	}
	cp := slices.Clone(values)
	slices.Sort(cp)
	idx := int(float64(len(cp)-1) * p)
	return round2(cp[idx])
}

func round2(v float64) float64 {
	return float64(int64(v*100+0.5)) / 100.0
}

func captureDockerStats() []string {
	out, err := exec.Command("docker", "stats", "--no-stream", "--format", "{{.Name}}: CPU={{.CPUPerc}} MEM={{.MemUsage}}").Output()
	if err != nil {
		return nil
	}
	return strings.Split(strings.TrimSpace(string(out)), "\n")
}

func captureProcessRss() map[string]string {
	res := make(map[string]string)
	services := []string{"pfm-core-ledger-java", "pfm-forecast-engine-go", "pfm-ai-worker-python", "pfm-ingestion-bff-go", "pfm-web-nextjs"}
	for _, svc := range services {
		pidBytes, err := os.ReadFile("/tmp/pfm-logs/" + svc + ".pid")
		if err != nil {
			continue
		}
		pid := strings.TrimSpace(string(pidBytes))
		out, err := exec.Command("ps", "-p", pid, "-o", "%cpu,rss,vsz,comm", "--no-headers").Output()
		if err == nil {
			res[svc] = strings.TrimSpace(string(out))
		}
	}
	return res
}

func capturePostgresConnections() string {
	out, err := exec.Command("docker", "exec", "postgres-core-ledger", "psql", "-U", "postgres", "-d", "pfm_core_ledger", "-tAc", "SELECT count(*) FROM pg_stat_activity WHERE datname='pfm_core_ledger';").Output()
	if err != nil {
		return "N/A"
	}
	return strings.TrimSpace(string(out)) + " active connections"
}

func captureRedisMemory() string {
	out, err := exec.Command("docker", "exec", "pfm-redis", "valkey-cli", "info", "memory").Output()
	if err != nil {
		return "N/A"
	}
	for _, line := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(line, "used_memory_human:") {
			return strings.TrimSpace(strings.TrimPrefix(line, "used_memory_human:"))
		}
	}
	return "N/A"
}

func seedPilotTenants() {
	tenants := []string{
		"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
		"cccccccc-cccc-4ccc-8ccc-cccccccccccc",
		"dddddddd-dddd-4ddd-8ddd-dddddddddddd",
		"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
	}
	for _, t := range tenants {
		sql := fmt.Sprintf("SET LOCAL app.current_tenant_id = '%s'; INSERT INTO tenants (id, tenant_id, name, monthly_net_income) VALUES ('%s', '%s', 'Pilot Tenant', 15000.0000) ON CONFLICT (id) DO NOTHING;", t, t, t)
		_ = exec.Command("docker", "exec", "postgres-core-ledger", "psql", "-U", "postgres", "-d", "pfm_core_ledger", "-c", sql).Run()
	}
}

func main() {
	seedPilotTenants()
	baseURL := os.Getenv("BASE_URL")
	if baseURL == "" {
		baseURL = "http://localhost:18080"
	}

	pilot := runProfile(baseURL, "pilot_5_users", 5, 6*time.Second, 80*time.Millisecond)
	stress := runProfile(baseURL, "tier1_bank_stress", 1000, 10*time.Second, 5*time.Millisecond)

	report := map[string]any{
		"executed_at":       time.Now().UTC().Format(time.RFC3339),
		"pilot_5_users":     pilot,
		"tier1_bank_stress": stress,
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(report)
}
