#!/usr/bin/env bash
# Battery widget: icon + percent. Tooltip adds status, time left, and the brightness readout (lighting.sh).
# No battery (desktop) prints empty text, so waybar hides the module.

bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
[ -n "$bat" ] || { echo '{"text":""}'; exit; }

cap=$(<"$bat/capacity")
status=$(<"$bat/status")
icons=($'' $'' $'' $'' $'')
icon=${icons[$(( cap >= 100 ? 4 : cap / 20 ))]}
class=
if [ "$status" = Charging ]; then icon=$''; class=charging
elif [ "$status" = "Not charging" ] || [ "$status" = Full ]; then icon=$''; class=plugged
elif [ "$cap" -le 15 ]; then class=critical
elif [ "$cap" -le 30 ]; then class=warning
fi

# Time left from energy/power (µWh / µW), discharging only.
left=
if [ "$status" = Discharging ] && [ -r "$bat/power_now" ] && [ "$(<"$bat/power_now")" -gt 0 ]; then
  m=$(( $(<"$bat/energy_now") * 60 / $(<"$bat/power_now") ))
  left=$(printf '   (%dh %02dm left)' $((m / 60)) $((m % 60)))
fi

light=$("$HOME/.config/waybar/lighting.sh" 2>/dev/null | jq -r '.tooltip // empty')
jq -nc --arg t "$icon $cap%" --arg c "$class" --arg tip " Battery    $cap%  $status$left

$light" '{text: $t, class: $c, tooltip: $tip}'
