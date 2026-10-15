#!/usr/bin/env bash
# Pomodoro timer for waybar. State stored in a single key=value file.

STATE_DIR="$HOME/.cache/waybar-pomodoro"
STATE_FILE="$STATE_DIR/state"
CONF_FILE="$HOME/.config/waybar/pomodoro.conf"
mkdir -p "$STATE_DIR"

[ -f "$CONF_FILE" ] || cat >"$CONF_FILE" <<EOF
# Durations in minutes
WORK_MIN=25
BREAK_MIN=5
EOF

WORK_MIN=25
BREAK_MIN=5
# shellcheck disable=SC1090
. "$CONF_FILE"

# State: status=idle|running|paused, phase=work|break, end=<epoch>, remaining=<sec>
STATUS=idle
PHASE=work
END=0
REMAINING=$((WORK_MIN*60))
if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
fi

save() {
    cat >"$STATE_FILE" <<EOF
STATUS=$STATUS
PHASE=$PHASE
END=$END
REMAINING=$REMAINING
EOF
}

phase_seconds() {
    case "$PHASE" in
        work) echo $((WORK_MIN*60)) ;;
        break) echo $((BREAK_MIN*60)) ;;
    esac
}

now=$(date +%s)

case "$1" in
    toggle)
        case "$STATUS" in
            idle)
                REMAINING=$(phase_seconds)
                END=$((now + REMAINING))
                STATUS=running
                ;;
            running)
                REMAINING=$((END - now))
                [ "$REMAINING" -lt 0 ] && REMAINING=0
                STATUS=paused
                ;;
            paused)
                END=$((now + REMAINING))
                STATUS=running
                ;;
        esac
        save
        pkill -RTMIN+8 waybar 2>/dev/null
        exit 0
        ;;
    reset)
        STATUS=idle
        PHASE=work
        REMAINING=$((WORK_MIN*60))
        END=0
        save
        pkill -RTMIN+8 waybar 2>/dev/null
        exit 0
        ;;
    skip)
        if [ "$PHASE" = work ]; then PHASE=break; else PHASE=work; fi
        REMAINING=$(phase_seconds)
        if [ "$STATUS" = running ]; then
            END=$((now + REMAINING))
        else
            STATUS=idle
            END=0
        fi
        save
        pkill -RTMIN+8 waybar 2>/dev/null
        exit 0
        ;;
    edit)
        kitty --class waybar-pomodoro-edit -e "${EDITOR:-nvim}" "$CONF_FILE" >/dev/null 2>&1 &
        exit 0
        ;;
esac

# Status output
if [ "$STATUS" = running ]; then
    REMAINING=$((END - now))
    if [ "$REMAINING" -le 0 ]; then
        notify-send -a pomodoro "Pomodoro" "$PHASE complete"
        if [ "$PHASE" = work ]; then PHASE=break; else PHASE=work; fi
        REMAINING=$(phase_seconds)
        END=$((now + REMAINING))
        save
    fi
fi

mins=$((REMAINING / 60))
secs=$((REMAINING % 60))
time_str=$(printf "%02d:%02d" "$mins" "$secs")

case "$PHASE" in
    work)  icon="" ;;
    break) icon="" ;;
esac

case "$STATUS" in
    running) state_icon="" ;;
    paused)  state_icon="" ;;
    idle)    state_icon="" ;;
esac

tooltip="Pomodoro - ${PHASE} (${STATUS})
Left click: start/pause
Right click: reset
Middle click: edit
Scroll: skip phase
Work: ${WORK_MIN}m  Break: ${BREAK_MIN}m"

jq -nc --arg t "$icon $time_str $state_icon" \
       --arg tt "$tooltip" \
       --arg c "pomo-$PHASE pomo-$STATUS" \
       '{text:$t, tooltip:$tt, class:$c}'
