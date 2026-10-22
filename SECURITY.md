# Security

Shortcut Coach runs as your user inside the Omarchy shell, like every Omarchy
plugin (plugins are not sandboxed). What it does:

- Reads your key bindings with `omarchy-menu-keybindings --print`.
- Keeps progress in `~/.local/state/omarchy-shortcut-coach.json` (plus a
  `.bak` copy and a `.lock` file), readable only by you.
- Runs `hyprctl` to check for fullscreen windows and to focus its own window.
- Watches for a few seconds of keyboard idle time (Wayland idle notify) to
  time check-ins. It never records what you type.

It makes no network requests, needs no privileges, and installs nothing
outside the plugin folder.

## Reporting a problem

Please open a GitHub issue, or for anything sensitive, use GitHub's private
vulnerability reporting on this repository.
