#!/usr/bin/env bash
# Aggregated system stats for a single waybar widget. Output JSON; tooltip holds the detail.

# Sample /proc/stat twice; top -bn1 only reports since-boot averages.
read -r _ u1 n1 s1 i1 w1 q1 sq1 _ < /proc/stat
read -r _ u2 n2 s2 i2 w2 q2 sq2 _ < <(sleep 0.3; cat /proc/stat)
idle=$(( (i2 + w2) - (i1 + w1) ))
total=$(( (u2+n2+s2+i2+w2+q2+sq2) - (u1+n1+s1+i1+w1+q1+sq1) ))
cpu=$(awk "BEGIN { printf \"%.0f\", $total ? 100 * (1 - $idle / $total) : 0 }")

read -r total used <<<"$(free -m | awk '/^Mem:/ { print $2, $3 }')"
mem_pct=$(( used * 100 / total ))

# -P forces single-line output so long device names don't wrap and break parsing.
read -r disk_pct disk_used disk_total <<<"$(df -hP / | awk 'NR==2 { print $5, $3, $2 }')"

temp=$(sensors 2>/dev/null | awk -F'[:+°]' '/^Package id 0:|^Tctl:|^Tdie:|^edge:/ { gsub(/ /,"",$3); print $3; exit }')
[ -z "$temp" ] && temp="?"

ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
[ -z "$ssid" ] && ssid="—"
ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{ for(i=1;i<=NF;i++) if($i=="src"){ print $(i+1); exit } }')
[ -z "$ip" ] && ip="—"

uptime_str=$(uptime -p 2>/dev/null | sed 's/^up //')
load=$(awk '{print $1", "$2", "$3}' /proc/loadavg)

tooltip=" System
 CPU       ${cpu}%   (load ${load})
 RAM       ${mem_pct}%   ${used} / ${total} MB
 Disk /    ${disk_pct}   ${disk_used} / ${disk_total}
 Temp      ${temp}°C
 Net       ${ssid}   ${ip}
 Up        ${uptime_str}"

jq -nc --arg t "$tooltip" '{text:"", tooltip:$t, class:"sysinfo"}'
