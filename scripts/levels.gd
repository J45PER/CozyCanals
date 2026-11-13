extends RefCounted
## Level data. Each level has a tile map and a matching height map.
##
## Tile legend:
##   .  grass        t  tree         o  rock (cannot be built on)
##   r  wild river   d  derelict canal (silted up)   c  working canal
##   l  country lane h  cottage      S  start wharf  E  end wharf
## Heights are digits 0-2; canals need a lock to step between levels.

const LEVELS := [
	{
		"name": "The Old Cut",
		"blurb": "A forgotten canal lies silted up. Dredge it, fill the gaps and bridge the lane.",
		"coins": 170,
		"charm_goal": 14,
		"tiles": [
			"..t...l..t.",
			".t....l....",
			"...t..l..t.",
			"Sdd..dldddE",
			"...........",
			".t..t.l..t.",
			"t.....l....",
			"..t..tl.t..",
		],
		"heights": [
			"00000000000",
			"00000000000",
			"00000000000",
			"00000000000",
			"00000000000",
			"00000000000",
			"00000000000",
			"00000000000",
		],
	},
	{
		"name": "Willow Brook",
		"blurb": "Turn the wild brook into a navigable canal. Boats need a lock to step down the hill.",
		"coins": 200,
		"charm_goal": 18,
		"tiles": [
			"tt....t.....",
			"t.....o...t.",
			"Srrr........",
			"...r.o...t..",
			".t.rrrr.....",
			"......r..o..",
			"..t...rr..rE",
			".....t....t.",
			"t.......t...",
		],
		"heights": [
			"111110000000",
			"111110000000",
			"111110000000",
			"111110000000",
			"111110000000",
			"111110000000",
			"111100000000",
			"111100000000",
			"111000000000",
		],
	},
	{
		"name": "Over the Hill",
		"blurb": "Cut a brand new route. Climb the hill with a flight of locks, or wind around it.",
		"coins": 330,
		"charm_goal": 24,
		"tiles": [
			"..t.....t....",
			"...t..o....t.",
			"S...........E",
			".t.......t...",
			"......t......",
			"..o........t.",
			".t....h..o...",
			"...dddldddt..",
			"t.....l....t.",
			"...t..l.t....",
		],
		"heights": [
			"0000111110000",
			"0001122211000",
			"0001122211000",
			"0001122211000",
			"0001112111000",
			"0000111110000",
			"0000000000000",
			"0000000000000",
			"0000000000000",
			"0000000000000",
		],
	},
]
