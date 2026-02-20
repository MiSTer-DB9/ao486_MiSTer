#!/usr/bin/env bash
# Copyright (c) 2020 José Manuel Barroso Galindo <theypsilon@gmail.com>

set -euo pipefail

UPSTREAM_REPO="https://github.com/MiSTer-devel/ao486_MiSTer.git"
CORE_NAME="ao486"
MAIN_BRANCH="dev"
UPSTREAM_BRANCH="master"

echo "Fetching upstream:"
git remote remove upstream 2> /dev/null || true
git remote add upstream ${UPSTREAM_REPO}
git -c protocol.version=2 fetch --no-tags --prune --no-recurse-submodules upstream
git checkout -qf remotes/upstream/${UPSTREAM_BRANCH}

COMMIT_TO_MERGE=$(git log -n 1 --pretty=format:%H "remotes/upstream/${UPSTREAM_BRANCH}")

export GIT_MERGE_AUTOEDIT=no
git config --global user.email "theypsilon@gmail.com"
git config --global user.name "The CI/CD Bot"
git config --global rerere.enabled true

echo
echo "Syncing with upstream:"
git fetch origin --unshallow 2> /dev/null || true
git checkout -qf ${MAIN_BRANCH}

if git merge-base --is-ancestor "${COMMIT_TO_MERGE}" HEAD; then
	echo "No new commits found. Exiting."
	exit
fi

echo
echo "START rerere-train.sh"

# Remember original branch
ORIGINAL_BRANCH=$(git symbolic-ref -q HEAD) ||
ORIGINAL_HEAD=$(git rev-parse --verify HEAD) || {
	echo >&2 "rerere-train.sh: Not on any branch and no commit yet?"
	exit 1
}

mkdir -p ".git/rr-cache" || true
git rev-list --parents "HEAD" |
while read commit parent1 other_parents
do
	if test -z "${other_parents}"
	then
		# Skip non-merges
		continue
	fi
	git checkout -q "${parent1}^0"
	if git merge ${other_parents} >/dev/null 2>&1
	then
		# Cleanly merges
		continue
	fi
	if test -s ".git/MERGE_RR"
	then
		git show -s --pretty=format:"Learning from %h %s" "${commit}"
		git rerere
		git checkout -q ${commit} -- .
		git rerere
	fi
	git reset -q --hard
done

if test -z "${ORIGINAL_BRANCH}"
then
	git checkout "${ORIGINAL_HEAD}"
else
	git checkout "${ORIGINAL_BRANCH#refs/heads/}"
fi

echo "END rerere-train.sh"
echo

git merge -Xignore-all-space --no-commit ${COMMIT_TO_MERGE} || ./.github/notify_error.sh "UPSTREAM MERGE CONFLICT" $@
git submodule update --init --recursive

echo "Build start:"
RELEASE_FILE="${CORE_NAME}_$(date +%Y%m%d).rbf"
docker build -t artifact . || ./.github/notify_error.sh "COMPILATION ERROR" $@
docker run --rm artifact > "releases/${RELEASE_FILE}"
echo
echo "Pushing release:"
git add releases
git commit -m "BOT: Merging upstream, releasing ${RELEASE_FILE}"

git push origin ${MAIN_BRANCH}
