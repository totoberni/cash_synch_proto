# VPS Provider Analysis for AI Agent Documentation Infrastructure

**Date**: 2026-03-01
**Last Updated**: 2026-03-01
**Purpose**: Evaluate VPS providers for deploying autonomous documentation agents at scale
**Decision Status**: DRAFT - Awaiting CEO review

---

## Use Case Requirements

The VPS will host a **multi-AI-agent automated documentation pipeline** that:

1. Listens for Git webhooks (lightweight, event-driven)
2. Processes code changes through AI models via **API calls** (Claude, GPT, Gemini — NOT local model hosting)
3. Generates and updates static HTML documentation
4. Syncs with Google Apps Script projects (HTTP POST/GET)
5. Runs **n8n** workflows for orchestration (queue mode with workers)
6. Hosts **MCP (Model Context Protocol) servers** for tool integration
7. Manages PostgreSQL + Redis for state/queue management
8. **Orchestrates ~10 concurrent AI agent chains**, scaling to 20-40+ as the architecture matures

### Resource Estimate (Base Infrastructure)

| Component | CPU | RAM | Storage | Network |
|-----------|-----|-----|---------|---------|
| n8n main process | 1 vCPU | 400-600 MB | 10 GB | Moderate |
| n8n workers (x2-3) | 1-2 vCPU | 400-1000 MB each | — | Moderate |
| MCP servers (2-3) | 0.5-1 vCPU | 1-2 GB | 5 GB | Low |
| Webhook listener (Node.js) | 0.5 vCPU | 512 MB | 1 GB | Low |
| PostgreSQL | 0.5-1 vCPU | 1-2 GB | 20 GB | Low |
| Redis (queue broker) | 0.25 vCPU | 256-512 MB | 1 GB | Low |
| Nginx reverse proxy | 0.1 vCPU | 64 MB | 1 GB | Low |
| **TOTAL (base stack)** | **4-6 vCPU** | **4-7 GB** | **40-50 GB** | **Moderate** |

**Key insight**: Since we're calling AI APIs (not hosting models locally), we don't need GPU or extreme compute. The real bottleneck is **RAM for concurrent agent processes** and **network for parallel API calls**.

---

## Multi-Agent Concurrency Analysis

### The Scaling Challenge

Our pipeline won't run one agent at a time. The architecture requires **concurrent agent chains** — multiple documentation agents processing different batches, files, or code modules simultaneously. Each agent chain involves:

1. **Receiving a batch** from the n8n queue
2. **Fetching diffs** from GitHub API (HTTP calls, awaiting responses)
3. **Processing through LLM APIs** (Claude/GPT — 3-8 API round-trips per chain)
4. **Writing output** (HTML generation, file I/O)
5. **Reporting results** back to the orchestrator

Each chain is I/O-bound (waiting on API responses) rather than CPU-bound, which means we can run many more concurrent chains than vCPU count — **as long as we have enough RAM**.

### Per-Agent Resource Profile (API-Calling Agents)

| Resource | Per Agent Chain | Notes |
|----------|----------------|-------|
| RAM | 200-500 MB | n8n worker memory per execution + payload buffers |
| CPU | ~0.1-0.3 vCPU sustained | Mostly idle (waiting on API responses); spikes during JSON parsing |
| Network | ~1-5 MB per chain | API request/response payloads (tokens in/out) |
| Disk I/O | Minimal | Writing batch results, HTML output |

**Critical factor**: Token consumption for agentic workflows is **20-30x higher** than standard chatbot interactions (source: Introl). Each agent chain makes multiple LLM calls with full context windows. This doesn't affect server resources (computation happens on the API provider's side) but dramatically affects **API costs** — see cost estimates at the end of this document.

### Concurrency Tiers

| Concurrent Agents | n8n Workers | Worker Concurrency | Total RAM (stack + agents) | Recommended VPS |
|-------------------|-------------|--------------------|----------------------------|-----------------|
| **5-10** (Phase 1) | 2 | 5 | 8-10 GB | 4 vCPU / 8 GB (CX33) |
| **10-20** (Phase 2) | 2-3 | 8 | 12-16 GB | 8 vCPU / 16 GB (CX43) |
| **20-40** (Phase 3) | 3-4 | 10 | 16-24 GB | 8-16 vCPU / 16-32 GB (CX43-CX53) |
| **40+** (Phase 4) | 4+ or multi-node | 10 | 24+ GB | 16 vCPU / 32 GB (CX53) or cluster |

### n8n Queue Mode Architecture (Required for 10+ Agents)

For concurrent agent execution, n8n must run in **queue mode**. This separates the UI/webhook handler from execution workers via Redis:

```
┌──────────────┐     ┌──────────┐     ┌──────────────┐
│ n8n Main     │────>│  Redis   │<────│ n8n Worker 1 │  (concurrency: 8)
│ (UI + hooks) │     │  (queue) │<────│ n8n Worker 2 │  (concurrency: 8)
└──────────────┘     └──────────┘<────│ n8n Worker 3 │  (concurrency: 8)
                                      └──────────────┘
                                      Total: ~24 concurrent executions
```

**Performance benchmark** (official n8n data): Queue mode delivers **7x throughput** — from 23 req/s to 162 req/s with 0% failure rate, compared to 31% failure rate in single-process mode.

**Docker Compose scaling**:
```bash
# Scale workers dynamically
docker compose up -d --scale n8n-worker=3
```

**Key environment variables**:
```env
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=redis
N8N_WORKER_CONCURRENCY=8        # Jobs per worker (default: 10)
DB_TYPE=postgresdb               # PostgreSQL required for queue mode
OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
```

### Agent Execution Timeline (I/O Bound)

A single documentation agent chain takes ~30-120 seconds, but most of that time is spent **waiting** on API responses:

```
Time →  0s          10s         30s         60s        90s       120s
Agent:  [fetch diff] [wait...] [LLM call 1] [wait...] [LLM 2] [write HTML]
CPU:    ████░░░░░░░░████░░░░░░░████░░░░░░░████░░░░░░████░░░░████████
        ^active      ^idle       ^active     ^idle     ^act   ^active
```

Because agents are I/O-bound, 10 agents running concurrently on a 4 vCPU server only sustain ~1-2 vCPU average load. **RAM is the actual limiting factor**, not CPU.

### Reliability Concern: Shared vs Dedicated vCPU

On shared vCPU plans (CX series), other tenants can cause CPU contention:
- Agent chain completing in 45 seconds Monday morning → 300+ seconds Tuesday afternoon
- n8n's default execution timeout is 300 seconds — contention can cause chain failures

**Recommendation**: Start with shared (CX series) for cost. Monitor execution times. If timeout failures exceed 5%, upgrade to **dedicated vCPU** (CCX series) for consistent performance.

---

## Provider Comparison

### 1. Hetzner Cloud (Germany)

**Recommended Tiers** (by scaling phase):

| Spec | CX33 (Start) | CX43 (Growth) | CX53 (Scale) | CCX23 (Dedicated) |
|------|--------------|---------------|--------------|-------------------|
| vCPU | 4 (shared) | 8 (shared) | 16 (shared) | 4 (dedicated) |
| RAM | 8 GB | 16 GB | 32 GB | 16 GB |
| Storage | 80 GB NVMe | 160 GB NVMe | 320 GB NVMe | 160 GB NVMe |
| Bandwidth | 20 TB/mo | 20 TB/mo | 20 TB/mo | 20 TB/mo |
| **Monthly** | **€5.49** | **€9.49** | **€17.49** | **€24.49** |
| Agent capacity | 5-10 | 10-20 | 20-40 | 10-20 (stable) |

**Pros**:
- Best price-to-performance ratio in Europe (unmatched)
- EU-only data centers (Germany, Finland) — full GDPR compliance
- 20 TB/mo bandwidth included (generous for API-calling agents)
- Docker natively supported, full root access
- Excellent API for automation (Terraform, Ansible support)
- Hourly billing available
- Hetzner Volumes for expandable storage
- Built-in firewalls and private networks
- **Smooth upgrade path**: CX33 → CX43 → CX53 with no data migration

**Cons**:
- No managed database (must self-host PostgreSQL/Redis)
- Less polished UI than DigitalOcean
- Limited marketplace compared to DO/AWS
- Support is adequate but not premium
- Shared vCPU can cause contention under neighbor load

**Agent Scaling Verdict**: CX33 (€5.49) handles the MVP comfortably with 5-10 concurrent agents. When scaling to 20+, CX43 (€9.49) at double the RAM for under €10/mo is remarkable value. The CX53 (€17.49) at 32 GB RAM handles 40+ concurrent agents — for the price of a single lunch.

**PRICE INCREASE ALERT** (April 1, 2026): Hetzner announced ~30-37% price increases effective April 2026 across all cloud tiers, citing rising hardware and infrastructure costs. Estimated post-increase pricing:

| Plan | Current | Est. Post-April | Change |
|------|---------|-----------------|--------|
| CX33 | €5.49 | ~€7.14 | +30% |
| CX43 | €9.49 | ~€12.34 | +30% |
| CX53 | €17.49 | ~€22.74 | +30% |
| CCX23 | €24.49 | ~€31.84 | +30% |

**Even with the increase**, Hetzner remains 3-5x cheaper than DigitalOcean/Vultr for equivalent specs. The upgrade path recommendation doesn't change.

---

### 2. Contabo (Germany)

**Recommended Tier**: Cloud VPS M

| Spec | Cloud VPS S | Cloud VPS M |
|------|-------------|-------------|
| vCPU | 4 | 6 |
| RAM | 8 GB | 16 GB |
| Storage | 200 GB NVMe | 400 GB NVMe |
| Bandwidth | 32 TB/mo | 32 TB/mo |
| **Monthly** | **~€5.99** | **~€10.49** |
| Agent capacity | 5-10 | 10-15 |

**Pros**:
- Extremely generous storage (200-400 GB NVMe)
- EU data centers (Germany, UK)
- Docker/KVM supported
- Full root access
- Very competitive pricing for the specs
- 32 TB bandwidth

**Cons**:
- Mixed reputation for support quality and response times
- Network performance can be inconsistent (reported latency spikes)
- Overselling concerns (shared resources) — **critical for agent concurrency**
- Less mature API than Hetzner/DO
- Provisioning can take hours (not instant)
- **Agent concern**: CPU contention from overselling makes execution times unpredictable; agent chains may timeout

**Agent Scaling Verdict**: The 16 GB RAM on VPS M is attractive for 10-15 agents, but Contabo's overselling reputation is a serious risk for concurrent agent workloads where consistent API response handling matters. Use as **development/staging only**.

---

### 3. DigitalOcean (US/EU)

**Recommended Tier**: Regular Droplet 8GB

| Spec | 4GB Droplet | 8GB Droplet |
|------|-------------|-------------|
| vCPU | 2 | 4 |
| RAM | 4 GB | 8 GB |
| Storage | 80 GB SSD | 160 GB SSD |
| Bandwidth | 4 TB/mo | 5 TB/mo |
| **Monthly** | **~$24** | **~$48** |
| Agent capacity | 3-5 | 5-10 |

**Pros**:
- Best developer experience (clean UI, excellent docs)
- 1-click Docker, n8n, PostgreSQL marketplace apps
- Managed databases available (PostgreSQL, Redis) for additional cost
- EU data centers (Amsterdam, Frankfurt, London)
- Monitoring, alerts, and team management built-in
- Excellent API and CLI tooling
- Spaces (S3-compatible object storage)
- Strong community and tutorial library

**Cons**:
- Significantly more expensive than Hetzner (4-8x for similar specs)
- Lower bandwidth allocation (4-5 TB vs 20 TB) — **risk for high-volume API calls**
- NVMe not available on basic droplets (regular SSD)
- US-based company (GDPR compliance via DPA, not inherent)
- **Agent concern**: 5 TB bandwidth may not suffice for 20+ agents making heavy API calls

**Agent Scaling Verdict**: At $48/mo for 8 GB (enough for ~10 agents), you get managed services but pay 8x what Hetzner charges for equivalent specs. Only justified if managed PostgreSQL/Redis is critical and you're not scaling beyond 10 agents.

---

### 4. Vultr (US/EU)

**Recommended Tier**: Cloud Compute (Regular) 8GB

| Spec | 4GB | 8GB |
|------|-----|-----|
| vCPU | 2 | 4 |
| RAM | 4 GB | 8 GB |
| Storage | 100 GB SSD | 200 GB SSD |
| Bandwidth | 3 TB/mo | 4 TB/mo |
| **Monthly** | **~$24** | **~$48** |
| Agent capacity | 3-5 | 5-10 |

**Pros**:
- Wide datacenter selection (Amsterdam, Paris, Frankfurt, Stockholm, Madrid, Warsaw)
- Block storage and object storage available
- Docker supported, full root access
- Managed databases (PostgreSQL, Redis) at extra cost
- Good API

**Cons**:
- Similar pricing to DigitalOcean (expensive vs Hetzner)
- Limited bandwidth (3-4 TB vs 20 TB) — **worst for agent scaling**
- Less community/tutorials than DO
- US-based (GDPR via DPA)

**Agent Scaling Verdict**: Comparable to DigitalOcean but with even less bandwidth. No advantage over Hetzner for agent workloads.

---

### 5. OVH Cloud (France)

**Recommended Tier**: VPS Comfort

| Spec | VPS Starter | VPS Comfort |
|------|-------------|-------------|
| vCPU | 2 | 4 |
| RAM | 4 GB | 8 GB |
| Storage | 80 GB NVMe | 160 GB NVMe |
| Bandwidth | 500 Mbps unlimited | 1 Gbps unlimited |
| **Monthly** | **~€8** | **~€16** |
| Agent capacity | 3-5 | 5-10 |

**Pros**:
- French company, EU data centers (Strasbourg, Paris, Frankfurt)
- Unlimited bandwidth (no overage charges) — **good for heavy API traffic**
- Anti-DDoS protection included
- Competitive pricing
- GDPR compliant by default (EU entity)

**Cons**:
- Support quality varies significantly
- UI/UX is dated and confusing
- Control panel less intuitive than competitors
- Provisioning delays reported
- API less mature than Hetzner/DO
- **Agent concern**: Only 4 vCPU / 8 GB at the Comfort tier — need higher (more expensive) tier for 20+ agents

**Agent Scaling Verdict**: Unlimited bandwidth is attractive for heavy API traffic, but 8 GB RAM at €16 is poor value compared to Hetzner CX43 (16 GB at €9.49). Only worth considering if bandwidth caps are a concern.

---

## Summary Comparison Table

| Provider | Plan | vCPU | RAM | Storage | BW/mo | Monthly | Agents (est.) | EU | GDPR |
|----------|------|------|-----|---------|-------|---------|---------------|-----|------|
| **Hetzner** | CX33 | 4 | 8 GB | 80 GB NVMe | 20 TB | **€5.49** | 5-10 | DE, FI | Native |
| **Hetzner** | CX43 | 8 | 16 GB | 160 GB NVMe | 20 TB | **€9.49** | 10-20 | DE, FI | Native |
| **Hetzner** | CX53 | 16 | 32 GB | 320 GB NVMe | 20 TB | **€17.49** | 20-40 | DE, FI | Native |
| **Hetzner** | CCX23 | 4 (ded) | 16 GB | 160 GB NVMe | 20 TB | **€24.49** | 10-20 (stable) | DE, FI | Native |
| **Contabo** | VPS S | 4 | 8 GB | 200 GB NVMe | 32 TB | €5.99 | 5-10 | DE, UK | Native |
| **Contabo** | VPS M | 6 | 16 GB | 400 GB NVMe | 32 TB | €10.49 | 10-15 | DE, UK | Native |
| **DigitalOcean** | 8GB | 4 | 8 GB | 160 GB SSD | 5 TB | ~€44 | 5-10 | AMS, FRA | DPA |
| **Vultr** | 8GB | 4 | 8 GB | 200 GB SSD | 4 TB | ~€44 | 5-10 | AMS, PAR | DPA |
| **OVH** | Comfort | 4 | 8 GB | 160 GB NVMe | Unlim | €16 | 5-10 | FR, DE | Native |

---

## Final Shortlist & Recommendation (Agent-Scaled)

### Scaling Roadmap (Recommended Path)

| Phase | Agents | Provider | Plan | Monthly | When |
|-------|--------|----------|------|---------|------|
| **MVP** | 5-10 | Hetzner | CX33 | €5.49 | Day 1 |
| **Growth** | 10-20 | Hetzner | CX43 | €9.49 | Month 2-3 |
| **Scale** | 20-40 | Hetzner | CX53 | €17.49 | Month 6+ |
| **Stability** | 10-20 (dedicated) | Hetzner | CCX23 | €24.49 | If timeouts occur |

### 1st Choice: Hetzner Cloud CX33 → CX43 Growth Path

**Why**: Start lean at €5.49/mo with 8 GB RAM (enough for 5-10 concurrent agents + full stack). As agent count grows past 10, upgrade to CX43 (16 GB, €9.49) — still under €10/mo. The upgrade is a button click with no data migration.

**Setup**: Docker Compose with n8n (queue mode), PostgreSQL, Redis, 2 workers, MCP servers, webhook listener, Nginx reverse proxy. Total: ~€5.49/mo (+ domain ~€10/year).

### 2nd Choice: Contabo Cloud VPS M (~€10.49/mo)

**Why**: If storage is a priority (400 GB NVMe) or you need 16 GB RAM from day one. Good for storing AI conversation logs, generated documentation history, and batch archives.

**Caveat**: Overselling risk makes this unreliable for production agent workloads. Better as secondary/staging.

### 3rd Choice: Hetzner CCX23 (~€24.49/mo)

**Why**: If shared vCPU causes execution timeouts. Dedicated 4 vCPU provides consistent performance for 10-20 concurrent agents without noisy-neighbor issues. Still 2x cheaper than DigitalOcean's equivalent offering.

---

## n8n Queue Mode Requirements (Production Multi-Agent)

Per official n8n documentation, community recommendations, and production benchmarks:

| Configuration | Value | Notes |
|---------------|-------|-------|
| Execution mode | `queue` | Required for concurrent agents |
| Database | PostgreSQL | SQLite fails under concurrent writes |
| Queue broker | Redis (256-512 MB) | BullMQ-based job distribution |
| Workers per VPS | 2-4 | Scale with `docker compose --scale` |
| Concurrency per worker | 5-10 | `N8N_WORKER_CONCURRENCY` env var |
| Worker RAM | 200-500 MB each | Spikes during large payload processing |
| Main process RAM | 400-600 MB | UI, webhooks, scheduler |
| SSL termination | Nginx + Let's Encrypt | Traefik also supported |
| Health checks | Active | `QUEUE_HEALTH_CHECK_ACTIVE=true` |

**Performance**: Queue mode delivers **7x throughput** (162 req/s vs 23 req/s) with **0% failure rate** (vs 31% in single-process mode).

### Docker Compose Scaling

```bash
# Start with 2 workers
docker compose up -d

# Scale to 4 workers when agent load increases
docker compose up -d --scale n8n-worker=4
```

### VPS Tier → Worker/Agent Mapping

| VPS Resources | Workers | Concurrency/Worker | Max Concurrent Agents |
|---------------|---------|--------------------|-----------------------|
| 4 vCPU / 8 GB RAM | 2 | 5 | ~10 |
| 8 vCPU / 16 GB RAM | 2-3 | 8 | ~16-24 |
| 16 vCPU / 32 GB RAM | 3-4 | 10 | ~30-40 |

---

## Cost Projection (Annual, Agent-Scaled)

| Scenario | Provider | Plan | Monthly | Annual | Agents | Notes |
|----------|----------|------|---------|--------|--------|-------|
| **MVP** | Hetzner | CX33 | €5.49 | ~€66 | 5-10 | Sufficient for first pipeline |
| **Growth** | Hetzner | CX43 | €9.49 | ~€114 | 10-20 | Sweet spot for production |
| **Scale** | Hetzner | CX53 | €17.49 | ~€210 | 20-40 | Multi-repo documentation |
| **Dedicated** | Hetzner | CCX23 | €24.49 | ~€294 | 10-20 | Consistent performance |
| **Storage** | Contabo | VPS M | €10.49 | ~€126 | 10-15 | Large doc archives |
| **Premium** | DigitalOcean | 8GB | ~€44 | ~€528 | 5-10 | Managed services only |

**Recommendation for CEO**: Start with **Hetzner CX33 at €5.49/mo** (~€66/year). This handles 5-10 concurrent agents — more than enough for the initial SISTEMA_DIPENDENTI documentation pipeline. When agent count grows past 10, upgrade to CX43 (€9.49/mo) for double the RAM. Total first-year investment: **under €120** for the VPS itself.

**Additional costs to budget**:
- Domain name: ~€10-15/year
- AI API costs (Claude/GPT/Gemini): Variable — **this is the dominant cost**; budget €50-200/mo depending on usage volume
- SSL: Free (Let's Encrypt)
- Monitoring: Free (Prometheus + Grafana in Docker, or Hetzner Cloud metrics)

### API Cost Estimate (The Real Expense)

Since agents call external LLM APIs, the VPS cost is negligible compared to API usage:

| Agent Activity | Tokens/Chain | Chains/Day | Monthly Cost (Claude est.) |
|----------------|-------------|------------|----------------------------|
| Light (5 agents, small batches) | ~10K tokens | 10-20 | ~€20-50 |
| Moderate (10 agents, daily batches) | ~20K tokens | 30-60 | ~€80-150 |
| Heavy (20+ agents, frequent batches) | ~30K tokens | 60-120 | ~€200-400 |

**The VPS is <5% of total infrastructure cost. API spend is 95%+.** Optimize agents (shorter prompts, caching, use Haiku for simple tasks) for the biggest savings.

---

## Next Steps

1. **Immediate**: Complete sandbox plan2 Phases 1-6 (local ngrok pipeline)
2. **After CEO approval**: Sign up for Hetzner Cloud (5-minute process)
3. **Day 1**: Provision CX33, install Docker, deploy stack
4. **Day 2**: Migrate from ngrok to VPS endpoint
5. **Week 1**: Test full pipeline with 2-3 concurrent agents
6. **Week 2**: Scale to 5-10 agents, monitor RAM usage
7. **Month 1**: Evaluate if upgrade to CX43 is needed
8. **Month 3+**: Scale agents based on documentation needs

---

## Sources

- [MassiveGRID — Best VPS for n8n AI Agents](https://massivegrid.com/blog/best-vps-n8n-ai-agents/)
- [TezHost — 5 Critical Infrastructure Secrets for n8n AI Agents](https://tezhost.com/n8n-ai-agents-most-teams-miss-in-2026/)
- [VPS.us — n8n VPS Requirements by Tier](https://vps.us/blog/n8n-vps-requirements/)
- [NextGrowth.AI — n8n Queue Mode Docker Compose Guide](https://nextgrowth.ai/scaling-n8n-queue-mode-docker-compose/)
- [n8n Docs — Queue Mode Configuration](https://docs.n8n.io/hosting/scaling/queue-mode/)
- [n8n Docs — Concurrency Control](https://docs.n8n.io/hosting/scaling/concurrency-control/)
- [n8n Blog — 15 Best Practices for Deploying AI Agents](https://blog.n8n.io/best-practices-for-deploying-ai-agents-in-production/)
- [Introl — AI Agent Infrastructure Requirements](https://introl.com/blog/ai-agent-infrastructure-autonomous-systems-compute-requirements-2025)
- [Hetzner Cloud Pricing](https://www.hetzner.com/cloud)
- [CostGoat — Hetzner Cloud Pricing Calculator (Feb 2026)](https://costgoat.com/pricing/hetzner)
- [HostingJournalist — Hetzner Price Increase 2026](https://hostingjournalist.com/news/hetzner-to-significantly-raise-cloud-and-server-prices-in-2026)
- [Hetzner Price Adjustment Docs](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)
- [Contabo Blog — Self-Hosting n8n Guide](https://contabo.com/blog/self-hosting-n8n-a-comprehensive-docker-vps-guide/)
- [n8n Hosting Documentation](https://docs.n8n.io/hosting/)
- [Best European VPS Hosting 2026](https://hostadvice.com/vps/europe/)
