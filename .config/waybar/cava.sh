#!/usr/bin/env bash
# Waybar cava bridge — emits unicode bar glyphs from cava ascii output.

CFG="$HOME/.config/waybar/cava-waybar.conf"
BARS=10

if [ ! -f "$CFG" ]; then
    mkdir -p "$(dirname "$CFG")"
    cat > "$CFG" <<EOF
[general]
bars = $BARS
framerate = 60
sensitivity = 100
autosens = 1
[input]
method = pipewire
source = auto
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
EOF
fi

# 8-level block characters keyed 0..7
dict="s/;/ /g;s/0/▁/g;s/1/▂/g;s/2/▃/g;s/3/▄/g;s/4/▅/g;s/5/▆/g;s/6/▇/g;s/7/█/g"

exec cava -p "$CFG" | sed -u "$dict"
