#!/usr/bin/env bash
# Claude Code hook: track top-level sessions for waybar + play the finished noise.
# Wired to SessionStart, UserPromptSubmit, Stop, Notification, SessionEnd, SubagentStart, SubagentStop.
# Hooks firing inside a subagent carry agent_id and are ignored, except Subagent{Start,Stop}
# which keep a live agent count: the session only counts as finished once main has stopped
# and every (background) subagent is in.
DIR="${XDG_RUNTIME_DIR:-/tmp}/claude-sessions"
mkdir -p "$DIR"
in=$(cat)
ev=$(jq -r .hook_event_name <<<"$in")
[[ $ev == Subagent* ]] || ! jq -e '.agent_id' <<<"$in" >/dev/null 2>&1 || exit 0
[[ -n ${CLAUDE_TRACK_SKIP:-} ]] && exit 0  # the title generator below is itself a claude run
sid=$(jq -r .session_id <<<"$in")
f="$DIR/$sid"
now=$(date +%s)

# pid of the claude process, so the waybar side can prune sessions killed without SessionEnd
pid=$PPID
for _ in 1 2 3 4 5; do
  grep -q claude "/proc/$pid/cmdline" 2>/dev/null && break
  pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null) || break
done

# review-all exports RA_STAGE per headless stage. Interactive sessions use the cwd name.
name="${RA_STAGE:+ra:$RA_STAGE}"; group="${RA_RUN:-$sid}"
[[ -n $name ]] || name=$(basename "$(jq -r .cwd <<<"$in")")

case $ev in
  SessionEnd) rm -f "$f" ;;
  *)
    agents=$(jq -r '.agents // 0' "$f" 2>/dev/null); main=$(jq -r '.main // "active"' "$f" 2>/dev/null)
    status=$(jq -r '.status // "idle"' "$f" 2>/dev/null); done=$(jq -r '.done // false' "$f" 2>/dev/null)
    pause=$(jq -r '.pause // ""' "$f" 2>/dev/null); text=$(jq -r '.text // ""' "$f" 2>/dev/null)
    noise=""; fire=""; main=${main:-active}; agents=${agents:-0}; status=${status:-idle}; done=${done:-false}
    prompt=$(jq -r '.prompt // ""' <<<"$in")
    # Background subagents wake main with a synthetic <task-notification> prompt: not a user turn.
    [[ $ev == UserPromptSubmit && $prompt == "<task-notification>"* ]] && ev=Wake
    # /pause-timer: pause the ledger timer at every ready until `/pause-timer off`. Typed mid-turn it covers
    # that turn (live), typed while idle it starts with the next real prompt (armed) so its own turn does not trigger it.
    if [[ $ev == UserPromptSubmit && $prompt == /pause-timer* ]]; then
      ev=Pause
      if [[ $prompt == *off* ]]; then pause=""; elif [[ $status == running ]]; then pause=live; else pause=armed; fi
    fi
    # /text: same arming as /pause-timer, pings the phone at every ready until `/text off`.
    if [[ $ev == UserPromptSubmit && $prompt == /text* ]]; then
      ev=Pause
      if [[ $prompt == *off* ]]; then text=""; elif [[ $status == running ]]; then text=live; else text=armed; fi
    fi
    case $ev in
      SessionStart) status=idle; agents=0 ;;
      UserPromptSubmit) status=running; main=active; agents=0; done=false; [[ $pause == armed ]] && pause=live; [[ $text == armed ]] && text=live ;;  # ponytail: reset guards against a missed SubagentStop
      Pause|Wake) status=running; main=active ;;
      SubagentStart) agents=$((agents+1)) ;;
      SubagentStop) agents=$((agents>0 ? agents-1 : 0)) ;;
      Stop) main=stopped ;;
      Notification) status=waiting; noise=1 ;;
    esac
    # finished = main stopped and no subagent still out. `done` keeps it to one noise per user prompt,
    # since the last SubagentStop can wake main once more after the finishing Stop.
    if [[ $main == stopped ]]; then
      if (( agents == 0 )); then status=ready; [[ $done == true ]] || { noise=1; fire=1; done=true; }; else status=running; fi
    fi
    # sticky: `fire` is the once-per-prompt ready edge, so a late SubagentStop does not repeat them
    if [[ -n $fire && $pause == live ]]; then
      ( for d in 5 10 20 0; do  # ponytail: short retry, review-all's pause_timer backs off ~10 min
          [[ $(jq -r '.class // empty' <<<"$("$HOME/.config/waybar/ledger-timer.sh" pause 2>/dev/null)") == paused ]] && { pkill -RTMIN+9 waybar; break; }
          (( d )) || break; sleep "$d"; done ) >/dev/null 2>&1 &
      disown
    fi
    title=$(jq -r '.title // empty' "$f" 2>/dev/null)
    if [[ -n $fire && $text == live ]]; then
      # ponytail: phone must be reachable by KDE Connect (same LAN). Stays local, no outside service.
      # KDE Connect's sendnotifications plugin forwards this. The phone titles it with the app name.
      # Critical passes the plugin's generalUrgency=2 filter, which keeps ordinary notifications off the phone.
      # swaync ignores app names matching "claude @ ", so nothing pops up on the desktop.
      # The image never reaches the phone on kdeconnect 26.04.3: iconFromQImage() skips image.save(). Kept for when that is fixed.
      ( notify-send -u critical -a "claude @ $(uname -n)" -h "string:image-path:$HOME/.claude/hooks/claude.png" "[ready] ${title:-$name}" ) >/dev/null 2>&1 &
      disown
    fi
    started=$(jq -r '.started // empty' "$f" 2>/dev/null)
    turn=$(jq -r '.turn // empty' "$f" 2>/dev/null)
    [[ $ev == UserPromptSubmit || -z $turn ]] && turn=$now
    jq -nc --arg s "$status" --arg n "$name" --arg tr "$(jq -r '.transcript_path // ""' <<<"$in")" --arg ti "$title" --arg m "$main" --arg g "$group" --arg pz "$pause" --arg tx "$text" \
      --argjson st "${started:-$now}" --argjson t "$turn" --argjson p "${pid:-0}" --argjson a "$agents" --argjson d "$done" \
      '{status:$s, name:$n, title:$ti, transcript:$tr, started:$st, turn:$t, pid:$p, main:$m, agents:$a, done:$d, group:$g, pause:$pz, text:$tx}' > "$f"
    # One-shot haiku summary of the first prompt, written back once it lands.
    if [[ $ev == UserPromptSubmit && -z $title && -z $RA_STAGE ]]; then
      ( t=$(jq -r .prompt <<<"$in" | head -c 2000 | CLAUDE_TRACK_SKIP=1 claude -p --model haiku \
            "Title this request in at most 6 words. Output only the title, no punctuation." 2>/dev/null | head -1)
        [[ -n $t && -f $f ]] && { jq -c --arg t "$t" '.title=$t' "$f" > "$f.new" && mv "$f.new" "$f"; }
      ) >/dev/null 2>&1 &
      disown
    fi
    ;;
esac

# Noise: parent session finished or waiting on input (subagents never reach here). review-all stage 1 stays quiet.
case "${noise:-}:${RA_STAGE:-}" in
  1:fable|1:opus|:*) ;;
  1:*) paplay /usr/share/sounds/freedesktop/stereo/message-new-instant.oga & ;;
esac
exit 0
