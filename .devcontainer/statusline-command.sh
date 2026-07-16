#!/bin/bash
# Claude Code status line: shows model name, a progress bar and the
# context-window usage percentage. Mirrors the host configuration so the
# container status line looks identical to the one on the host machine.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
used=$(echo "$input" | jq -r '.context_window.used_percentage // 0')

used_int=$(printf '%.0f' "$used")

bar_width=10
filled=$(( used_int * bar_width / 100 ))
if [ "$filled" -gt "$bar_width" ]; then filled=$bar_width; fi
empty=$(( bar_width - filled ))

bar=""
for ((i=0; i<filled; i++)); do bar="${bar}#"; done
for ((i=0; i<empty; i++)); do bar="${bar}-"; done

printf "\033[2m%s [%s] %s%%\033[0m" "$model" "$bar" "$used_int"
