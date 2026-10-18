#!/bin/bash
# generate-changelog.sh - markdown changelog of the commits since the previous tag
#
# Usage: generate-changelog.sh [from-ref] [to-ref]
#   from-ref  previous tag / commit  (default: the last tag reachable from to-ref, excluding TAG)
#   to-ref    end of the range       (default: HEAD)
#
# Environment:
#   TAG                tag being released (excluded when auto-detecting, used for the compare link)
#   VERSION            heading version (default: TAG without its "v" prefix)
#   NOTES              markdown inserted between the heading and the sections (release message)
#   GITHUB_REPOSITORY  owner/repo, enables commit, issue and compare links
#   GITHUB_TOKEN       optional, used to look up the author login of non-noreply emails
#   GITHUB_ACTIONS     set by the runner, enables the collapsible log group (written to stderr)
#
# Rendered in the conventional-changelog shape used by puppeteer/lerna releases: a version heading
# linking to the compare view, one "###" section per Conventional Commit type, one "*" line per
# commit with its pull request reference, its commit link and its author, then the contributors.
# Works on a repo that pushes straight to a branch (GitHub only lists merged pull requests).
set -euo pipefail

FROM="${1:-}"
TO="${2:-HEAD}"
REPO="${GITHUB_REPOSITORY:-}"
TAG="${TAG:-}"
VERSION_ENV="${VERSION:-}"
NOTES="${NOTES:-}"

if [ -z "$FROM" ]; then
  if [ -n "$TAG" ]; then
    FROM="$(git describe --tags --abbrev=0 --exclude "$TAG" "$TO" 2>/dev/null || true)"
  else
    FROM="$(git describe --tags --abbrev=0 "$TO^" 2>/dev/null || true)"
  fi
fi

# Diagnostic only: stdout carries the markdown and is redirected into the release body, so the
# actions log group must go to stderr.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  {
    echo "::group::Changelog range"
    echo "  from : ${FROM:-<first commit>}"
    echo "  to   : $TO"
    echo "::endgroup::"
  } >&2
fi

commits() {
  # Newest first, like a release page. --use-mailmap lets a .mailmap in the repository rewrite an
  # author email to a GitHub one.
  if [ -n "$FROM" ]; then
    git log --no-merges --use-mailmap --format='%H%x1f%s%x1f%an%x1f%ae' "$FROM..$TO"
  else
    git log --no-merges --use-mailmap --format='%H%x1f%s%x1f%an%x1f%ae' "$TO"
  fi
}

commit_link() {
  # Inline code inside the link text: GitHub renders it as a monospace link, still clickable.
  if [ -n "$REPO" ]; then echo "[\`$1\`](https://github.com/$REPO/commit/$2)"; else echo "\`$1\`"; fi
}

# A commit email becomes a profile link two ways: a GitHub noreply address encodes the login
# (<id>+<login>@users.noreply.github.com), and any other address is looked up through the commit API,
# which only yields an account when the email is actually linked to one. Otherwise the git name is
# kept. `git log --use-mailmap` runs first, so a .mailmap in the repository wins for both cases.
profile_link() { echo "[@$1](https://github.com/$1)"; }

# One request per distinct email, using the first commit that carries it.
api_login() {
  local commit="$1" body token
  [ -n "$REPO" ] && [ -n "$commit" ] || return 0
  command -v curl >/dev/null 2>&1 || return 0
  token="$(printf '%s' "${GITHUB_TOKEN:-${GH_TOKEN:-}}")"
  if [ -n "$token" ]; then
    body="$(curl -fsSL -m 10 -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/$REPO/commits/$commit" 2>/dev/null || true)"
  else
    body="$(curl -fsSL -m 10 -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/$REPO/commits/$commit" 2>/dev/null || true)"
  fi
  [ -n "$body" ] || return 0
  # Only the top-level author object carries the login; the commit author object has name/email.
  printf '%s' "$body" | tr -d ' \r\n\t' | grep -o '"login":"[^"]*"' | sed -n '1p' | sed 's/.*:"//; s/"$//'
}

declare -A LOGIN_CACHE

author_label() {
  local name="$1" mail="$2"
  if [ -n "${LOGIN_CACHE[$mail]:-}" ]; then profile_link "${LOGIN_CACHE[$mail]}"; else echo "$name"; fi
}

# Fill LOGIN_CACHE once: author_label runs inside a command substitution, so a cache written there
# would live in a subshell, and one API request per distinct email keeps us far from the rate limit.
resolve_authors() {
  local mail login
  for mail in "${!EMAIL_HASH[@]}"; do
    case "$mail" in
      *@users.noreply.github.com)
        login="${mail%%@*}"; login="${login##*+}"
        if [ -n "$login" ]; then LOGIN_CACHE["$mail"]="$login"; continue; fi ;;
    esac
    LOGIN_CACHE["$mail"]="$(api_login "${EMAIL_HASH[$mail]}")"
  done
}

# Heading version: v1.0.7 -> 1.0.7, the tag prefix is noise on a release page.
version_of() {
  local version="$1"
  version="${version#v}"; version="${version#V}"
  echo "$version"
}

# Release date: the tagged commit date when the tag exists, today otherwise.
release_date() {
  if [ -n "$TAG" ] && git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    git log -1 --format=%cs "$TAG"
  else
    date +%F
  fi
}

section_of() {
  case "$1" in
    feat)      echo "Features" ;;
    fix)       echo "Bug Fixes" ;;
    perf)      echo "Performance" ;;
    refactor)  echo "Refactoring" ;;
    docs)      echo "Documentation" ;;
    build|ci)  echo "Build & CI" ;;
    test)      echo "Tests" ;;
    style)     echo "Styling" ;;
    revert)    echo "Reverts" ;;
    chore)     echo "Chores" ;;
    *)         echo "Other Changes" ;;
  esac
}

ORDER=("Breaking Changes" "Features" "Bug Fixes" "Performance" "Refactoring" "Documentation" "Build & CI" "Tests" "Styling" "Reverts" "Chores" "Other Changes")

declare -A FOUND
declare -A BREAKING
declare -A EMAIL_HASH
AUTHORS=()
TOTAL=0

# First commit of every author, used as the lookup key for the API.
while IFS=$'\x1f' read -r hash _ name mail; do
  [ -n "$hash" ] || continue
  [ -n "${EMAIL_HASH[$mail]:-}" ] || EMAIL_HASH["$mail"]="$hash"
done < <(commits)

resolve_authors

# A commit is breaking when it is flagged with "!" after the type/scope, or when its body carries a
# "BREAKING CHANGE:" footer (--grep matches any line of the message, -F keeps the colon literal).
while read -r breaking_hash; do
  [ -n "$breaking_hash" ] && BREAKING["$breaking_hash"]=1
  true
done < <(
  if [ -n "$FROM" ]; then
    git log --no-merges --format='%H' -F --grep='BREAKING CHANGE' "$FROM..$TO"
  else
    git log --no-merges --format='%H' -F --grep='BREAKING CHANGE' "$TO"
  fi
)

while IFS=$'\x1f' read -r hash subject name mail; do
  [ -n "$hash" ] || continue

  short="${hash:0:7}"
  label="$(author_label "$name" "$mail")"
  TOTAL=$((TOTAL + 1))

  # Conventional Commits: type(scope)!: subject
  if [[ "$subject" =~ ^([A-Za-z]+)(\(([^\)]+)\))?(!)?:[[:space:]]*(.+)$ ]]; then
    type="${BASH_REMATCH[1],,}"; scope="${BASH_REMATCH[3]}"
    breaking="${BASH_REMATCH[4]}"; text="${BASH_REMATCH[5]}"
  else
    type=""; scope=""; breaking=""; text="$subject"
  fi

  # The pull request number sits at the end of the subject: link it and strip it from the text.
  refs=""
  for number in $(printf '%s' "$text" | grep -oE '\(#[0-9]+\)' | tr -d '()#'); do
    if [ -n "$REPO" ]; then refs+="([#$number](https://github.com/$REPO/issues/$number)) "; else refs+="(#$number) "; fi
  done
  refs="${refs% }"
  text="$(printf '%s' "$text" | sed -E 's/[[:space:]]*\(#[0-9]+\)//g; s/[[:space:]]+$//')"

  entry="* $(commit_link "$short" "$hash") "
  [ -n "$scope" ] && entry+="**$scope**: "
  entry+="$text"
  [ -n "$refs" ] && entry+=" $refs"
  [ -n "$label" ] && entry+=" $label"

  FOUND["$(section_of "$type")"]+="$entry"$'\n'
  if [ -n "$breaking" ] || [ -n "${BREAKING[$hash]:-}" ]; then
    FOUND["Breaking Changes"]+="$entry"$'\n'
  fi

  case " ${AUTHORS[*]} " in
    *" $label "*) ;;
    *) AUTHORS+=("$label") ;;
  esac
done < <(commits)

if [ "$TOTAL" -eq 0 ]; then
  if [ -n "$FROM" ]; then echo "_No changes since \`$FROM\`._"; else echo "_No changes._"; fi
  exit 0
fi

# ## [1.0.7](compare) (2026-10-18)
VERSION="${VERSION_ENV:-$(version_of "${TAG:-$TO}")}"
RELEASED="$(release_date)"
if [ -n "$REPO" ] && [ -n "$FROM" ]; then
  echo "## [$VERSION](https://github.com/$REPO/compare/$FROM...${TAG:-$TO}) ($RELEASED)"
elif [ -n "$REPO" ] && [ -n "$TAG" ]; then
  echo "## [$VERSION](https://github.com/$REPO/releases/tag/$TAG) ($RELEASED)"
else
  echo "## $VERSION ($RELEASED)"
fi
echo ""

# Release message handed over by the caller, kept verbatim between the heading and the sections.
if [ -n "$NOTES" ]; then
  printf '%s\n\n' "$NOTES"
fi

# Compare view, right under the message and above the sections (same wording as GitHub notes).
if [ -n "$REPO" ] && [ -n "$FROM" ]; then
  echo "**Full Changelog**: https://github.com/$REPO/compare/$FROM...${TAG:-$TO}"
  echo ""
fi

for section in "${ORDER[@]}"; do
  [ -n "${FOUND[$section]:-}" ] || continue
  echo "### $section"
  echo ""
  printf '%s' "${FOUND[$section]}"
  echo ""
done

echo "### Contributors"
echo ""
for author in "${AUTHORS[@]}"; do echo "* $author"; done
echo ""
