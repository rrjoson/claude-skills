---
name: watch-pr
description: Use when user wants to monitor a PR until it is ready to merge. Schedules a recurring remote agent that checks CI, reviews, and merge conflicts, then DMs Ricardo on Slack with next steps. Reschedules itself until the PR is merged or closed.
---

# Watch PR Until Merge-Ready

Monitor a PR continuously. Each run checks CI status, review state, and merge conflicts, then DMs Ricardo on Slack. If not yet ready, schedules the next check automatically.

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
3. If not yet ready, schedule yourself again in {CHECK_INTERVAL_MINUTES} minutes

## Step A — Check PR status

Run these in parallel:

```bash
gh pr view {PR_NUMBER} --repo apolloio/leadgenie --json state,mergeable,reviewDecision,title,url,headRefName
```

```bash
gh pr checks {PR_NUMBER} --repo apolloio/leadgenie --json name,status,conclusion 2>/dev/null || echo "[]"
```

Parse results:
- `state`: if "MERGED" or "CLOSED" → PR is done, send final Slack message and STOP (do not reschedule)
- `mergeable`: "CONFLICTING" → needs rebase
- `reviewDecision`: "REVIEW_REQUIRED" → needs review, "CHANGES_REQUESTED" → has requested changes, "APPROVED" → approved
- CI checks: any with conclusion "FAILURE" or "TIMED_OUT" → failing tests; all "SUCCESS" or "SKIPPED" or "NEUTRAL" → CI passing; any "IN_PROGRESS" or "QUEUED" or "PENDING" → still running

## Step B — Determine readiness

PR is merge-ready if ALL are true:
- `state` is "OPEN"
- `mergeable` is "MERGEABLE" (not "CONFLICTING" or "UNKNOWN")
- `reviewDecision` is "APPROVED" (or null/empty and no review required)
- All CI checks have conclusion "SUCCESS", "SKIPPED", or "NEUTRAL" (none failing, none pending)

## Step C — Send Slack DM

Use the Slack MCP tool `mcp__claude_ai_Slack__slack_send_message` to DM user `{SLACK_USER_ID}`.

**If merge-ready:**
```
✅ PR #{PR_NUMBER} is ready to merge!
{PR_TITLE}
{PR_URL}

All checks passed, review approved, no conflicts. Ship it!
```
Then STOP — do not reschedule.

**If merged or closed:**
```
🎉 PR #{PR_NUMBER} ({STATE}): {PR_TITLE}
{PR_URL}

Stopping watch — PR is {STATE}.
```
Then STOP — do not reschedule.

**If not ready, compose a message listing blockers:**

Start with:
```
👀 PR #{PR_NUMBER}: {PR_TITLE}
{PR_URL}

Not yet ready:
```

Then append each blocker on its own line:
- `mergeable == "CONFLICTING"` → `• ⚠️ Needs rebase — conflicts with master`
- `reviewDecision == "REVIEW_REQUIRED"` → `• 👥 Waiting for review`
- `reviewDecision == "CHANGES_REQUESTED"` → `• 🔄 Changes requested — address reviewer feedback`
- Any CI failing → `• ❌ Failing checks: {comma-separated failing check names}`
- Any CI still running → `• ⏳ Checks still running: {comma-separated pending check names}`

End with:
```
Next check in {CHECK_INTERVAL_MINUTES} minutes.
```

Send this DM.

## Step D — Reschedule (only if PR is still open and not ready)

Use the `RemoteTrigger` tool with action "create" and a `run_once_at` timestamp set to NOW + {CHECK_INTERVAL_MINUTES} minutes (UTC, RFC3339 format). Get current time first:

```bash
date -u +%Y-%m-%dT%H:%M:%SZ
```

Add {CHECK_INTERVAL_MINUTES} minutes to that timestamp for `run_once_at`.

Use this exact body structure:
- name: "watch-pr-{PR_NUMBER}"
- run_once_at: <computed timestamp>
- environment_id: "env_012Cc5A75FHp243UFQL6supn"
- model: "claude-sonnet-4-6"
- sources: [{"git_repository": {"url": "https://github.com/apolloio/leadgenie"}}]
- allowed_tools: ["Bash", "Read"]
- mcp_connections: [{"connector_uuid": "857a67c2-5807-4c7c-ab11-4603f6a4f3d2", "name": "Slack", "url": "https://mcp.slack.com/mcp"}]
- events[0].data.message.content: (this exact same prompt, verbatim)

Generate a fresh lowercase UUID v4 for events[0].data.uuid.
```

Substitute real values before saving the prompt:
- `{PR_NUMBER}` → actual PR number (e.g. `12345`)
- `{PR_TITLE}` → fetch now: `gh pr view {PR_NUMBER} --repo apolloio/leadgenie --json title --jq .title`
- `{PR_URL}` → fetch now: `gh pr view {PR_NUMBER} --repo apolloio/leadgenie --json url --jq .url`
- `{SLACK_USER_ID}` → from config (e.g. `U01XXXXXXXX`)
- `{CHECK_INTERVAL_MINUTES}` → from Step 1 (default `30`)
- `{STATE}` → filled in at runtime by the remote agent

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
First check in ~2 minutes, then every {CHECK_INTERVAL_MINUTES} min.
Routine: https://claude.ai/code/routines/{ROUTINE_ID}
```

---

## Notes

- The remote agent uses `RemoteTrigger` to reschedule itself — this is the recursive polling mechanism. Each agent instance creates the next one.
- The routine auto-stops when the PR is merged, closed, or ready — no cleanup needed.
- To cancel early: https://claude.ai/code/routines and disable the routine.
- The Slack MCP connector is required. If `mcp__claude_ai_Slack__slack_send_message` fails, the check still completes (reschedule still happens).
