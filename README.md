# claude-code-statusline

A muted, three-line status line for [Claude Code](https://code.claude.com/docs/en/statusline), written in bash and tuned for Git Bash on Windows.

```
📁 Chess    🤖 Opus 5.5 low    💬 statusline-ideas
🧠 ████░░░░░░ 36% (360.0k/1.0M tok)    💰 $1.24    📝 +120 −34
⏳ ██████░░░░ 61% (1h 5m)    📅 █████████░ 92% (3d 23h)
```

Each line covers a wider scope than the one above it:

1. **Where you are:** folder, model and effort level, session name
2. **This session:** context window usage, cost, lines changed
3. **Your account:** 5-hour and 7-day subscription limits, with time until each resets

## What each item shows

| Line | Item | Shows | Color (256-color code) | JSON field |
|---|---|---|---|---|
| 1 | 📁 | Folder name, bold | teal (73) | `workspace.current_dir` |
| 1 | 🤖 | Model, then effort level | steel blue (110), khaki (144) | `model.display_name`, `effort.level` |
| 1 | 💬 | Session name | mauve (139) | `session_name` |
| 2 | 🧠 | Context bar, percentage, tokens used / window size | gradient | `context_window.*` |
| 2 | 💰 | Session cost in USD | tan (180) | `cost.total_cost_usd` |
| 2 | 📝 | Lines added and removed | sage (108), brick (167) | `cost.total_lines_added`, `cost.total_lines_removed` |
| 3 | ⏳ | 5-hour limit bar, percentage, time until reset | gradient | `rate_limits.five_hour.*` |
| 3 | 📅 | 7-day limit bar, percentage, time until reset | gradient | `rate_limits.seven_day.*` |

The session name goes last on line 1 because it only appears once the session has a name (from `/rename`, `--name`, or an AI-generated title), so nothing else shifts when it shows up.

### Bars and percentages

- Each bar has 10 cells. Filled cells (`█`) are colored by position along a sage → tan → brick-red ramp (`108 108 143 144 179 180 173 173 167 167`), so a fuller bar ends further toward red. Empty cells (`░`) are dark grey (238).
- Percentages are sage under 50%, golden tan (179) from 50% to 79%, and brick red (167) at 80% and above.
- Reset times read `5m` under an hour, `1h 5m` under a day, and `3d 23h` beyond that.
- Values Claude Code hasn't reported yet show an empty grey bar and `--`.

## Setup

1. Install [jq](https://jqlang.org/), for example `winget install jqlang.jq`. The script finds `jq` even when your shell's PATH is out of date after installing.
2. Copy `statusline-command.sh` to `~/.claude/statusline-command.sh`.
3. Add this to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline-command.sh"
     }
   }
   ```

The script reads every field with a single `jq` call and does the rest in plain bash without starting other processes, so each refresh takes about 0.1 s on Windows.

## Tests

```bash
bash tests/run.sh
```

The tests pipe sample session JSON into the script and check its exact output, including missing fields, invalid input, bar rounding, colors, number formatting, reset countdowns, and speed. They need only bash and jq.

## Rebuild it from a description

> A three-line Claude Code status line in muted 256-color text, with sections separated by four spaces and each section starting with an emoji. Line 1: 📁 the folder name (bold teal), 🤖 the model (steel blue) followed by the effort level (khaki), then 💬 the session name (mauve) last, shown only once the session has a name. Line 2: 🧠 a 10-cell context bar using █ and ░ with a sage-to-tan-to-brick-red gradient, the percentage, and "(used/total tok)" in dim text; then 💰 the cost as $0.00; then 📝 +lines added (green) and −lines removed (red). Line 3: ⏳ the 5-hour limit and 📅 the 7-day limit, each with the same kind of bar, a percentage and the dim time until it resets ("1h 5m" or "3d 23h"). Percentages are green under 50%, tan from 50% to 79% and red at 80% and above. Missing values show an empty grey bar and "--".
