import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from progress import (  # noqa: E402
    _Progress,
    _heartbeat_message,
    _line_indicates_fetch_complete,
    _line_indicates_transcribe_started,
)


class ProgressStageTests(unittest.TestCase):
    def test_fetching_before_complete_stays_in_download_stage(self) -> None:
        progress = _Progress("download")
        line = "Fetching 12 files:  42%|####2     | 5/12 [01:00<02:00, 10.0s/it]"

        if _line_indicates_fetch_complete(line) or _line_indicates_transcribe_started(line):
            progress.set_stage("transcribe")

        self.assertEqual(progress.get_stage(), "download")
        self.assertIn("📥 模型下载/准备中", _heartbeat_message(progress.get_stage(), 65))
        self.assertNotIn("推理中", _heartbeat_message(progress.get_stage(), 65))

    def test_fetching_complete_switches_to_transcribe_stage(self) -> None:
        progress = _Progress("download")
        line = "Fetching 12 files: 100%|##########| 12/12 [38:00<00:00, 190.0s/it]"

        if _line_indicates_fetch_complete(line):
            progress.set_stage("transcribe")

        self.assertEqual(progress.get_stage(), "transcribe")
        self.assertIn("⏳ 转录推理中", _heartbeat_message(progress.get_stage(), 120))

    def test_segment_output_switches_to_transcribe_stage(self) -> None:
        progress = _Progress("download")
        line = "[00:01.000 --> 00:02.000] 大家好"

        if _line_indicates_transcribe_started(line):
            progress.set_stage("transcribe")

        self.assertEqual(progress.get_stage(), "transcribe")
        self.assertIn("⏳ 转录推理中", _heartbeat_message(progress.get_stage(), 2))

    def test_initial_transcribe_stage_uses_transcribe_heartbeat(self) -> None:
        progress = _Progress("transcribe")

        self.assertEqual(progress.get_stage(), "transcribe")
        self.assertEqual(_heartbeat_message(progress.get_stage(), 9), "      ⏳ 转录推理中... 已用时 0:09")


if __name__ == "__main__":
    unittest.main()
