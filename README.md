# Arch Linux Dotfiles

Personal dotfiles for an Arch Linux system.

This repository tracks selected configuration files under `~/.config` and related shell settings to allow quick rebuilds on new machines.

## Structure

- `.config/` – Application and window manager configs (Hyprland, Waybar, Kitty, etc.)
- `.bashrc` – Interactive shell configuration
- `.bash_profile` – Login shell entry point

Only explicitly whitelisted files are tracked. Everything else in `$HOME` is ignored by default.

## Usage

Clone into `$HOME`:

```bash
git clone <repo-url> ~
```

## Per-machine config

`~/.config/hypr/hyprland.conf` ends with `source = ~/.config/hypr/local.conf`. That file is untracked and holds machine-specific lines: monitors, GPU env vars, waybar launcher, and plugin binds (e.g. split-monitor-workspaces on the desktop). Create it on each machine, at minimum:

```
monitor = , preferred, auto, 1
exec-once = waybar
```
