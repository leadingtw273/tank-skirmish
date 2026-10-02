## 導航與三秒 rollout 共用的純控制律；不查詢地圖、不改 actor 或實際 phase。
extends RefCounted

const TURN_IN_PLACE := deg_to_rad(32.0)

static func flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)

static func steering_target(position: Vector3, path: PackedVector3Array, index: int, speed: float) -> Vector3:
	if path.is_empty(): return position
	index = clampi(index, 0, path.size() - 1)
	var distance := clampf(4.0 + speed * 0.8, 4.0, 8.0)
	var previous := position
	for i in range(index, path.size()):
		var point := flat(path[i])
		var length := previous.distance_to(point)
		if length >= distance and length > 0.0001: return previous.lerp(point, distance / length)
		distance -= length
		previous = point
	return previous

static func nominal(position: Vector3, goal: Vector3, stop_distance: float, next: Vector3,
		path: PackedVector3Array, path_index: int, finished: bool, reachable: bool,
		speed: float, forward: Vector3, velocity: Vector3, angular: float, params: Dictionary) -> Dictionary:
	var direct := position.distance_to(flat(goal))
	if direct <= maxf(stop_distance, 0.0): return _stop(speed, &"arrived")
	if path.is_empty(): return _stop(speed, &"no_path")
	var index := clampi(path_index, 0, path.size()-1)
	var remaining := position.distance_to(flat(path[index]))
	for i in range(index+1, path.size()): remaining += flat(path[i-1]).distance_to(flat(path[i]))
	if remaining <= 0.5 or finished: return _stop(speed, &"partial_end")
	var desired := flat(next)-position
	if desired.length_squared() <= 0.0001: desired = flat(goal)-position
	if desired.length_squared() <= 0.0001: return _stop(speed, &"arrived" if reachable else &"partial_end")
	var drift := flat(velocity)
	var lead := minf(0.8, desired.length() * 0.5 / maxf(drift.length(), 0.01))
	desired -= drift * lead
	var direction := desired.normalized()
	var angle := atan2(forward.cross(direction).y, forward.dot(direction))
	var turn := clampf((angle-angular*0.8)/TURN_IN_PLACE, -1.0, 1.0) * float(params.effort)
	var movement := 0.0
	var braking := false
	if absf(angle) <= TURN_IN_PLACE:
		var available := minf(maxf(direct-maxf(stop_distance-0.2,0.0),0.0),maxf(remaining-0.3,0.0))
		var limit := maxf(float(params.speed),0.01)*lerpf(1.0,float(params.turn_ratio),absf(turn))
		var target_speed := minf(limit,sqrt(2.0*float(params.deceleration)*available))
		if index < path.size()-1:
			var following := flat(path[index+1]-path[index])
			if not following.is_zero_approx() and direction.angle_to(following.normalized()) > deg_to_rad(10.0):
				target_speed = minf(target_speed,sqrt(2.0*float(params.deceleration)*maxf(position.distance_to(flat(next))-0.5,0.0)))
		movement = clampf(target_speed/limit,0.0,1.0)
		braking = target_speed < speed-0.05
	return {"movement":movement,"turn":turn,"braking":braking,"status":&"moving"}

static func cross_action(position: Vector3, forward: Vector3, angular: float, target: Vector3,
		heading: Vector3, phase: StringName, params: Dictionary) -> Dictionary:
	var angle := atan2(forward.cross(heading).y,forward.dot(heading))
	var turn := clampf((angle-angular*0.8)/TURN_IN_PLACE,-1.0,1.0)*float(params.effort)
	var remaining := (target-position).dot(heading)
	var movement := minf(1.0,sqrt(maxf(0.0,2.0*float(params.deceleration)*(remaining-0.5)))/maxf(float(params.speed),0.01))
	if phase != &"cross": movement = 0.0
	return {"movement":movement,"turn":turn,"braking":movement<1.0,"status":&"moving"}

static func forecast(root: Transform3D, speed: float, angular: float, velocity: Vector3, state: Dictionary) -> Dictionary:
	var position := flat(root.origin)
	var forward := flat(-root.basis.x).normalized()
	var params: Dictionary = state.params
	if state.mode == &"cross":
		var angle := atan2(forward.cross(state.heading).y,forward.dot(state.heading))
		if state.phase == &"align" and absf(angle)<=deg_to_rad(3.0) and absf(angular)<=0.03:
			state.phase = &"cross"
		if state.phase == &"cross" and (position-(state.target as Vector3)).dot(state.heading)>=-0.7 and absf(speed)<=0.15:
			state.phase = &"done"
		if state.phase == &"done": return _stop(absf(speed),&"arrived")
		return cross_action(position,forward,angular,state.target,state.heading,state.phase,params)
	var path: PackedVector3Array = state.path
	var index := int(state.index)
	while index < path.size()-1 and position.distance_to(flat(path[index])) <= 3.0: index += 1
	state.index = index
	var next := steering_target(position,path,index,absf(speed))
	return nominal(position,state.goal,float(state.stop),next,path,index,false,true,absf(speed),forward,velocity,angular,params)

static func _stop(speed: float, status: StringName) -> Dictionary:
	return {"movement":0.0,"turn":0.0,"braking":speed>0.1,"status":&"moving" if speed>0.1 else status}
