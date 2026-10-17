#!/data/data/com.termux/files/usr/bin/bash
#
# AI CLI Environment & Provider Configuration Helper
# Sets up environment variables and helper commands for:
#   - Google Antigravity CLI (agy)
#   - OpenCode CLI (opencode)
#   - OpenAI Codex CLI (codex)
#   - Google Gemini CLI (gemini)
#   - GitHub Copilot CLI (copilot)
#

set -Eeuo pipefail

ENV_FILE="${HOME}/.ai-env"
RC_FILE="${HOME}/.zshrc"

GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
YELLOW=$'\033[1;33m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()    { printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"; }
success() { printf '%s[SUCCESS]%s %s\n' "$GREEN" "$NC" "$*"; }
warn()    { printf '%s[WARNING]%s %s\n' "$YELLOW" "$NC" "$*"; }

if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" <<'EOF'
# ========================================================
# AI CLI Environment Variables & API Keys
# ========================================================
# Keep your API keys private. Never commit this file to git.

# Google Gemini API
# export GEMINI_API_KEY=""

# OpenAI API (for Codex / OpenCode / third-party tools)
# export OPENAI_API_KEY=""

# Anthropic API (for OpenCode Claude integrations)
# export ANTHROPIC_API_KEY=""

# OpenRouter API (for multi-model access in OpenCode)
# export OPENROUTER_API_KEY=""

# GitHub Personal Access Token (if not using browser OAuth)
# export GITHUB_TOKEN=""

EOF
    chmod 600 "$ENV_FILE"
    success "Created private AI environment template: $ENV_FILE"
else
    info "AI environment configuration already exists at $ENV_FILE"
fi

# Ensure ~/.ai-env is sourced in ~/.zshrc
if [[ -f "$RC_FILE" ]]; then
    if ! grep -qF 'source "$HOME/.ai-env"' "$RC_FILE"; then
        printf '\n# Load AI environment configuration\n[[ -f "$HOME/.ai-env" ]] && source "$HOME/.ai-env"\n' >> "$RC_FILE"
        success "Integrated $ENV_FILE into $RC_FILE"
    fi
fi

# Also check ~/.bashrc
if [[ -f "$HOME/.bashrc" ]]; then
    if ! grep -qF 'source "$HOME/.ai-env"' "$HOME/.bashrc"; then
        printf '\n# Load AI environment configuration\n[[ -f "$HOME/.ai-env" ]] && source "$HOME/.ai-env"\n' >> "$HOME/.bashrc"
        success "Integrated $ENV_FILE into ~/.bashrc"
    fi
fi

printf '\n%s=== AI CLI Quick Reference & Auth Instructions ===%s\n\n' "$BOLD$GREEN" "$NC"
printf '1. %sGoogle Antigravity CLI%s:\n' "$BOLD" "$NC"
printf '   Run: %sagy%s (Authenticates via your Google developer account)\n\n' "$YELLOW" "$NC"

printf '2. %sOpenCode AI Assistant%s:\n' "$BOLD" "$NC"
printf '   Run: %sopencode%s\n' "$YELLOW" "$NC"
printf '   Config: ~/.config/opencode/ (Set your preferred model and API key)\n\n'

printf '3. %sOpenAI Codex CLI%s:\n' "$BOLD" "$NC"
printf '   Run: %scodex login%s or export %sOPENAI_API_KEY%s in %s~/.ai-env%s\n\n' "$YELLOW" "$NC" "$BOLD" "$NC" "$YELLOW" "$NC"

printf '4. %sGoogle Gemini CLI%s:\n' "$BOLD" "$NC"
printf '   Run: %sgemini%s (Interactive prompt) or set %sGEMINI_API_KEY%s in %s~/.ai-env%s\n\n' "$YELLOW" "$NC" "$BOLD" "$NC" "$YELLOW" "$NC"

printf '5. %sGitHub Copilot CLI%s:\n' "$BOLD" "$NC"
printf '   Run: %scopilot%s and authenticate with GitHub via browser/device code\n\n' "$YELLOW" "$NC"

printf '%s=== Credential Security & Encrypted Backup ===%s\n\n' "$BOLD$CYAN" "$NC"
printf 'Your credentials in %s are protected with 0600 permissions.\n' "$ENV_FILE"
printf 'To create a password-encrypted backup before wiping or migrating devices:\n'
printf '  %sgpg --symmetric --cipher-algo AES256 %s%s\n' "$YELLOW" "$ENV_FILE" "$NC"
printf 'To restore on a new device:\n'
printf '  %sgpg --decrypt %s.gpg > %s && chmod 600 %s%s\n\n' "$YELLOW" "$ENV_FILE" "$ENV_FILE" "$ENV_FILE" "$NC"
