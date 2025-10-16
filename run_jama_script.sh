#!/bin/bash
# Run Jama API script and push generated files to GitHub

# Go to project directory
cd /home/rellab/KCE_KPI || exit

# Start SSH agent (needed for cron)
eval "$(ssh-agent -s)"
ssh-add /home/rellab/.ssh/id_rsa   # Replace with your private key path

# Activate Python virtual environment
source venv/bin/activate

# Install/update dependencies (optional)
pip install --upgrade pip
pip install pandas py-jama-rest-client

# Pull latest changes from repo
git pull origin main

# Run Python script
python3 kpi.py

# Stage the generated files
git add kp_data.csv defect_data.csv testrun_data.json

# Commit changes if there are any
git commit -m "Auto update KPI & defect data" || echo "No changes to commit"

# Push changes via SSH
git push origin main

# Log the run
echo "Run completed at $(date)" >> cron.log
