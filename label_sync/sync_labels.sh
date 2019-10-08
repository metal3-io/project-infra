#!/bin/bash
set -ex

# Clean-up in case we exit
function clean {
  cd "$SCRIPTDIR"
  rm token--*
}
trap clean EXIT

if [ "$1" == "confirm" ]
then
  LABEL_SYNC_CONFIRM="--confirm"
fi

# Find out where we're executed from
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get variables from the config file
if [ -z "${CONFIG:-}" ]; then
    # See if there's a config_$USER.sh in the SCRIPTDIR
    if [ -f "${SCRIPTDIR}/config_${USER}.sh" ]; then
        echo "Using CONFIG ${SCRIPTDIR}/config_${USER}.sh"
        CONFIG="${SCRIPTDIR}/config_${USER}.sh"
    else
        echo "Please run with a configuration environment set."
        echo "eg CONFIG=config_example.sh ./sync_labels.sh"
        exit 1
    fi
fi
source $CONFIG

# Ensure we have the minimum variables to run
REQUIRED_VARS="LABEL_SYNC_CONFIG LABEL_SYNC_GITHUB_TOKEN LABEL_SYNC_GITHUB_ORG"
for var in $REQUIRED_VARS
do
 if [ -z "${!var}" ]
 then
   echo "Missing required variable: $var"
   exit 1
 fi
done

# Ensure this is a fully qualified path
LABEL_SYNC_CONFIG=$(realpath "$LABEL_SYNC_CONFIG")
[ -f "$LABEL_SYNC_CONFIG" ] || exit 1

# Clone k8s test-infra which has label_sync repo
if [ ! -d test-infra ]
then
  git clone https://github.com/kubernetes/test-infra.git
else
  cd test-infra || exit 1
  git checkout master
  git pull origin master
  cd .. || exit 1
fi

# Write token to a file
token_file=$(mktemp "token--XXXXXXXXXX")
echo "$LABEL_SYNC_GITHUB_TOKEN" > "$token_file"

if [ -n "$LABEL_SYNC_SKIP" ]
then
  LABEL_SYNC_SKIP_REPOS="--skip $LABEL_SYNC_SKIP"
fi

pushd .
cd test-infra
bazel run //label_sync -- \
  --config "$LABEL_SYNC_CONFIG" \
  --token "$SCRIPTDIR/$token_file" \
  --orgs "$LABEL_SYNC_GITHUB_ORG" $LABEL_SYNC_CONFIRM $LABEL_SYNC_SKIP_REPOS
popd

echo "Success!"
