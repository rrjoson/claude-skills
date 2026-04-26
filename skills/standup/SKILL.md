---
name: standup
description: Generates and posts a daily standup to a Slack channel. Fetches GitHub PRs (using Events API for zero lag), Zoom/Notion meeting action items, Google Calendar events, and previous standup items. Use when user runs /standup or asks to generate a standup. Supports /standup test to DM a preview instead of posting.
---

# Daily Standup Generator

Generate a daily standup interactively. Follow this flow exactly, step by step.

Copy this checklist and check off steps as you complete them:

```
Standup Progress:
- [ ] Step 0: Load config (or run first-time setup)
- [ ] Step 1: Fetch (Slack + Calendar + GitHub + Zoom + Notion) in parallel
- [ ] Step 2: Show numbered question block, wait for reply
- [ ] Step 3: Parse numbered annotations + free text
- [ ] Step 4: Enrich remaining ticket/PR titles
- [ ] Step 5: Categorize and infer Last/Next 24h
- [ ] Step 6: Compose standup in Slack mrkdwn format
- [ ] Step 7: Show preview, get approval (revise if needed)
- [ ] Step 8: Send to Slack
```

---

## STEP 0 — Load config (or run first-time setup)

Run this Bash block to load or initialize config:

```bash
CONFIG="$HOME/.claude/skills/standup/config.json"
if [ -f "$CONFIG" ]; then
  cat "$CONFIG"
else
  echo "NO_CONFIG"
fi
```

**If config exists:** parse and store all fields. Proceed to Step 1.

**If `NO_CONFIG`:** Run first-time setup:

1. Ask: **"What's your work email?"**
2. Derive `slack_display_name` = email prefix before `@`, capitalized (e.g. `brian@company.com` → `Brian`)
3. Auto-detect timezone:
   ```bash
   readlink /etc/localtime | sed 's|.*/zoneinfo/||'
   ```
   Show result. Ask: **"Your timezone looks like `[detected]` — is that right? (y/n)"**
   If no, ask user to type their IANA timezone (e.g. `America/New_York`, `Asia/Manila`).
4. Auto-detect GitHub login:
   ```bash
   gh api /user --jq .login 2>/dev/null
   ```
5. Look up Slack user ID via `mcp__claude_ai_Slack__slack_search_users` with the email. Extract `id` field.
6. Ask: **"What's the Slack channel ID for your standup channel?"** (user can find this in Slack → right-click channel → View channel details → scroll to bottom)
7. Ask: **"What's your Jira base URL?"** (e.g. `yourorg.atlassian.net`)
8. Ask: **"What's your GitHub org?"** (e.g. `myorg`)
9. Write config:
   ```bash
   cat > "$HOME/.claude/skills/standup/config.json" << EOF
   {
     "email": "[EMAIL]",
     "timezone": "[TIMEZONE]",
     "github_login": "[GH_LOGIN]",
     "github_org": "[GH_ORG]",
     "slack_display_name": "[DISPLAY_NAME]",
     "slack_user_id": "[SLACK_USER_ID]",
     "standup_channel_id": "[STANDUP_CHANNEL_ID]",
     "jira_base_url": "[JIRA_BASE_URL]",
     "first_run_complete": false
   }
   EOF
   ```
10. Say: **"Setup complete! Generating your first standup preview..."**
11. Continue to Step 1. After Step 8, set `first_run_complete: true` in config.

**Config shape** (reference for all steps below):
```json
{
  "email": "you@company.com",
  "timezone": "Asia/Manila",
  "github_login": "yourhandle",
  "github_org": "myorg",
  "slack_display_name": "YourName",
  "slack_user_id": "U01XXXXXXXX",
  "standup_channel_id": "C01XXXXXXXX",
  "jira_base_url": "yourorg.atlassian.net",
  "first_run_complete": false
}
```

**Test mode detection:** If the user ran `/standup test`, set `test_mode = true`. This affects Step 8.

---

## STEP 1 — Fetch everything in parallel

Run ALL of these simultaneously (Slack MCP calls + Bash for GitHub):

**A. Previous standup:**
Use `mcp__claude_ai_Slack__slack_search_public_and_private` with query: `from:@{config.slack_display_name} in:[your-standup-channel-name]`
- sort: timestamp desc, limit: 1
- Use `{config.standup_channel_id}` when filtering by channel
- Convert all Slack link syntax `<url|text>` → markdown `[text](url)` for display in conversation
- Extract individual `◦` bullet items from the **Next 24h** section only
- For each bullet, parse the Slack link: `<url|display_text>` → store `{ text: display_text, url: url }`
  - If `display_text` is a full title (not just a Jira key), use it directly — **no Jira fetch needed**
  - If `display_text` is a bare Jira key, show it as-is
- Store as the "previous items" list: `[{ action_verb, title, url }]` parsed from each bullet

**B. Google Calendar meetings (if Google Calendar MCP available):**
Make two `mcp__claude_ai_Google_Calendar__list_events` calls (calendarId: `{config.email}`, timeZone: `{config.timezone}`, orderBy: `startTime`, eventTypeFilter: `["default"]`):
- Past 24h: startTime = (now - 24h), endTime = now
- Next 24h: startTime = now, endTime = (now + 24h)

Filter rules — KEEP an event only if ALL are true:
1. Has `attendees` array with at least one attendee whose email ≠ `{config.email}`
2. User's attendee entry does NOT have `responseStatus: "declined"`
3. Summary does NOT match time-block patterns (non-working hours, working hours, dinner, lunch, sleep, gym, workout)
4. Not all-day with only the user as attendee

EXCEPTION: Always keep events where organizer email contains your company domain and summary contains "All Hands", "Town Hall", or "All-Hands".

For each kept event, format time in `{config.timezone}` 12-hour format (e.g. `6:00 PM`). List participants as first names only (from email prefix before @), exclude the user's own name, show first 2 then `+N` for the rest.

**If Google Calendar MCP unavailable:** skip silently, omit Meetings section from standup.

**C. Slack mentions (last 24h):**
Use `mcp__claude_ai_Slack__slack_search_public_and_private` with:
- query: `@{config.slack_display_name} after:[yesterday's date in YYYY-MM-DD]`
- Limit to 10 most recent results

Display under header `*Mentions in the last 24h:*` showing: channel name, sender first name, short snippet, timestamp. If none found, skip the section.

**D. GitHub activity (last 24h):**

Uses the GitHub Events API for reviewed PRs — no search index lag.

Run in a single Bash call with parallel background jobs:

```bash
YESTERDAY=$(date -v-1d -u +%Y-%m-%dT%H:%M:%SZ)
GH_LOGIN=$(gh api /user --jq .login 2>/dev/null)
(gh search prs --author @me --owner {config.github_org} --created ">$(date -v-1d +%Y-%m-%d)" --json number,title,url,state --limit 10 > /tmp/gh_created_prs.json 2>/dev/null) &
(gh api "/users/$GH_LOGIN/events" 2>/dev/null | python3 -c "
import json, sys
from datetime import datetime, timezone
cutoff = datetime.fromisoformat('$YESTERDAY'.replace('Z','+00:00'))
events = json.load(sys.stdin)
seen = set()
prs = []
for e in events:
    if e['type'] == 'PullRequestReviewEvent':
        ts = datetime.fromisoformat(e['created_at'].replace('Z','+00:00'))
        if ts > cutoff:
            num = e['payload']['pull_request']['number']
            repo = e['repo']['name']
            state = e['payload']['review']['state']
            if num not in seen:
                seen.add(num)
                prs.append({'number': num, 'repo': repo, 'url': f'https://github.com/{repo}/pull/{num}', 'review_state': state})
print(json.dumps(prs))
" > /tmp/gh_reviewed_prs.json 2>/dev/null) &
wait
```

After `wait`, fetch titles for reviewed PRs:

```bash
python3 -c "
import json, subprocess
prs = json.load(open('/tmp/gh_reviewed_prs.json'))
for pr in prs:
    result = subprocess.run(['gh', 'pr', 'view', str(pr['number']), '--repo', pr['repo'], '--json', 'title,url'], capture_output=True, text=True)
    if result.returncode == 0:
        data = json.loads(result.stdout)
        pr['title'] = data['title']
        pr['url'] = data['url']
    else:
        pr['title'] = f\"PR #{pr['number']}\"
print(json.dumps(prs))
" > /tmp/gh_reviewed_prs_titled.json 2>/dev/null
```

Use `/tmp/gh_reviewed_prs_titled.json` as the reviewed PRs source. These are the "auto-detected" items.

**E. Meeting action items — Zoom + Notion (last 24h):**
Run Zoom and Notion fetches in parallel (both are sequential sub-steps internally).

**Zoom (primary — if Zoom MCP available):**
1. Call `mcp__claude_ai_Zoom_for_Claude__search_meetings` with:
   - `from`: 24 hours ago in UTC (`2026-01-01T00:00:00Z` format)
   - `to`: now in UTC
   - Keep only meetings where `has_summary: true` OR `has_my_notes: true`

2. For each qualifying meeting, call `mcp__claude_ai_Zoom_for_Claude__get_meeting_assets` with the `meeting_uuid`. Extract action items from TWO sources:

   **Source A — AI Companion meeting summary** (team meetings, retros, syncs):
   - Check `meeting_summary.next_steps`
   - Filter for items mentioning `{config.slack_display_name}` in the assignee or text

   **Source B — My Notes** (solo planning sessions):
   - Only use if `meeting_summary` is null/empty
   - Look in `my_notes.content_markdown` for a `## Action Items` section
   - Parse bullets starting with `{config.slack_display_name}:`
   - Strip the prefix, keep action item text

   Store all Zoom items as: `{ text, meeting_topic, meeting_created_at, source: "zoom" }`

**If Zoom MCP unavailable:** skip silently.

**Notion AI meeting notes (secondary — if Notion MCP available):**
1. Call `mcp__claude_ai_Notion__notion-query-meeting-notes` with filter `date_is_within: the_past_week`. After results return, **discard any note where `created_time` is older than 24h ago**.

2. For each remaining note, call `mcp__claude_ai_Notion__notion-fetch` with the note's `url`. In the page content, find the `### Action Items` section and parse lines matching:
   - `- [ ] {config.slack_display_name} to [action]` → store action text, mark as `owner: "user"`
   - `- [ ] All team members to [action]` → store action text, mark as `owner: "team"`
   - Skip `- [x]` lines (completed items)

   Store all Notion items as: `{ text, meeting_topic, meeting_created_at, owner, source: "notion" }`

**If Notion MCP unavailable:** skip silently.

**Deduplication between Zoom and Notion:**
- If a Notion note's `created_time` is within ±30 minutes of a Zoom meeting that has `has_summary: true`, skip that Notion note's items (Zoom is more reliable).
- If the same action item text appears in both sources (fuzzy match), keep only the Zoom version.

**In the numbered block:**
- Zoom items: `N. [Action item text] (from [Meeting title])`
- Notion items (user-owned): `N. [Action item text] (from [Meeting title])`
- Notion items (team-owned): `N. [Action item text] (from [Meeting title]) (team)`

If no action items found, skip section silently.

**MCP warning:** At end of Step 2, if any optional MCP (Calendar, Zoom, Notion) was unavailable, append: `⚠️ Skipped: [source] not connected`

---

## STEP 2 — Build numbered question block and display

Show:
1. Previous standup (from A) with clickable markdown links
2. Slack mentions (from C)
3. Calendar meetings summary (from B)

Then show the numbered question block combining previous standup items + auto-detected GitHub activity. **Deduplicate**: if a PR from GitHub auto-detection already appears in the previous standup items (match by PR number or title), do NOT repeat it.

Format the block exactly like this:

```
*What happened? Reply with number + quick note.*

*Previous standup items:*
1. [Action verb] [Title](URL)
2. [Action verb] [Title](URL)
...

*New GitHub activity:*
N. Created PR: [PR title] (#XXXXX)
N. Reviewed (approved): [PR title] (#XXXXX)
N. Reviewed (changes requested): [PR title] (#XXXXX)

*Meeting action items:*
N. [Action item text] (from [Meeting title])
N. [Action item text] (from [Meeting title]) (team)

Add any new items as free text below your numbered answers ↓
```

If a section has no items, skip it entirely.

---

## STEP 3 — Parse reply

User replies with numbered annotations + optional free text.

**Parse numbered lines** — map annotation to disposition:

| Annotation | Last 24h | Next 24h | Action verb |
|------------|----------|----------|-------------|
| "merged" | ✓ | — | "Merged" |
| "in progress" / "still in progress" / "wip" | ✓ | ✓ | Last: "Continued work on" / Next: "Continue work on" |
| "didn't get chance" / "no chance" | — | ✓ | "Continue work on" (auto-carry) |
| "skip" / "drop" | — | — | (remove) |
| "yes" (for auto-detected PR) | ✓ | — | "Created PR for" or "Reviewed" based on source |
| "approved" | ✓ | — | "Approved" |
| "requested changes" | ✓ | — | "Requested changes on" |
| "done" / "completed" (for meeting action item) | ✓ | — | "Completed" |
| Custom text | ✓ | — | Infer from text |

For `review_state` from Events API: map `approved` → "Approved", `changes_requested` → "Requested changes on", `commented` → "Reviewed".

Meeting action items with no annotation default to: Next 24h, verb inferred from the action item text.

**Parse free-text lines** (unnumbered): extract any JIRA keys (e.g. PROJ-123), PR numbers, or GitHub URLs mentioned.

---

## STEP 4 — Fetch remaining ticket and PR titles (all in parallel)

Only fetch items NOT already known. Batch ALL lookups into a single Bash call:

```bash
(jira issue view PROJ-123 --raw > /tmp/jira_PROJ-123.json 2>/dev/null) &
(gh pr view 456 --repo {config.github_org}/repo --json title,url > /tmp/pr_456.json 2>/dev/null) &
wait
```

After `wait`, read each output file:

**For Jira tickets:**
- Parse `fields.summary`, `fields.parent.fields.summary` (epic name)
- Build webUrl: `https://{config.jira_base_url}/browse/KEY`
- Format: `<WEBURL|full summary>`

**For GitHub PRs:**
- Parse `title`, `url`
- Format: `<url|full PR title>`

If a file is empty or missing, use plain text for that item.

---

## STEP 5 — Infer Last 24h vs Next 24h and categorize

**Categorization:**
- Jira ticket with parent → category = parent epic summary
- Jira ticket that IS an epic (no parent) → category = its own summary
- PR with Jira key in title → use that ticket's category logic
- PR with no Jira key, or plain text → category = "General"
- Sort categories alphabetically; always put "Meetings" last

**Action verb inference for free-text items:**
- "added / opened / created a PR" → "Opened PR for"
- "worked on / continued" → "Continued work on"
- "requested review" → "Requested review for"
- "merged" → "Merged"
- "reviewed" → "Reviewed"
- "shipped / deployed" → "Shipped"
- "fixed" → "Fixed"
- "will merge" → "Merge" (next 24h imperative)

---

## STEP 6 — Compose standup

Use this EXACT Slack mrkdwn format:

```
*Standup — [Month Day, Year]*

*Last 24 Hours*
• _[Category Name]_
  ◦ [Action verb] <TICKET_WEBURL|Full ticket or PR title>
• _[Meetings]_
  ◦ [Time in user's timezone] — [Meeting Title] (with [Name1], [Name2])
  ◦ No meetings  ← if none

*Next 24 Hours*
• _[Category Name]_
  ◦ [Action verb] <TICKET_WEBURL|Full ticket or PR title>
• _[Meetings]_
  ◦ [Time in user's timezone] — [Meeting Title] (with [Name1], [Name2])
  ◦ No meetings  ← if none
```

Rules:
- Section headers bold, category names italic with square brackets
- Each item ONE line: `[Action verb] <url|full title>`
- Link text = full ticket summary or full PR title (never truncated)
- Sort categories alphabetically; Meetings always last
- If no tickets at all: `◦ No active tickets`

---

## STEP 7 — Show preview and allow edits

Display the composed standup in a code block. Say:

> Here's your standup preview. Want any changes before I send it?

Revise and re-show if user requests changes. Repeat until approved.

---

## STEP 8 — Send to Slack

**Determine destination:**

- **First run** (`config.first_run_complete === false`) OR **test mode** (`/standup test`):
  Send as DM to `{config.slack_user_id}` using `mcp__claude_ai_Slack__slack_send_message`.
  Confirm: "Sent as a DM to you ✓"
  If first run: update `first_run_complete` to `true` in config:
  ```bash
  python3 -c "
  import json
  path = '$HOME/.claude/skills/standup/config.json'
  c = json.load(open(path))
  c['first_run_complete'] = True
  json.dump(c, open(path, 'w'), indent=2)
  "
  ```
  Then say: "First run complete — next time `/standup` will post directly to your standup channel."

- **Normal run** (first run complete, not test mode):
  Send to `{config.standup_channel_id}` using `mcp__claude_ai_Slack__slack_send_message`.
  Confirm: "Sent to your standup channel ✓"
