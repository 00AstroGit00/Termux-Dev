---
name: termux-security-audit
description: Use when auditing scripts, environment files, dependencies, file permissions, or code changes for security vulnerabilities, hardcoded secrets, or Android Termux compatibility risks.
---

# Termux Security & Compatibility Audit Runbook

## Objective
Ensure code, configuration, scripts, and runtime commands adhere to strict security boundaries and Android Termux constraints.

## Procedures

### 1. Secret & Credential Scanning
- Search for leaked API tokens, passwords, private keys, or webhook URLs:
  - Check files against patterns: `_API_KEY`, `_TOKEN`, `BEGIN OPENSSH PRIVATE KEY`, `ghp_`, `sk-`.
  - Ensure private environment variables reside strictly in `~/.ai-env` with `chmod 600`.
  - Validate that `.gitignore` contains `.env*`, `*.key`, and credential stores.
- **Redaction Mandate**: NEVER print or echo detected secret values, tokens, or private keys to stdout, terminal logs, or generated documentation. Report solely the affected file path, line number, credential classification, and remediation instructions.

### 2. Path & Sandbox Verification
- Termux binaries and scripts must use `$PREFIX` (`/data/data/com.termux/files/usr`), never hardcoded `/usr` or `/bin`.
- Ensure scripts have executable permissions (`chmod 755`) and valid Termux shebangs (`#!/data/data/com.termux/files/usr/bin/...`).

### 3. Destructive Operation Guardrails
- Reject broad wildcard deletions (`rm -rf *`, `rm -rf /`).
- Protect configuration directories (`~/.config`, `~/.gemini`, `~/.codex`, `~/.copilot`).
- Preserve non-interfering user configurations, formatting, and docstrings during edits.
