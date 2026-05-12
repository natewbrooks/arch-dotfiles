export NVM_DIR="$HOME/.nvm"
[ -s /usr/share/nvm/init-nvm.sh ] && source /usr/share/nvm/init-nvm.sh

# Aliases
alias resume='zen-browser https://docs.google.com/document/d/1_s2Q1L99kyKsP11ck1t4rAB843GPnhyY5OfILBrDwkk/edit?tab=t.0'
alias start-gb='code -n $HOME/dev/gopanda/galaxy-bids/galaxy-bids.code-workspace'
alias start-rms='code -n $HOME/dev/rate-my-slippi/rate-my-slippi.code-workspace'

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