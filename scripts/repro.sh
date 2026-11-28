#!/usr/bin/env bash
# Runs the operations of both styles against two gateway compositions each and
# writes the outcome to results/<HC_VERSION>/<style>/<composition>/.
#   styles:        new-style (explicit @lookup/@key), old-style (Node resolvers, inferred lookups)
#   compositions:  catalog-only (control), catalog+reviews,
#                  catalog+reviews+assistance (old-style only)
set -uo pipefail
cd "$(dirname "$0")/.."
export HC_VERSION="${HC_VERSION:-16.7.7}"
LOGS=".logs"
mkdir -p "$LOGS"
pids=()
trap 'kill "${pids[@]}" 2>/dev/null' EXIT

start() { # project-dir port
  (cd "$1" && exec dotnet run --no-build --no-launch-profile --urls "http://localhost:$2") \
    >"$LOGS/$(basename "$1").log" 2>&1 &
  pids+=($!)
}
stop() { kill "$@" 2>/dev/null; wait "$@" 2>/dev/null; }
wait_for() { until curl -s -o /dev/null "http://localhost:$1/graphql?query=%7B__typename%7D"; do sleep 0.5; done; }

run_composition() { # style label subgraph...
  local style="$1" label="$2"; shift 2
  local out="results/$HC_VERSION/$style/$label"
  ./scripts/compose.sh "$style" "$@" >/dev/null || { echo "compose failed"; exit 1; }
  mkdir -p "$out"; rm -f "$out"/*
  cp src/Gateway/gateway.graphqls "$out/gateway.graphqls"

  start src/Gateway 5100; local gateway=$!
  wait_for 5100

  {
    echo "HotChocolate $HC_VERSION, $style, composition: $label"
    printf '%-26s %-5s %s\n' "operation" "http" "result"
    for file in "operations/$style"/*.graphql; do
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

  stop "$gateway"
}

for style in new-style old-style; do
  ./scripts/compose.sh "$style" >/dev/null || { echo "build/compose failed ($style)"; exit 1; }
  start "src/$style/Catalog" 5101; catalog=$!
  start "src/$style/Reviews" 5102; reviews=$!
  wait_for 5101; wait_for 5102

  run_composition "$style" catalog-only Catalog
  run_composition "$style" catalog+reviews Catalog Reviews
  if [ "$style" = old-style ]; then
    start "src/$style/Assistance" 5103; assistance=$!
    wait_for 5103
    run_composition "$style" catalog+reviews+assistance Catalog Reviews Assistance
    stop "$assistance"
  fi

  stop "$catalog" "$reviews"
done

./scripts/report.sh
