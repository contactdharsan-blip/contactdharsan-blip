#!/usr/bin/env bash
# Regenerate the ASCII stat blocks in the profile README from local git repos.
#
#   ./ascii-stats.sh <README path> <repo root> [repo root ...]
#
# Rewrites whatever sits between <!--WHOAMI:START/END--> and <!--LANGS:START/END-->.
# Counts only commits authored by AUTHORS, and only tracked source files.

set -euo pipefail

README="${1:?usage: ascii-stats.sh <README> <repo> [repo...]}"
shift
REPOS=("$@")

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

for d in "${REPOS[@]}"; do
  [ -d "$d/.git" ] || { echo "skip (not a repo): $d" >&2; continue; }

  n=$(git -C "$d" log --all "${AUTHOR_ARGS[@]}" --oneline 2>/dev/null | wc -l | tr -d ' ')
  commits=$(( commits + n ))

  while IFS= read -r f; do
    L=$(lang_of "$f") || continue
    lines=$(wc -l < "$d/$f" 2>/dev/null || echo 0)
    tallies+="$L $lines"$'\n'
  done < <(git -C "$d" ls-files 2>/dev/null | grep -Ev "$SKIP")
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

repo_count=${#REPOS[@]}

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
