#!/bin/bash
# ------------------------------------------------------------------
# run_jama_script.sh
# Cron-friendly: run kpi.py, stage outputs, commit if changed, push main
# Logs appended to /home/rellab/KCE_KPI/cron.log and retained 14 days
# ------------------------------------------------------------------

PROJECT_DIR="/home/rellab/KCE_KPI"
VENV_PY="$PROJECT_DIR/venv/bin/python3"
LOG_FILE="$PROJECT_DIR/cron.log"
SSH_KEY="/home/rellab/.ssh/id_ed25519"
ENV_FILE="$PROJECT_DIR/.env"
BRANCH="main"

{
  echo "============================================================"
  echo "Script started at: $(date '+%Y-%m-%d %H:%M:%S')"

  # Move to project dir
  cd "$PROJECT_DIR" || { echo "❌ Cannot cd to $PROJECT_DIR"; exit 1; }

  # Safety: ensure .env exists (contains client_ID and client_Secrect)
  if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Missing .env file at $ENV_FILE - aborting"
    echo "Please create .env with client_ID and client_Secrect"
    echo "Run aborted at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"
    exit 1
  fi

  # Load environment variables from .env (exported)
  set -a
  source "$ENV_FILE"
  set +a

  # Ensure we are on main and up-to-date
  git fetch origin "$BRANCH" >/dev/null 2>&1
  # If main exists locally, checkout it; otherwise create tracking branch
  if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    git checkout "$BRANCH" >/dev/null 2>&1 || true
  else
    git checkout -b "$BRANCH" origin/"$BRANCH" >/dev/null 2>&1 || git checkout -b "$BRANCH"
  fi
  git pull origin "$BRANCH" --no-rebase >/dev/null 2>&1 || echo "⚠️ git pull warning"

  echo "On branch: $(git rev-parse --abbrev-ref HEAD)"

  # Start ssh agent and add key (key must be passphrase-free or agent should already have it)
  eval "$(ssh-agent -s)" >/dev/null 2>&1
  ssh-add "$SSH_KEY" >/dev/null 2>&1 || echo "⚠️ ssh-add failed (check key or passphrase)"

  # Activate venv python if exists, else fall back to system python3
  if [ -x "$VENV_PY" ]; then
    PYEXEC="$VENV_PY"
  else
    PYEXEC="python3"
    echo "⚠️ Venv python not found; using system python3"
  fi

  # Run the Python script
  if $PYEXEC "$PROJECT_DIR/kpi.py"; then
    echo "✅ Python script finished successfully at: $(date '+%Y-%m-%d %H:%M:%S')"
  else
    echo "❌ Python script failed at: $(date '+%Y-%m-%d %H:%M:%S')"
    # continue to attempt git staging so logs/errors are captured
  fi

  # Show git status before staging (helpful for debugging)
  echo "---- git status (before add) ----"
  git status --short -b

  # Stage everything changed (explicit, catches all outputs)
  git add -A

  echo "---- Staged files (cached) ----"
  git --no-pager diff --cached --name-only || echo "(none staged)"

  # Commit only if there are staged changes
  if git diff --cached --quiet; then
    echo "ℹ️ No changes to commit."
  else
    if git commit -m "Auto update on $(date '+%Y-%m-%d %H:%M:%S')"; then
      echo "✅ Commit created."
      if git push origin "$BRANCH"; then
        echo "✅ Changes pushed to origin/$BRANCH."
      else
        echo "❌ Git push failed (exit $?)."
      fi
    else
      echo "❌ Git commit failed."
    fi
  fi

  # Optional: remove accidental stray file if present
  if [ -f ".......................end.........................." ]; then
    git rm -f ".......................end.........................." >/dev/null 2>&1 || true
    git commit -m "Remove stray file" >/dev/null 2>&1 || true
    git push origin "$BRANCH" >/dev/null 2>&1 || true
    echo "ℹ️ Removed stray file if existed."
  fi

  # Log retention: delete logs older than 14 days (if you create rotated ones)
  # (keeps main cron.log untouched; if you implement rotation, you can adapt this)
  find "$PROJECT_DIR" -type f -name "cron.log.*" -mtime +14 -delete 2>/dev/null

  echo "Run completed at: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "============================================================"
} >> "$LOG_FILE" 2>&1
