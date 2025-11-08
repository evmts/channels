# P12: Production Hardening

**Meta:** P12 | Deps: All previous | Owner: Core

## Zig Profiling/Optimization

**Built-in:**
- `std.testing.benchmark` - basic timing
- `@setCold/@setHot` - branch hints
- `@setRuntimeSafety(false)` - disable checks hot paths
- `std.debug.print` timing manual
- Comptime evaluation - move work to compile time

**External profilers:**
- `perf` (Linux syscalls) - official tracking uses this
- `valgrind` - memory profiling
- Custom instrumentation

**Official tracking:** ziglang.org/perf - benchmarks every master commit (speed, mem, throughput)

**Optimization:** Profile first (perf/valgrind), then: comptime, inline, SIMD, algorithm/data structure choice

**Recent wins:** 5-50% wall-clock improvements (self-hosted x86_64 backend, 2025)

## Summary

Prepare system for production deployment - security audit, performance optimization, monitoring, operational tooling, documentation polish. Critical for real-world usage - without hardening, system vulnerable to attacks, performance issues, operational failures. Comprehensive phase covering security, reliability, observability, deployment automation, user documentation. Not feature development - quality, security, operations focus.

## Objectives

- OBJ-1: Security audit by external firm (cryptography, protocol logic)
- OBJ-2: Performance optimization (profiling, hot path tuning)
- OBJ-3: Monitoring + metrics (Prometheus, alerting)
- OBJ-4: Operational tooling (deployment, backup, recovery)
- OBJ-5: Documentation polish (user guides, API docs, troubleshooting)

## Success Criteria

**Done when:**
- Security audit passed (0 critical, <5 high)
- Performance optimized (2x faster vs P11)
- Monitoring complete (all metrics tracked, dashboard + alerts)
- Deploy automation works (CI/CD pipeline <30min deploy)
- Docs complete (100% API coverage, guides exist)
- Production-ready sign-off

**Exit gates:** Audit passed, benchmarks 2x improved, monitoring live, CI/CD working, docs published

## Architecture

**Components:** SecurityAudit (external review + fixes), PerformanceOptimizer (profile-guided optimization), MonitoringStack (metrics collection + dashboards), DeploymentPipeline (CI/CD automation), DocumentationSite (user-facing docs)

**Focus Areas:**
1. Security: Crypto validation, input sanitization, DOS prevention
2. Performance: Memory allocation, WASM JIT, network batching
3. Reliability: Error handling, recovery, graceful degradation
4. Observability: Logging, metrics, tracing, debugging
5. Operations: Deployment, configuration, backup, monitoring

## Data Structures

```zig
pub const Metrics = struct {
    channels_created: Counter,
    messages_sent: Counter,
    signatures_verified: Counter,
    derivation_duration: Histogram,
    event_log_size: Gauge,

    pub fn record(self: *Self, metric: MetricType, value: f64) void;
};

pub const Config = struct {
    rpc_url: []const u8,
    p2p_listen: []const u8,
    data_dir: []const u8,
    log_level: LogLevel,
    metrics_port: u16,

    pub fn loadFromFile(path: []const u8, a: Allocator) !Config;
};
```

## APIs

```zig
// Init with production config
pub fn initProduction(config_path: []const u8, a: Allocator) !*Node;
```

## Implementation

**W1-2:** Security audit prep + initiation + performance profiling
**W3:** Audit findings analysis + optimization planning
**W4:** Security fixes + performance optimization
**W5:** Monitoring + CI/CD + deployment automation
**W6:** Documentation polish + load testing + final validation

**Tasks:** T1: Audit prep (L) | T2: External audit (XL) | T3: Fix findings (L) | T4: Profiling (M) | T5: Optimize hot paths (L) | T6: Metrics impl (M) | T7: Monitoring dashboards (M) | T8: CI/CD pipeline (M) | T9: Deployment automation (M) | T10: Docs polish (L) | T11: User guides (L) | T12: Load testing (L)

**Path:** T1→T2→T3→T4→T5→T12 (parallel: T6→T7, T8→T9, T10→T11)

## Testing

**Unit:** Metrics recorded correctly, config loads from file

**Integration:**
- Load test: 1000 concurrent channels (<60s)
- Recovery after crash during funding

## Dependencies

**Req:** All previous phases (1-11)
**External:** Security audit firm, monitoring stack (Prometheus, Grafana), CI/CD (GitHub Actions)

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|Critical security findings|M|Critical|Comprehensive audit, [fuzz testing](../docs/fuzz-tests.md), time buffer for fixes|
|Performance regression|M|H|Continuous benchmarking, profiling|
|Monitoring overhead|L|M|Optimize metrics collection, sampling|
|Deploy automation failures|M|M|Extensive testing, rollback procedures|
|Docs incomplete|M|M|Allocate dedicated time, review process|

## Deliverables

**Security:** Audit report + all findings addressed, threat model doc, security best practices guide
**Performance:** Profiling report, 2x improvement in key benchmarks, optimization guide
**Operations:** Monitoring dashboards (Grafana), CI/CD pipeline (GitHub Actions), deployment automation (Docker/K8s), backup/recovery procedures
**Documentation:** Complete API reference, user guides (getting started, tutorials), operational docs (deployment, monitoring, troubleshooting), FAQ + troubleshooting

## Validation Gates

- G1: Audit initiated, profiling complete, metrics spec done
- G2: Audit findings addressed, optimization 50% complete
- G3: Monitoring live, CI/CD working, docs 80% complete
- G4: All complete, load tested, stakeholder sign-off, PRODUCTION READY

## Acceptance

**Criteria:**
- Security: 0 critical, <5 high (all addressed)
- Performance: 2x improvement in key benchmarks
- Monitoring: All critical metrics tracked, alerts configured
- CI/CD: <30min deploy time, automated tests pass
- Docs: 100% API coverage, guides complete, reviewed

**Sign-off:** Security lead, Ops lead, Product lead

**Ready for:** Mainnet deployment, public beta, external users

## Refs

**Phases:** All (1-11)
**External:** OWASP top 10, Cloud Native Security, Prometheus docs, Grafana docs

## Example

```bash
# Production deployment
$ zig build -Drelease-safe
$ ./deploy.sh production

# Monitor metrics
$ curl http://localhost:9090/metrics
channels_created 1523
messages_sent 45210

# Check logs
$ tail -f logs/node.log | grep ERROR

# Backup data
$ ./backup.sh daily
```
