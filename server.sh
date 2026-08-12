#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/vars"

repo_name=$1

if [ -z $dir ]; then
  echo "new: repo name not provided"
  exit 1
fi

cat git.repos | while IFS= read -r repo; do
  git clone "ssh://${REMOTE_NAME}${TARGET_GIT_SERVER}/$repo" "$GIT_REPO/repos/$repo" || true
done
