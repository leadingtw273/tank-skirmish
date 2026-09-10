## 四個車型共用的離線部位碰撞與有限表面資料格式。
class_name TankPartGeometry
extends Resource

@export var stable_center := Vector3.ZERO
@export var parts: Array[TankPartDefinition] = []


func is_valid_geometry() -> bool:
	if not stable_center.is_finite() or parts.is_empty():
		return false
	var seen: Dictionary = {}
	for part in parts:
		if part == null or not part.is_valid_part() or seen.has(part.id):
			return false
		seen[part.id] = true
	return seen.has("hull") and seen.has("gun") and (seen.has("turret") or seen.has("fixed_upper_hull") or parts.size() == 4)


func part_named(part_id: StringName) -> TankPartDefinition:
	for part in parts:
		if part != null and part.id == part_id:
			return part
	return null
