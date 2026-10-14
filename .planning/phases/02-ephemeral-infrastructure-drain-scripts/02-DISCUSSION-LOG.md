# Phase 2: Ephemeral Infrastructure & Drain Scripts - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md; this log preserves the alternatives considered.

**Date:** 2026-10-14
**Phase:** 2-Ephemeral Infrastructure & Drain Scripts
**Areas discussed:** Last-resort teardown recovery, Drain failure behavior, Failed make up behavior, Timeout and retry policy

---

## Last-resort teardown recovery

| Question | Option | Description | Selected |
|----------|--------|-------------|----------|
| Last resort after ordered teardown fails | Project-owned recovery script | Explicit AWS CLI cleanup for known resource classes. | |
| | Scoped nuke tool | aws-nuke/cloud-nuke with narrow account/resource targeting. | **SELECTED** |
| | | Manual runbook only; no bulk deletion automation. | |
| Target boundary | Project-tagged resources only | Target matching project tags and preserve unrelated account resources. | **SELECTED** |
| | Whole member account | Delete everything not explicitly excluded. | |
| | Operator-selected resources | Review resource IDs before deletion. | |
| Confirmation before deletion | Preview then type account ID | Preview targets, then require account-ID confirmation. | |
| | Confirm every resource | Approve each resource individually. | |
| | Preview only | Show targets without a second confirmation. | **SELECTED** |
| Trigger | Separate manual command | Keep normal make down fail-closed; invoke recovery deliberately. | **SELECTED** |
| | Offer a prompt in make down | Ask whether to run recovery after a failure. | |
| | Run automatically | Invoke the nuke after a failed drain or destroy. | |

**User's choices:** Scoped nuke tool; project-tagged resources only; preview only; separate manual command.
**Notes:** The project-tag-only boundary may not cover untagged controller-created resources. Do not silently widen the deletion scope.

---

## Drain failure behavior

| Question | Option | Description | Selected |
|----------|--------|-------------|----------|
| Response to a failed drain | Stop immediately | Preserve the cluster for diagnosis; do not start Terraform destroy. | **SELECTED** |
| | Continue remaining drains | Attempt remaining drains, report failures, skip destroy. | |
| | Continue through destroy | Continue despite failure and rely on final verification. | |
| Failure detail | Step summary and AWS state | Show failed step, last observed state, and elapsed time. | **SELECTED** |
| | Verbose command logs | Print full kubectl/AWS output inline. | |
| | Structured report file | Save per-step results in a machine-readable file. | |
| Retry after remediation | Rerun make down from step 1 | Make completed drain actions safe to repeat. | **SELECTED** |
| | Resume from failed step | Track progress and resume at the failed stage. | |
| | Run individual drain scripts | Let the operator select a script. | |
| After all drains pass | Continue automatically | Preserve the one-command lifecycle; failures still stop before destroy. | **SELECTED** |
| | Prompt before destroy | Add a human checkpoint before Terraform. | |
| | Require an explicit flag | Do not destroy unless a confirmation flag is supplied. | |

**User's choices:** Stop at the first drain failure; show step/state/time; rerun from step 1; continue automatically to Terraform destroy after all drains pass.

---

## Failed make up behavior

| Question | Option | Description | Selected |
|----------|--------|-------------|----------|
| Partial provisioning failure | Leave resources for inspection | Preserve state/evidence; operator can diagnose and run make down explicitly. | **SELECTED** |
| | Automatically run make down | Immediately try to remove created resources. | |
| | Ask at failure time | Let the operator choose cleanup or inspection. | |
| Retry after diagnosis | Rerun make up | Let Terraform reconcile tracked resources. | **SELECTED** |
| | Require make down first | Require an empty account before retry. | |
| | Manual state recovery | Require explicit inspection/state repair first. | |
| Automatic provisioning retry | No automatic retry | Surface the first failure and let the operator fix it. | **SELECTED** |
| | One bounded retry | Retry once after a short delay. | |
| | Retry until timeout | Continue retrying within the overall up budget. | |
| Teardown after partial failure | Support every stage | make down must work even with an incomplete or unhealthy cluster. | **SELECTED** |
| | Only after EKS is healthy | Earlier failures need manual Terraform recovery. | |
| | Best effort, then manual | Try normal teardown, then accept manual cleanup. | |
| Failure output | Failed stage and safe next step | Name the stage/action, preserve its error output, and point to recovery. | **SELECTED** |
| | Full logs inline | Print all provider output directly. | |
| | Summary plus log file | Keep terminal output short and save a durable full log. | |

**User's choices:** Leave partial resources for inspection; rerun make up after fixing the cause; no automatic retries; make down supports every stage; report the failed stage and safe next step.

---

## Timeout and retry policy

| Question | Option | Description | Selected |
|----------|--------|-------------|----------|
| 15-minute make down target | One total teardown deadline | All drain polling shares one end-to-end budget. | **SELECTED** |
| | A deadline per drain step | Each drain receives its own limit; total can exceed 15 minutes. | |
| | Per-step limits within total cap | Individual limits plus an overall 15-minute deadline. | |
| Extend drain deadline | Fixed 15-minute cap | Preserve the roadmap's hard gate. | **SELECTED** |
| | Explicit per-run override | Allow a clearly logged longer deadline for unusual delays. | |
| | Wait without a cap | Prioritize completion over predictable duration. | |
| Temporary AWS/API poll error | Bounded retry within deadline | Retry transient errors without extending the deadline. | **SELECTED** |
| | Fail on first API error | Stop at the first polling error. | |
| | Retry until the deadline | Keep retrying every error until time expires. | |
| Timings in COSTS.md | Successful runs only | Keep published measurements comparable to the success criterion. | **SELECTED** |
| | Successes and failures | Record failures separately for regression visibility. | |
| | All attempts, one metric | Include all attempts in the same timing series. | |

**User's choices:** One hard shared 15-minute deadline; no override; bounded transient-error retries within that deadline; record successful teardown timings only.

---

## the agent's Discretion

No areas were delegated to the agent during discussion. Implementation discretion is recorded in `02-CONTEXT.md`.

## Deferred Ideas

None.
