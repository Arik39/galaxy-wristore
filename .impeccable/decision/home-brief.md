# Home: My Watch

Scope: the app's Home tab, the first screen and the hub of Galaxy Wristore (iOS and Android, Flutter). Visitor mode: Operate.

Audience and job: Tizen Galaxy Watch owners managing their watch over Wi-Fi, often after a reset or a move to an iPhone. On this screen they:
- see at once whether the watch is connected and safe;
- reach faces, apps and backup;
- act on the one thing at risk.

Constraints:
- The watch states have to stay readable: not set up, connecting, connected, busy with another device, Debugging off or asleep.
- Figures are real when connected. Demo data is labelled as demo and is never shipped as real.
- Reduce Motion is honoured.

Chosen direction: the Full-Screen Feed, a dealt challenger. The user switched to it after seeing the first build (Night Showroom with a 3D watch). The user then pinned three things:
- futuretech, minimal, never neon;
- far less text, and a different title style from the tall condensed one;
- their own watch face as the hero, with no 3D model (neither the procedural watch nor the CC-BY Gear S3 Classic looked real enough).

Memorable moment: your real face, big, inside a hairline bezel that turns as you swipe to your next face, with a tick you can feel at each step.

Unresolved:
- Which original-app features are reachable over sdb. They are verified per feature before they are designed as working.
- Languages beyond English.

## Direction contract

THESIS: The watch's own face is the screen. One real face picture, big and round inside a hairline bezel, leads every visit; everything else stays quiet below it. It refuses the category default: a product render above a settings list.

OWN-WORLD:
- Near-black (#09090A) under a faint 16 px dot grid.
- Hairlines at 18% white, square-ish 3 px corners.
- One ink white (#EDEFF2) for text, live state and progress; greys for quiet text.
- Red (#E2554F) only for what is at risk. No other colour, no glow, no neon.
- Archivo expanded and light for titles and figures; the system face for body.
- Tracked small capitals for labels. White line icons.

STORY: The owner sees their face as it is on the wrist, swipes the bezel round through the faces they have, sees at once what is not backed up, and acts with the one white button.

FIRST VIEWPORT:
- "My Watch" top left, its state top right.
- The face disc at about 80% width, ringed by a 60-tick bezel.
- A rail of three white line icons on the right edge: details, back up (red dot when at risk), discover.
- The face's name centred under the disc, with one tracked label.
- Two figures over a hairline: battery, and backed up (red when at risk).
- One full-width white button, then the icon tab bar.

FORM:
- Full-Screen Feed, fused with the user's futuretech pins: one item owns the screen, a right rail, a low caption, the next item one swipe away. Dealt challenger, chosen by the user after the first build. seed:5e9a04a639c164f1
- Signature interaction, the bezel:
  - Swiping between faces turns the ring, with a haptic tick for each face.
  - While the phone talks to the watch, the ring's ticks light up one by one as the progress. When the job is done, the ring makes one full turn.
- Motion: exponential ease-out over 280 to 420 ms, always interruptible. Reduce Motion gives instant swaps and a still ring.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
