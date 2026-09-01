## 回報坦克四個履帶接地點的通用地表互動；不指定煙塵素材或擁有世界特效。
extends Node3D

## 接地互動的來源身分；SurfaceEffects 以它和接地點身分穩定管理持續發射器。
@export var source_id: StringName = &"player_tank"
## 向下查詢可互動地表的物理碰撞遮罩。
@export_flags_3d_physics var ground_collision_mask := 128
## 每個手調接地點上方的查詢起始偏移，單位為公尺。
@export_range(0.0, 3.0, 0.01) var ray_start_height := 0.5
## 每個接地點向下查詢的總長度，單位為公尺。
@export_range(0.05, 10.0, 0.01) var ray_length := 1.5
## 實際線速度達此值時，接地互動強度為 1.0，單位為公尺／秒。
@export_range(0.01, 100.0, 0.01) var linear_speed_for_full_intensity := 15.0
## 實際偏航角速度達此值時，原地旋轉的接地互動強度為 1.0，單位為弧度／秒。
@export_range(0.01, 10.0, 0.01) var angular_speed_for_full_intensity := 0.8

## 通用接地回報：來源、接地點、是否命中、位置、法線、強度、來源線速度與合成運動速度。
signal track_contact(
		source: StringName,
		contact_id: StringName,
		active: bool,
		world_position: Vector3,
		ground_normal: Vector3,
		intensity: float,
		source_velocity: Vector3,
		source_motion_speed: float,
)

@onready var tank: CharacterBody3D = get_parent() as CharacterBody3D
@onready var contact_points: Array[Marker3D] = [$LeftFront, $LeftRear, $RightFront, $RightRear]


func _physics_process(_delta: float) -> void:
	## 每個點都以獨立的世界座標射線查詢；未命中仍回報，讓世界層只停用該點的發射器。
	if tank == null or not is_instance_valid(tank):
		return
	var linear_speed := absf(float(tank.call("get_actual_linear_speed")))
	var angular_speed := absf(float(tank.call("get_actual_angular_speed")))
	var motion_speed := maxf(linear_speed, angular_speed)
	var intensity := clampf(maxf(
		linear_speed / maxf(linear_speed_for_full_intensity, 0.01),
		angular_speed / maxf(angular_speed_for_full_intensity, 0.01),
	), 0.0, 1.0)
	var source_velocity := tank.get_real_velocity()
	for point in contact_points:
		_emit_contact_for(point, intensity, source_velocity, motion_speed)


func _emit_contact_for(point: Marker3D, intensity: float, source_velocity: Vector3, source_motion_speed: float) -> void:
	var from := point.global_position + Vector3.UP * maxf(ray_start_height, 0.0)
	var to := from + Vector3.DOWN * maxf(ray_length, 0.05)
	var query := PhysicsRayQueryParameters3D.create(from, to, ground_collision_mask, [tank.get_rid()])
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var active := not result.is_empty()
	var world_position := point.global_position
	var ground_normal := Vector3.UP
	if active:
		world_position = result["position"] as Vector3
		ground_normal = result["normal"] as Vector3
	track_contact.emit(source_id, point.name, active, world_position, ground_normal, intensity, source_velocity, source_motion_speed)
