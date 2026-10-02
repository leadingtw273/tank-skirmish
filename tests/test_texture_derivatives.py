import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "roads" / "prepare_texture_derivatives.py"
SPEC = importlib.util.spec_from_file_location("texture_derivatives", MODULE_PATH)
derivatives = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(derivatives)


class TextureDerivativeTests(unittest.TestCase):
    def test_detects_psd_magic_even_when_extension_is_png(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "mislabeled.png"
            path.write_bytes(b"8BPS" + b"fixture")
            self.assertTrue(derivatives.is_psd_payload(path))

    def test_ignores_actual_png_magic(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "valid.png"
            path.write_bytes(derivatives.PNG_MAGIC + b"fixture")
            self.assertFalse(derivatives.is_psd_payload(path))

    def test_writes_only_the_supported_skip_import_sidecar(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "mislabeled.png"
            source.write_bytes(b"8BPS" + b"fixture")
            derivatives.write_skip_import(source)
            self.assertEqual((Path(temporary) / "mislabeled.png.import").read_text(), derivatives.SKIP_IMPORT)
            (Path(temporary) / "mislabeled.png.import").write_text('[remap]\nimporter="texture"\nvalid=false\n')
            derivatives.write_skip_import(source)
            self.assertEqual((Path(temporary) / "mislabeled.png.import").read_text(), derivatives.SKIP_IMPORT)
            (Path(temporary) / "mislabeled.png.import").write_text('importer="texture"\n')
            with self.assertRaises(FileExistsError):
                derivatives.write_skip_import(source)
