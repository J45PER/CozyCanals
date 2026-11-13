# Cozy Canals

A cosy canal-building game set in the British countryside, for phones and tablets.
Restore silted-up cuts, turn wild brooks into navigable canals and dig brand new
routes, then line them with towpaths, locks, bridges, pubs and cafes.

![Level 2](docs/level2.png)

## Running it

1. Install [Godot 4.5](https://godotengine.org/download) (standard build, not .NET).
2. Open the editor, choose **Import**, and pick `project.godot` from this folder.
3. Press **F5** to play.

To play on a phone or tablet, use Godot's **one-click deploy** (Android) or
**Project > Export** (Android / iOS) once the export templates are installed.

## How to play

Canals run off the edge of the map at signposted points. Link them all into one
navigable network. As soon as two are joined, narrowboats start passing through
in both directions, and each one earns coins as it leaves the map.

| Tool | What it does | Cost |
| --- | --- | --- |
| Move | Drag the map (two fingers pan and pinch-zoom with any tool) | - |
| Canal | Dredge a river or derelict canal, or dig through grass. Drag to draw | 5 / 15 |
| Lock | Joins canal on two different levels | 25 - 40 |
| Bridge | Carries a lane or footpath over the canal | 20 / 35 |
| Towpath | Drag along a canal to lay a path on its bank | 3 |
| Tree, Cottage, Cafe, Pub | Add charm. Buildings go beside the canal or a lane | 2 - 50 |
| Clear | Removes something you built and refunds it in full | - |

Each level has three stars: link every canal, lay towpath along 80% of the
routes between them, and reach the charm goal.

Building snaps to a grid so it works well under a thumb, but the grid is
hidden: canals, rivers and lanes are drawn as curves, and the land is a
patchwork of irregular fields and hedgerows.

On desktop: left mouse builds, right mouse drags the map, the wheel zooms.

## Project layout

- `scripts/board.gd` - game state and rules (no rendering, so it is testable)
- `scripts/board_view.gd` - isometric renderer; all art is drawn in code
- `scripts/main.gd` - input, camera and HUD
- `scripts/levels.gd` - level maps as text grids; add a level by adding an entry
- `tests/` - headless checks

## Tests

```bash
godot --headless --import
godot --headless -s tests/test_levels.gd      # every level is solvable within budget
xvfb-run godot -s tests/test_input.gd         # taps and drags through the real scene
```
