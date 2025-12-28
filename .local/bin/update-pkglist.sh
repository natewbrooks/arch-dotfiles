#!/usr/bin/env bash
set -e

OUT_DIR="$HOME/.config"
PAC_TMP="$(mktemp)"
AUR_TMP="$(mktemp)"

pacman -Qqe | sort > "$PAC_TMP"
pacman -Qqm | sort > "$AUR_TMP"

PAC_OUT="$OUT_DIR/pkglist-pacman.txt"
AUR_OUT="$OUT_DIR/pkglist-aur.txt"

if ! cmp -s "$PAC_TMP" "$PAC_OUT"; then
  mv "$PAC_TMP" "$PAC_OUT"
else
  rm "$PAC_TMP"
fi

if ! cmp -s "$AUR_TMP" "$AUR_OUT"; then
  mv "$AUR_TMP" "$AUR_OUT"
else
  rm "$AUR_TMP"
fi
