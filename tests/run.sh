#!/usr/bin/env bash
# Tests for statusline-command.sh. Each test pipes sample JSON into the script
# and checks its output. Run from anywhere: bash tests/run.sh
# Needs only bash and jq.

export LC_ALL=C.UTF-8
cd "$(dirname "$0")/.." || exit 1
SCRIPT=statusline-command.sh

pass=0
fail=0

# render <json>: runs the script, sets RAW (with colors) and OUT (colors
# stripped) and ERR (stderr)
render() {
  local errfile
  errfile=$(mktemp)
  RAW=$(printf '%s' "$1" | bash "$SCRIPT" 2>"$errfile")
  ERR=$(cat "$errfile")
  rm -f "$errfile"
  OUT=$(printf '%s' "$RAW" | sed 's/\x1b\[[0-9;]*m//g')
}

# line <n>: prints line n of the stripped output
line() { printf '%s\n' "$OUT" | sed -n "${1}p"; }

check() {
  local name=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$name" "$expected" "$actual"
  fi
}

check_contains() {
  local name=$1 needle=$2 haystack=$3
  if [[ $haystack == *"$needle"* ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected to contain: %s\n  actual: %s\n' "$name" "$needle" "$haystack"
  fi
}

# json <jq expression>: builds test input; $now is the current epoch seconds.
# Reset times add 30s of slack so a minute boundary mid-test can't flip them.
json() { jq -cn --argjson now "$(date +%s)" "$1"; }

BS=$(printf '\x5c')
FULL=$(jq -cn --arg dir "C:${BS}Users${BS}jacob${BS}IdeaProjects${BS}Chess" --argjson now "$(date +%s)" '{
  model: {display_name: "Opus 5.5"},
  workspace: {current_dir: $dir},
  session_name: "statusline-ideas",
  effort: {level: "low"},
  cost: {total_cost_usd: 1.237, total_lines_added: 120, total_lines_removed: 34},
  context_window: {used_percentage: 36, total_input_tokens: 355000, total_output_tokens: 5000, context_window_size: 1000000},
  rate_limits: {
    five_hour: {used_percentage: 61, resets_at: ($now + 3900 + 30)},
    seven_day: {used_percentage: 92, resets_at: ($now + 345600 + 3600 * 23 + 30)}
  }
}')

# --- full input renders all three lines exactly ---
render "$FULL"
check "full: line 1" "📁 Chess    🤖 Opus 5.5 low    💬 statusline-ideas" "$(line 1)"
check "full: line 2" "🧠 ████░░░░░░ 36% (360.0k/1.0M tok)    💰 \$1.24    📝 +120 −34" "$(line 2)"
check "full: line 3" "⏳ ██████░░░░ 61% (1h 5m)    📅 █████████░ 92% (4d 23h)" "$(line 3)"
check "full: three lines" "3" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check "full: no stderr" "" "$ERR"

# --- session name is optional and goes last ---
render "$(printf '%s' "$FULL" | jq -c 'del(.session_name)')"
check "no session name: line 1" "📁 Chess    🤖 Opus 5.5 low" "$(line 1)"

# --- minimal input shows placeholders ---
render "$(json '{model: {display_name: "Opus 5.5"}}')"
check "minimal: line 1" "🤖 Opus 5.5" "$(line 1)"
check "minimal: line 2" "🧠 ░░░░░░░░░░ --% (--/-- tok)    💰 \$--    📝 +0 −0" "$(line 2)"
check "minimal: line 3" "⏳ ░░░░░░░░░░ --%    📅 ░░░░░░░░░░ --%" "$(line 3)"

# --- invalid JSON doesn't crash or print errors ---
render "not json"
check "invalid json: no stderr" "" "$ERR"
check "invalid json: line 2" "🧠 ░░░░░░░░░░ --% (--/-- tok)    💰 \$--    📝 +0 −0" "$(line 2)"

# --- folder name from either path style ---
render "$(json '{workspace: {current_dir: "/c/Users/jacob/IdeaProjects/Chess"}}')"
check "forward-slash path" "📁 Chess" "$(line 1)"
render "$(json '{cwd: "/home/me/project"}')"
check "falls back to cwd" "📁 project" "$(line 1)"

# --- bar fill rounds to the nearest cell ---
# (extraction uses bash string trimming: sed and grep can't match the
# multi-byte block characters reliably in Git Bash)
bar_for() {
  render "$(json "{context_window: {used_percentage: $1}}")"
  local l
  l=$(line 2)
  l=${l#🧠 }
  printf '%s' "${l%% *}"
}
check "bar 0%" "░░░░░░░░░░" "$(bar_for 0)"
check "bar 4%" "░░░░░░░░░░" "$(bar_for 4)"
check "bar 5%" "█░░░░░░░░░" "$(bar_for 5)"
check "bar 36%" "████░░░░░░" "$(bar_for 36)"
check "bar 100%" "██████████" "$(bar_for 100)"
check "bar over 100% is capped" "██████████" "$(bar_for 130)"
render "$(json '{context_window: {used_percentage: 99.6}}')"
check_contains "fractional percent rounds" " 100% " "$OUT"

# --- bar cells follow the gradient ---
render "$(json '{context_window: {used_percentage: 100}}')"
codes=$(printf '%s' "$RAW" | sed -n 2p | grep -o $'\033\\[38;5;[0-9]*m█' | grep -o '5;[0-9]*' | cut -d';' -f2 | tr '\n' ' ')
check "gradient order" "108 108 143 144 179 180 173 173 167 167 " "$codes"

# --- percentage color thresholds ---
pct_color() {
  render "$(json "{context_window: {used_percentage: $1}}")"
  printf '%s' "$RAW" | sed -n 2p | grep -o $'\033\\[38;5;[0-9]*m'"$1%" | grep -o '5;[0-9]*' | cut -d';' -f2
}
check "49% is green" "108" "$(pct_color 49)"
check "50% is tan" "179" "$(pct_color 50)"
check "79% is tan" "179" "$(pct_color 79)"
check "80% is red" "167" "$(pct_color 80)"

# --- token counts ---
tokens_for() {
  render "$(json "{context_window: {used_percentage: 1, total_input_tokens: $1, total_output_tokens: 0, context_window_size: 200000}}")"
  line 2 | sed 's/.*(\(.*\)\/.*/\1/'
}
check "999 tokens" "999" "$(tokens_for 999)"
check "1000 tokens" "1.0k" "$(tokens_for 1000)"
check "12345 tokens" "12.3k" "$(tokens_for 12345)"
check "1.5M tokens" "1.5M" "$(tokens_for 1500000)"

# --- cost ---
cost_for() {
  render "$(json "{cost: {total_cost_usd: $1}}")"
  local l
  l=$(line 2)
  l=${l#*💰 }
  printf '💰 %s' "${l%% *}"
}
check "cost rounds to cents" "💰 \$1.24" "$(cost_for 1.237)"
check "zero cost" "💰 \$0.00" "$(cost_for 0)"
check "tiny cost shows 4 decimals" "💰 \$0.0012" "$(cost_for 0.0012)"

# --- reset countdowns ---
reset_for() {
  render "$(json "{rate_limits: {five_hour: {used_percentage: 10, resets_at: (\$now + $1)}}}")"
  local l
  l=$(line 3)
  printf '%s' "${l%%    📅*}"
}
check "reset under an hour" "⏳ █░░░░░░░░░ 10% (5m)" "$(reset_for 330)"
check "reset under a day" "⏳ █░░░░░░░░░ 10% (3h 0m)" "$(reset_for 10830)"
check "reset over a day" "⏳ █░░░░░░░░░ 10% (4d 0h)" "$(reset_for 345630)"
check "reset in the past is hidden" "⏳ █░░░░░░░░░ 10%" "$(reset_for -60)"

# --- speed: each refresh should stay well under a second ---
start=$(date +%s%N)
for _ in 1 2 3 4 5; do printf '%s' "$FULL" | bash "$SCRIPT" >/dev/null; done
avg_ms=$((($(date +%s%N) - start) / 5000000))
if ((avg_ms < 500)); then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL: speed\n  expected under 500 ms per refresh, took %s ms\n' "$avg_ms"
fi

printf '\n%d passed, %d failed (about %d ms per refresh)\n' "$pass" "$fail" "$avg_ms"
((fail == 0))
