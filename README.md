# Shortcut Coach

Learn Omarchy shortcuts a few at a time. A cap icon in the bar opens a short
"up next" list; check a shortcut off once you know it (confetti!) and the next
one takes its place. Below it, every shortcut is grouped into five sections,
Essentials through Omarchy Master. Nothing is locked: open any section to check
off what you already know, or tick a whole section with "I know these". Keys come from your live Hyprland bindings, so rebound shortcuts show
your keys, and lessons for shortcuts you don't have are skipped.

## Not sure yet? Press Practice

Practice is expanding spaced retrieval. You try the shortcut once right away,
then it comes back as a small check-in card while you work: after 10
minutes, 1 hour, 1 day, 4 days, 2 weeks and 6 weeks. "Remembered" moves it
to the next, longer gap; "Show me" retries in 10 minutes and steps it back;
after the 6-week check it's locked in.

Why these gaps:

- **Pimsleur (1967)** proposed graduated interval recall: each gap a
  multiple of the last, so every recall comes just as memory starts to
  fade. His paper gives a ratio of 5 (5s, 25s, 2m, 10m, ...), not a fixed
  list.
- **Karpicke & Roediger (2007)**: delaying the first test helps long-term
  retention, so the first check-in waits 10 minutes; recalling beats
  re-reading (Roediger & Karpicke 2006).
- **Cepeda et al. (2008)**: the best gap is a shrinking share of how long
  you want to remember, and a gap that's too long costs much less than one
  that's too short. Gaps here grow about 3-4x.
- **Sleep** consolidates motor sequences (Walker et al. 2002), so the third
  check-in comes the next day.
- **Interruptions** cost least at natural breaks: check-ins wait for a pause
  in your typing, come at least 15 minutes apart, at most 8 a day, never
  take keyboard focus, and skip fullscreen apps and time away.

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
./shortcut-coach later <id>    # start practice (spaced check-ins)
./shortcut-coach pause on      # pause check-ins (meetings)
./shortcut-coach batch 8       # learn 8 at a time (default 6)
./shortcut-coach done-section 2  # check off a whole section
./shortcut-coach reset         # start over
```

Your own lessons go to the front of the queue. Progress lives in
`~/.local/state/omarchy-shortcut-coach.json`.
