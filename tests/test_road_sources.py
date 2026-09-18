import importlib.util, json, struct, tempfile, unittest, zipfile
from pathlib import Path
MODULE_PATH = Path(__file__).parents[1] / "scripts" / "roads" / "import_sources.py"
SPEC = importlib.util.spec_from_file_location("import_sources", MODULE_PATH); sources = importlib.util.module_from_spec(SPEC); assert SPEC.loader is not None; SPEC.loader.exec_module(sources)
def glb(document):
    encoded = json.dumps(document, separators=(",", ":")).encode(); encoded += b" " * (-len(encoded) % 4); body = struct.pack("<I4s", len(encoded), b"JSON") + encoded
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body
class RoadSourceTests(unittest.TestCase):
    def test_safe_archive_path_rejects_escape(self):
        for path in ("../escape.glb", "/absolute.glb", "nested/../../escape.png"):
            with self.assertRaises(ValueError): sources.safe_archive_path(path)
    def test_extracts_identical_bytes_and_builds_embedded_material_catalog(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, source_root = Path(temporary), Path(temporary) / "source"; source_root.mkdir()
            fixture = glb({"images": [{"name": "embedded-road"}], "textures": [{"source": 0}], "materials": [{"name": "Road", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}]})
            for _, name in sources.PACKS:
                with zipfile.ZipFile(source_root / name, "w") as archive:
                    archive.writestr("PLUS/model.glb", fixture); archive.writestr("PLUS/texture.png", b"PNG fixture"); archive.writestr("2. License.png", b"licence evidence"); archive.writestr("PLUS/only_source.fbx", b"not imported")
            catalog = sources.import_sources(source_root, root); extracted = root / "assets" / "AtomicRealmModularRoads" / "base" / "PLUS" / "model.glb"
            self.assertEqual(extracted.read_bytes(), fixture); self.assertEqual(len(catalog["packs"]), 8); self.assertEqual(catalog["packs"][0]["models"][0]["materials"], [{"name": "Road", "image_name": "embedded-road"}]); self.assertEqual(catalog["packs"][0]["missing_glb"], ["PLUS/only_source.fbx"]); self.assertTrue((root / "assets" / "AtomicRealmModularRoads" / "source-manifest.json").exists())
            sources.import_sources(source_root, root); extracted.write_bytes(b"different")
            with self.assertRaises(FileExistsError): sources.import_sources(source_root, root)
