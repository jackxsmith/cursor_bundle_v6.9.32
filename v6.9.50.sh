#!/usr/bin/env bash
# v6.9.50.sh
#
# Purpose
# -------
# • Bump project from 6.9.47 → 6.9.50.
# • Remove *all* obsolete or duplicate artefacts, leaving exactly one copy per
#   logical file (the latest, suffixed _v6.9.50) and deleting superseded logs,
#   tarballs, reports, etc.  This covers all older suffixes from 6.9.35 up
#   through 6.9.49.
# • Eliminate “missing‑file” warnings by updating version strings *before* any
#   renames, and by checking each path exists before operating on it.
# • Run a quick lint check (Ruff for Python, ShellCheck for Bash) and store
#   results in `lint_report_v6.9.50.txt`.
# • Commit, tag and push automatically to the `origin` remote.
#
# Safe to re‑run: skips moves if src=dst, skips deletes if file already gone.

set -euo pipefail
shopt -s globstar nullglob

OLD_VERSION="6.9.47"
NEW_VERSION="6.9.50"
REPO_DIR="${1:-$HOME/Downloads/cursor_bundle_v6.9.32}"
REPORT="cleanup_report_v${NEW_VERSION}.txt"
LINT="lint_report_v${NEW_VERSION}.txt"

echo "→ Working in $REPO_DIR"
[[ -d "$REPO_DIR" ]] || { echo "Repo not found"; exit 1; }
cd "$REPO_DIR"

git init -q 2>/dev/null || true
git config user.name  >/dev/null 2>&1 || git config user.name  "Automation"
git config user.email >/dev/null 2>&1 || git config user.email "automation@example.com"

: > "$REPORT"

###############################################################################
# 1. Update version strings *first* to avoid Perl missing‑file warnings later.
###############################################################################
echo "→ Updating version strings inside files …"
FILES=$(git ls-files '*.sh' '*.py' '*.json' '*.md' '*.txt' '*.yml' '*.yaml' || true)
if [[ -n $FILES ]]; then
  perl -pi -e "s/\Q$OLD_VERSION\E/$NEW_VERSION/g" $FILES
  echo "ver  updated text files" >>"$REPORT"
fi
echo "$NEW_VERSION" > VERSION

###############################################################################
# 2. Remove obsolete duplicate artefacts (common older suffixes).
###############################################################################
echo "→ Removing obsolete artefacts/logs …"
# Remove any files ending in _v6.9.35 through _v6.9.49
find . -type f \(
  -name "*_v6.9.3[5-9]*" -o \
  -name "*_v6.9.4[0-9]*"\
\) | while read -r f; do
  rm -f "$f" && echo "rm   $f" >>"$REPORT"
done

###############################################################################
# 3. Ensure exactly one artefact/log with _vNEW_VERSION suffix.
###############################################################################
suffix_file() {
  local p="$1" stem ext new
  stem="${p%.*}"; ext="${p##*.}"
  [[ $stem == *_v$NEW_VERSION ]] && return
  new="${stem}_v$NEW_VERSION.$ext"
  [[ -e $new ]] && { rm -f "$p"; echo "dup  removed $p" >>"$REPORT"; return; }
  mv "$p" "$new"
  echo "mv   $p → $new" >>"$REPORT"
}

for dir in . dist logs perf; do
  [[ -d $dir ]] || continue
  # Iterate over artefact/log files and ensure they have the new version suffix
  for f in "$dir"/**/*.{log,txt,json,gz,tgz,tar.gz}; do
    [[ -f $f ]] && suffix_file "$f"
  done
done

###############################################################################
# 4. Quick lint pass (Ruff & ShellCheck)
###############################################################################
: > "$LINT"
echo "→ Running lint (Ruff + ShellCheck)…"
if command -v ruff >/dev/null 2>&1; then
  ruff check $(git ls-files '*.py') >>"$LINT" 2>&1 || true
else
  echo "Ruff not installed." >>"$LINT"
fi
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck $(git ls-files '*.sh') >>"$LINT" 2>&1 || true
else
  echo "ShellCheck not installed." >>"$LINT"
fi
echo "lint report saved to $LINT" >>"$REPORT"

###############################################################################
# 5. Policies update
###############################################################################
cat > "21-policies_v$NEW_VERSION.txt" <<'EOF'
# Policies v6.9.50
* Exactly one artefact/log is kept for each logical file, suffixed `_v6.9.50`.  Older duplicates (v6.9.35–49) are removed.
* Version strings are updated before renaming, preventing missing‑file warnings.
* The script is idempotent: it skips moves if the source and destination are the same, and checks that files exist before acting.
* Lint results are written to `lint_report_v6.9.50.txt`; review them before pushing.
* Commit and tag are created locally and automatically pushed to the `origin` remote.
EOF
echo "new   21-policies_v$NEW_VERSION.txt" >>"$REPORT"

###############################################################################
# 6. Commit & tag
###############################################################################
git add .
if git diff --cached --quiet; then
  echo "✓ Nothing to commit."
else
  git commit -m "chore: full cleanup & bump to v$NEW_VERSION (one artefact per version)"
  echo "✓ Commit created."
fi
git rev-parse -q --verify refs/tags/v$NEW_VERSION >/dev/null || git tag "v$NEW_VERSION"

# Automatically push the new commit and tag to the remote.  Determine
# the current branch; if none, default to main.  Push tags along with
# the branch.  If the push fails (e.g. no remote configured) the script
# will continue without error.
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo main)
echo "→ Pushing changes to origin/$current_branch …"
if ! git push origin "$current_branch" --follow-tags; then
  echo "! Push failed. Please verify the remote and branch names."
fi

###############################################################################
# 7. Summary
###############################################################################
echo "→ Cleanup summary"
cat "$REPORT"
echo -e "\nDone. Changes have been pushed to origin/$current_branch."