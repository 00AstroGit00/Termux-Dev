---
name: termux-git-review
description: Use when reviewing Git status, generating clean diffs, inspecting branch changes, or preparing safe commits and pull requests in Termux repositories.
---

# Termux Git Workflow & Code Review Runbook

## Objective
Provide clean, concise, and non-destructive Git inspection and review workflows within Android Termux environments.

## Procedures

### 1. Repository Inspection & Worktree Preservation
Before any modification, inspect the working tree:
```bash
git status --short --branch
git diff --stat
```
- **Context Preservation**: Never execute destructive repository resets (`git reset --hard`, `git restore .`, `git checkout -- .`) or indiscriminate cleaning (`git clean -fd`) that discard uncommitted, unstaged, or staged user changes.

### 2. Targeted Change Analysis
- Inspect exact changes line-by-line: `git diff`
- Inspect staged changes: `git diff --staged`
- Verify untracked files: ensure sensitive tokens, `.env`, or build artifacts are ignored by `.gitignore`.

### 3. Verification Before Commit
- Verify all modified files compile and pass syntax checks.
- Check line endings and whitespace hygiene.
- Never use `git add .` or `git add -A` blindly; stage only modified and tested files intentionally.

### 4. Safe Commit Discipline
- Write structured commit messages explaining the problem, solution, and rationale.
- Never amend pushed commits on shared branches or force-push without explicit permission.
