# Shortcut Coach

Learn Omarchy shortcuts a few at a time. A cap icon in the bar opens a short
"up next" list; check a shortcut off once you know it (confetti!) and the next
one takes its place. Below it, every shortcut is grouped into five sections,
Essentials through Omarchy Master. Nothing is locked: open any section to check
off what you already know, or tick a whole section with "I know these". Keys come from your live Hyprland bindings, so rebound shortcuts show
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
./shortcut-coach done-section 2  # check off a whole section
./shortcut-coach reset         # start over
```

Your own lessons go to the front of the queue. Progress lives in
`~/.local/state/omarchy-shortcut-coach.json`.
