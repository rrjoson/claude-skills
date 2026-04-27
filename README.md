# Claude Skills

Personal Claude Code skills for Ricardo Joson.

## Skills

### `add-highlight`
Logs an achievement or contribution to the Highlight Artifacts DB in Notion. Accepts Slack/PR URLs or a plain description, drafts the entry with CGP tags, confirms, then creates the Notion page.

**Usage:** `/add-highlight` or describe something you did

### `mentorship-inbound`
Evaluates MentorCruise mentorship applications — scores applicants, drafts a response, and creates a Notion row.

**Usage:** `/mentorship-inbound` (auto-reads Gmail) or `/mentorship-inbound [paste text]`

**Context file:** `mentorship/context.md` — rubric, templates, booking link, Notion DB reference.

## Structure

```
skills/
  add-highlight/
    skill.md          # Skill instructions (loaded by Claude Code)
  mentorship-inbound/
    SKILL.md          # Skill instructions (loaded by Claude Code)
mentorship/
  context.md          # Rubric, focus areas, message templates
```

## Setup

Skills are symlinked or copied to `~/.claude/skills/` to be discovered by Claude Code.
Context files live at `~/.claude/mentorship/`.
