"""Layer guards must reject direct and indirect Production/example coupling."""
from pathlib import Path
import tempfile
import unittest
from cedar_poo_py_test.layer_checks import imports, run


class LayerTests(unittest.TestCase):
    def test_nested_comments_and_multiline_imports(self):
        source = '/- import Examples.Hidden /- nested -/ -/\nimport CedarPooSpec.A\n  Examples.B -- comment\nnamespace X\ndef x := 1'
        self.assertEqual(imports(source), ['CedarPooSpec.A', 'Examples.B'])

    def test_transitive_import_cannot_hide_example_dependency(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Productions').mkdir()
            (root / 'Productions/Profile.lean').write_text('import Other.Shim\n')
            (root / 'Other').mkdir()
            (root / 'Other/Shim.lean').write_text('import Examples.Case\n')
            with self.assertRaisesRegex(ValueError, 'Productions.Profile -> Other.Shim -> Examples.Case'):
                run(root)
            (root / 'Other/Shim.lean').write_text('import CedarPooSpec.Contract\n')
            run(root)

    def test_library_cannot_import_production(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'CedarPooSpec.lean').write_text('import Productions.Profile\n')
            with self.assertRaisesRegex(ValueError, 'CedarPooSpec -> Productions.Profile'):
                run(root)
