# Phase 2: Ephemeral Infrastructure & Drain Scripts - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the per-session AWS infrastructure layer in `layers/10-infra` and the lifecycle commands/scripts needed to provision and completely destroy it: VPC, EKS 1.34, system node group, AWS-side platform resources, and ordered drain/teardown handling. No application code is part of this phase. The roadmap's two consecutive clean `make up`/`make down` cycles on an empty cluster remain a hard gate before application code. STATE.md still records Phase 1 verification as human-needed; this discussion does not mark that prerequisite or the Phase 2 gate as passed.

</domain>

<decisions>
## Implementation Decisions

### Failed provisioning
- **D-01:** If `make up` fails after creating resources, leave the partial stack intact for inspection. Cleanup is explicit through `make down`; do not automatically destroy useful failure evidence.
- **D-02:** After diagnosing and fixing the cause, the operator reruns `make up` so Terraform can reconcile tracked resources. Do not add automatic provisioning retries.
- **D-03:** `make down` must support cleanup after a provisioning failure at any stage, including an incomplete or unhealthy cluster. On failure, identify the failed stage and safe next step, preserving the originating error output.

### Drain failures and teardown deadline
- **D-04:** Stop `make down` on the first failed drain step and do not begin Terraform destroy. Report the failed step, last observed AWS/Kubernetes state, and elapsed time.
- **D-05:** After remediation, retry teardown by rerunning `make down` from its first step. Drain actions must therefore be safe to repeat. If all drains pass, continue automatically into Terraform destroy; do not add a confirmation prompt between drains and destroy.
- **D-06:** Use one hard 25-minute (1500s) deadline for the teardown operation (raised from 15 minutes on 2026-10-26 after the measured 1162s run); drain polling shares the deadline rather than receiving independent limits that can stack. Do not provide a per-run deadline override. Retry transient AWS/API polling errors a bounded number of times within the same deadline; do not extend the deadline. Record successful teardown timings in `COSTS.md`; failed attempts are not part of the published timing series.

### Last-resort recovery
- **D-07:** Use a scoped nuke tool for last-resort recovery instead of a project-owned bulk-deletion script or a manual-only runbook. Limit it to project-tagged resources; show a target preview but do not require a second confirmation. Invoke it only through a separate manual command, never automatically from `make down`.
- **D-08:** The recovery target boundary must not widen beyond project-tagged resources without a new decision. The teardown sweep deliberately checks untagged controller-created resources too; the scoped nuke may not remove those. It must report uncovered/orphaned resources for explicit handling rather than silently broadening deletion scope. Research/planning must determine whether a suitable tool can honor this boundary.

### the agent's Discretion
- Select the specific scoped nuke tool after verifying its target filtering and preview behavior.
- Choose polling intervals, AWS error classification, command output formatting beyond the required failure summary, and safe no-op handling for resources absent after a partial `make up`, provided the locked stop/timeout behavior and repeatable teardown contract are preserved.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase contract and project constraints
- `.planning/ROADMAP.md` §"Phase 2: Ephemeral Infrastructure & Drain Scripts" — goal, requirements, time bounds, success criteria, parallelism, and the two-cycle hard gate.
- `.planning/REQUIREMENTS.md` — LIFE-01 through LIFE-06, NET-01 through NET-05 and NET-07, EKS-01, EKS-02, EKS-04, EKS-08, and OWN-02.
- `.planning/PROJECT.md` §"Constraints" and §"Key Decisions" — same-day lifecycle, cost/learning floor, Terraform ownership, EKS/network choices, and AWS account boundary.
- `.planning/phases/01-account-l0-bootstrap-teardown-harness/01-CONTEXT.md` — inherited state/backend, account baseline, `verify-teardown.sh` contract, project tagging, and Phase 2 hand-offs (especially D-04, D-07 through D-14, D-31, and D-35).

### Infrastructure and teardown design
- `.planning/research/ARCHITECTURE.md` §"Decision 2 — Terraform layering" — L1 contents, state key, provider boundary, and pinned module versions.
- `.planning/research/ARCHITECTURE.md` §"Decision 3 — Teardown choreography" — ordered drain/destroy sequence, orphan classes, and AWS-confirmed polling requirement.
- `.planning/research/ARCHITECTURE.md` §"Decision 4 — Network architecture" — AZs/CIDRs, subnet tiers, fck-nat ENI routing, gateway endpoints, and default-off interface endpoints.
- `.planning/research/PITFALLS.md` §"Pitfall 2: EKS resources survive `terraform destroy`" and §"Pitfall 12: Destroy dependency deadlocks" — controller-created resources, ordering, finalizers, and failure modes.
- `.planning/research/PITFALLS.md` §"Pitfall 3: You cannot trust Cost Explorer to tell you the teardown worked" — tagged and untagged verification layers; relevant limitation for the project-tag-only recovery boundary.
### Existing interfaces and upstream module contract
- `Makefile` — current lifecycle entry point, doctor/preflight, Terraform/backend conventions; `up` and `down` are not implemented yet.
- `sh/verify-teardown.sh` — existing three-way exit contract (`0` clean, `1` orphans, `2` verifier/credential error), report, and blind-spot inventory.
- `layers/10-infra/README.md` and `layers/10-infra/variables.tf` — current L1 stub and inherited region/project defaults.
- `docs/CONVENTIONS.md` — exact pins, four-key tags, Makefile-only Terraform initialization, and allowlist discipline.
- `tests/static_contracts.bats` and `tests/helpers/load.bash` — existing Bats/static-contract conventions and helpers.
- `https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v21.26.0/docs/UPGRADE-21.0.md` — authoritative EKS v21 breaking changes; read before planning module use. In particular, do not copy v19/v20 `aws-auth` or Karpenter IRSA examples.

**Known source inconsistency:** The roadmap describes the lifecycle as a seven-step sequence/success criterion but enumerates disable Argo auto-sync, three drains, three layer destroys, and verification (eight actions). The architecture document numbers these actions 0 through 7. Resolve the named-step count while preserving the required order; do not drop an action to make the count match.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Makefile` provides root-relative Terraform initialization/backend handling, `doctor`, and the existing teardown/test targets. Extend this as the repository's lifecycle entry point; do not bypass its generated backend contract.
- `sh/verify-teardown.sh` already performs tagged and explicit resource enumeration and writes `.teardown-report.json`; Phase 2 `make down` must preserve its three-way result rather than treating every nonzero as the same condition.
- `tests/` uses Bats, shared helpers in `tests/helpers/load.bash`, static source contracts, and replay fixtures. Add phase-2 lifecycle and drain checks using those conventions.

### Established Patterns
- Every Terraform provider uses exact version pins and the four default tags `Project`, `Layer`, `ManagedBy`, and `Environment`; `Layer` distinguishes immortal bootstrap from ephemeral resources.
- Terraform initialization goes through Make because the S3 backend config is generated at repository root and layer state keys are passed explicitly.
- Shell scripts use Bash and fail-closed error handling; the teardown verifier distinguishes orphan findings from an unknown/error state.
- `layers/10-infra` is currently a stub with the `infra/terraform.tfstate` backend key, `us-east-1` default, and project/environment defaults. There are no Phase 2 drain scripts or `make up`/`make down` targets yet.

### Integration Points
- `make down` consumes `sh/verify-teardown.sh` as its final verification and must preserve its exit meaning.
- The three cluster drain scripts precede Terraform destroys in reverse layer order; their terminal-state checks must use AWS API evidence, not just successful `kubectl delete` calls.
- `layers/10-infra` is the ephemeral L1 state; daily commands must never destroy `layers/00-bootstrap`.

</code_context>

<specifics>
## Specific Ideas

- Treat partial provisioning as an inspectable/recoverable state: no implicit rollback, no automatic retries, and `make down` remains the recovery path at every provisioning stage.
- Keep the nuke command separate from normal teardown. The preview is informational; target scope stays project-tag-only and must not expand to untagged/account-wide deletion.
- A 15-minute hard deadline applies across teardown rather than resetting for each drain; bounded retries consume that same budget.
- Phase 1's verification is still human-needed in STATE.md. The two successful empty-cluster round-trips have not yet been recorded; do not proceed to application code until the hard gate is actually met.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 2 scope.

</deferred>

---

*Phase: 2-Ephemeral Infrastructure & Drain Scripts*
*Context gathered: 2026-10-14*
