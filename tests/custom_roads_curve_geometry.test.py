import math
from pathlib import Path
import unittest

RADIUS = 24.0
ANGLE = math.pi / 4.0
BASE_STRAIGHT = 12.0


class CustomCurveGeometryTests(unittest.TestCase):
    def test_curve2_is_an_exact_45_degree_radius_24_arc(self):
        entry = (0.0, -6.0)
        exit_ = (RADIUS * (1.0 - math.cos(ANGLE)), -6.0 + RADIUS * math.sin(ANGLE))
        self.assertAlmostEqual(exit_[0], 7.0294372515, places=9)
        self.assertAlmostEqual(exit_[1], 10.9705627485, places=9)
        self.assertAlmostEqual(math.hypot(entry[0] - RADIUS, entry[1] + 6.0), RADIUS, places=9)
        self.assertAlmostEqual(math.hypot(exit_[0] - RADIUS, exit_[1] + 6.0), RADIUS, places=9)
        self.assertAlmostEqual(RADIUS * ANGLE, 6.0 * math.pi, places=9)

    def test_uvs_and_cross_section_come_from_the_12m_source_mesh(self):
        arc_length = RADIUS * ANGLE
        self.assertAlmostEqual(arc_length / BASE_STRAIGHT, math.pi / 2.0, places=9)
        script = (Path(__file__).parents[1] / "scripts" / "roads" / "build_custom_roads.gd").read_text()
        self.assertIn('ROAD1_SOURCE := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road1.glb"', script)
        self.assertIn("clip_z(triangle, local_start, true)", script)
        self.assertIn("ARC_STEPS := 32", script)
        self.assertIn("uvs.append(vertex.uv)", script)

    def test_source_y_wrappers_keep_outer_ports_and_explicit_inner_ports(self):
        script = (Path(__file__).parents[1] / "scripts" / "roads" / "build_custom_roads.gd").read_text()
        self.assertIn('ROAD11_SOURCE := "res://assets/AtomicRealmModularRoads/base/PLUS/gltf/Road11_Y_Splitter_45.glb"', script)
        self.assertIn("make_compact_wrapper(ROAD12_L_SOURCE", script)
        self.assertIn('point("DiagonalInner", Vector3(8.137953 * side, 0.0, 8.104688)', script)
        self.assertIn('point("NorthInner", Vector3(0.0, 0.0, 11.485281)', script)
        self.assertIn("clip_source_surface(source, constraints, y_offset)", script)


if __name__ == "__main__":
    unittest.main()
