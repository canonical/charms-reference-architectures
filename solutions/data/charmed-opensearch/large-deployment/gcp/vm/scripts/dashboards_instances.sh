#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Return each requested machine's instance name and zone.
set -euo pipefail

read -r model machines < <(jq -r '"\(.model) \(.machines)"')
count=$(tr ',' '\n' <<<"$machines" | wc -l)
timeout=900
deadline=$((SECONDS + timeout))

while [ "$SECONDS" -lt "$deadline" ]; do
  instances=$(juju status --model "$model" --format=json | jq -c --arg ids "$machines" '
    [.machines[($ids | split(","))[]]
     | select((."instance-id" // "pending") != "pending")
     | {key: ."instance-id", value: ((.hardware // "") | capture("availability-zone=(?<zone>[^ ]+)").zone)}]
    | from_entries')
  if [ "$(jq length <<<"$instances")" -eq "$count" ]; then
    echo "$instances"
    exit 0
  fi
  sleep 10
done

echo "OpenSearch Dashboards machines $machines have no instance and zone after $timeout seconds." >&2
exit 1
