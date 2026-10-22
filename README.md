# Shortcut Coach

Learn Omarchy shortcuts a few at a time, in five levels from First Day to
Omarchy Master. A cap icon in the bar opens a short
checklist; check a shortcut off once you know it and the next one takes its
place. Keys come from your live Hyprland bindings, so rebound shortcuts show
your keys, and lessons for shortcuts you don't have are skipped.

## Install

```bash
omarchy plugin add <repo-url> --enable
```

## Add your own lessons

Anything (you, a script, an AI agent) can add a lesson with the CLI:

```bash
./shortcut-coach add "SUPER + H" "Open Hermes" "Ask the agent anything"
./shortcut-coach list          # what you're learning now
./shortcut-coach list --all    # everything, mastered included
./shortcut-coach done <id>     # check one off
./shortcut-coach undo <id>     # bring one back
./shortcut-coach batch 8       # learn 8 at a time (default 6)
./shortcut-coach reset         # start over from Level 1
```

Your own lessons go to the front of the queue. Progress lives in
`~/.local/state/omarchy-shortcut-coach.json`.
