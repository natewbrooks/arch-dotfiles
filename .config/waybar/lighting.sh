#!/usr/bin/env bash
# Aggregated brightness widget. Tooltip shows all states.

gamma=$(cat "$HOME/.cache/gamma.value" 2>/dev/null || echo "1.0")
gamma_pct=$(awk -v g="$gamma" 'BEGIN{printf "%.0f", g*100}')

kbd_path="/sys/class/leds/asus::kbd_backlight"
kbd=$(cat "$kbd_path/brightness" 2>/dev/null || echo 0)
kbd_max=$(cat "$kbd_path/max_brightness" 2>/dev/null || echo 3)
kbd_pct=$(( kbd * 100 / (kbd_max == 0 ? 1 : kbd_max) ))

bl_dir=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
if [ -n "$bl_dir" ]; then
    bl=$(cat "$bl_dir/brightness")
    bl_max=$(cat "$bl_dir/max_brightness")
    bl_pct=$(( bl * 100 / (bl_max == 0 ? 1 : bl_max) ))
    bl_line=$'\n'" Screen     ${bl_pct}%"
else
    bl_line=""
fi

tooltip=" Brightness
 Gamma      ${gamma_pct}%
 Keyboard   ${kbd}/${kbd_max}  (${kbd_pct}%)${bl_line}

F2/F3 keyboard · F7/F8 gamma"

icon=" ${gamma_pct}%"

jq -nc --arg t "$tooltip" --arg i "$icon" '{text:$i, tooltip:$t, class:"lighting"}'
