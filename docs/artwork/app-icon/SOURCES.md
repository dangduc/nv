# Icon artwork sources

## Saturn V

`saturn-v.svg` uses the Saturn V group from
[Saturn V & N1 comparison.svg](https://commons.wikimedia.org/wiki/File:Saturn_V_%26_N1_comparison.svg)
on Wikimedia Commons.

- Original artwork: NASA, *Mir Hardware Heritage*, NASA Reference Publication 1357, March 1995.
- Original SVG upload: Inductiveload, April 16, 2010.
- Source revision used: Lucabon, September 22, 2019.
- Commons license designation: public domain in the United States, `PD NASA`.
- Source file SHA-1: `3bacc2dd83508f222cfb8e33952cc36bbf694884`.
- Source file SHA-256: `411f55a10e7071c063ce84629e0ad624fe5f5dbd2d9c3a03e88425a036d9d5fd`.
- Related raster source: [Saturn V vs N1 — to scale drawing.png](https://commons.wikimedia.org/wiki/File:Saturn_V_vs_N1_-_to_scale_drawing.png).

The extraction keeps group `g8266` and its four required mask and clipping definitions.
The drawing's geometry, styles, and two embedded shading masks are unchanged.
The N1 group and unused definitions are omitted.
A wrapper positions and uniformly scales the vertical Saturn V on a transparent 1024 × 1024 canvas.

The `small/` directory contains wider rocket variants for small icons:

| Icon size | Horizontal width relative to the main rocket |
| --- | --- |
| 48 pixels | 2× |
| 32 pixels | 2.5× |
| 16 pixels | 3.5× |

These variants preserve the rocket's height and source drawing. Their horizontal scale and position change to improve visibility at small sizes.
Each uses the same 1024 × 1024 viewBox as `source-page.svg`.
The main rocket remains in use at 128 pixels and larger.

At 32 and 16 pixels, `small/squircle-background.svg` replaces the paper with a blank `#FDE9D9` squircle.
The rocket and crane retain their size, position, and drawing at these sizes.
The paper remains at 48 pixels and larger.

## Launch tower and crane

`launch-tower.svg` is a separate vector drawing based on the supplied launchpad photograph,
`Screenshot 2026-09-22 at 00.50.27.png`.
The photograph is a visual reference; it is not embedded in the SVG.
Its source and license were not supplied.

The drawing includes red lattice girders, service platforms, lower supports, a launcher deck, and a crane with a left-facing boom.
The steel uses solid `#d33b27` red with fine dark outlines.
The photograph's muted colors are interpreted as emergency red for this icon.
The tower is drawn as a flat front elevation to match the Saturn V.
Platforms and the launcher deck have horizontal edges, with no visible top or side faces.
The crane housing uses rectangular shapes, and the lattice remains transparent between its girders.

The original perspective crane is saved in `revisions/02-perspective-launch-tower/` with its composition, previews, and checksums.

`icon-composition.svg` combines the three layers: paper, launch tower, then Saturn V.
The rocket is scaled to 78% around its lower end to leave room for the overhead crane.
The original rocket SVGs retain their geometry and placement.
At 48, 32, and 16 pixels, the tower moves left so the wider rocket leaves part of the steelwork visible.

Run `python3 docs/artwork/app-icon/compose.py` from the repository to regenerate the composition.
The script also writes small-size compositions and HTML previews to `build/app-icon-design/`.

## Source page

`source-page.svg` contains the supplied excerpt from
[Comanche055/REENTRY_CONTROL.agc](https://github.com/chrislgarry/Apollo-11/blob/master/Comanche055/REENTRY_CONTROL.agc)
in the `chrislgarry/Apollo-11` repository. It includes the hardcopy notes and the start of page 844.

The file identifies the code as public domain. Its header credits transcription from MIT Museum hardcopy images,
digitized by Paul Fjeld and arranged by Deborah Douglas. It names Ron Burkey as the contact.

The page artwork was created for this project. The supplied AGC assembly excerpt is printed in black on `#FDE9D9` paper.
All 59 lines are retained. Tabs are expanded to eight-column stops to preserve the listing's alignment in SVG.
The page is drawn twice, with an offset copy behind the front sheet.
Each sheet has tractor-feed holes and perforated tear-off margins, like continuous-feed dot-matrix printer paper.

The previous white-paper revision is saved in `revisions/01-white-paper/` with its SVGs, credits, and previews.

All three component SVGs use the same canvas. Use `compose.py` to apply the launchpad layout and layer order.
