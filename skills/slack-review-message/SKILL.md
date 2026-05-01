---
name: slack-review-message
description: Draft a short Slack message asking for PR review. Activate when user says "slack message", "review message", "ask for review", or "draft review request".
---

# Slack Review Message

Draft a concise Slack message requesting a code review.

## When to Activate

- User says "slack message", "review message", "ask for review"
- User wants to share a PR in Slack for review

## Instructions

### 1. Gather Context

**Priority order:**
1. **Conversation first** — extract PR URL, Jira ticket, and description from the current conversation (what was just built, reviewed, or discussed). Use conversation context to write a richer `description` line than the PR title alone.
2. **Git fallback** — only if no PR is mentioned in conversation: `gh pr list --head $(git branch --show-current) --json url,title --jq '.[0]'`
3. **Ask** — if still missing after both: PR link, Jira ticket, who to cc

### 2. Output Format

Output plain text (no markdown blockquotes, no `>` prefixes) that can be directly pasted into Slack:

```
for review: https://github.com/apolloio/leadgenie/pull/XXXXX
description: One-line summary of what this does and why
closes: TICKET-###
cc @name
```

### Rules

- **Plain text only** -- no blockquotes, no code fences around the output
- **Raw GitHub URL** -- use the full URL as plain text, not markdown link syntax
- **description line** -- prefix with `description:`, keep to a single sentence, focus on what and why
- **cc line** -- include if the user mentions reviewers, omit if not provided
- **closes line** -- use the Jira ticket from the branch name or conversation
