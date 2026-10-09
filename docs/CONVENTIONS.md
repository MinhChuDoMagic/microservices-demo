# Infrastructure Conventions

These rules preserve the daily rebuild-and-teardown loop. Apply them to every new Terraform layer
and resource.

## Explicit CloudWatch Log-Group Retention

Declare each CloudWatch log group explicitly in Terraform and set `retention_in_days = 1`. Do not
rely on an emitting service to create it implicitly: implicit groups default to never expire, can
survive the resource that created them, and can accumulate cost across teardown cycles.

There are zero instances of this convention in Phase 1 because none of the bootstrap layer's
resources emits CloudWatch logs natively. The convention is carried by a static guard rather than a
placeholder resource.

## Four-Key Tags

Every provider's `default_tags` must include `Project`, `Layer`, `ManagedBy`, and `Environment`.
`Layer` is load-bearing: the teardown verifier uses it to distinguish immortal bootstrap resources
from ephemeral resources. Do not repeat a provider-level default tag in a resource-level `tags`
block; duplicate definitions can conflict and obscure the shared tagging contract.

## Exact Version Pins

Pin Terraform, providers, and modules to exact versions. Mirror every pin into `VERSIONS.md` so a
future rebuild does not silently resolve to newer behavior.

## Terraform Initialization Through Make

Run Terraform initialization only through the Makefile. The S3 backend blocks are intentionally
partial and depend on generated `backend.hcl` values; a hand-run `terraform init` can initialize the
wrong backend and put state in the wrong place.

## Teardown Allowlist

Each allowlist entry is a reviewed edit with an inline reason. Never widen the allowlist to make an
orphan disappear from the report; investigate and remove the resource or document why that specific
resource must survive teardown.