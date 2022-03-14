#! /usr/bin/env bash

set -eu

# Clone the target repo and change the directory to cloned repo name
gclonecd () {
    url=$1;
    reponame=$(echo $url | awk -F/ '{print $NF}' | sed -e 's/.git$//');
    if [ -d "$reponame" ]; then
      echo "Target repo folder already exists"
    else 
      git clone $url $reponame;
      cd $reponame;
    fi
}

# If git diff on the target branch against source repo outputs ONLY markdown or
# OWNERS file, return exit code (rc): 0 to skip integration tests, otherwise 
# return 1 to run integration tests
exclude_markdown_and_owners_files() {
  for file in $(git diff origin/"${REPO_BRANCH}"..."${UPDATED_BRANCH}" --name-only)
  do
    filename=$(basename -- "$file")
    extension="${filename##*.}"
    filename="${filename%.*}"
    if [[ $extension != "md" ]]
    then
      if [[ $filename != "OWNERS" ]]
      then
        echo "The file(s) changed contains other extensions and files than markdown or OWNERS file"
        return 1
      fi
    fi
  done
  return 0
}

# If the target repo and branch are the same as the source repo and branch
# we're running a main test, return exit code (rc): 1 to run integration tests,
# otherwise check the updated branch to decide on whether skipping or running 
# the integration tests.
if [[ "${UPDATED_BRANCH}" == "${REPO_BRANCH}" ]] && [[ "${UPDATED_REPO}" == *"${REPO_ORG}/${REPO_NAME}"* ]]; then
  echo "Main job is runnning, not skipping integration tests"
  return 1
else
  echo "Clone updated repo"
  gclonecd $UPDATED_REPO
  echo "Run skipping the integration test custom script to find out git diff"
  exclude_markdown_and_owners_files
fi