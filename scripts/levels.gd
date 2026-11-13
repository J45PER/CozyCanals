extends RefCounted
## Level data. Each level has a tile map and a matching height map.
##
## Tile legend:
##   #  off the map  .  grass        t  woodland     o  rock (cannot be built on)
##   r  wild river   d  derelict canal (silted up)   c  working canal
##   l  country lane h  cottage
##   P  portal: a canal running off the edge of the map. Boats arrive and
##      leave through portals, and every portal must be linked to finish.
## Heights are digits 0-2; canals need a lock to step between levels.
## "portals" names each P in reading order (left to right, top to bottom).

const LEVELS := [
	{
		"name": "The Old Cut",
		"blurb": "A forgotten canal lies silted up. Dredge it, fill the gaps and bridge the lane so boats can pass through again.",
		"coins": 190,
		"charm_goal": 14,
		"portals": ["Ambleford", "Thistlewick"],
		"tiles": [
			"###...l..####",
			"##.t..l...t##",
			"#..t..l.....#",
			"..t...ll.t...",
			"Pdd....l.....",
			"....dddldd...",
			"#.t....l.dd.P",
			"##...t.ll..t#",
			"##.t....l..##",
			"####..t.l.###",
		],
		"heights": [
			"0000000000000",
			"0000000000000",
			"0000000000000",
			"0000000000000",
			"0000000000000",
			"0000000000000",
			"0000000000000",
			"0000000000000",
			"0000000000000",
			"0000000000000",
		],
	},
	{
		"name": "Willow Brook",
		"blurb": "Turn the winding brook into a canal. Boats need a lock to step down the hill, and a new cut to reach Marlow Wharf.",
		"coins": 230,
		"charm_goal": 18,
		"portals": ["Upper Shaw", "Marlow Wharf"],
		"tiles": [
			"####..tt....##",
			"##t.........t#",
			"Prrr...o......",
			"#..rr....t....",
			"#.t.r..o......",
			"##..rrr...t...",
			"##....rr......",
			"###.t..r..o..#",
			"###....rr....P",
			"####...r...###",
		],
		"heights": [
			"11111000000000",
			"11111000000000",
			"11111000000000",
			"11111000000000",
			"11111000000000",
			"11111000000000",
			"11110000000000",
			"11110000000000",
			"11110000000000",
			"11110000000000",
		],
	},
	{
		"name": "Three Ways",
		"blurb": "Three canals meet here. Build a junction that links them all - over the ridge with locks, or the long way round.",
		"coins": 360,
		"charm_goal": 24,
		"portals": ["Hartley Top", "Ambleford", "Coombe Basin"],
		"tiles": [
			"####.l.....t###",
			"###..l......t##",
			"##..tll...o...#",
			"#.....lh.t.....",
			"..t...l.......P",
			"Pc....l........",
			"#.....l..t.....",
			"#.t..ll....o..#",
			"##...l..d....##",
			"##..ll..d.t.###",
			"###.l...d..####",
			"####l...P.#####",
		],
		"heights": [
			"000000000111000",
			"000000000111000",
			"000000000121000",
			"000000000121000",
			"000000000111000",
			"000000000111000",
			"000000000111000",
			"000000000110000",
			"000000000100000",
			"000000000000000",
			"000000000000000",
			"000000000000000",
		],
	},
]
