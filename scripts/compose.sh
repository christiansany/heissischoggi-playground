#!/usr/bin/env bash
# Builds everything, exports the subgraph schemas of one style and composes
# src/Gateway/gateway.far.
# Usage: scripts/compose.sh <new-style|old-style> [Subgraph...]   (default: Catalog Reviews)
# old-style also has the subgraph Assistance.
set -euo pipefail
cd "$(dirname "$0")/.."
HC_VERSION="${HC_VERSION:-16.7.7}"
STYLE="${1:?usage: compose.sh <new-style|old-style> [Subgraph...]}"; shift
SUBGRAPHS=("$@")
[ ${#SUBGRAPHS[@]} -eq 0 ] && SUBGRAPHS=(Catalog Reviews)

dotnet tool restore >/dev/null
for dir in "src/$STYLE"/*/ src/Gateway; do
  dotnet build "$dir" -p:HotChocolateVersion="$HC_VERSION" -v q --nologo >/dev/null
done

port() { case "$1" in Catalog) echo 5101 ;; Reviews) echo 5102 ;; Assistance) echo 5103 ;; esac; }
compose_args=()
for dir in "src/$STYLE"/*/; do
  dir="${dir%/}"; p="$(basename "$dir")"
  (cd "$dir" && dotnet run --no-build -- schema export >/dev/null)

  # `schema export` always writes port 5000; point the subgraph at its real port.
  filter='.transports.http.url = "http://localhost:\($port)/graphql"'
  # old-style: mark the source schema as Fusion v1 style, like schemas that were
  # written without composition directives. The composition then infers
  # @lookup (from `node` and `<type>By<Key>` fields), @key and @shareable.
  [ "$STYLE" = old-style ] && filter="$filter | .version = \"1.0.0\""
  jq --arg port "$(port "$p")" "$filter" "$dir/schema-settings.json" > "$dir/schema-settings.json.tmp"
  mv "$dir/schema-settings.json.tmp" "$dir/schema-settings.json"
done
for p in "${SUBGRAPHS[@]}"; do compose_args+=(-f "src/$STYLE/$p/schema.graphqls"); done

# old-style: the gateway exposes `Query.node`, like the subgraphs do.
[ "$STYLE" = old-style ] && compose_args+=(--enable-global-object-identification)

rm -f src/Gateway/gateway.far
dotnet nitro fusion compose "${compose_args[@]}" -a src/Gateway/gateway.far

# Keep a readable copy of the composed execution schema next to the archive.
unzip -p src/Gateway/gateway.far 'gateway/*/gateway.graphqls' > src/Gateway/gateway.graphqls
