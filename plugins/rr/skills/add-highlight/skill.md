---
name: add-highlight
description: Add an entry to Ricardo's Highlight Artifacts DB in Notion. Use when Ricardo describes something he shipped, improved, fixed, or contributed — oncall improvements, automations built, PRs merged, process simplifications, team impact. Trigger on "log this", "add to highlights", "add highlight", "note this", "record what I did", or when Ricardo describes an achievement and asks to add or track it. Even if he doesn't say "highlight" explicitly, use this skill whenever he's describing work worth capturing for perf review purposes.
---

# Add Highlight Artifact

Log an achievement or contribution to Ricardo's Highlight Artifacts DB in Notion.

## Hardcoded config

- **Data source ID**: `5fc7bb7b-5b64-44d9-b028-35034b500146`
- **Ricardo's user ID**: `user://b7d36298-ad55-4eb8-9000-b7a62375d412`
- **Squad**: `https://www.notion.so/816c0e8a44b3499a8432d400c1ba4c53`

## CGP Tags — pick 1–3 most fitting

| Category | Options |
|----------|---------|
| Impact | `Impact: Scope` · `Collaborative Reach` · `Impact Levers` |
| Results | `Results: Operational Excellence` · `Results: Ownership` · `Results: Impact` · `Results: Decision Making` |
| Talent | `Talent: Planning` · `Talent: Personal Growth` · `Talent: Development` · `Talent: Hiring` |
| Culture | `Culture: Collaboration` · `Culture: Org Health` · `Culture: Communication` |
| Craft | `Craft: Code Fluency` · `Craft: Architecture Design` · `Craft: Diagnosis` · `Craft: Observability` · `Craft: Software Design` · `Craft: Business Acumen` · `Craft: Technical Strategy` |
| Direction | `Direction: Agility` · `Direction: Innovation` · `Direction: Strategy` |

## Steps

### 1. Gather context

If Ricardo gave Slack or PR URLs, fetch them to understand what happened. If his description is already specific enough, skip fetching.

### 2. Draft the entry

Propose:
- **What**: 1–2 sentences. Lead with the action and concrete outcome. Write it like a perf review bullet — specific, outcome-focused, no fluff. Example: *"Automated Weekly Fabric Surfaces Quality Metrics via Claude Routine — fixed Slack formatting bugs found during oncall, eliminated manual Slack Workflow, zero manual steps required going forward"*
- **Artifact**: best URL (PR, Slack thread, Notion page, etc.)
- **CGP Tags**: 1–3 tags that fit the nature of the contribution

### 3. Confirm

Show the draft. Ask for thumbs up or edits.

Skip this step if Ricardo said something like "just add it" or "go ahead" — create directly.

### 4. Create the Notion page

Use `notion-create-pages` with:
- Parent: `data_source_id: 5fc7bb7b-5b64-44d9-b028-35034b500146`
- Properties:

```json
{
  "What": "<text>",
  "Artifact": "<url>",
  "CGP Tags": "[\"Tag 1\", \"Tag 2\"]",
  "Who": "[\"user://b7d36298-ad55-4eb8-9000-b7a62375d412\"]",
  "Squad": "[\"https://www.notion.so/816c0e8a44b3499a8432d400c1ba4c53\"]"
}
```

### 5. Return the created page URL

For multiple entries in one go, batch-confirm all drafts before creating any.
