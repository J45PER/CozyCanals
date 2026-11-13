extends RefCounted
## The game's modes. Every map comes from the generator, so a level is just
## a name, a seed and a handful of settings (see mapgen.gd for what they mean).

const JOURNEY := [
	{"name": "The Old Cut", "seed": 11, "w": 18, "h": 13, "portals": 2, "derelict": 0.85, "places": 1,
		"woods": 0.4, "budget": 1.7, "charm_goal": 12,
		"blurb": "A forgotten canal lies silted up. Drag along it to dredge it, and fill in the gaps."},
	{"name": "Willow Brook", "seed": 23, "w": 19, "h": 14, "portals": 2, "derelict": 0.5, "places": 2,
		"river": true, "budget": 1.6, "charm_goal": 14,
		"blurb": "Give the pub and the church a footpath to the towpath."},
	{"name": "Nettle Bank", "seed": 38, "w": 20, "h": 14, "portals": 2, "derelict": 0.4, "places": 2,
		"hills": 1, "budget": 1.6, "charm_goal": 16,
		"blurb": "The land rises here. Canals climb a level with a lock - they are built for you, at a price."},
	{"name": "Three Ways", "seed": 41, "w": 21, "h": 15, "portals": 3, "derelict": 0.4, "places": 2,
		"hills": 1, "budget": 1.55, "charm_goal": 18,
		"blurb": "Three canals meet. Build a junction that links them all."},
	{"name": "Hartley Flight", "seed": 62, "w": 22, "h": 15, "portals": 2, "derelict": 0.2, "places": 3,
		"hills": 2, "river": true, "budget": 1.5, "charm_goal": 20,
		"blurb": "A proper climb. Go over the top with a flight of locks, or find the long way round."},
	{"name": "Mill Lane", "seed": 64, "w": 22, "h": 16, "portals": 2, "derelict": 0.3, "places": 2,
		"roads": 1, "farms": 1, "hills": 1, "budget": 1.5, "charm_goal": 22,
		"blurb": "A road crosses the valley. The farm wants a road of its own to reach it."},
	{"name": "Coombe Junction", "seed": 72, "w": 23, "h": 16, "portals": 3, "derelict": 0.3, "places": 3,
		"roads": 1, "farms": 1, "river": true, "hills": 1, "budget": 1.45, "charm_goal": 24,
		"blurb": "River, road and three canals. Bridges are built wherever a path or road crosses water."},
	{"name": "Stonebridge", "seed": 85, "w": 24, "h": 17, "portals": 3, "derelict": 0.2, "places": 3,
		"roads": 2, "farms": 2, "hills": 2, "budget": 1.4, "charm_goal": 26,
		"blurb": "Two roads and steep ground. Plan the line before you dig."},
	{"name": "Four Counties", "seed": 93, "w": 25, "h": 18, "portals": 4, "derelict": 0.2, "places": 4,
		"roads": 1, "farms": 2, "river": true, "hills": 2, "budget": 1.4, "charm_goal": 28,
		"blurb": "Four canals from four counties. Bring them together."},
	{"name": "The Long Pound", "seed": 108, "w": 27, "h": 19, "portals": 4, "derelict": 0.1, "places": 4,
		"roads": 2, "farms": 2, "river": true, "hills": 2, "budget": 1.35, "charm_goal": 32,
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
		"budget": 1.4, "charm_goal": 24,
	}


## A big open map with no budget and no goals.
static func free_build(seed_: int) -> Dictionary:
	return {
		"name": "Free Build", "seed": seed_, "w": 30, "h": 22,
		"blurb": "No budget and no goals. Build the waterway you would like to walk along.",
		"portals": 4, "derelict": 0.15, "places": 4, "roads": 2, "farms": 0,
		"river": true, "hills": 2, "unlimited": true, "charm_goal": 0,
	}
