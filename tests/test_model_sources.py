import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from model_sources import (  # noqa: E402
    MLX_MODELSCOPE_SPECS,
    _adapt_modelscope_dir,
    is_local_model_path,
    maybe_prepare_model_source,
    modelscope_spec_for,
)


class ModelSourceTests(unittest.TestCase):
    def test_mlx_large_v3_turbo_maps_to_modelscope_4bit(self) -> None:
        spec = modelscope_spec_for(
            "large-v3-turbo",
            "mlx-community/whisper-large-v3-turbo",
            "mlx-whisper",
        )

        self.assertIsNotNone(spec)
        self.assertEqual(spec.repo, "mlx-community/whisper-large-v3-turbo-4bit")
        self.assertEqual(spec.adapter, "mlx_model_safetensors")

    def test_ctranslate2_turbo_maps_to_faster_whisper_turbo(self) -> None:
        spec = modelscope_spec_for("large-v3-turbo", "large-v3-turbo", "whisper-ctranslate2")

        self.assertIsNotNone(spec)
        self.assertEqual(spec.repo, "mobiuslabsgmbh/faster-whisper-large-v3-turbo")

    def test_local_model_path_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertTrue(is_local_model_path(tmp))

    def test_mlx_modelscope_adapter_creates_weights_safetensors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            model_dir = Path(tmp)
            source = model_dir / "model.safetensors"
            source.write_bytes(b"fake")

            _adapt_modelscope_dir(model_dir, MLX_MODELSCOPE_SPECS["mlx-community/whisper-large-v3-turbo"])

            self.assertEqual((model_dir / "weights.safetensors").read_bytes(), b"fake")

    def test_auto_without_modelscope_mapping_falls_back_to_hf(self) -> None:
        model, source = maybe_prepare_model_source(
            "small",
            "mlx-community/whisper-small-mlx",
            "mlx-whisper",
            {},
            "auto",
            True,
        )

        self.assertEqual(model, "mlx-community/whisper-small-mlx")
        self.assertEqual(source, "hf")

    def test_explicit_modelscope_without_mapping_fails(self) -> None:
        with redirect_stderr(StringIO()):
            with self.assertRaises(SystemExit):
                maybe_prepare_model_source(
                    "small",
                    "mlx-community/whisper-small-mlx",
                    "mlx-whisper",
                    {},
                    "modelscope",
                    True,
                )


if __name__ == "__main__":
    unittest.main()
