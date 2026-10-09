# Phase 1: User Setup Required

**Generated:** 2026-10-09
**Phase:** 01-account-l0-bootstrap-teardown-harness
**Status:** Complete

## Environment Variables

| Status | Variable | Source | Add to |
|--------|----------|--------|--------|
| [x] | `github_owner_id` | GitHub repository metadata | `layers/00-bootstrap/terraform.tfvars` (gitignored) |
| [x] | `github_repo_id` | GitHub repository metadata | `layers/00-bootstrap/terraform.tfvars` (gitignored) |

The repository was created on 2026-09-23. Its owner ID is `82219047` and repository ID is
`1383184443`; both values are configured locally. No credentials or AWS account IDs are stored here.

## Dashboard Configuration

- [x] **Determine the GitHub OIDC subject format**
  - Repository: `MinhChuDoMagic/microservices-demo`
  - Evidence: repository creation date is after the immutable-subject cutover on 2026-07-15.
  - Result: use owner-ID and repository-ID qualified subjects.
  - The repository is public, so the unredacted claim-debugging action was not run.

## Verification

The live AWS trust policies were checked against the ID-qualified pull-request and main-branch
subjects. The Terraform configuration validates, and the trust-policy Bats suite passes without
skips.

---

**Once confirmed:** status is `Complete`; no further account setup is required for this checkpoint.