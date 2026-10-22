# The method behind Shortcut Coach

This explains why Shortcut Coach works the way it does and which research
each choice rests on. Where a design choice is our own judgment rather than
something a study tested, it says so.

## The problem

Keyboard shortcuts are a skill: a mapping from an intention ("put this
window on desktop 3") to a key sequence your hands produce without
thinking. People rarely learn them from a reference card. They look one up,
use it once, and look it up again next week. A full list, like Omarchy's
`Super + K`, is the right tool for looking up and the wrong one for
learning.

Most shortcut trainers ask you to stop working and sit through a lesson or a
game. That suits a first afternoon with a new system. It doesn't help with
the long tail: the shortcut you meant to start using a month ago.

Shortcut Coach takes a different approach. It lives in the bar, shows only a
few shortcuts at a time, and turns the ones you're unsure of into brief
check-ins spread across your normal work, timed by what's known about how
memory works.

## Principles and evidence

### 1. Small batches

Up next shows six shortcuts. Seeing a short list is less daunting than a long
one and keeps attention on a few items at once. This is a design judgment
informed by common practice in learning apps, not a number from a specific
study.

### Related shortcuts are taught together

Omarchy's shortcuts follow a pattern: Super + a number goes to a desktop,
adding Shift takes the window along, adding Alt as well sends it without
you. The same goes for arrows: Super + arrow moves focus, adding Shift
swaps the window. Variants like these are one lesson, with the variant in the
tip, and related contrasts (float and pop-out, the Print-key captures) sit
next to each other. Learning a rule is easier than memorizing its instances
as unrelated facts, the idea behind chunking. Grouping them this way is our
design judgment rather than a tested result.

### 2. Recall beats re-reading

Trying to remember something strengthens memory more than reading it again,
an effect known as the testing effect or retrieval practice. Roediger and
Karpicke (2006) found that students who were tested on a passage remembered
more of it two days and one week later than students who re-studied it,
though re-studying did slightly better on a test after five minutes.

That's why a check-in asks *"Do you remember how to…?"* and hides the keys
(`? ? ?`) until you ask to see them, and why Practice starts by asking you to
actually press the shortcut once.

### 3. Spacing, and expanding gaps

Practice spread out over time beats the same practice crammed together,
one of the most reliable findings in memory research (the spacing effect).

**Pimsleur (1967)** proposed *graduated interval recall* for language
learning: recall each item again just as the chance of remembering it starts
to drop, then wait longer before the next recall, since each successful
recall makes the memory last longer. His paper doesn't give a fixed list of
times. It gives a rule, each interval about five times the previous one, and
works an example: 5 seconds, 25 seconds, about 2 minutes, about 10 minutes,
and so on, with the tenth recall about four months out. The list often
quoted as "Pimsleur's schedule" (1 hour, 5 hours, 1 day, 5 days, 25 days…)
is a rounding of those powers of five. He also said one schedule won't fit
every item equally well.

**Later research refined this.** Karpicke and Roediger (2007) compared
expanding gaps with equal gaps. Expanding gaps did better on a test 10
minutes later, equal gaps did better two days later, and the factor that
mattered most for long-term retention was *delaying the first test*: a test
right after learning is too easy to do much good. Kang et al. (2014) found
equal and expanding schedules came out about the same at eight weeks, but
expanding gaps kept people remembering more successfully *during* practice,
which matters for a tool people use while they work.

### 4. How long the gaps should be

**Cepeda et al. (2008)** tested more than 1,300 people across many gap
lengths and retention periods. The best gap depends on how long you want to
remember something: it's a sizable share of a one-week retention period and
a much smaller share of a one-year period. They also found the cost is
lopsided. A gap that's too long costs much less than one that's too short.

Shortcut Coach's gaps grow about three to four times each step: 10 minutes,
1 hour, 1 day, 4 days, 2 weeks, 6 weeks. That's gentler than Pimsleur's
five times, and the choice errs on the side of waiting a bit long rather
than asking too soon. The first check-in waits 10 minutes rather than coming
immediately, following Karpicke and Roediger.

### 5. Sleep

Skills built from finger sequences improve with sleep. In Walker et al.
(2002), people practicing a finger-tapping sequence were about 20% faster
after a night's sleep, with little improvement over the same hours awake. So
the third check-in comes the next day, with a night's sleep in between,
instead of a few hours later.

### 6. Mistakes

A check-in is a flash card: the question first, then **Show answer**, then you
grade yourself, the show-then-grade flow of Anki and similar apps. Recalling
before seeing the answer is the retrieval practice; grading after it keeps
the grade honest. When you press **Missed it**, the
shortcut comes back in 10 minutes and steps back one gap (two from the
2-week check on, since a miss that late suggests the memory is weaker than
the schedule assumed). Pimsleur's rule was simply to show the right answer
whether or not you got it; the step-back rule follows modern
spaced-repetition software such as Anki, which sends a forgotten card back
through short relearning steps. It steps back rather than restarting
because relearning something you once knew is much faster than learning it
new (the savings effect, going back to Ebbinghaus), which modern schedulers
such as FSRS also build in. After three misses a shortcut is marked
*tricky*. These specific numbers are our judgment, not tested values.

### 7. Interruptions

A check-in is an interruption, and interruptions have a cost. Mark et al.
(2008) found that interrupted people finished work faster but reported more
stress and frustration. Research on interruption timing generally finds
that interrupting at a natural break in a task costs much less than
interrupting in the middle of it.

So check-ins wait for a few seconds' pause in your typing, never take
keyboard focus, skip fullscreen apps (calls, video) and time away from the
computer, come at least 15 minutes apart, and stop at 8 a day. **Pause**
turns them off. The specific limits are our judgment.

### 8. Locked in

A shortcut counts as locked in after passing the six-week check-in. By then
it has been recalled successfully six times over about two months, with the
last gap roughly six weeks long. We don't claim it will never fade, only
that it has been recalled successfully after long gaps.

## What we're not doing yet

- **Counting real use.** Using a shortcut for real during the day is the
  best practice there is and should count as a passed check-in. Hyprland
  doesn't report when a key binding fires, so this needs more work.
- **Adapting per shortcut.** Pimsleur noted that items differ, and modern
  schedulers such as FSRS fit intervals to each item from your answers. The
  current schedule is the same for every shortcut apart from the misses.
- **Measuring results.** We haven't tested whether the coach makes people
  learn shortcuts faster. These are design choices grounded in research on
  memory, not results from a study of this tool.

## References

- Pimsleur, P. (1967). A memory schedule. *The Modern Language Journal,
  51*(2), 73–75. [Full text (ERIC)](https://files.eric.ed.gov/fulltext/ED012150.pdf)
- Landauer, T. K., & Bjork, R. A. (1978). Optimum rehearsal patterns and
  name learning. In *Practical Aspects of Memory* (pp. 625–632). Academic
  Press.
- Roediger, H. L., & Karpicke, J. D. (2006). Test-enhanced learning: Taking
  memory tests improves long-term retention. *Psychological Science, 17*(3),
  249–255. [PDF](https://psychology.ecu.edu/wp-content/pv-uploads/sites/216/2019/03/Roediger-Karpicke-2006.pdf)
- Karpicke, J. D., & Roediger, H. L. (2007). Expanding retrieval practice
  promotes short-term retention, but equally spaced retrieval enhances
  long-term retention. *Journal of Experimental Psychology: Learning,
  Memory, and Cognition, 33*(4), 704–719.
  [PDF](https://www.gwern.net/doc/psychology/spaced-repetition/2007-karpicke.pdf)
- Cepeda, N. J., Vul, E., Rohrer, D., Wixted, J. T., & Pashler, H. (2008).
  Spacing effects in learning: A temporal ridgeline of optimal retention.
  *Psychological Science, 19*(11), 1095–1102.
  [PDF](https://www.evullab.org/pdf/CepedaVulRohrerWixtedPashler-PS-2008.pdf)
- Kang, S. H. K., Lindsey, R. V., Mozer, M. C., & Pashler, H. (2014).
  Retrieval practice over the long term: Should spacing be expanding or
  equal-interval? *Psychonomic Bulletin & Review, 21*(6), 1544–1550.
- Walker, M. P., Brakefield, T., Morgan, A., Hobson, J. A., & Stickgold, R.
  (2002). Practice with sleep makes perfect: Sleep-dependent motor skill
  learning. *Neuron, 35*(1), 205–211.
- Mark, G., Gudith, D., & Klocke, U. (2008). The cost of interrupted work:
  More speed and stress. *Proceedings of CHI 2008*, 107–110.
  [PDF](https://www.interruptions.net/literature/Mark-CHI08.pdf)
- Anki manual, deck options (learning and relearning steps).
  [docs.ankiweb.net](https://docs.ankiweb.net/deck-options.html)
