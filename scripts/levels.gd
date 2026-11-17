extends RefCounted
## The game's modes. Every map comes from the generator, so a level is just
## a name, a seed and a handful of settings (see mapgen.gd for what they mean).

const JOURNEY := [
	{"name": "The Old Cut", "seed": 11, "w": 18, "h": 13, "portals": 2, "derelict": 0.85, "places": 1,
		"woods": 0.4, "budget": 1.7, "cosy": [0, 1, 4],
		"blurb": "A forgotten Victorian canal lies silted up. Tap a stretch to restore it, then drag to dig the gaps."},
	{"name": "Willow Brook", "seed": 23, "w": 19, "h": 14, "portals": 2, "derelict": 0.5, "places": 2,
		"river": true, "budget": 1.6, "cosy": [1, 1, 5],
		"blurb": "Give the pub and the church a footpath to the towpath. Boats can use the brook too."},
	{"name": "Nettle Bank", "seed": 38, "w": 20, "h": 14, "portals": 2, "derelict": 0.4, "places": 2,
		"hills": 1, "budget": 1.6, "cosy": [1, 2, 6],
		"blurb": "A quiet cut with two places to connect. Add a lock or some moorings for charm."},
	{"name": "Three Ways", "seed": 41, "w": 21, "h": 15, "portals": 3, "derelict": 0.4, "places": 2,
		"hills": 1, "budget": 1.55, "cosy": [2, 2, 6],
		"blurb": "Three canals meet. Build a junction that links them all."},
	{"name": "Hartley Flight", "seed": 62, "w": 22, "h": 15, "portals": 2, "derelict": 0.2, "places": 3,
		"hills": 2, "river": true, "budget": 1.5, "cosy": [2, 3, 8],
		"blurb": "The river runs through. Boats can use it, so join your canals to it and save digging."},
	{"name": "Mill Lane", "seed": 64, "w": 22, "h": 16, "portals": 2, "derelict": 0.3, "places": 2,
		"roads": 1, "farms": 1, "hills": 1, "budget": 1.5, "cosy": [2, 3, 8],
		"blurb": "A road comes in from each side of the valley. Join the two ends, and give the farm a road to reach it."},
	{"name": "Coombe Junction", "seed": 72, "w": 23, "h": 16, "portals": 3, "derelict": 0.3, "places": 3,
		"roads": 1, "farms": 1, "river": true, "hills": 1, "budget": 1.45, "cosy": [2, 4, 10],
		"blurb": "River, road and three canals. Join the road across the water: bridges are built where it crosses at 30 degrees or more."},
	{"name": "Stonebridge", "seed": 85, "w": 24, "h": 17, "portals": 3, "derelict": 0.2, "places": 3,
		"roads": 2, "farms": 2, "hills": 2, "budget": 1.4, "cosy": [3, 4, 10],
		"blurb": "Two roads need joining across the valley. Plan the crossings before you dig."},
	{"name": "Four Counties", "seed": 93, "w": 25, "h": 18, "portals": 4, "derelict": 0.2, "places": 4,
		"roads": 1, "farms": 2, "river": true, "hills": 2, "budget": 1.4, "cosy": [3, 5, 12],
		"blurb": "Four canals from four counties. Bring them together."},
	{"name": "The Long Pound", "seed": 108, "w": 27, "h": 19, "portals": 4, "derelict": 0.1, "places": 4,
		"roads": 2, "farms": 2, "river": true, "hills": 2, "budget": 1.35, "cosy": [3, 6, 14],
		"blurb": "The grand finale: a whole network on a tight budget."},
]


## Today's map: the same for everyone on a given date.
static func daily(date: Dictionary) -> Dictionary:
	var seed_: int = date.year * 10000 + date.month * 100 + date.day
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var roads := rng.randi_range(0, 2)
	return {
		"name": "Daily Cut, %d %s" % [date.day, ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug",
			"Sep", "Oct", "Nov", "Dec"][date.month - 1]],
		"blurb": "One map a day, the same for everyone. Finish with as many coins as you can.",
		"seed": seed_, "w": 23, "h": 16,
		"portals": rng.randi_range(2, 4), "derelict": rng.randf_range(0.1, 0.5),
		"places": rng.randi_range(2, 4), "roads": roads, "farms": mini(roads, rng.randi_range(0, 2)),
		"river": rng.randf() < 0.6, "hills": rng.randi_range(0, 2),
		"budget": 1.4, "cosy": [2, 4, 10],
	}


## A big open map with no budget and no goals.
static func free_build(seed_: int) -> Dictionary:
	return {
		"name": "Free Build", "seed": seed_, "w": 30, "h": 22,
		"blurb": "No budget and no goals. Build the waterway you would like to walk along.",
		"portals": 4, "derelict": 0.15, "places": 4, "roads": 2, "farms": 0,
		"river": true, "hills": 2, "unlimited": true,
	}
