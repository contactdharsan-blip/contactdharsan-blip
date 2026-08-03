#!/usr/bin/env bash
# Regenerate the ASCII stat blocks in the profile README.
#
#   ./ascii-stats.sh <README> [repo ...]
#
# With no repos listed it discovers them: every git checkout under SEARCH_ROOTS,
# plus any repo on your GitHub account that isn't on disk (cloned bare into
# CACHE_DIR). That way the counts cover everything you've written rather than
# whatever happened to be checked out.
#
# Rewrites what sits between <!--WHOAMI:START/END--> and <!--LANGS:START/END-->.
# Counts only commits authored by AUTHORS, and only tracked source files.

set -euo pipefail

README="${1:?usage: ascii-stats.sh <README> [repo...]}"
shift
REPOS=("$@")

SEARCH_ROOTS=("$HOME" "$HOME/Downloads" "$HOME/Documents")
SEARCH_DEPTH=3
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/profile-stats-repos"

# Repos that are on GitHub but aren't yours to claim.
SKIP_REPOS='^(banana-claude|plugin|notchy|open-design|claude-buddy|PasteClip)$'

discover() {
  local found=()

  # The roots overlap ($HOME already reaches $HOME/Downloads within the depth
  # limit), so the same checkout surfaces more than once. Resolve and dedupe,
  # otherwise every nested repo is counted twice.
  while IFS= read -r g; do
    found+=("$g")
  done < <(
    for root in "${SEARCH_ROOTS[@]}"; do
      [ -d "$root" ] || continue
      find "$root" -maxdepth "$SEARCH_DEPTH" -type d -name .git \
        -not -path '*/node_modules/*' -not -path '*/Library/*' \
        -not -path "$CACHE_DIR/*" 2>/dev/null
    done | sed 's|/\.git$||' | while IFS= read -r p; do
      cd "$p" 2>/dev/null && pwd -P
    done | sort -u
  )

  # Anything on GitHub that isn't already on disk, fetched into the cache.
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    mkdir -p "$CACHE_DIR"
    while IFS= read -r name; do
      [[ "$name" =~ $SKIP_REPOS ]] && continue
      local have=0
      for f in "${found[@]}"; do
        [ "$(basename "$f")" = "$name" ] && { have=1; break; }
        git -C "$f" remote get-url origin 2>/dev/null | grep -qi "/$name\(\.git\)\?$" && { have=1; break; }
      done
      [ "$have" = 1 ] && continue

      if [ -d "$CACHE_DIR/$name/.git" ]; then
        git -C "$CACHE_DIR/$name" fetch -q --all 2>/dev/null || true
      else
        echo "  cloning $name" >&2
        gh repo clone "$name" "$CACHE_DIR/$name" -- -q 2>/dev/null || continue
      fi
      found+=("$CACHE_DIR/$name")
    done < <(gh repo list --limit 200 --no-archived --json name,isFork \
               --jq '.[] | select(.isFork | not) | .name')
  fi

  printf '%s\n' "${found[@]}"
}

if [ ${#REPOS[@]} -eq 0 ]; then
  echo "discovering repos..." >&2
  while IFS= read -r r; do [ -n "$r" ] && REPOS+=("$r"); done < <(discover)
fi

AUTHORS=(
  contactdharsan@gmail.com
  contactdharsan@github.com
  kesavand@gmail.com
  kesavan@cogniferlabs.com
)
AUTHOR_ARGS=()
for a in "${AUTHORS[@]}"; do AUTHOR_ARGS+=(--author="$a"); done

SKIP='(^|/)(node_modules|vendor|dist|build|\.next|Pods|third_party|generated)/'
BAR_WIDTH=40
MIN_SHARE=0.5   # drop languages under this percent of total, they are just noise

# printf "%'d" depends on locale and silently no-ops on a plain C locale.
commafy() {
  awk -v n="$1" 'BEGIN {
    s = sprintf("%d", n); out = ""; c = 0
    for (i = length(s); i > 0; i--) {
      out = substr(s, i, 1) out; c++
      if (c % 3 == 0 && i > 1) out = "," out
    }
    print out
  }'
}

lang_of() {
  case "${1##*.}" in
    kt|kts)      echo Kotlin ;;
    swift)       echo Swift ;;
    rs)          echo Rust ;;
    py)          echo Python ;;
    ts|tsx)      echo TypeScript ;;
    js|jsx)      echo JavaScript ;;
    java)        echo Java ;;
    c|cc|cpp|h|hpp) echo 'C/C++' ;;
    sh|bash|zsh) echo Shell ;;
    sql)         echo SQL ;;
    html)        echo HTML ;;
    css|scss)    echo CSS ;;
    go)          echo Go ;;
    rb)          echo Ruby ;;
    dart)        echo Dart ;;
    m|mm)        echo ObjC ;;
    *)           return 1 ;;
  esac
}

commits=0
tallies=""

counted=0
for d in "${REPOS[@]}"; do
  # A .git directory can exist and still not be a usable repo (stale checkout,
  # broken submodule pointer). Ask git, don't trust the directory.
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "skip (not a usable repo): $d" >&2; continue; }

  n=$( { git -C "$d" log --all "${AUTHOR_ARGS[@]}" --oneline 2>/dev/null || true; } \
         | wc -l | tr -d ' ')

  # Authorship is the filter. A checkout you never committed to — a fork, a
  # vendored dependency, someone else's tool — contributes neither commits nor
  # lines. This is why discovery can sweep broadly without a skip list.
  [ "$n" -eq 0 ] && continue

  commits=$(( commits + n ))
  counted=$(( counted + 1 ))

  while IFS= read -r f; do
    L=$(lang_of "$f") || continue
    lines=$(wc -l < "$d/$f" 2>/dev/null || echo 0)
    tallies+="$L $lines"$'\n'
  done < <( { git -C "$d" ls-files 2>/dev/null || true; } | grep -Ev "$SKIP" || true)
done

# language -> total, descending
sorted=$(printf '%s' "$tallies" | awk 'NF{s[$1]+=$2} END{for(k in s) print s[k], k}' | sort -rn)
total=$(printf '%s\n' "$sorted" | awk '{s+=$1} END{print s+0}')
max=$(printf '%s\n' "$sorted" | head -1 | awk '{print $1}')

bars=$(printf '%s\n' "$sorted" | awk -v w="$BAR_WIDTH" -v max="$max" \
                                     -v total="$total" -v minshare="$MIN_SHARE" '
  function commafy(n,   s,out,i,c) {
    s = sprintf("%d", n); out = ""; c = 0
    for (i = length(s); i > 0; i--) {
      out = substr(s, i, 1) out; c++
      if (c % 3 == 0 && i > 1) out = "," out
    }
    return out
  }
  ($1 / total) * 100 < minshare { next }
  {
    filled = int(($1 / max) * w + 0.5)
    if (filled < 1) filled = 1
    bar = ""
    for (i = 0; i < filled; i++) bar = bar "\342\226\210"
    for (i = filled; i < w; i++) bar = bar "\342\226\221"
    printf "  %-12s %s %8s\n", $2, bar, commafy($1)
  }')

repo_count=$counted   # repos you actually authored in, not repos scanned

whoami_block=$(cat <<EOF
\`\`\`
dharsan@github
──────────────────────────────────────────────────
  repos ........ ${repo_count} authored
  commits ...... $(commafy "$commits")
  lines ........ $(commafy "$total")
  focus ........ local-first, offline-capable
  editor ....... nvim, Xcode when forced
  building ..... Avorio · backglass · agent-bridge
──────────────────────────────────────────────────
\`\`\`
EOF
)

langs_block=$(cat <<EOF
\`\`\`
${bars}

  $(commafy "$total") lines of source across ${repo_count} repos, vendored code excluded
\`\`\`
EOF
)

# awk -v cannot carry newlines, so the replacement body is passed as a file.
replace_block() {
  local marker="$1" body="$2" file="$3"
  local bodyfile tmp
  bodyfile=$(mktemp); tmp=$(mktemp)
  printf '%s\n' "$body" > "$bodyfile"
  awk -v start="<!--${marker}:START-->" -v end="<!--${marker}:END-->" \
      -v bodyfile="$bodyfile" '
    $0 == start {
      print
      while ((getline line < bodyfile) > 0) print line
      close(bodyfile)
      skipping = 1
      next
    }
    $0 == end { print; skipping = 0; next }
    !skipping { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  rm -f "$bodyfile"
}

replace_block WHOAMI "$whoami_block" "$README"
replace_block LANGS  "$langs_block"  "$README"

echo "updated $README — ${repo_count} repos, ${commits} commits, ${total} lines"
