#!/usr/bin/env bash
# Cuts a release: writes VERSION, keeps project.yml in step, commits and tags.
#
#   ./scripts/release.sh 1.7.0
#
# Build, sign and notarise afterwards with ./scripts/build-release.sh --notarize,
# then publish with gh release create.
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: ./scripts/release.sh <version>   e.g. 1.7.0" >&2
  exit 1
fi
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "version must look like 1.2.3" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty — commit first" >&2
  exit 1
fi

# A tag that already exists somewhere other than HEAD means work landed on top
# of a version that was already cut — which is how a tag ends up describing less
# than its own changelog entry claims. Moving it has to be a decision, not a
# silent overwrite.
if EXISTING="$(git rev-parse -q --verify "refs/tags/v$VERSION")"; then
  if [ "$EXISTING" != "$(git rev-parse HEAD)" ]; then
    echo "v$VERSION is already tagged at ${EXISTING:0:7}, but HEAD is $(git rev-parse --short HEAD)." >&2
    echo "$(git rev-list --count "v$VERSION"..HEAD) commit(s) have landed since it was cut." >&2
    echo "Either bump the version, or move the tag deliberately:" >&2
    echo "  git tag -d v$VERSION && git push origin :refs/tags/v$VERSION" >&2
    exit 1
  fi
fi

# The changelog is part of the release, not an afterthought: refuse to tag
# without an entry, so no version can ship undocumented.
if ! grep -q "## \[$VERSION\]" CHANGELOG.md; then
  echo "CHANGELOG.md has no '## [$VERSION]' section — add one first" >&2
  exit 1
fi

echo "$VERSION" > VERSION
# VERSION is the source of truth, but XcodeGen reads project.yml, so the two
# have to agree or the bundle ships a version the tag disagrees with.
/usr/bin/sed -i '' "s/^    MARKETING_VERSION: .*/    MARKETING_VERSION: \"$VERSION\"/" project.yml

git add VERSION CHANGELOG.md project.yml
# Both are often bumped as part of the feature commit, in which case there is
# nothing left to commit here — that's fine, not an error.
if git diff --cached --quiet; then
  echo "VERSION, CHANGELOG.md and project.yml already committed — tagging that commit"
else
  git commit -m "Release $VERSION"
fi
git tag -a "v$VERSION" -m "Release $VERSION"

echo
echo "tagged v$VERSION. To publish:"
echo "  git push && git push --tags"
echo "  ./scripts/build-release.sh --notarize"
echo "  gh release create v$VERSION build/Klipt-$VERSION.dmg --title \"Klipt v$VERSION\" --notes \"...\""
