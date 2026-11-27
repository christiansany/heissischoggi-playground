#!/usr/bin/env bash
# Builds everything, exports the subgraph schemas and composes src/Gateway/gateway.far.
# Usage: scripts/compose.sh [Subgraph...]   (default: Catalog Reviews)
set -euo pipefail
cd "$(dirname "$0")/.."
HC_VERSION="${HC_VERSION:-16.7.7}"
SUBGRAPHS=("$@")
[ ${#SUBGRAPHS[@]} -eq 0 ] && SUBGRAPHS=(Catalog Reviews)

dotnet tool restore >/dev/null
for p in Catalog Reviews Gateway; do
  dotnet build "src/$p" -p:HotChocolateVersion="$HC_VERSION" -v q --nologo >/dev/null
done
for p in Catalog Reviews; do
  (cd "src/$p" && dotnet run --no-build -- schema export >/dev/null)
done

# `schema export` always writes port 5000; point each subgraph at its real port.
sed -i.bak 's#localhost:5000#localhost:5101#' src/Catalog/schema-settings.json
sed -i.bak 's#localhost:5000#localhost:5102#' src/Reviews/schema-settings.json
rm -f src/*/schema-settings.json.bak

args=()
for p in "${SUBGRAPHS[@]}"; do args+=(-f "src/$p/schema.graphqls"); done
rm -f src/Gateway/gateway.far
dotnet nitro fusion compose "${args[@]}" -a src/Gateway/gateway.far

# Keep a readable copy of the composed execution schema next to the archive.
unzip -p src/Gateway/gateway.far 'gateway/*/gateway.graphqls' > src/Gateway/gateway.graphqls
