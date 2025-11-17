#!/bin/bash
# ------------------------------------------------------------------
# Jama KPI Auto Script - Server Cron Version
# Logs activity, updates data files, and pushes to GitHub securely.
# ------------------------------------------------------------------

PROJECT_DIR="/home/rellab/KCE_KPI"
PYTHON_ENV="$PROJECT_DIR/venv/bin/python3"
LOG_FILE="$PROJECT_DIR/cron.log"
SSH_KEY="/home/rellab/.ssh/id_ed25519"
ENV_FILE="$PROJECT_DIR/.env"

{
echo "------------------------------------------------------------"
echo "Script started at: $(date '+%Y-%m-%d %H:%M:%S')"

# --- Safety check for required files ---
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Missing .env file at $ENV_FILE"
    echo "Aborting run..."
    echo "------------------------------------------------------------"
    exit 1
fi

# --- Load Jama credentials ---
set -a
source "$ENV_FILE"
set +a

# --- Start SSH agent for Git push ---
eval "$(ssh-agent -s)" >/dev/null 2>&1
ssh-add "$SSH_KEY" >/dev/null 2>&1

# --- Activate Python virtual environment ---
if [ -f "$PROJECT_DIR/venv/bin/activate" ]; then
    source "$PROJECT_DIR/venv/bin/activate"
else
    echo "⚠️  Virtual environment not found. Creating new one..."
    python3 -m venv "$PROJECT_DIR/venv"
    source "$PROJECT_DIR/venv/bin/activate"
    pip install --upgrade pip
    pip install pandas py-jama-rest-client
fi

# --- Move to project folder ---
cd "$PROJECT_DIR" || { echo "❌ Failed to cd to $PROJECT_DIR"; exit 1; }

# --- Pull latest changes from GitHub ---
git pull origin main

# --- Run Python script ---
if $PYTHON_ENV "$PROJECT_DIR/kpi.py"; then
    echo "✅ Script completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
else
    echo "❌ Script failed at $(date '+%Y-%m-%d %H:%M:%S')"
fi

# --- Stage data files for commit ---
git add kp_data.csv defect_data.csv testrun_data.json

# --- Commit & push only if changes exist ---
if git diff --cached --quiet; then
    echo "ℹ️ No changes to commit."
else
    git commit -m "Auto update on $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1
    if git push origin main; then
        echo "✅ Changes pushed successfully."
    else
        echo "❌ Git push failed."
    fi
fi

# --- Cleanup old logs (older than 14 days) ---
find "$PROJECT_DIR" -type f -name "cron.log*" -mtime +14 -delete 2>/dev/null

echo "Run completed at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
} >> "$LOG_FILE" 2>&1
