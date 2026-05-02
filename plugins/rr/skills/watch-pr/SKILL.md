---
name: watch-pr
description: Use when user wants to monitor a PR until it is ready to merge. Schedules a recurring remote agent that checks CI, reviews, and merge conflicts, then DMs Ricardo on Slack. Stops automatically when action is needed from Ricardo (CI failing, changes requested, needs rebase) or when PR is ready/merged. Only auto-reschedules when waiting on external things (CI running, reviewer).
---

# Watch PR Until Merge-Ready

Monitor a PR continuously. Each run checks CI status, review state, and merge conflicts, then DMs Ricardo on Slack.

**Reschedules only when waiting on external things** (CI running, awaiting reviewer). **Stops immediately when action is needed from Ricardo** (CI failing, changes requested, needs rebase) — re-trigger manually after fixing. Also stops after 48 checks (~24h at 30min default) as a safety TTL.

## When to Activate

- User says "watch PR", "monitor PR", "keep an eye on PR", "notify me when PR is ready"
- User provides a PR number and wants ongoing status updates

## Checklist

```
Watch PR Progress:
- [ ] Step 1: Collect PR number and check interval
- [ ] Step 2: Load config (Slack user ID)
- [ ] Step 3: Craft remote agent prompt
- [ ] Step 4: Schedule first one-time routine via RemoteTrigger
- [ ] Step 5: Confirm to user with routine link
```

---

## Step 1 — Collect inputs

Extract the PR number from the user's message. If not provided, ask:

> "Which PR number do you want to watch?"

Default check interval: **30 minutes**. If user specifies a different interval (e.g. "check every hour"), store it as `check_interval_minutes`.

Default max checks: **48** (~24h at 30min). Store as `max_checks`.

---

## Step 2 — Load config

```bash
CONFIG="$HOME/.claude/skills/standup/config.json"
if [ -f "$CONFIG" ]; then cat "$CONFIG"; fi
```

Extract `slack_user_id` (e.g. `U01XXXXXXXX`) and `github_org` from config. These go into the remote prompt.

If no config exists, ask the user for their Slack user ID directly.

---

## Step 3 — Craft the remote agent prompt

The remote agent must be **completely self-contained** — it starts with zero context. Build the prompt as a literal string substituting real values:

```
You are a PR watch agent. Your job:
1. Check PR #{PR_NUMBER} in repo apolloio/leadgenie for merge-readiness
2. DM the user on Slack with a status update
3. Reschedule yourself ONLY if waiting on external things (CI running, awaiting reviewer)
4. STOP if action is needed from Ricardo, PR is done, or TTL reached

This is check #{CHECK_NUMBER} of {MAX_CHECKS} maximum.

## Step A — Check PR status

Run these in parallel:

```bash
gh pr view {PR_NUMBER} --repo apolloio/leadgenie --json state,mergeable,reviewDecision,title,url,headRefName
```

```bash
gh pr checks {PR_NUMBER} --repo apolloio/leadgenie --json name,status,conclusion 2>/dev/null || echo "[]"
```

Parse results:
- `state`: "MERGED" or "CLOSED" → PR is done
- `mergeable`: "CONFLICTING" → needs rebase (Ricardo must act)
- `reviewDecision`: "REVIEW_REQUIRED" → waiting for reviewer, "CHANGES_REQUESTED" → Ricardo must act, "APPROVED" → approved
- CI checks conclusions: "FAILURE" or "TIMED_OUT" → failing (Ricardo must act); "SUCCESS"/"SKIPPED"/"NEUTRAL" → passing; "IN_PROGRESS"/"QUEUED"/"PENDING" → still running (wait)

## Step B — Classify state

Determine which category applies:

**DONE** (send final message, STOP, do not reschedule):
- `state` is "MERGED" or "CLOSED"

**READY** (send ready message, STOP, do not reschedule):
- `state` is "OPEN"
- `mergeable` is "MERGEABLE"
- `reviewDecision` is "APPROVED" (or null/empty)
- All CI conclusions are "SUCCESS", "SKIPPED", or "NEUTRAL"

**ACTION_NEEDED** (send blocker message, STOP, do not reschedule — Ricardo must fix and re-trigger):
- `mergeable` is "CONFLICTING", OR
- `reviewDecision` is "CHANGES_REQUESTED", OR
- Any CI conclusion is "FAILURE" or "TIMED_OUT"

**TTL_EXCEEDED** (send expiry message, STOP, do not reschedule):
- {CHECK_NUMBER} >= {MAX_CHECKS}

**WAITING** (send status message, reschedule):
- None of the above — CI still running and/or awaiting reviewer with no blockers

## Step C — Send Slack DM

Use the Slack MCP tool `mcp__claude_ai_Slack__slack_send_message` to DM user `{SLACK_USER_ID}`.

**If DONE:**
```
🎉 PR #{PR_NUMBER} ({STATE}): {PR_TITLE}
{PR_URL}

PR is {STATE}. Watch stopped.
```

**If READY:**
```
✅ PR #{PR_NUMBER} is ready to merge!
{PR_TITLE}
{PR_URL}

All checks passed, review approved, no conflicts. Ship it!
```

**If ACTION_NEEDED:**
```
🛑 PR #{PR_NUMBER}: {PR_TITLE}
{PR_URL}

Needs your attention (watch stopped):
```
Then append each blocker on its own line:
- `mergeable == "CONFLICTING"` → `• ⚠️ Needs rebase — conflicts with master`
- `reviewDecision == "CHANGES_REQUESTED"` → `• 🔄 Changes requested — address reviewer feedback`
- Any CI failing → `• ❌ Failing checks: {comma-separated failing check names}`

End with:
```

Fix and re-trigger the watch when ready.
```

**If TTL_EXCEEDED:**
```
⏰ PR #{PR_NUMBER}: {PR_TITLE}
{PR_URL}

Watch expired after {MAX_CHECKS} checks (~{HOURS}h). Re-trigger if still needed.
```
(compute HOURS = MAX_CHECKS * CHECK_INTERVAL_MINUTES / 60)

**If WAITING:**
```
👀 PR #{PR_NUMBER}: {PR_TITLE}
{PR_URL}

Still waiting (check {CHECK_NUMBER}/{MAX_CHECKS}):
```
Then append each pending item:
- Any CI still running → `• ⏳ Checks running: {comma-separated pending check names}`
- `reviewDecision == "REVIEW_REQUIRED"` AND CI passing → `• 👥 Waiting for reviewer`

End with:
```

Next check in {CHECK_INTERVAL_MINUTES} minutes.
```

## Step D — Reschedule (ONLY if WAITING)

If state is NOT WAITING, do not reschedule. Stop.

If WAITING, use the `RemoteTrigger` tool with action "create" and a `run_once_at` timestamp set to NOW + {CHECK_INTERVAL_MINUTES} minutes (UTC, RFC3339 format). Get current time first:

```bash
date -u +%Y-%m-%dT%H:%M:%SZ
```

Add {CHECK_INTERVAL_MINUTES} minutes to that timestamp for `run_once_at`.

**Important:** In the recursive prompt, replace `{CHECK_NUMBER}` with the current check number + 1 (e.g. if this is check 3, next prompt has CHECK_NUMBER = 4).

Use this exact body structure:
- name: "watch-pr-{PR_NUMBER}"
- run_once_at: <computed timestamp>
- environment_id: "env_012Cc5A75FHp243UFQL6supn"
- model: "claude-sonnet-4-6"
- sources: [{"git_repository": {"url": "https://github.com/apolloio/leadgenie"}}]
- allowed_tools: ["Bash", "Read"]
- mcp_connections: [{"connector_uuid": "857a67c2-5807-4c7c-ab11-4603f6a4f3d2", "name": "Slack", "url": "https://mcp.slack.com/mcp"}]
- events[0].data.message.content: (this exact same prompt with CHECK_NUMBER incremented)

Generate a fresh lowercase UUID v4 for events[0].data.uuid.
```

Substitute real values before saving the prompt:
- `{PR_NUMBER}` → actual PR number (e.g. `12345`)
- `{PR_TITLE}` → fetch now: `gh pr view {PR_NUMBER} --repo apolloio/leadgenie --json title --jq .title`
- `{PR_URL}` → fetch now: `gh pr view {PR_NUMBER} --repo apolloio/leadgenie --json url --jq .url`
- `{SLACK_USER_ID}` → from config (e.g. `U01XXXXXXXX`)
- `{CHECK_INTERVAL_MINUTES}` → from Step 1 (default `30`)
- `{CHECK_NUMBER}` → `1` (first run; increments in each recursive prompt)
- `{MAX_CHECKS}` → from Step 1 (default `48`)
- `{STATE}` → filled in at runtime by the remote agent
- `{HOURS}` → filled in at runtime by the remote agent

---

## Step 4 — Schedule via RemoteTrigger

First load the tool:

```
ToolSearch: select:RemoteTrigger
```

Get the current UTC time:
```bash
date -u +%Y-%m-%dT%H:%M:%SZ
```

Set `run_once_at` to **2 minutes from now** (first check fires almost immediately).

Call `RemoteTrigger` with:
```json
{
  "action": "create",
  "body": {
    "name": "watch-pr-{PR_NUMBER}",
    "run_once_at": "<2 minutes from now in UTC>",
    "enabled": true,
    "job_config": {
      "ccr": {
        "environment_id": "env_012Cc5A75FHp243UFQL6supn",
        "session_context": {
          "model": "claude-sonnet-4-6",
          "sources": [
            {"git_repository": {"url": "https://github.com/apolloio/leadgenie"}}
          ],
          "allowed_tools": ["Bash", "Read"],
          "mcp_connections": [
            {
              "connector_uuid": "857a67c2-5807-4c7c-ab11-4603f6a4f3d2",
              "name": "Slack",
              "url": "https://mcp.slack.com/mcp"
            }
          ]
        },
        "events": [
          {
            "data": {
              "uuid": "<fresh lowercase uuid v4>",
              "session_id": "",
              "type": "user",
              "parent_tool_use_id": null,
              "message": {
                "role": "user",
                "content": "<the fully substituted prompt from Step 3>"
              }
            }
          }
        ]
      }
    }
  }
}
```

---

## Step 5 — Confirm to user

Show:
```
Watching PR #{PR_NUMBER}: {PR_TITLE}
First check in ~2 minutes, then every {CHECK_INTERVAL_MINUTES} min (max {MAX_CHECKS} checks).
Stops automatically if CI fails, rebase needed, or changes requested — re-trigger after fixing.
Routine: https://claude.ai/code/routines/{ROUTINE_ID}
```

---

## Notes

- **Stop conditions:** merged/closed, ready to merge, ACTION_NEEDED (ball in Ricardo's court), TTL exceeded
- **Reschedule condition:** WAITING only — CI running or awaiting reviewer with no blockers
- The `{CHECK_NUMBER}` counter increments in each recursive prompt; prevents infinite loops via TTL
- To cancel early: https://claude.ai/code/routines and disable the routine
- The Slack MCP connector is required. If `mcp__claude_ai_Slack__slack_send_message` fails, the check still completes (reschedule still happens if WAITING)
