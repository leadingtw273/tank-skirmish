## LEA-173：車身 move_and_slide 接觸的有限水平滑動／偏航計算；不寫入場景節點。
class_name TankContactResponse
extends RefCounted

const HORIZONTAL_EPSILON := 0.0001
const DEAD_ZONE_RADIANS := deg_to_rad(15.0)
const FULL_RESPONSE_RADIANS := deg_to_rad(30.0)
const SLIDE_SPEED_RATIO := 0.35


static func horizontal_normal(normal: Vector3) -> Vector3:
	var result := Vector3(normal.x, 0.0, normal.z)
	return result.normalized() if result.length_squared() > HORIZONTAL_EPSILON * HORIZONTAL_EPSILON else Vector3.ZERO


static func response_gain(intent_direction: Vector3, outward_normal: Vector3) -> float:
	if intent_direction.is_zero_approx() or outward_normal.is_zero_approx():
		return 0.0
	## 0 度是意圖正面朝入牆方向（即 -outward normal）。
	var inward_alignment := clampf(-intent_direction.dot(outward_normal), -1.0, 1.0)
	if inward_alignment <= 0.0:
		return 0.0
	var angle := acos(inward_alignment)
	if angle <= DEAD_ZONE_RADIANS:
		return 0.0
	return smoothstep(DEAD_ZONE_RADIANS, FULL_RESPONSE_RADIANS, angle)


static func slide_target(
	intent_direction: Vector3,
	outward_normal: Vector3,
	speed_limit: float,
	movement_amount: float,
	gain: float,
) -> Vector3:
	if gain <= 0.0:
		return Vector3.ZERO
	return intent_direction.slide(outward_normal) * maxf(speed_limit, 0.0) * absf(movement_amount) * SLIDE_SPEED_RATIO * gain


static func remove_inward_components(candidate: Vector3, normals: Array[Vector3]) -> Vector3:
	var result := candidate
	for normal in normals:
		var inward := result.dot(normal)
		if inward < 0.0:
			result -= normal * inward
	for normal in normals:
		if result.dot(normal) < -HORIZONTAL_EPSILON:
			return Vector3.ZERO
	return result


static func auto_yaw_moment(
	contact_point: Vector3,
	stable_center: Vector3,
	outward_normal: Vector3,
	intent_direction: Vector3,
	movement_amount: float,
	conservative_radius: float,
	gain: float,
) -> float:
	if gain <= 0.0 or conservative_radius <= HORIZONTAL_EPSILON:
		return 0.0
	var blocked_strength := maxf(0.0, -intent_direction.dot(outward_normal)) * absf(movement_amount)
	var arm := contact_point - stable_center
	arm.y = 0.0
	var reaction := outward_normal * blocked_strength
	return clampf(arm.cross(reaction).y / conservative_radius, -1.0, 1.0) * gain
