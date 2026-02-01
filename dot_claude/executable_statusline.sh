#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
PERCENT_USED=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | xargs printf "%.1f")

# Color coding based on context usage
if (( $(echo "$PERCENT_USED > 80" | bc -l) )); then
    COLOR="\033[31m"  # Red for high usage
elif (( $(echo "$PERCENT_USED > 50" | bc -l) )); then
    COLOR="\033[33m"  # Yellow for moderate usage
else
    COLOR="\033[32m"  # Green for low usage
fi
RESET="\033[0m"

echo -e "[$MODEL] ${COLOR}Context: ${PERCENT_USED}%${RESET}"
