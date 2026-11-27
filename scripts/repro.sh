#!/usr/bin/env bash
# Runs every operation in operations/ against two gateway compositions and
# writes the outcome to results/<HC_VERSION>/<composition>/:
#   catalog+reviews  -> the bug
#   catalog-only     -> control: same operations, Reviews subgraph not composed
set -uo pipefail
cd "$(dirname "$0")/.."
export HC_VERSION="${HC_VERSION:-16.7.7}"
LOGS=".logs"
mkdir -p "$LOGS"
pids=()
trap 'kill "${pids[@]}" 2>/dev/null' EXIT

start() { # name port
  (cd "src/$1" && exec dotnet run --no-build --no-launch-profile --urls "http://localhost:$2") \
    >"$LOGS/$1.log" 2>&1 &
  pids+=($!)
}
wait_for() { until curl -s -o /dev/null "http://localhost:$1/graphql?query=%7B__typename%7D"; do sleep 0.5; done; }

run_composition() { # label subgraph...
  local label="$1"; shift
  local out="results/$HC_VERSION/$label"
  ./scripts/compose.sh "$@" >/dev/null || { echo "compose failed"; exit 1; }
  mkdir -p "$out"; rm -f "$out"/*

  start Gateway 5100; local gateway=$!
  wait_for 5100

  {
    echo "HotChocolate $HC_VERSION, composition: $label"
    printf '%-26s %-5s %s\n' "operation" "http" "result"
    for file in operations/*.graphql; do
      name="$(basename "$file" .graphql)"
      status="$(jq -Rs '{query: .}' "$file" | curl -s -o "$out/$name.response.txt" -w '%{http_code}' \
        http://localhost:5100/graphql \
        -H 'Content-Type: application/json' \
        -H 'Accept: multipart/mixed; incrementalSpec=v0.2, application/json' \
        -H 'Fusion-Operation-Plan: 1' \
        --data-binary @-)"
      result="$(grep '^{' "$out/$name.response.txt" | jq -rs \
        'if any(.[]; .errors) then "ERROR: " + ([.[] | .errors // [] | .[] | (.extensions.exception.message // .message)] | first)
         elif length > 1 then "ok, \(length) parts (deferred)" else "ok, single response" end')"
      printf '%-26s %-5s %s\n' "$name" "$status" "$result"

      # The plan is in `extensions.fusion.operationPlan` of the first JSON payload.
      grep -m1 '^{' "$out/$name.response.txt" \
        | jq -e '.extensions.fusion.operationPlan' >"$out/$name.plan.json" 2>/dev/null \
        || rm -f "$out/$name.plan.json"
    done
  } | tee "$out/summary.txt"
  echo

  kill "$gateway" 2>/dev/null; wait "$gateway" 2>/dev/null
}

./scripts/compose.sh >/dev/null || { echo "build/compose failed"; exit 1; }
start Catalog 5101
start Reviews 5102
wait_for 5101; wait_for 5102

run_composition catalog-only Catalog
run_composition catalog+reviews Catalog Reviews   # last, so gateway.far is the failing one
