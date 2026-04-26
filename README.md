# Claude Skills

Personal Claude Code skills for Ricardo Joson.

## Skills

### `mentorship-inbound`
Evaluates MentorCruise mentorship applications — scores applicants, drafts a response, and creates a Notion row.

**Usage:** `/mentorship-inbound` (auto-reads Gmail) or `/mentorship-inbound [paste text]`

**Context file:** `mentorship/context.md` — rubric, templates, booking link, Notion DB reference.

## Structure

```
skills/
  mentorship-inbound/
    SKILL.md          # Skill instructions (loaded by Claude Code)
mentorship/
  context.md          # Rubric, focus areas, message templates
```

## Setup

Skills are symlinked or copied to `~/.claude/skills/` to be discovered by Claude Code.
Context files live at `~/.claude/mentorship/`.
