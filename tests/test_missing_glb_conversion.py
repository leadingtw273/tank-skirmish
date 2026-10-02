import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "roads" / "convert_missing_glbs.py"
SPEC = importlib.util.spec_from_file_location("convert_missing_glbs", MODULE_PATH)
converter = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(converter)


class MissingGlbConversionTests(unittest.TestCase):
    def test_closed_unique_conversion_set(self):
        self.assertEqual(
            [(item["pack"], item["id"], item["source"]) for item in converter.CONVERSIONS],
            [
                ("parking", "Road5_Shoulder2", "PLUS/dae/Road5_Shoulder2.dae"),
                ("signs", "SignCircle", "PLUS/Blank_Sign_Meshes/dae/SignCircle.dae"),
                ("racetrack", "Racetrack1_YellowBlue_Curbs_Curve_45_Long_Right", "PLUS/fbx/Racetrack1_YellowBlue_Curbs_Curve_45_Long_Right.fbx"),
            ],
        )

    def test_zip_path_escape_is_rejected(self):
        with self.assertRaises(ValueError): converter.safe_relative("PLUS/../../escape.fbx")
