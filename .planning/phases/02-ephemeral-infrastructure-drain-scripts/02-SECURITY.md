---
phase: "02"
slug: "ephemeral-infrastructure-drain-scripts"
status: verified
threats_open: 0
asvs_level: 1
created: "2026-10-15"
---

# Phase 02 - Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Operator CLI to Make/Bash | Operator intent selects ordered, destructive lifecycle actions. | Commands, layer identifiers, account and region context |
| Make/Bash to AWS/Terraform | Credentials and remote state select the target account and resources. | Credentials, state keys, API requests |
| Operator to EKS API | Trusted CIDRs and access entries govern Kubernetes API reachability. | Operator network identity, kubeconfig requests |
| Drain scripts to AWS/Kubernetes | Untrusted API and CLI responses determine whether resources are absent. | JSON responses, resource IDs, deletion requests |
| Recovery wrapper to Cloud Nuke | A separate manual tool can discover or delete resources. | Account, region, tag filter, resource-type scope |
| Phase gate to application work | Acceptance evidence controls progression to application code. | Test results, live infrastructure evidence, timing records |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-02-01 | E | Make destroy-layer allowlist | high | mitigate | `_layer-state` and `_destroy-layer` accept only 10-infra, 20-data, and 30-gitops; lifecycle tests cover the boundary. | closed |
| T-02-02 | T | Drain result and stage ordering | high | mitigate | `down.sh` fails closed for unknown state or drain failure; lifecycle tests assert no destroy follows an unresolved drain. | closed |
| T-02-03 | D | Concurrent or wedged teardown | medium | mitigate | Atomic `.down.lock` plus fixed 900-second GNU timeout in `Makefile`; signal cleanup is tested. | closed |
| T-02-04 | R | Teardown verdict | medium | mitigate | Verifier results 0, 1, and 2 remain distinct through Make; Bats covers clean, orphan, and error outcomes. | closed |
| T-02-05 | E | EKS API endpoint/access entry | high | mitigate | `up.sh` validates trusted IPv4 CIDRs and Terraform rejects `0.0.0.0/0`; operator access is explicit. | closed |
| T-02-06 | T | Module/provider/add-on resolution | high | mitigate | Exact Terraform/provider/module/add-on pins and lockfiles are checked against `VERSIONS.md` by static contracts and `make validate`. | closed |
| T-02-07 | I | AWS tags and operator endpoint | medium | mitigate | Provider default tags are explicit; account ID and live credentials are gitignored, and endpoint CIDRs are restricted. | closed |
| T-02-08 | D | Failed provisioning | medium | mitigate | `up.sh` performs one apply, preserves partial state and diagnostics, and does not retry or destroy automatically. | closed |
| T-02-09 | E | Karpenter IAM role and PassRole | high | mitigate | The pinned EKS Karpenter module owns AWS resources and Pod Identity; static contracts verify the module boundary and role configuration. | closed |
| T-02-10 | T | Interruption queue and EventBridge wiring | medium | mitigate | The pinned module owns the queue/event path; Terraform validation and static source contracts pass. | closed |
| T-02-11 | T | Terraform/Kubernetes ownership boundary | high | mitigate | Kubernetes and Helm providers are statically restricted to 30-gitops; L1 remains AWS-only. | closed |
| T-02-12 | D | Interruption event handling | low | accept | Runtime interruption handling belongs to the later GitOps phase; this phase only creates the AWS delivery path. | closed (accepted; below high threshold) |
| T-02-13 | T | AWS terminal-state predicates | high | mitigate | Drain scripts validate raw JSON and require explicit terminal absence; transition and malformed-response fixtures pass. | closed |
| T-02-14 | E | kubectl operator access | high | mitigate | `doctor.sh` requires the pinned compatible kubectl, expected account/region, and trusted endpoint preflight. | closed |
| T-02-15 | D | Poll/retry loops | medium | mitigate | AWS attempts and polling are bounded; the Make-level 900-second timeout bounds the full teardown process. | closed |
| T-02-16 | R | Failed partial-cluster cleanup | medium | mitigate | Drain failures name the stage, preserve observed state and errors, and provide retry-from-step-one guidance. | closed |
| T-02-17 | T | Fixture response selection | high | mitigate | Scenario fixtures are operation-keyed and call-counted; harness self-tests verify precedence and fail on missing responses. | closed |
| T-02-18 | D | Retry behavior | medium | mitigate | Retry counts are fixed and transient errors are classified; lifecycle tests cover retry limits. | closed |
| T-02-19 | R | Drain state assertions | medium | mitigate | Tests assert AWS arguments, transitions, diagnostics, and absence of Terraform destroy after failure. | closed |
| T-02-20 | E | False clean state | high | mitigate | Unknown, malformed, and error responses fail closed; fixture tests cover these negative cases. | closed |
| T-02-21 | D | Deadline and polling loops | high | mitigate | `Makefile` wraps the complete `down.sh` process in fixed GNU `timeout` 900s with TERM/KILL escalation; bounded retries and signal diagnostics remain in place. | closed |
| T-02-22 | E | Terraform destroy layer selection | high | mitigate | Make-owned fixed L3/L2/L1 helpers reject all other layers; static and behavioral tests exclude L0. | closed |
| T-02-23 | T | Drain-success progression | high | mitigate | Any drain error or unknown status stops teardown before destroy; lifecycle tests cover all drain boundaries. | closed |
| T-02-24 | R | Timing ledger | medium | mitigate | Successful timing output is emitted only after verifier exit 0; the ledger contract excludes failed runs. | closed |
| T-02-25 | T | Recovery resource filters | high | mitigate | Positive Project tag config excludes VPC; no resource type is enabled for deletion until per-type proof passes. | closed |
| T-02-26 | E | Cloud Nuke binary/config | high | mitigate | Expected account/region and pinned version/checksum checks precede any future preview or deletion; deletion is currently disabled. | closed |
| T-02-27 | D | Untagged residual resources | medium | mitigate | Recovery remains report-only and verifier output identifies uncovered resources without widening scope. | closed |
| T-02-28 | T | Preview-to-execution target drift | high | mitigate | Scope construction is shared and contract tests assert identical preview/execution arguments; invocation is currently disabled. | closed |
| T-02-29 | E | Live account/region boundary | high | mitigate | `doctor.sh` checks account and region before lifecycle operations; `nuke-project.sh` independently verifies both. | closed |
| T-02-30 | T | Recovery scope and untagged resources | high | mitigate | Deletable resource types remain empty because Project-only tagged/untagged and cascade proof is incomplete. | closed |
| T-02-31 | T | Application-code phase gate | high | mitigate | Phase 2 live acceptance is a blocking human checkpoint; application source remains absent until two clean rounds pass. | closed |
| T-02-32 | R | Lifecycle timing evidence | medium | mitigate | Timing data is recorded only after complete successful runs and verifier exit 0; failed runs are excluded. | closed |

*Status: open / closed / open - below high threshold (non-blocking)*
*Severity: critical > high > medium > low - only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) / accept (documented risk) / transfer (third-party)*

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-02-01 | T-02-12 | Runtime interruption behavior is implemented and exercised in the later GitOps phase; Phase 2 provides only the AWS delivery path. | Phase 02 plan disposition | 2026-10-15 |

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-15 | 32 | 32 | 0 | Orchestrator source review; security auditor subagent could not access workspace |

## Audit Notes

- The standard security auditor returned `ESCALATE` because its isolated session could not read the workspace. The orchestrator cross-checked the authored registers against current Make, Terraform, lifecycle, recovery, and test sources.
- Code review warning WR-01 remains: `SECONDS`-based drain diagnostics may be offset across Bash subprocesses. The fixed Make-level GNU timeout still bounds the complete teardown to 900 seconds; the warning does not leave the hard deadline unenforced.
- The separate Phase 2 live-acceptance checkpoint remains blocked by Phase 1 `human_needed`; this security sign-off does not authorize live AWS operations or mark the phase complete.

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-15 (security controls only; phase live acceptance remains blocked)