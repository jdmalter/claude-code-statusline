#!/usr/bin/env bash
# Claude Code status line, in three lines ordered from narrowest to widest
# scope:
#   1. where you are: folder, model + effort, session name. The session name
#      goes last because it only appears once the session is named, so
#      nothing else shifts when it shows up.
#   2. this session's usage: context window bar, cost, lines changed
#   3. account-wide subscription limits: 5-hour and 7-day bars, each with a
#      countdown to its reset
# Fields Claude Code doesn't report are left out or shown as placeholders.

input=$(cat)

# Locate jq even if PATH hasn't picked up a fresh install yet. On Windows,
# PATH updates are only broadcast to newly-launched top-level processes, so a
# long-lived Git Bash session can have a stale inherited PATH indefinitely
# even after jq is installed/updated via winget. JQ must resolve to an
# absolute path here, never the bare string "jq" -- otherwise the jq()
# wrapper below would call itself recursively instead of the real binary.
JQ=""
if command -v jq >/dev/null 2>&1; then
  JQ=$(command -v jq)
fi

# 1) Re-derive PATH from the live Windows registry rather than trusting the
# shell's (possibly stale) inherited PATH. reg.exe lives in
# C:\Windows\System32, which is part of the OS-level PATH and is essentially
# always already correct even in a stale shell, so this can succeed even
# when `command -v jq` above just failed.
if [ -z "$JQ" ] && command -v reg.exe >/dev/null 2>&1; then
  have_cygpath=0
  command -v cygpath >/dev/null 2>&1 && have_cygpath=1
  for hive in "HKCU\\Environment" "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment"; do
    [ -n "$JQ" ] && break
    reg_value=$(MSYS_NO_PATHCONV=1 reg.exe query "$hive" /v Path 2>/dev/null \
      | tr -d '\r' \
      | grep -E "REG_(EXPAND_)?SZ" \
      | sed -E 's/^.*REG_(EXPAND_)?SZ[[:space:]]+//')
    [ -z "$reg_value" ] && continue
    old_ifs="$IFS"
    IFS=';'
    for win_dir in $reg_value; do
      [ -z "$win_dir" ] && continue
      if [ "$have_cygpath" -eq 1 ]; then
        unix_dir=$(cygpath -u "$win_dir" 2>/dev/null)
      else
        unix_dir="$win_dir"
      fi
      if [ -n "$unix_dir" ] && [ -x "$unix_dir/jq.exe" ]; then
        JQ="$unix_dir/jq.exe"
        break
      fi
    done
    IFS="$old_ifs"
  done
fi

# 2) Last resort: glob-search common install locations. A wildcard is used
# instead of one exact hardcoded WinGet package-folder name, so a future jq
# reinstall/version bump under a differently-named folder is still found.
# Scanning other users' AppData can trigger permission-denied noise, hence
# the 2>/dev/null on the loop.
if [ -z "$JQ" ]; then
  shopt -s nullglob
  candidates=(
    /c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/jq.exe
    /c/ProgramData/chocolatey/bin/jq.exe
    /mingw64/bin/jq.exe
    /c/tools/jq.exe
    /usr/bin/jq.exe
  )
  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ] 2>/dev/null; then
      JQ="$candidate"
      break
    fi
  done
  shopt -u nullglob
fi

jq() { "$JQ" "$@"; }

# Bars use Unicode block characters, so make sure output is UTF-8.
export LC_ALL=C.UTF-8

# --- colors (muted 256-color palette) ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[38;5;108m'
YELLOW=$'\033[38;5;179m'
RED=$'\033[38;5;167m'
BAR_EMPTY=$'\033[38;5;238m'
C_DIR=$'\033[38;5;73m'
C_SESSION=$'\033[38;5;139m'
C_MODEL=$'\033[38;5;110m'
C_EFFORT=$'\033[38;5;144m'
C_COST=$'\033[38;5;180m'

# soft green -> tan -> muted red ramp; each filled bar cell takes the color
# for its position, so a fuller bar reads as a heat map
GRADIENT=(108 108 143 144 179 180 173 173 167 167)

BAR_WIDTH=10

# --- read every field in a single jq call ---
# Starting a process is slow on Windows, and one jq/awk call per field made
# each refresh take over a second. So jq reads everything at once and rounds
# numbers to integers, letting the rest of the script use plain bash math.
# Fields are joined with the ASCII unit separator (\x1f) rather than a tab,
# because `read` merges runs of whitespace separators and would drop empty
# fields.
IFS=$'\x1f' read -r model_name current_dir session_name effort_level \
  ctx_pct ctx_tokens ctx_size cost_usd lines_added lines_removed \
  five_pct five_resets_at seven_pct seven_resets_at <<<"$(jq -r '
  def int: if . == null then null else round end;
  [
    .model.display_name,
    (.workspace.current_dir // .cwd),
    .session_name,
    .effort.level,
    (.context_window.used_percentage | int),
    ((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)),
    (.context_window.context_window_size // 0),
    .cost.total_cost_usd,
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.rate_limits.five_hour.used_percentage | int),
    (.rate_limits.five_hour.resets_at | int),
    (.rate_limits.seven_day.used_percentage | int),
    (.rate_limits.seven_day.resets_at | int)
  ] | map(if . == null then "" else tostring end) | join("\u001f")
' <<<"$input" 2>/dev/null)"

# The helpers below return their result in REPLY instead of printing it, so
# calling them doesn't fork a subshell (also slow on Windows).

# sets REPLY to the color for an integer percentage
color_for_pct() {
  if (($1 < 50)); then
    REPLY=$GREEN
  elif (($1 < 80)); then
    REPLY=$YELLOW
  else
    REPLY=$RED
  fi
}

# sets REPLY to a gradient bar for an integer percentage
make_bar() {
  local filled=$((($1 * BAR_WIDTH + 50) / 100))
  ((filled > BAR_WIDTH)) && filled=$BAR_WIDTH
  ((filled < 0)) && filled=0
  local bar="" i
  for ((i = 0; i < BAR_WIDTH; i++)); do
    if ((i < filled)); then
      bar+=$'\033[38;5;'"${GRADIENT[i * ${#GRADIENT[@]} / BAR_WIDTH]}m█"
    else
      bar+="${BAR_EMPTY}░"
    fi
  done
  REPLY="${bar}${RESET}"
}

# sets REPLY to a placeholder bar for when a value isn't reported yet
empty_bar() {
  local bar="" i
  for ((i = 0; i < BAR_WIDTH; i++)); do bar+="░"; done
  REPLY="${BAR_EMPTY}${bar}${RESET}"
}

# sets REPLY to a token count shortened to one decimal, like "360.0k"
format_tokens() {
  local n=$1 t
  if ((n >= 1000000)); then
    t=$(((n + 50000) / 100000))
    REPLY="$((t / 10)).$((t % 10))M"
  elif ((n >= 1000)); then
    t=$(((n + 50) / 100))
    REPLY="$((t / 10)).$((t % 10))k"
  else
    REPLY=$n
  fi
}

# sets REPLY to the time until a Unix epoch seconds value, as "Xd Yh",
# "Xh Ym", or "Ym". Empty if the value is empty or already in the past.
reset_display() {
  REPLY=""
  [ -z "$1" ] && return
  local now diff days hours minutes
  printf -v now '%(%s)T' -1
  diff=$(($1 - now))
  ((diff <= 0)) && return
  days=$((diff / 86400))
  hours=$(((diff % 86400) / 3600))
  minutes=$(((diff % 3600) / 60))
  if ((days > 0)); then
    REPLY="${days}d ${hours}h"
  elif ((hours > 0)); then
    REPLY="${hours}h ${minutes}m"
  else
    REPLY="${minutes}m"
  fi
}

# sets REPLY to a rate-limit segment: emoji, bar, percentage, reset countdown
limit_segment() {
  local emoji=$1 pct=$2 resets_at=$3
  if [ -z "$pct" ]; then
    empty_bar
    REPLY="${emoji} ${REPLY} ${DIM}--%${RESET}"
    return
  fi
  local bar color
  make_bar "$pct"; bar=$REPLY
  color_for_pct "$pct"; color=$REPLY
  reset_display "$resets_at"
  local reset=""
  [ -n "$REPLY" ] && reset=" ${DIM}(${REPLY})${RESET}"
  REPLY="${emoji} ${bar} ${color}${pct}%${RESET}${reset}"
}

# sets REPLY to the non-empty args joined with a four-space gap
join_parts() {
  local joined="" part
  for part in "$@"; do
    [ -z "$part" ] && continue
    if [ -z "$joined" ]; then
      joined=$part
    else
      joined+="    ${part}"
    fi
  done
  REPLY=$joined
}

# --- line 1: where you are (folder, model + effort, session name) ---
dir_segment=""
dir_name=${current_dir##*[\\/]}
[ -n "$dir_name" ] && dir_segment="📁 ${C_DIR}${BOLD}${dir_name}${RESET}"

model_segment=""
[ -n "$model_name" ] && model_segment="🤖 ${C_MODEL}${model_name}${RESET}"
[ -n "$effort_level" ] && model_segment+=" ${C_EFFORT}${effort_level}${RESET}"

session_segment=""
[ -n "$session_name" ] && session_segment="💬 ${C_SESSION}${session_name}${RESET}"

join_parts "$dir_segment" "$model_segment" "$session_segment"
line1=$REPLY

# --- line 2: this session's usage (context, cost, lines changed) ---
if [ -n "$ctx_pct" ]; then
  make_bar "$ctx_pct"; bar=$REPLY
  color_for_pct "$ctx_pct"; color=$REPLY
  format_tokens "$ctx_tokens"; tok_display=$REPLY
  format_tokens "$ctx_size"; size_display=$REPLY
  context_segment="🧠 ${bar} ${color}${ctx_pct}%${RESET} ${DIM}(${tok_display}/${size_display} tok)${RESET}"
else
  empty_bar
  context_segment="🧠 ${REPLY} ${DIM}--% (--/-- tok)${RESET}"
fi

if [ -n "$cost_usd" ]; then
  # show more decimals for tiny non-zero costs that would round to $0.00
  printf -v cost_display '%.2f' "$cost_usd"
  if [ "$cost_display" = "0.00" ] && [ "$cost_usd" != "0" ]; then
    printf -v cost_display '%.4f' "$cost_usd"
  fi
  cost_segment="💰 ${C_COST}\$${cost_display}${RESET}"
else
  cost_segment="💰 ${DIM}\$--${RESET}"
fi

lines_segment="📝 ${GREEN}+${lines_added:-0}${RESET} ${RED}−${lines_removed:-0}${RESET}"

join_parts "$context_segment" "$cost_segment" "$lines_segment"
line2=$REPLY

# --- line 3: account-wide subscription rate limits ---
limit_segment "⏳" "$five_pct" "$five_resets_at"; five_segment=$REPLY
limit_segment "📅" "$seven_pct" "$seven_resets_at"; seven_segment=$REPLY
join_parts "$five_segment" "$seven_segment"
line3=$REPLY

printf "%s\n%s\n%s" "$line1" "$line2" "$line3"
