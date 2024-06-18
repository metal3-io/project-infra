#!/bin/bash

HEADER="application/vnd.scanner.adapter.vuln.report.harbor+json; version=1.0"
BASE_URL="registry.nordix.org"
PROJECT="projects/metal3"
HARBOR_API="https://${BASE_URL}/api/v2.0/${PROJECT}/repositories"

# DRY_RUN argument is present in all of the  functions that call the Harbor API.
# The default value for DRY_RUN is true thus unless it is manually set to false
# the function won't call the API instead it will print out the intended action.

# RESULT_NUM is a common argument and it specifies the maximum number of top level
# JSON objects in the JSON array that is returned after a API call.

# NOTE: Tags are not unique identifiers but digests are!

# NOTE: digests in the cleanup exclusion list file have to be in the following format
# sha256:<digest_number>

# Cleans a OCI repository that is specified as the first argument.
# It is required to supply a file that contains a clear text list of the
# digests of the artifacts that are excluded from the cleanup.
# There is also an argument named RETENTION that specifies the number of the
# latest artifacts that won't be deleted.
harbor_clean_OCI_repository(){
  local IMAGE="${1:?}"
  local PINFILE="${2:?}"
  local RETENTION_LIMIT="${3:-5}"
  local DRY_RUN="${4:-true}"
  local RESULT_NUM="${5:-50}"

  local DIGEST_DATA=""
  DIGEST_DATA="$(harbor_list_OCI_repository_digests "$IMAGE" "false" "$RESULT_NUM")"

  mapfile -t < <(echo "$DIGEST_DATA" |\
    diff --suppress-common-lines - "$PINFILE" |\
    sed -ne 's/< //p')

  for ((i = 0; i < ${#MAPFILE[@]}; ++i)); do
      local position=$(( i + 1 ))
      if (( RETENTION_LIMIT < position )); then
          harbor_delete_OCI_artifact "$IMAGE" "" "${MAPFILE[$i]}" "$DRY_RUN"
      fi
  done
}

# Deletes a single OCI artifact based on the specified digest.
harbor_delete_OCI_artifact(){
    local IMAGE="${1:?}"
    local TAG="${2:-""}"
    local DIGEST="${3:-""}"
    local DRY_RUN="${4:-true}"
    local AUTH="${DOCKER_USER:?}:${DOCKER_PASSWORD:?}"

    local REFERENCE=""
    REFERENCE="$(harbor_create_reference "$TAG" "$DIGEST")"

    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY_RUN: DELETE $HARBOR_API/$IMAGE/artifacts/$REFERENCE"
    else
        curl -s -H "$HEADER" -X "DELETE" --basic -u "$AUTH" "$HARBOR_API/$IMAGE/artifacts/$REFERENCE"
    fi
}

# Returns the digest numbers from an harbor repository in a clear text list format.
# The list of the digests is soerted in a descencding order starting from latest
# image and ending with oldest image digest.
harbor_list_OCI_repository_digests(){
    local IMAGE="${1:?}"
    local DRY_RUN="${2:-"true"}"
    local RESULT_NUM="${3:-50}"
    local AUTH="${DOCKER_USER:?}:${DOCKER_PASSWORD:?}"
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY_RUN: GET digest(s) from $IMAGE"
        harbor_list_OCI_repository "$IMAGE" "$DRY_RUN" "$RESULT_NUM"
    else
       local RAW_DATA=""
       RAW_DATA="$(harbor_list_OCI_repository "$IMAGE" "$DRY_RUN" "$RESULT_NUM" )"
       harbor_convert_json_to_list "$RAW_DATA" | jq '.[].digest' | sed -e 's/\"//g'
    fi
}


# Returns untabulated JSON containing all artifacts based from the
# the repository (for the image) that was specified as the first argument.
harbor_list_OCI_repository(){
    local IMAGE="${1:?}"
    local DRY_RUN="${2:-"true"}"
    local RESULT_NUM="${3:-50}"
    local AUTH="${DOCKER_USER:?}:${DOCKER_PASSWORD:?}"
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY_RUN: GET $HARBOR_API/$IMAGE/artifacts"
    else
        curl -s -H "$HEADER" -X "GET" --basic -u "$AUTH" "$HARBOR_API/$IMAGE/artifacts?page_size=$RESULT_NUM"
    fi
}

# Returns untabulated JSON containing artifacts based on the supplied
# reference that could be digest or tag. When a tag is supplied
# the function might return multiple artifact objects.
harbor_get_OCI_artifact(){
    local IMAGE="${1:?}"
    local TAG="${2:-""}"
    local DIGEST="${3:-""}"
    local DRY_RUN="${4:-true}"
    local RESULT_NUM="${5:-50}"
    local AUTH="${DOCKER_USER:?}:${DOCKER_PASSWORD:?}"
    local REFERENCE=""

    REFERENCE="$(harbor_create_reference "$TAG" "$DIGEST")"

    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY_RUN: GET $HARBOR_API/$IMAGE/artifacts/$REFERENCE"
    else
	curl -s -H "$HEADER" -X "GET" --basic -u "$AUTH" \
        "$HARBOR_API/$IMAGE/artifacts/$REFERENCE?page_size=$RESULT_NUM"
    fi
}

# Returns digests based on a tag in a clear text list
harbor_get_digests_from_tag(){
    local IMAGE="${1:?}"
    local TAG="${2:?}"
    local DRY_RUN="${3:-true}"
    local RESULT_NUM="${4:-50}"
    local AUTH="${DOCKER_USER:?}:${DOCKER_PASSWORD:?}"
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY_RUN: GET digest(s) of $HARBOR_API/$IMAGE/artifacts/$TAG"
        harbor_get_OCI_artifact "$IMAGE" "$TAG" "" "$DRY_RUN" "$RESULT_NUM"
    else
        local RAW_DATA=""
	RAW_DATA="$(harbor_get_OCI_artifact "$IMAGE" "$TAG" "" "$DRY_RUN" "$RESULT_NUM" )"
        harbor_convert_json_to_list "$RAW_DATA" | jq '.[].digest' | sed -e 's/\"//g'
    fi
}

# There are API endpoints that might return a single object or a list of objects
# as a result of a query the API might return a single JSON object instead of a list.
# In order to make the parsing logic simpler this function can be used to turn the results
# of a query.
harbor_convert_json_to_list(){
    local RAW_DATA="${1:?}"
    if [ "$(echo "$RAW_DATA" | jq '.' | head -n 1 )" != "[" ]; then
        echo "$RAW_DATA" | jq '[.]'
    else
        echo "$RAW_DATA" | jq '.'
    fi
}

# Digest is a unique ID while tag is not thus if it is
# possible the digest has to be used as reference
harbor_create_reference(){
    local TAG="${1:-""}"
    local DIGEST="${2:-""}"
    local REFERENCE=""
    if [ "$DIGEST" != "" ]; then
        REFERENCE="$DIGEST"
    else
        if [ "$TAG" != "" ]; then
            REFERENCE="$TAG"
        else
           echo "ERROR: Either digest or tag is required to generate reference!"
           exit 1
        fi
    fi
    echo "$REFERENCE"
}

