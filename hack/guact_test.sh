#!/usr/bin/env bash
set -euo pipefail

# ---- Change only name ----
NAME="${1:-cluster-api-provider-metal3}"
QUIET="${2:-false}"
CDX_DIR="./cdx-output"
# true (default) standalone: this script manages its own port-forwards.
MANAGE_PORT_FORWARD="${MANAGE_PORT_FORWARD:-true}"
# --------------------------
ORG="metal3-io"

say() { [ "$QUIET" != true ] && echo "$@" || true; }

run() {
    if [ "$QUIET" = true ]; then "$@" >/dev/null; else "$@"; fi
}

wait_for_port() {
    local port="$1" i
    for i in $(seq 1 150); do          # 30s cap
        nc -z localhost "$port" 2>/dev/null && return 0
        sleep 0.2
    done
    echo "ERROR: nothing listening on localhost:${port} after 30s" >&2
    return 1
}

mkdir -p "$CDX_DIR" repos

if [ "$MANAGE_PORT_FORWARD" = true ]; then
    say "Starting port forwards..."
    kubectl port-forward -n guac svc/graphql-server 8080:8080 >/tmp/graphql-portforward.log 2>&1 &
    GRAPHQL_PID=$!
    kubectl port-forward -n guac svc/visualizer 3000:3000 >/tmp/visualizer-portforward.log 2>&1 &
    VISUALIZER_PID=$!
    cleanup() { kill "$GRAPHQL_PID" "$VISUALIZER_PID" 2>/dev/null || true; }
    trap cleanup EXIT
    wait_for_port 8080
    wait_for_port 3000
    say "Port forwards up."
fi

# ---------------------------------------------------------------------------
# Checkout. --tags is required: git describe below needs the tags present
# locally to have anything to describe against.
# ---------------------------------------------------------------------------
BRANCH="main"
REPO_DIR="./repos/${NAME}"

if [ ! -d "${REPO_DIR}/.git" ]; then
    run git clone "https://github.com/${ORG}/${NAME}.git" "$REPO_DIR"
fi
run git -C "$REPO_DIR" fetch --tags --force origin "$BRANCH"
run git -C "$REPO_DIR" checkout "$BRANCH"
run git -C "$REPO_DIR" reset --hard "origin/${BRANCH}"
say "Using branch: $BRANCH"

# ---------------------------------------------------------------------------
# Version = nearest tag reachable from HEAD, tag only.
#   --abbrev=0 : strip the "-<commits>-g<sha>" suffix, so main (ahead of the
#                last tag) still reports the clean tag, e.g. v0.13.1
#   --tags     : match lightweight tags too, not just annotated
#   --match    : only v-prefixed version tags, ignore any stray tags
#   --always   : last-resort short-SHA if the repo has no v* tag at all
#                (won't fire for the metal3 Go repos, which are always tagged)
# ---------------------------------------------------------------------------
DESCRIBE=$(git -C "$REPO_DIR" describe --tags --abbrev=0 --always --match 'v[0-9]*')
VERSION="${DESCRIBE#v}"
COMMIT_SHA=$(git -C "$REPO_DIR" rev-parse --short HEAD)
OUT="${CDX_DIR}/${NAME}-${VERSION}-${BRANCH}-${COMMIT_SHA}.cdx.json"
say "Describe: $DESCRIBE  ->  version: $VERSION"

# ---------------------------------------------------------------------------
# Go module identity. Read the module path out of go.mod (usually but not
# always github.com/${ORG}/${NAME}).
# ---------------------------------------------------------------------------
if [ ! -f "${REPO_DIR}/go.mod" ]; then
    echo "ERROR: ${NAME} has no go.mod -- this script is Go-only." >&2
    exit 1
fi
MODULE=$(awk '/^module /{print $2; exit}' "${REPO_DIR}/go.mod")
[ -n "$MODULE" ] || MODULE="github.com/${ORG}/${NAME}"

PURL_NOVER="pkg:golang/${MODULE}"
PKG_URI="${PURL_NOVER}@${VERSION}"
say "Module: $MODULE"
say "Root purl: $PKG_URI"

# ---------------------------------------------------------------------------
# SBOM
# ---------------------------------------------------------------------------
say "Generating SBOM..."
if [ "$QUIET" = true ]; then
    syft "dir:${REPO_DIR}" --source-name "$NAME" --source-version "$VERSION" \
        -o cyclonedx-json@1.6="$OUT" >/dev/null 2>/dev/null
else
    syft "dir:${REPO_DIR}" --source-name "$NAME" --source-version "$VERSION" \
        -o cyclonedx-json@1.6="$OUT"
fi

# ---------------------------------------------------------------------------
# Patch the root component + dependency graph.
#   - Collapse syft's version-less "main module" component onto PKG_URI
#     (matched by exact prefix OR prefix+"@" with an empty/(devel) version --
#     submodules like .../apis@v0.0.0 are NOT matched, so they keep their own
#     identity).
#   - Mirror the root into .components so it's first-class + queryable.
#   - Give the root a dependencies entry pointing at every other component.
#     Syft emits a dependencies array, and GUAC only auto-wires "root depends
#     on everything" when that array is ABSENT -- without this the root is an
#     orphan node with nothing for `guacone query vuln` to traverse.
# ---------------------------------------------------------------------------
say "Patching root component + dependency graph..."
jq --arg purl "$PKG_URI" --arg pfx "$PURL_NOVER" \
   --arg name "$NAME" --arg version "$VERSION" '
  .metadata.component = ((.metadata.component // {}) + {
      "type": "application",
      "name": (.metadata.component.name // $name),
      "version": $version,
      "purl": $purl
  })
  | .metadata.component."bom-ref" = (.metadata.component."bom-ref" // ("root-" + $name))
  | .metadata.component."bom-ref" as $ref
  | .components = ((.components // []) | map(
      if ((.purl // "") == $pfx)
         or (((.purl // "") | startswith($pfx + "@"))
             and ((.version // "") | (. == "" or . == "(devel)")))
      then (.version = $version | .purl = $purl)
      else . end))
  | (if ([.components[] | select(."bom-ref" == $ref)] | length) == 0 then
       .components += [{ "bom-ref": $ref, "type": "application",
                         "name": $name, "version": $version, "purl": $purl }]
     else
       (.components[] | select(."bom-ref" == $ref)) |= (.version = $version | .purl = $purl)
     end)
  | ([.components[]? | ."bom-ref" | select(. != $ref)] | unique) as $kids
  | .dependencies = (((.dependencies // []) | map(select(.ref != $ref)))
                     + [{ "ref": $ref, "dependsOn": $kids }])
  ' "$OUT" > "${OUT}.tmp"
mv "${OUT}.tmp" "$OUT"

PKG_COUNT=$(jq '[.components[]? | select(.purl != null)] | length' "$OUT")

if [ "$QUIET" != true ]; then
    echo
    echo "Root component:"
    jq -r '"\(.metadata.component.name)  \(.metadata.component.version)  \(.metadata.component.purl)"' "$OUT"
    echo "Components with a purl: ${PKG_COUNT}"
    echo "SBOM written to: $OUT"
    echo
fi

# ---------------------------------------------------------------------------
# Ingest. Drop --add-license-on-ingest if the clearlydefined lookups stall
# you -- it only feeds the license graph, not vuln matching.
# ---------------------------------------------------------------------------
if [ "$QUIET" = true ]; then
    guacone collect --gql-addr http://localhost:8080/query \
        --add-vuln-on-ingest --add-eol-on-ingest --add-license-on-ingest \
        files "$OUT" >/dev/null 2>&1
else
    guacone collect --gql-addr http://localhost:8080/query \
        --add-vuln-on-ingest --add-eol-on-ingest --add-license-on-ingest \
        files "$OUT"
fi

# ---------------------------------------------------------------------------
# Query. Re-read the purl from the file rather than trusting PKG_URI, so a
# failed patch skips the query instead of crashing the batch.
# ---------------------------------------------------------------------------
INGESTED_PURL=$(jq -r '.metadata.component.purl // empty' "$OUT")

echo "${NAME} @ ${VERSION} (golang)"

if [ -z "$INGESTED_PURL" ]; then
    echo "No purl found in the generated SBOM for ${NAME} -- skipping vuln query."
else
    echo "Package URI: $INGESTED_PURL"
    if [ "$QUIET" = true ]; then
        if ! QUERY_OUT=$(guacone query vuln uri "$INGESTED_PURL" 2>/dev/null); then
            echo "guacone query failed for ${INGESTED_PURL} -- see logs above."
        else
            echo "$QUERY_OUT"
        fi
    else
        guacone query vuln uri "$INGESTED_PURL" \
            || echo "guacone query failed for ${INGESTED_PURL} -- see logs above."
    fi
fi
echo