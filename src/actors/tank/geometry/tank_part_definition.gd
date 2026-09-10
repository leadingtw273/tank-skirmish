## 一個離線烘焙的坦克可碰撞部位；座標固定於其機械 anchor，不依賴視覺後座。
class_name TankPartDefinition
extends Resource

const MAX_CONVEX_SHAPES := 16
const MAX_SURFACE_POINTS := 12

@export_enum("hull", "turret", "gun", "fixed_upper_hull") var id := "hull"
@export_enum("hull", "turret", "gun") var anchor := "hull"
## baked mesh 的 local 座標轉入 anchor 的靜態轉換。
@export var anchor_transform := Transform3D.IDENTITY
## 每一個元素是一個凸 hull；2026-09-09 核可每部位最多十六個。
@export var convex_shapes: Array[ConvexPolygonShape3D] = []
## 與 convex_shapes 一一對應、位於 anchor 座標的局部轉換。
@export var convex_transforms: Array[Transform3D] = []
## 固定排序的有限表面採樣點，位於 anchor 座標，最多十二點。
@export var surface_points := PackedVector3Array()


func is_valid_part() -> bool:
	if convex_shapes.is_empty() or convex_shapes.size() != convex_transforms.size() or convex_shapes.size() > MAX_CONVEX_SHAPES:
		return false
	if surface_points.is_empty() or surface_points.size() > MAX_SURFACE_POINTS:
		return false
	for shape in convex_shapes:
		if shape == null or shape.points.is_empty():
			return false
	return true
