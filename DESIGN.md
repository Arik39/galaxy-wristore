---
name: Galaxy Wristore
description: The everyday home for a Tizen Galaxy Watch, iPhone and Android, with the watch's own face as the screen.
colors:
  void: "#09090A"
  graphite: "#141518"
  graphite-high: "#1C1D21"
  ink: "#EDEFF2"
  ink-soft: "#A8ADB5"
  ink-faint: "#7A7F88"
  alert: "#E2554F"
  line: "#EDEFF22E"
  line-faint: "#EDEFF214"
typography:
  large-title:
    fontFamily: "Archivo, sans-serif"
    fontSize: "26px"
    fontWeight: 300
    lineHeight: 1.23
    letterSpacing: "0.2px"
    fontVariation: "'wdth' 125, 'wght' 300"
  title:
    fontFamily: "Archivo, sans-serif"
    fontSize: "20px"
    fontWeight: 380
    lineHeight: 1.3
    fontVariation: "'wdth' 125, 'wght' 380"
  name:
    fontFamily: "Archivo, sans-serif"
    fontSize: "18px"
    fontWeight: 400
    lineHeight: 1.28
    fontVariation: "'wdth' 125, 'wght' 400"
  figure:
    fontFamily: "Archivo, sans-serif"
    fontSize: "26px"
    fontWeight: 350
    lineHeight: 1.15
    fontFeature: "'tnum'"
    fontVariation: "'wdth' 112, 'wght' 350"
  figure-small:
    fontFamily: "Archivo, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.29
    fontFeature: "'tnum'"
    fontVariation: "'wdth' 112, 'wght' 400"
  body:
    fontFamily: "system-ui, -apple-system, Roboto, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.375
  body-strong:
    fontFamily: "system-ui, -apple-system, Roboto, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.375
  secondary:
    fontFamily: "system-ui, -apple-system, Roboto, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.36
  caption:
    fontFamily: "system-ui, -apple-system, Roboto, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.31
  label:
    fontFamily: "system-ui, -apple-system, Roboto, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.36
    letterSpacing: "2.2px"
  button:
    fontFamily: "system-ui, -apple-system, Roboto, sans-serif"
    fontSize: "12px"
    fontWeight: 700
    lineHeight: 1.33
    letterSpacing: "2.4px"
rounded:
  control: "3px"
  panel: "6px"
spacing:
  xs: "4px"
  s: "8px"
  m: "12px"
  l: "16px"
  xl: "20px"
  screen: "22px"
  xxl: "24px"
  section: "32px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.void}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    padding: "14px 20px"
    height: "46px"
  button-outlined:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    padding: "14px 20px"
    height: "46px"
  button-destructive:
    backgroundColor: "transparent"
    textColor: "{colors.alert}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    padding: "14px 20px"
    height: "46px"
  segment:
    backgroundColor: "transparent"
    textColor: "{colors.ink-soft}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
  segment-selected:
    backgroundColor: "{colors.graphite-high}"
    textColor: "{colors.ink}"
  input:
    backgroundColor: "{colors.graphite}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
  sheet:
    backgroundColor: "{colors.graphite}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
  snackbar:
    backgroundColor: "{colors.graphite-high}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.panel}"
  demo-badge:
    backgroundColor: "transparent"
    textColor: "{colors.ink-faint}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "3px 8px"
  tab-bar:
    backgroundColor: "{colors.void}"
    textColor: "{colors.ink-faint}"
    height: "56px"
---

# Design System: Galaxy Wristore

## Overview

**Creative North Star: "The Face Is the Screen"**

The watch's own face leads. One real face picture, big and round inside a hairline bezel of 60 ticks, sits on near-black, and everything else stays quiet beneath it. The world is an instrument: a dark field with a faint dot grid, hairline rules, one ink white, and one red that appears only where something would be lost. It is futuretech and minimal, and it never glows.

Density is low and text is sparse. A screen carries a wide, light Archivo title top left, a few tracked capital labels, figures set like readouts, and one white button. The platform's own face carries body text, so the app reads native on iPhone and on Android while the titles, names and figures carry the identity. The coloured element on any screen is usually the user's own watch face. The interface itself has no colour beyond ink, greys and the risk red.

Rejected and not part of this world: a violet palette, glow or neon, and a 3D watch model or product render above a settings list.

**Key Characteristics:**
- Near-black field (void) under a 16 px dot grid of 6% white dots.
- One ink white for text, live state and progress; greys for quieter text; no second accent.
- Red only for what a reset would lose and for refusals.
- Hairlines at 18% ink; nearly square corners (3 px controls, 6 px containers).
- Archivo, wide and light, for titles, names and figures; tracked 11 px capitals for labels.
- The bezel: 60 ticks that turn, light up as progress, and spin once when a job is done.
- Exponential ease-out from 280 to 420 ms, and Reduce Motion honoured everywhere.

## Colors

A monochrome instrument palette: near-black, graphite, one ink white with two quieter greys, and a single warning red.

### Primary
- **Instrument Ink** (ink): All primary text, icons, live state, progress ticks, checkbox fills, input focus borders, the filled primary button and the tab bar's open-tab dot. Live state is drawn in ink because the world has no second accent. 17.3:1 on void.

### Secondary
- **Reset Red** (alert): Only what a reset would lose (unbacked faces and apps, the red dot on the rail's backup icon and on grid pictures, a "Not backed up" value, the backed-up count when some are missing) and refusals (failed verification, remove and delete actions). 5.3:1 on void.

### Neutral
- **Void** (void): The screen background under the dot grid, the tab bars, and the text on a white button.
- **Graphite** (graphite): Bottom sheets, dialogs, text field fills and picture placeholders.
- **Graphite High** (graphite-high): Snackbars, popup menus and the selected segment.
- **Soft Ink** (ink-soft): Secondary lines, captions, section header labels and unselected segments. 8.8:1 on void.
- **Faint Ink** (ink-faint): Field labels, spec-row labels, hint text, inactive tab icons and the DEMO badge. About 4.9:1 on void and 4.5:1 on graphite; it is the quietest text colour allowed.
- **Hairline** (line, ink at 18%): Dividers, spec-row rules, outlined control borders, sheet, dialog and menu edges, the DEMO badge outline, and the bezel's outer ring.
- **Faint Hairline** (line-faint, ink at 8%): Only for borders under or over a bar that content scrolls beneath (title bars, tab bars, the restore action bar), the bezel's inner ring, and secondary picture rings (grid tiles, initials placeholders).

### Named Rules
**The One Ink Rule.** Text, icons, live state and progress are all ink or its greys. There is no brand accent, no glow and no neon; the colour on screen belongs to the user's watch faces.

**The Red Means Loss Rule.** Red marks only what a reset would destroy and things the app or watch refuses. Never use it for emphasis, decoration, branding or a generic error tint.

**The 18 Percent Rule.** A hairline is ink at 18%. The 8% faint hairline is reserved for scroll-under bar borders, the bezel's inner ring and secondary picture rings; it is not a quieter divider.

## Typography

**Display Font:** Archivo variable (bundled), set wide (wdth 125, 112 for figures) and light.
**Body Font:** The platform face (SF Pro on iOS, Roboto on Android).
**Label Font:** The platform face, 11 px semibold tracked capitals.

**Character:** A wide, light grotesque gives titles and figures the feel of engraving on a watch case, while the native body face keeps reading text familiar on each platform.

### Hierarchy
- **Large Title** (Archivo 300, 26/32, wdth 125): A section's title top left ("My Watch", "Backup") and a pushed page's collapsing title. Follows the text size up to 1.5x, then holds.
- **Title** (Archivo 380, 20/26): Sheet titles and empty-state headings.
- **Name** (Archivo 400, 18/23): A face's or app's name, such as the name under the home disc; at 16 px it is the small centred title of a scrolled bar.
- **Figure** (Archivo 350, 26/30, wdth 112, tabular): Readouts such as battery and backed-up count, so digits do not jump as they change.
- **Figure Small** (Archivo 400, 17/22, wdth 112, tabular): Job percentages.
- **Body** (platform 400, 16/22): Values, list titles and explanations; Body Strong (600) for emphasis.
- **Secondary** (platform 400, 14/19) and **Caption** (platform 400, 13/17): Subtitles and metadata lines in soft ink.
- **Label** (platform 600, 11/15, 2.2 px tracking, uppercase): Spec-row and readout labels, section headers, status lines. 11 px is the floor; nothing is set smaller.
- **Button** (platform 700, 12/16, 2.4 px tracking, uppercase): Every button and segment label.

### Named Rules
**The Engraved Title Rule.** Titles, names and figures use Archivo wide and light. Never use a tall condensed or bold display style.

**The Tracked Capitals Rule.** Labels and buttons are small tracked capitals; running text stays in sentence case in the platform face.

**The Text Size Rule.** Every style follows the user's text size. Titles and bar controls are capped at 1.5x, and labels may wrap to two lines rather than clip.

## Layout

A single column with 22 px screen margins. Sections are separated by 32 px, and spacing follows one rhythm (4, 8, 12, 16, 20, 24 px). A section's title row sits top left with its actions on the right, and its height grows with text size. Pushed pages put a back chevron in a 52 px bar above a large title that hands over to a small centred one as the page scrolls. Bars become solid void at 95% with a faint hairline only once content scrolls under them.

Home is a full-screen feed. The face disc runs about 80% of the width and sits under the title. A rail of three line icons rides its right edge (details, back up with a red dot when at risk, discover). Below come the face name and one status label, then two readouts over a hairline split by a vertical hairline, then one full-width white button. Lists are spec sheets: a label on the left, the value flush right, and a hairline under each row. Face and package grids use two or three columns.

On tablets and in landscape the content is capped at 720 dp and centred. Pinned bottom actions sit above the tab bar. Every screen paints the Backdrop, and pushed pages paint their own so the page beneath does not show through.

## Elevation & Depth

The interface is flat and gets its depth from tone and hairlines. The background is void with a dot grid, sheets and dialogs are graphite, and snackbars, menus and selected segments are graphite high. Each of these carries a hairline edge instead of a shadow. Bars over scrolled content turn solid. Only the signature disc has real depth: a soft drop shadow, a faint pool of light beneath it and a glass sheen across the display, so it reads as a physical watch face.

### Shadow Vocabulary
- **Disc Shadow** (`box-shadow: 0 18px 40px rgba(0,0,0,0.6)`): Under the FaceDisc's round display only.
- **Disc Pool** (radial gradient of ink at 12% to transparent, an ellipse 80% of the disc wide): A faint light beneath the disc.
- **Glass** (linear gradient of white at 10% to transparent, from the top left): Over the disc's display.

### Named Rules
**The Flat Interface Rule.** Controls, rows, sheets and menus never cast shadows; they are separated by tone and an 18% hairline. Depth belongs to the watch face alone.

## Shapes

The corners are precise and nearly square: 3 px on buttons, segments, fields and the DEMO badge, and 6 px on sheets, dialogs, menus and snackbars. Lines are 1 px hairlines. Circles appear only where the world is round: the face disc and its bezel, round face pictures, status dots and the 4 px tab marker. App pictures are rounded squares (24% of their size). Icons are path-drawn on a 24-unit grid with a 1.7 stroke and round caps and joins.

## Components

### Buttons
Rectangles with a tracked capital label.
- **Shape:** Nearly square (3 px), at least 46 px tall, with 20 px horizontal padding. A long label wraps to two lines before it ellipsizes.
- **Primary:** Filled ink with void text. There is one per screen, and it is usually full width.
- **Outlined:** Transparent with ink text and a 45% ink border, for every other action.
- **Destructive:** Outlined in red with red text (remove from watch, delete).
- **Pressed / Disabled:** A filled button drops to 85% when pressed, and an 8% overlay tints the rest. Disabled is ink at 18% with faint text; outlined borders fade to 20%.
- **Text actions:** Section header and bar actions ("ALL") are bare ink text in the button style.

### Segmented Choice
- **Style:** 3 px corners, hairline outline, button-style labels, no check icon.
- **State:** The selected segment is lit graphite high with ink text. Unselected segments are transparent with soft ink. White is never used for a selected segment, because it is reserved for the screen's one primary button. Segments scale with text size only up to 1.5x.

### Inputs / Fields
- **Style:** A graphite fill, 3 px corners, a hairline border, faint ink hint text and a line icon at the start.
- **Focus:** The border turns ink.

### Checkboxes
- **Style:** Unchecked is a faint ink outline (1.5 px). Checked fills with ink and shows a void check mark.

### Lists and Spec Rows
- **Spec Row:** An uppercase label on the left (up to half the width, two lines at most) and a body value flush right, with a hairline below. The value turns red only when it is at risk.
- **Section Header:** A soft-ink tracked label over a hairline, with an optional text action or info icon on the right.
- **Package rows:** A round or rounded-square picture, a body title and a caption metadata line.

### Readout
A figure over its label: a tabular Archivo figure above a faint tracked label. A new value fades and slides up 30% on the standard ease. The figure turns red when it is at risk, and a long figure shrinks to fit rather than clip.

### Status and Progress
- **Status Dot:** A 6 px ink dot that pulses a fading halo while a job runs. With Reduce Motion it stays still.
- **Risk Dot:** A 9 px red dot ringed in void, on what a reset would remove.
- **Tick Bar / Job Progress:** The bezel's 60 ticks in a line, every fifth one taller. They light from the left as the job progresses. A nine-tick trail runs along them when the amount is unknown, and with Reduce Motion every fifth tick is lit instead. Above the ticks sits the job's step in ink tracked capitals, with the percentage in small figures.
- **DEMO Badge:** "DEMO" in faint tracked capitals inside a hairline 3 px outline. It always marks demo data.

### Navigation
- **Tab bar:** Icons only, on void with a faint hairline above. Inactive icons are faint ink and the open one is ink with a 4 px ink dot beneath. Labels remain for screen readers and tooltips. iOS uses a CupertinoTabBar (56 px) and Android an M3 NavigationBar (64 px, no indicator pill). Each tab keeps its own navigator.
- **Page transitions:** Follow the platform: a push with edge-swipe back on iOS, and predictive back on Android.

### FaceDisc (signature)
The user's real face picture, clipped round, inside a bezel drawn as a hairline outer ring, a faint inner ring and 60 ticks (every fifth one longer and brighter), with a fixed notch at twelve.
- **Swipe:** Pages between faces. The bezel turns five minute-ticks per face, with a haptic tick at each face.
- **Progress:** Lights the ticks from twelve. An unknown amount sends a nine-tick trail round the ring.
- **Completion:** One full 420 ms ease-out turn of the bezel with a haptic.
- **Dimmed:** Darkens the display by 62% for a watch that is asleep or out of reach.
- **Reduce Motion:** The ring stays still and pages snap at once. Screen readers get increase and decrease actions.
- **Grid pictures:** Face pictures in grids carry a static 60-tick bezel or a faint ring.

### Motion
Exponential ease-out (cubic-bezier(0.16, 1, 0.3, 1)) runs from an already visible state, and every animation can be interrupted. Use 280 ms for swaps, bar fades and page snaps, and 420 ms for the bezel turn, dimming and the picture viewer. Loops (the status pulse at 1.4 s and tick trails at 1.6 s) stop under Reduce Motion, and duration-based transitions become instant.

## Do's and Don'ts

### Do:
- **Do** set every screen on void with the 16 px dot grid, and let the user's face pictures be the colour.
- **Do** give a screen exactly one filled ink button; make every other action outlined, and destructive actions outlined in red.
- **Do** use red only for what a reset would lose and for refusals.
- **Do** draw hairlines at 18% ink; keep 8% for scroll-under bar borders, the bezel's inner ring and secondary picture rings.
- **Do** set titles, names and figures in Archivo wide and light, figures with tabular digits, and labels in 11 px tracked capitals.
- **Do** show progress as lit bezel ticks, either on the FaceDisc or as a Tick Bar.
- **Do** label demo data with the DEMO badge.
- **Do** animate with the exponential ease-out over 280 to 420 ms and give every motion a Reduce Motion path.
- **Do** cap content at 720 dp on tablets and let titles grow with text size up to 1.5x.

### Don't:
- **Don't** introduce a second accent colour, a violet palette, glow or neon.
- **Don't** put a 3D watch model or product render where the user's real face picture belongs.
- **Don't** fill a selected segment, chip or tab with white; white belongs to the one primary button.
- **Don't** cast shadows from controls, rows or sheets; only the FaceDisc has depth.
- **Don't** round corners beyond 3 px on controls or 6 px on containers.
- **Don't** use a tall condensed or bold display style for titles.
- **Don't** set any text below 11 px or any text colour quieter than faint ink.
- **Don't** use icon fonts or emoji glyphs; draw icons as 1.7-stroke line paths on the 24 grid.
