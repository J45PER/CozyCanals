# Cozy Canals

A cosy canal-building game set in the British countryside, for phones and tablets.
Restore silted-up cuts and dig new ones, then give every village, pub and farm
a way to reach the water.

![Level 9](docs/level9.png)

## Running it

1. Install [Godot 4.5](https://godotengine.org/download) (standard build, not .NET).
2. Open the editor, choose **Import**, and pick `project.godot` from this folder.
3. Press **F5** to play.

**Android test build:** `builds/CozyCanals.apk`. Download it on the phone and
open it to install (Android will ask you to allow installs from your browser
or files app). Rebuild it with `tools/build_apk.sh`.

## How to play

Canals run off the edge of the map at signposted points and on into the
countryside beyond. Drag with the Canal tool to draw a line between them; the
line follows your finger. Only the land inside the white outline can be built on. Once two are joined, narrowboats pass through and each one earns coins.

The build bar works like a city builder's: tap a category to open its tools,
tap a tool to pick it, and tap it again (or close the category) to put it down.
With a tool picked, one finger only ever draws and never moves the map; with no tool picked, one finger moves it. Two fingers pan and pinch-zoom
at any time; the + / - / Fit buttons on the right zoom and bring the map back.

| Category | Tools | Cost |
| --- | --- | --- |
| Restore | Tap or drag along silted old canal to restore that part of it | 4 a length |
| Waterways | Canal (drag to dig), Moorings, Wide water (a winding hole), Stone lock, Brick lock (tap a plain canal; locks are decoration) | 12 a step, moorings 10, wide water 25, lock 15 |
| Roads & Paths | Gravel path, Tarmac path, Dirt track, Lane, Road (with a white centre line), Roundabout (tap a junction of 3+ roads), Brick / Stone / Footbridge (tap a bridge to rebuild it) | 1 - 10 a step, roundabout 30, rebuild 10 |
| Buildings | Cottage, Terrace, Shop, Cafe, Pub, Boatyard, Windmill, Car park, Beer garden | 15 - 70 |
| Nature | Trees; Hedgerow, Stone wall, Fence (drag along a path or road to line both sides) | 2; 2 - 4 a length |
| Bulldoze | Knock down what you built (half the cost back), clear trees (6), or knock down one of the map's buildings (40; it stops being a goal) | - |

The land is flat, and rivers are navigable: boats use them as well as canals,
and a canal dug along a river replaces it, opening smoothly into the wider river
at each end. Locks are decoration (they add charm and slow boats a little).

Nothing is built over anything else: clear trees, or knock down a path,
before building there. Anything can be knocked down except where the map's
canals and roads start and end.

Drag a path or road off the edge of the map to lead it away into the
countryside (15). Cars use the roads, coming and going at the map's own
roads and at roads you lead off the map, and visit farms connected by road.

Paths and roads run into a building's plot and up to its door. A car park or
beer garden put next to a building joins its plot, as do neighbouring
buildings of the same kind (a row of terraces).

Every building stands in its own plot, fenced, hedged or walled to suit it,
with a gap and a front path or drive on the side its path or road arrives.
Pubs, shops, cafes, farms, boatyards and manors get a car park once a road
reaches them.

A path or road that crosses water gets a bridge automatically (+20). A crossing is always one bridge, however many cells of water it spans: it meets the water square-on, is sized to the water's width, and the road or path curves on its approaches to meet it.

Restored canal keeps its Victorian look (brick edging, cinder towpath); newly
dug cut has pale stone coping and a fresh gravel towpath.

**Stars:** link every canal; connect every place (the badge over it shows
whether it wants a path or a road); reach the charm goal.
The Daily Cut also gives a score: stars first, then coins left and charm.

## Modes

- **Journey** - ten maps of rising difficulty: hills and locks, rivers, junctions, then roads and farms.
- **Daily Cut** - one map a day from the date, the same for everyone, with a score to beat.
- **Free Build** - a large map with no budget and no goals.

Every map comes from a seeded generator (`scripts/mapgen.gd`), so a level is
just a name, a seed and a few settings in `scripts/levels.gd`.

## Artwork

Standing objects (buildings, trees, animals, boats) are PNG sprites in
`assets/sprites`, with several variants of most buildings. The current set is
designed and rendered by `tools/make_sprites.js`; see `docs/sprites.png` for
the whole set. To use your own art, replace a PNG with one of the same name
(details in `assets/sprites/README.md`).

The ground, water, paths, hedges, bridges and locks are drawn in code, because
they follow whatever the player draws.

## Project layout

- `scripts/world.gd` - game state and rules (no rendering, so it is testable)
- `scripts/mapgen.gd` - map generator; `scripts/autobuild.gd` - solver used for budgets and tests
- `scripts/world_view.gd` - isometric renderer; `scripts/sprites.gd` - sprite loader; `scripts/art.gd` - code-drawn ground and canal structures
- `scripts/main.gd` - menu, modes, input, camera and HUD
- `shaders/paper.gdshader` - paper grain and cloud-shadow overlay

## Tests

```bash
godot --headless --import
godot --headless -s tests/test_levels.gd      # every map generates, is solvable in budget, and refunds fully
xvfb-run godot -s tests/test_input.gd         # menu, finger-drag drawing, erase, boats, saving
```
