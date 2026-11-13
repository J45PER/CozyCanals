extends SceneTree
## Headless check that every level can be completed within its starting budget.
## Run with: godot --headless -s tests/test_levels.gd

const Board := preload("res://scripts/board.gd")
const Levels := preload("res://scripts/levels.gd")
const K := Board.K
const T := Board.Tool


static func tool_for(board: Board, from: Vector2i, to: Vector2i) -> int:
	var k := board.kind(to)
	if board.height(from) != board.height(to) and board.kind(from) != K.LOCK:
		return T.LOCK
	if k == K.LANE:
		return T.BRIDGE
	return -1 if Board.is_navigable(k) else T.CANAL


static func step_cost(board: Board, from: Vector2i, to: Vector2i) -> int:
	var k := board.kind(to)
	if k == K.VOID or absi(board.height(from) - board.height(to)) > 1:
		return -1
	var tool := tool_for(board, from, to)
	if tool == -1:
		return 0
	if k == K.LOCK:
		return 0
	return Board.cost_for(tool, k)


## Cheapest way to join two cells, as a list of cells (Dijkstra).
static func solve(board: Board, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var dist := {from: 0}
	var prev := {}
	var open: Array[Vector2i] = [from]
	while not open.is_empty():
		open.sort_custom(func(a, b): return dist[a] < dist[b])
		var c: Vector2i = open.pop_front()
		if c == to:
			break
		for d in Board.DIRS:
			var n := c + d
			var cost := step_cost(board, c, n)
			if cost < 0:
				continue
			if not dist.has(n) or dist[c] + cost < dist[n]:
				dist[n] = dist[c] + cost
				prev[n] = c
				if n not in open:
					open.append(n)
	var path: Array[Vector2i] = []
	if not prev.has(to):
		return path
	var cur := to
	while cur != from:
		path.append(cur)
		cur = prev[cur]
	path.append(from)
	path.reverse()
	return path


## Links every portal to the first one. Returns false if anything was refused.
static func build_all(board: Board) -> bool:
	for i in range(1, board.portals.size()):
		var path := solve(board, board.portals[0], board.portals[i])
		if path.is_empty():
			return false
		for j in range(1, path.size()):
			var tool := tool_for(board, path[j - 1], path[j])
			if tool != -1 and board.kind(path[j]) != K.LOCK and board.apply(tool, path[j]) != "":
				return false
	return true


func _init() -> void:
	var failed := false
	for data in Levels.LEVELS:
		var widths := {}
		for row in data.tiles + data.heights:
			widths[row.length()] = true
		var board := Board.new()
		board.load_level(data)
		var ok: bool = widths.size() == 1 and board.portals.size() >= 2
		ok = ok and board.linked == 1 and board.charm == 0
		ok = ok and Vector2i.ZERO not in board.portal_dirs
		ok = ok and build_all(board) and board.all_linked() and board.blocked_steps().is_empty()
		var spent: int = data.coins - board.coins
		# Boats must be able to run between every pair of portals.
		var n := board.portals.size()
		ok = ok and board.pairs.size() == n * (n - 1) / 2

		# Towpath along the whole network earns the second star.
		board.coins += 1000
		for c in board.network.keys():
			ok = ok and board.apply(T.TOWPATH, c) == ""
		ok = ok and board.towpath_pct == 100 and board.stars() >= 2

		# Clearing a built tile refunds it in full, towpath included.
		var before := board.coins
		for c in board.network.keys():
			if board.kind(c) == K.CANAL and board.orig[c.y * board.w + c.x] != K.CANAL:
				var paid := board.paid[c.y * board.w + c.x]
				ok = ok and paid > Board.TOWPATH_COST
				ok = ok and board.apply(T.CLEAR, c) == "" and board.coins == before + paid
				ok = ok and not board.has_towpath(c) and not board.all_linked()
				break
		print("%-14s %s  portals=%d  spent=%d of %d" % [
			data.name, "ok" if ok else "FAIL", n, spent, data.coins])
		failed = failed or not ok
	quit(1 if failed else 0)
