#!/usr/bin/env bash
set -euo pipefail

bucket="${1:?usage: empty-versioned-bucket.sh <bucket>}"

while :; do
	listing="$(aws s3api list-object-versions \
		--bucket "$bucket" \
		--max-keys 1000 \
		--output json)"
	delete_payload="$(jq -c '{Objects: ((.Versions // []) + (.DeleteMarkers // []) | map({Key, VersionId})), Quiet: true}' <<< "$listing")"
	count="$(jq '.Objects | length' <<< "$delete_payload")"
	if [[ "$count" -eq 0 ]]; then
		break
	fi

	delete_result="$(aws s3api delete-objects \
		--bucket "$bucket" \
		--output json \
		--delete "$delete_payload")"
	if jq -e '(.Errors // []) | length > 0' <<< "$delete_result" >/dev/null; then
		printf 'ERROR: S3 returned per-object deletion errors:\n' >&2
		jq -c '.Errors' <<< "$delete_result" >&2
		exit 1
	fi
	printf 'deleted %s versions/markers\n' "$count"
done

printf 'bucket %s is empty\n' "$bucket"