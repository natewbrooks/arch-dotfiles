export NVM_DIR="$HOME/.nvm"
[ -s /usr/share/nvm/init-nvm.sh ] && source /usr/share/nvm/init-nvm.sh

# Aliases
alias resume='zen-browser https://docs.google.com/document/d/1_s2Q1L99kyKsP11ck1t4rAB843GPnhyY5OfILBrDwkk/edit?tab=t.0'
alias start-gb='code -n $HOME/dev/gopanda/galaxy-bids/galaxy-bids.code-workspace'
alias start-rms='code -n $HOME/dev/personal/rate-my-slippi/rate-my-slippi.code-workspace'
alias omcor-open='gocryptfs $HOME/dev/.omcor-enc $HOME/dev/omcor'
alias omcor-close='fusermount -u $HOME/dev/omcor'

# omcor: unlock vault if locked, then open the omcor workspace. Locks on logout/shutdown.
omcor() {
  mountpoint -q ~/dev/omcor || omcor-open || return
  code -n ~/dev/omcor/omcor.code-workspace
}

# Functions
export PATH="$HOME/.local/bin:$PATH"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/home/n8/.lmstudio/bin"
# End of LM Studio CLI section

[ -f ~/.free-coding-models.env ] && . ~/.free-coding-models.env  # free-coding-models-env

# ---- Free Claude Code (FCC) ----
[ -f ~/.config/fcc/fcc.sh ] && source ~/.config/fcc/fcc.sh

# Temp / kill galaxybids server
killthatshit() {
  kill -9 $(lsof -t -i:9100) 2>/dev/null
  kill -9 $(lsof -t -i:9091) 2>/dev/null
  kill -9 $(lsof -t -i:3000) 2>/dev/null
}
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
export JAVA_HOME="$HOME/.local/jdk"

# Wireless adb: a stale server stops mDNS discovery, so restart it before reconnecting
adbup() {
  adb devices | grep -qw device && return
  adb kill-server && adb start-server
  adb devices | grep -qw device || adb connect adb-R5GL625Y9YK-PFW80s._adb-tls-connect._tcp
}

# GalaxyBids: reconnect wireless adb (if needed) then build+install on phone
droid() {
  cd ~/dev/gopanda/galaxy-bids/galaxy-bids-mobile || return
  hyprctl clients -j | grep -q '"class": "jetbrains-studio"' \
    || hyprctl dispatch exec "[workspace 9 silent] android-studio"
  adbup
  keytool -list -v -keystore android/app/debug.keystore -alias androiddebugkey -storepass android 2>/dev/null | grep 'SHA1:'
  npm run android
}

# GalaxyBids: mirror phone screen (reconnect wireless adb if needed)
mirror() {
  adbup
  scrcpy --max-fps 30 -b 4M --stay-awake "$@"
}
[ -f ~/.git-guard.sh ] && . ~/.git-guard.sh

# timesheetv2: tab-complete ./dev.sh targets, read from the script's `case` labels
_devsh() {
  local words; words=$(grep -oE '^  [a-z]+\)' "$1" | tr -d ' )')
  COMPREPLY=($(compgen -W "$words" -- "$2"))
}
complete -F _devsh ./dev.sh dev.sh

# Cycle wifi radio and reconnect (default: current SSID). Also disables power save, common lag cause on laptop only
reset-wifi() {
  local ssid=${1:-$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1}')}
  nmcli connection modify "$ssid" wifi.powersave 2
  nmcli radio wifi off && sleep 2 && nmcli radio wifi on && sleep 3
  nmcli connection up "$ssid"
}
