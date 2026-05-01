---
name: fix-coderabbit-comments
description: Automatically fixes CodeRabbit review comments on the current branch's PR. For each actionable comment, applies the fix, replies to the comment with what was done, then commits and pushes all changes.
---

# Fix CodeRabbit Comments

## When to Activate

- Called automatically by the PostToolUse hook after a `git push`
- User says "fix CodeRabbit comments", "address CodeRabbit", or "fix review bot comments"

## Progress

```
Fix CodeRabbit Comments:
- [ ] Step 1: PR identified for current branch
- [ ] Step 2: CodeRabbit comments fetched and triaged
- [ ] Step 3: Fixes applied per comment
- [ ] Step 4: Replies posted to each comment
- [ ] Step 5: Changes committed and pushed
```

---

## Step 1 — Identify the PR

```bash
gh pr list --head <branch> --json number,url,headRefName --jq '.[0]'
```

If no PR exists for this branch, stop silently with no output.

---

## Step 2 — Fetch and Triage CodeRabbit Comments

```bash
gh api repos/apolloio/leadgenie/pulls/<pr_number>/comments \
  --jq '[.[] | select(.user.login == "coderabbitai[bot]") | {id: .id, path: .path, line: .original_line, body: .body, in_reply_to_id: .in_reply_to_id}]'
```

Only process **top-level** comments (those without `in_reply_to_id`).

Skip comments where:
- Body contains "nitpick" or "suggestion" combined with no clear actionable change
- Body already contains a reply from a human (check via `gh api repos/apolloio/leadgenie/pulls/<pr_number>/comments --jq '[.[] | select(.in_reply_to_id == <id>)]'`)
- The file path no longer exists in the repo

For each actionable comment, record: `id`, `path`, `line`, and the requested change.

---

## Step 3 — Apply Fixes

For each actionable comment:

1. Read the file at `path`
2. Understand the change requested in the comment body
3. Apply the minimal fix — do not refactor surrounding code
4. Categorize the outcome:
   - `fixed` — change applied successfully
   - `already_resolved` — code already matches the request
   - `cannot_apply` — change is ambiguous, risky, or requires context not available (state reason)

Keep a log: `[{comment_id, path, outcome, reason}]`

---

## Step 4 — Reply to Each Comment

For every processed comment (fixed, already resolved, or cannot apply), post a reply:

```bash
gh api repos/apolloio/leadgenie/pulls/comments/<comment_id>/replies \
  -X POST \
  -f body="<reply>"
```

Reply templates:

- **fixed**: `"Fixed — <one sentence describing the change made>."`
- **already_resolved**: `"Already resolved — <one sentence explaining why the code already satisfies this>."`
- **cannot_apply**: `"Skipped — <reason: ambiguous/out of scope/requires broader refactor>."`

---

## Step 5 — Commit and Push

If any fixes were applied:

```bash
git add -p  # stage only changed files, not everything
git commit -m "Address CodeRabbit review comments"
git push
```

If nothing was fixed (all already_resolved or cannot_apply), do not create an empty commit.
