#!/bin/sh
# One release, end to end: gate, bundle, zip, checksum, tag, push, GitHub
# Release. Everything that assembles or signs the app stays in
# Scripts/build-app.sh; this script is the release steps around it.
#
#   Scripts/release.sh            # release the tag already at HEAD
#   Scripts/release.sh v1.2.3     # tag this commit, then release it
#
# The version (written without the leading v) is the one string behind the
# stamped CFBundleShortVersionString, oc-dashbar-<version>.zip and its
# .sha256, the tag v<version>, and the release title. An argument must match
# the tag at HEAD when one is there, and a tag that exists anywhere other
# than HEAD is a failure: nothing in here moves or reuses a tag.
#
# Failures are loud. A dirty tree, a missing tool, and a tag at another
# commit stop the run before anything is built. gh authentication is checked
# at the release step, after the tag is pushed, because no GitHub token is
# needed to build over SSH; when it fails, the exact command that finishes
# the release by hand is printed.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

die() {
    echo "release.sh: $*" >&2
    exit 1
}

# --- preconditions ---------------------------------------------------------

for tool in git swift xcrun ditto shasum plutil gh; do
    command -v "$tool" >/dev/null 2>&1 ||
        die "missing $tool; the release needs git, Xcode's command line tools (swift, xcrun), ditto, shasum, plutil and gh"
done
[ -x Scripts/build-app.sh ] || die "Scripts/build-app.sh is missing or not executable"
[ -f Scripts/release-notes.md ] || die "Scripts/release-notes.md is missing; the release notes are published from it"

if [ -n "$(git status --porcelain)" ]; then
    git status --short >&2
    die "working tree is dirty; commit or stash before releasing"
fi

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] ||
    die "on branch $(git rev-parse --abbrev-ref HEAD), and the release pushes main"

# --- the version -----------------------------------------------------------

arg="${1:-}"
head_tag="$(git describe --tags --exact-match 2>/dev/null || true)"
head_version=""
if [ -n "$head_tag" ]; then
    head_version="${head_tag#v}"
fi
arg_version="${arg#v}"

if [ -n "$arg_version" ] && [ -n "$head_version" ] && [ "$arg_version" != "$head_version" ]; then
    die "argument v$arg_version does not match the tag $head_tag at HEAD"
fi

version="${arg_version:-$head_version}"
[ -n "$version" ] ||
    die "no version: pass one (Scripts/release.sh v1.2.3) or tag this commit first"
tag="v$version"

case "$version" in
    [0-9][0-9]*.[0-9][0-9]*.[0-9][0-9]*) ;;
    *) die "version must look like 1.2.3 (got $version)" ;;
esac

head_sha="$(git rev-parse HEAD)"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    tag_sha="$(git rev-list -n 1 "$tag")"
    [ "$tag_sha" = "$head_sha" ] ||
        die "tag $tag already exists at $tag_sha, not HEAD ($head_sha); refusing to move it"
    echo "release.sh: $tag already points at HEAD"
fi

git fetch --quiet origin
origin_sha="$(git rev-parse origin/main)"
git merge-base --is-ancestor "$origin_sha" HEAD ||
    die "origin/main ($origin_sha) is not an ancestor of HEAD; the release would not fast-forward over published main"

# --- gate ------------------------------------------------------------------

echo "release.sh: gate: swift test"
swift test
echo "release.sh: gate: swift-format lint"
xcrun swift-format lint -r Sources Tests
echo "release.sh: gate: swift build"
swift build
echo "release.sh: gate: swift build -c release"
swift build -c release

# --- bundle, stamped -------------------------------------------------------

echo "release.sh: bundling oc-dashbar $version"
Scripts/build-app.sh release "$version"

plist="build/oc-dashbar.app/Contents/Info.plist"
stamped="$(plutil -extract CFBundleShortVersionString raw -o - "$plist")"
[ "$stamped" = "$version" ] || die "bundle stamp is $stamped, expected $version"
echo "release.sh: stamped CFBundleShortVersionString=$stamped"

# --- zip and checksum ------------------------------------------------------

zip="build/oc-dashbar-$version.zip"
sum="$zip.sha256"
rm -f "$zip" "$sum"
(
    cd build &&
        ditto -c -k --keepParent oc-dashbar.app "oc-dashbar-$version.zip" &&
        shasum -a 256 "oc-dashbar-$version.zip" >"oc-dashbar-$version.zip.sha256"
)
(cd build && shasum -a 256 -c "oc-dashbar-$version.zip.sha256")
echo "release.sh: $(cat "$sum")"

# --- tag and push ----------------------------------------------------------

if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    git tag -a "$tag" -m "oc-dashbar $tag"
fi
git push origin main
git push origin "$tag"

# --- GitHub Release --------------------------------------------------------

# gh is checked here, where the token is actually needed. Everything above
# works with no GitHub token at all; an unauthenticated run still leaves a
# pushed tag and the two final assets for the one command printed below.
if ! gh auth status >/dev/null 2>&1; then
    echo "release.sh: gh is not authenticated; every step except the GitHub Release is done." >&2
    echo "release.sh: log in once:" >&2
    echo "release.sh:   gh auth login -h github.com" >&2
    echo "release.sh: then run, from $root:" >&2
    echo "release.sh:   gh release create $tag --verify-tag --title \"oc-dashbar $tag\" --notes-file Scripts/release-notes.md $zip $sum" >&2
    exit 1
fi

gh release create "$tag" --verify-tag --title "oc-dashbar $tag" \
    --notes-file Scripts/release-notes.md "$zip" "$sum"

echo "release.sh: released $tag with $zip and $sum"
