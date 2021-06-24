#!/usr/bin/env bash

run_pull_request_command() {
  if [ "$(git rev-parse --revs-only "$SOURCE_BRANCH")" = "$(git rev-parse --revs-only "$1")" ]; then
    echo "Source and destination branches are the same."
    exit 0
  fi

  # Do not proceed if there are no file differences, this avoids PRs with just a merge commit and no content
  LINES_CHANGED=$(git diff --name-only "$1" "$SOURCE_BRANCH" -- | wc -l | awk '{print $1}')
  if [[ "$LINES_CHANGED" == "0" ]] && [[ ! "$INPUT_PR_ALLOW_EMPTY" == "true" ]]; then
    echo "No file changes detected between source and destination branches."
    exit 0
  fi

  # Workaround for `hub` auth error https://github.com/github/hub/issues/2149#issuecomment-513214342
  export GITHUB_USER="$GITHUB_ACTOR"

  COMMAND="hub pull-request \
    -b $1 \
    -h $SOURCE_BRANCH \
    --no-edit \
    $PR_ARG \
    || true"

  echo "$COMMAND"

  PR_URL=$(sh -c "$COMMAND")
  if [[ "$?" != "0" ]]; then
    exit 1
  fi

  echo ${PR_URL}
  # shellcheck disable=SC2082
  echo "::set-output name=destination_branch::$1"
  echo "::set-output name=pr_url::${PR_URL}"
  echo "::set-output name=pr_number::${PR_URL##*/}"
  if [[ "$LINES_CHANGED" == "0" ]]; then
    echo "::set-output name=has_changed_files::false"
  else
    echo "::set-output name=has_changed_files::true"
  fi
}

run_merge(){
  COMMAND="hub merge ${PR_URL}"

  echo "$COMMAND"

  MERGE=$(sh -c "$COMMAND")
  if [[ "$?" != "0" ]]; then
    exit 1
  fi

  echo "${MERGE}"
}

set -e
set -o pipefail

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Set the GITHUB_TOKEN environment variable."
  exit 1
fi

if [[ ! -z "$INPUT_SOURCE_BRANCH" ]]; then
  SOURCE_BRANCH="$INPUT_SOURCE_BRANCH"
elif [[ ! -z "$GITHUB_REF" ]]; then
  SOURCE_BRANCH=${GITHUB_REF/refs\/heads\//} # Remove branch prefix
else
  echo "Set the INPUT_SOURCE_BRANCH environment variable or trigger from a branch."
  exit 1
fi

# Github actions no longer auto set the username and GITHUB_TOKEN
git remote set-url origin "https://$GITHUB_ACTOR:$GITHUB_TOKEN@github.com/$GITHUB_REPOSITORY"

# Pull all branches references down locally so subsequent commands can see them
git fetch origin '+refs/heads/*:refs/heads/*' --update-head-ok

# Print out all branches
#git --no-pager branch -a -vv

echo "INPUT_DESTINATION_BRANCH_REGEX = ${INPUT_DESTINATION_BRANCH_REGEX}"
if [ -z "${INPUT_DESTINATION_BRANCH_REGEX}" ]; then
  DESTINATION_BRANCH="${INPUT_DESTINATION_BRANCH:-"master"}"
else
  branches=$(git --no-pager branch -a | grep "${INPUT_DESTINATION_BRANCH_REGEX}")
  echo "branches = ${branches}"
  readarray -t <<<"${branches}"
  for branch in "${MAPFILE[@]}"; do
    echo "branch = ${branch}"
    branch_trim=$(echo "${branch}" | sed 's/ *$//g')
    echo "branch_trim = ${branch_trim}"
    branch_trim=$(echo "${branch}" | xargs)
    echo "branch_trim 2 = ${branch_trim}"
    if [[ "${branch_trim}" != "${INPUT_DESTINATION_BRANCH_REGEX}" ]] && [[ "${branch_trim}" != *"*"* ]] && [[ "${branch_trim}" != remote* ]]; then
      echo "in with ${branch_trim}"
      run_pull_request_command "${branch_trim}"
      run_merge
    fi
  done
fi

#PR_ARG="$INPUT_PR_TITLE"
#if [[ ! -z "$PR_ARG" ]]; then
#  PR_ARG="-m \"$PR_ARG\""
#
#  if [[ ! -z "$INPUT_PR_TEMPLATE" ]]; then
#    sed -i 's/`/\\`/g; s/\$/\\\$/g' "$INPUT_PR_TEMPLATE"
#    PR_ARG="$PR_ARG -m \"$(echo -e "$(cat "$INPUT_PR_TEMPLATE")")\""
#  elif [[ ! -z "$INPUT_PR_BODY" ]]; then
#    PR_ARG="$PR_ARG -m \"$INPUT_PR_BODY\""
#  fi
#fi
#
#if [[ ! -z "$INPUT_PR_REVIEWER" ]]; then
#  PR_ARG="$PR_ARG -r \"$INPUT_PR_REVIEWER\""
#fi
#
#if [[ ! -z "$INPUT_PR_ASSIGNEE" ]]; then
#  PR_ARG="$PR_ARG -a \"$INPUT_PR_ASSIGNEE\""
#fi
#
#if [[ ! -z "$INPUT_PR_LABEL" ]]; then
#  PR_ARG="$PR_ARG -l \"$INPUT_PR_LABEL\""
#fi
#
#if [[ ! -z "$INPUT_PR_MILESTONE" ]]; then
#  PR_ARG="$PR_ARG -M \"$INPUT_PR_MILESTONE\""
#fi
#
#if [[ "$INPUT_PR_DRAFT" ==  "true" ]]; then
#  PR_ARG="$PR_ARG -d"
#fi