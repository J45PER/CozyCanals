extends SceneTree
## Headless check that every level can be completed within its starting budget.
## Run with: godot --headless -s tests/test_levels.gd

const Board := preload("res://scripts/board.gd")
const Levels := preload("res://scripts/levels.gd")
const K := Board.K
const T := Board.Tool


static func tool_for(board: Board, from: Vector2i, to: Vector2i) -> int:
	var k := board.kind(to)
	if board.height(from) != board.height(to):
		return T.LOCK
	if k == K.LANE:
		return T.BRIDGE
	return -1 if Board.is_navigable(k) else T.CANAL


static func step_cost(board: Board, from: Vector2i, to: Vector2i) -> int:
	var k := board.kind(to)
	if k == -1 or absi(board.height(from) - board.height(to)) > 1:
		return -1
	var tool := tool_for(board, from, to)
	if tool == -1:
		return 0
	if k == K.END or k == K.START:
		return -1
	return Board.cost_for(tool, k)


## Cheapest route from start to end as a list of cells (Dijkstra).
static func solve(board: Board) -> Array[Vector2i]:
	var dist := {board.start: 0}
	var prev := {}
	var open: Array[Vector2i] = [board.start]
	while not open.is_empty():
		open.sort_custom(func(a, b): return dist[a] < dist[b])
		var c: Vector2i = open.pop_front()
		if c == board.end:
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
	if not prev.has(board.end):
		return path
	var cur := board.end
	while cur != board.start:
		path.append(cur)
		cur = prev[cur]
	path.append(board.start)
	path.reverse()
	return path


static func build(board: Board, path: Array[Vector2i]) -> bool:
	for i in range(1, path.size()):
		var tool := tool_for(board, path[i - 1], path[i])
		if tool != -1 and board.apply(tool, path[i]) != "":
			return false
	return true


func _init() -> void:
	var failed := false
	for data in Levels.LEVELS:
		var board := Board.new()
		board.load_level(data)
		var ok: bool = board.route.is_empty() and board.charm == 0
		var path := solve(board)
		ok = ok and not path.is_empty() and build(board, path)
		ok = ok and not board.route.is_empty() and board.blocked_steps().is_empty()
		# Clearing a built tile must refund it in full.
		var before := board.coins
		var mid := path[path.size() / 2]
		if board.is_player_built(mid):
			var paid := board.paid[mid.y * board.w + mid.x]
			ok = ok and board.apply(T.CLEAR, mid) == "" and board.coins == before + paid
		print("%-14s %s  route=%d tiles  coins left=%d of %d" % [
			data.name, "ok" if ok else "FAIL", path.size(), before, data.coins])
		failed = failed or not ok
	quit(1 if failed else 0)
