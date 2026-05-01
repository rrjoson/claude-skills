---
name: mentorship-inbound
description: Evaluates MentorCruise mentorship applications for Ricardo Joson — scores applicants, drafts a response message, and creates a Notion row. Use when a new MentorCruise application arrives, when the user says "process application", or when pasting/forwarding a mentee application.
---

Read `/Users/apollo/.claude/mentorship/context.md` before evaluating. It contains the rubric, scoring criteria, focus areas, and all message templates.

## 1 — Get application text

1. If user passed text or image → use it.
2. Otherwise → use `Gmail:gmail_search_threads` to find the latest unread email from `info@mentorcruise.com` (subject: "mentee has applied"). Extract applicant name + message body.
3. If nothing found → ask user to paste the application text.

Dedup check before evaluating:
```sql
SELECT Name FROM "collection://34aab2b3-b496-80f9-8e68-000b3fb58a68" WHERE Name = '[name]'
```
If found → "Already in Notion. Check tracker." and stop.

## 2 — Evaluate

Apply rubric from context.md. Assign: **Strong / Maybe / No**.

## 3 — Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
APPLICANT:      [name]
SCORE:          [Strong / Maybe / No]
FIT:            [Good fit / Mismatch] — [one-line reason]
RED FLAGS:      [list or None]
GREEN FLAGS:    [list or None]
RECOMMENDATION: [Decline / Send Follow-up Question / Send Booking Link]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DRAFTED MESSAGE (copy-paste ready):
[message from context.md template — personalized with 1 specific sentence from application]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 4 — Create Notion row

Use `Notion:notion-create-pages` with parent `data_source_id: 34aab2b3-b496-80f9-8e68-000b3fb58a68`:

| Property | Value |
|----------|-------|
| Name | applicant name |
| Stage | Intake |
| Priority | High (Strong) / Medium (Maybe) / Low (No) |
| Source | Inbound |
| Goal | 1-line goal summary or "Unclear" |
| Next step | Send booking link / Send follow-up question / Send decline |

Page body: `## Application` → full text · `## Evaluation` → score + flags · `## Drafted Message` → full message.

Print the Notion page URL when done.

**Rules:** Always draft a message. Keep messages under 5 sentences. Never hallucinate details. Ambiguous goal → Maybe, not No.
