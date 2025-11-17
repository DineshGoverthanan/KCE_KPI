#!/bin/bash
# ------------------------------------------------------------------
# Jama KPI Auto Script - Cron-friendly (stages real outputs + pushes current branch)
# ------------------------------------------------------------------

PROJECT_DIR="/home/rellab/KCE_KPI"
PYTHON_BIN="$PROJECT_DIR/venv/bin/python3"
LOG_FILE="$PROJECT_DIR/cron.log"
SSH_KEY="/home/rellab/.ssh/id_ed25519"
ENV_FILE="$PROJECT_DIR/.env"
BRANCH="KCE_KPI_Server"   # branch to push (use the branch you're actively working on)

{
  echo "------------------------------------------------------------"
  echo "Script started at: $(date '+%Y-%m-%d %H:%M:%S')"

  cd "$PROJECT_DIR" || { echo "❌ Cannot cd to $PROJECT_DIR"; exit 1; }

  # ensure correct branch
  git fetch origin "$BRANCH" >/dev/null 2>&1
  git checkout "$BRANCH" >/dev/null 2>&1 || git checkout -b "$BRANCH" origin/"$BRANCH" >/dev/null 2>&1
  echo "On branch: $(git rev-parse --abbrev-ref HEAD)"

  # load env (if present)
  if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
  fi

  # start ssh-agent for push
  eval "$(ssh-agent -s)" >/dev/null 2>&1
  ssh-add "$SSH_KEY" >/dev/null 2>&1

  # run the python script (use venv python if available)
  if [ -x "$PYTHON_BIN" ]; then
    PYEXEC="$PYTHON_BIN"
  else
    PYEXEC="python3"
  fi

  if $PYEXEC "$PROJECT_DIR/kpi.py"; then
    echo "✅ Script completed successfully at: $(date '+%Y-%m-%d %H:%M:%S')"
  else
    echo "❌ Script FAILED at: $(date '+%Y-%m-%d %H:%M:%S')"
  fi

  # Stage actual outputs: use -A to include modified & new files
  echo "Git status before add:"
  git status --short -b

  git add -A
  echo "Staged files (cached):"
  git --no-pager diff --cached --name-only || true

  # Commit & push only if staged changes exist
  if git diff --cached --quiet; then
    echo "ℹ️ No changes to commit."
  else
    git commit -m "Auto update on $(date '+%Y-%m-%d %H:%M:%S')" || echo "⚠️ Commit failed"
    # push current branch
    CURBR="$(git rev-parse --abbrev-ref HEAD)"
    if git push origin "$CURBR"; then
      echo "✅ Pushed branch $CURBR to origin."
    else
      echo "❌ Push failed for branch $CURBR."
    fi
  fi

  # Log retention: keep cron.log for 14 days (rotate if you use multiple log files)
  find "$PROJECT_DIR" -type f -name "cron.log*" -mtime +14 -delete 2>/dev/null

  echo "Run completed at: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "============================================================"
} >> "$LOG_FILE" 2>&1
