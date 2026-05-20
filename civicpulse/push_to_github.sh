#!/usr/bin/env bash
# ============================================================
# CivicPulse – GitHub Setup Script
#
# Usage:
#   1. Create a new EMPTY repo on GitHub named "civicpulse"
#      (no README, no .gitignore — keep it blank)
#   2. Run: bash push_to_github.sh YOUR_GITHUB_USERNAME
# ============================================================

set -e

GITHUB_USER="${1:?Usage: bash push_to_github.sh <github_username>}"
REPO_NAME="civicpulse"
REMOTE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

echo ""
echo "=================================================="
echo "  CivicPulse → GitHub"
echo "  Remote: ${REMOTE_URL}"
echo "=================================================="
echo ""

# Init git
git init
git add .
git commit -m "feat: initial commit – CivicPulse political data pipeline

- Relational schema: Voters, Precincts, Candidates, Elections,
  Donations, ElectionResults (SQL Server + PostgreSQL compatible)
- 6 T-SQL stored procedures: donor summaries, voter turnout,
  top donors, funding breakdown, refresh aggregates, DQ validation
- 3 reporting views: DonorActivity, ElectionResultsSummary,
  VoterRegistrationSummary
- Python ETL: synthetic data generator (Faker) + bulk loader
- Pipeline audit logging with TRY/CATCH error handling"

# Push
git branch -M main
git remote add origin "${REMOTE_URL}"
echo ""
echo "Pushing to GitHub (you may be prompted for credentials)..."
git push -u origin main

echo ""
echo "✓  Done! Visit: https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo ""
