# claude-code-statusline

A single bash script, `statusline-command.sh`, that renders a three-line Claude Code status line. Claude Code pipes session JSON to it on stdin and shows whatever it prints. The README documents the layout, colors and setup.

## Environment

- Runs in Git Bash on Windows. Keep it working there first; don't rely on GNU-only tools or Linux paths.
- The installed copy lives at `~/.claude/statusline-command.sh`. This repo is the source. After changing the script here, copy it there to see it live: `cp statusline-command.sh ~/.claude/`.
- `.gitattributes` keeps `*.sh` as LF. Bash fails on CRLF, so don't change that.

## Rules for the script

- **Speed matters.** It runs on every refresh, and starting a process on Windows is slow. All fields come from the single `jq` call near the top: add new fields to that call instead of calling `jq` again. Don't add `awk`, `sed`, `date`, or other external commands to the render path.
- **No subshells in helpers.** Helpers return results in `REPLY` instead of printing, so callers don't need `$(...)`. Follow that pattern for new helpers.
- **Fields are joined with `\x1f`,** not tabs, because `read` merges runs of whitespace separators and would drop empty fields.
- **Missing fields must not break output.** Any field can be absent. Leave the item out, or show the placeholder style (empty grey bar, `--`).
- **Line layout:** line 1 is where you are (folder, model + effort, session name last), line 2 is this session's usage, line 3 is account-wide limits. Items that can appear later go at the end of a line so nothing shifts.
- **Colors** are muted 256-color codes defined once at the top. Use the existing variables rather than inline escape codes.
- **Emojis:** avoid ones that need the U+FE0F variation selector (like ✏️ or ⏱️). Some terminals render them at the wrong width.

## Testing

There are no automated tests. Build sample input with `jq -n` (not `echo`, which can mangle Windows-path backslashes) and pipe it in. Strip colors to read the output:

```bash
jq -n '{model:{display_name:"Opus 5.5"},workspace:{current_dir:"/c/x/Chess"},context_window:{used_percentage:36,total_input_tokens:355000,total_output_tokens:5000,context_window_size:1000000}}' \
  | bash statusline-command.sh | sed 's/\x1b\[[0-9;]*m//g'
```

Check at least: full input, minimal input (model only), invalid JSON, and a Windows path with backslashes. Time it with `time bash statusline-command.sh < sample.json`; a refresh should stay near 0.1 s.

When the layout, colors, or setup change, update the README to match.
