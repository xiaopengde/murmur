"""Subprocess output relay and heartbeat progress helpers for Murmur."""

from __future__ import annotations

import os
import re
import subprocess
import threading
import time
from collections import deque
from pathlib import Path

ProgressStage = str

TRANSCRIBE_SEGMENT_RE = re.compile(r"^\s*\[\d{2}:\d{2}\.\d{3}\s+-->\s+\d{2}:\d{2}\.\d{3}\]")


def _hf_hub_cache_dir(env: dict[str, str]) -> Path:
    hf_hub_cache = env.get("HF_HUB_CACHE") or os.environ.get("HF_HUB_CACHE")
    if hf_hub_cache:
        return Path(hf_hub_cache)
    hf_home = env.get("HF_HOME") or os.environ.get("HF_HOME")
    if hf_home:
        return Path(hf_home) / "hub"
    return Path.home() / ".cache" / "huggingface" / "hub"


def _dir_size_bytes(path: Path) -> int:
    if not path.exists():
        return 0
    total = 0
    try:
        for p in path.rglob("*"):
            if p.is_file():
                try:
                    total += p.stat().st_size
                except OSError:
                    pass
    except OSError:
        pass
    return total


def _format_byte_size(num_bytes: int) -> str:
    if num_bytes >= 1024**3:
        return f"{num_bytes / 1024**3:.1f} GB"
    return f"{num_bytes / 1024**2:.0f} MB"


def _prepare_child_env(env: dict[str, str]) -> dict[str, str]:
    child = dict(env)
    child["PYTHONUNBUFFERED"] = "1"
    child.pop("HF_HUB_DISABLE_PROGRESS_BARS", None)
    return child


class _Progress:
    def __init__(self, initial_stage: ProgressStage) -> None:
        self.stop = threading.Event()
        self.stage = initial_stage
        self.downloading = False
        self.download_done = False
        self.last_cache_bytes = 0
        self.lock = threading.Lock()

    def set_stage(self, stage: ProgressStage, announce: bool = False) -> None:
        with self.lock:
            if self.stage == stage:
                return
            self.stage = stage
        if announce and stage == "transcribe":
            print("      📥 模型下载/准备完成，开始转录推理...", flush=True)

    def get_stage(self) -> ProgressStage:
        with self.lock:
            return self.stage


def _line_indicates_transcribe_started(line: str) -> bool:
    return bool(TRANSCRIBE_SEGMENT_RE.search(line))


def _line_indicates_fetch_complete(line: str) -> bool:
    low = line.lower()
    if "fetch" in low and "100%" in line:
        return True
    if "snapshot" in low and ("100%" in line or "complete" in low or "done" in low):
        return True
    return False


def _heartbeat_message(stage: ProgressStage, elapsed: int) -> str:
    m, s = divmod(elapsed, 60)
    if stage == "transcribe":
        return f"      ⏳ 转录推理中... 已用时 {m}:{s:02d}"
    return f"      📥 模型下载/准备中... 已用时 {m}:{s:02d}"


def _should_relay_child_line(line: str) -> bool:
    low = line.lower()
    keywords = ("download", "fetch", "pull", "snapshot", "install", "resolved", "error", "warning", "mb/s", "kb/s", "it/s", "transcrib")
    return any(kw in low for kw in keywords) or "%" in line or "━" in line or "█" in line or "▌" in line


def _monitor_hf_cache(progress: _Progress, env: dict[str, str], baseline_bytes: int, total_hint: int | None) -> None:
    hub = _hf_hub_cache_dir(env)
    stable_rounds = 0
    while not progress.stop.wait(3):
        current = _dir_size_bytes(hub)
        delta = max(0, current - baseline_bytes)
        if delta > 2 * 1024 * 1024:
            progress.downloading = True
            stable_rounds = 0
        if not progress.downloading or progress.download_done:
            continue
        if current == progress.last_cache_bytes:
            stable_rounds += 1
            if stable_rounds >= 5:
                progress.download_done = True
                progress.set_stage("transcribe", announce=True)
            continue
        stable_rounds = 0
        progress.last_cache_bytes = current
        # total_hint 只是粗估；一旦实际下载量超过它，就别再显示会误导的「/ ~75MB (99%)」，
        # 只老实报已下载体积（估算偏小很常见：模型外还有 tokenizer / VAD 等附带文件）。
        if total_hint and delta < total_hint:
            pct = f" ({int(delta * 100 / total_hint)}%)"
            total_part = f" / ~{_format_byte_size(total_hint)}"
        else:
            pct = ""
            total_part = ""
        print(f"      📥 模型下载中: {_format_byte_size(delta)}{total_part}{pct}", flush=True)


def _inference_heartbeat(progress: _Progress) -> None:
    t0 = time.monotonic()
    while not progress.stop.wait(30):
        elapsed = int(time.monotonic() - t0)
        print(_heartbeat_message(progress.get_stage(), elapsed), flush=True)


def _relay_subprocess_output(proc: subprocess.Popen[str], progress: _Progress, tail: deque[str]) -> None:
    assert proc.stdout is not None
    try:
        for raw in proc.stdout:
            line = raw.rstrip("\n\r")
            if not line.strip():
                continue
            tail.append(line)
            if _should_relay_child_line(line):
                print(f"      {line}", flush=True)
            if _line_indicates_fetch_complete(line) or _line_indicates_transcribe_started(line):
                progress.download_done = True
                progress.set_stage("transcribe", announce=False)
    except OSError:
        pass


def run_subprocess_with_progress(
    cmd: list[str],
    env: dict[str, str],
    total_hint: int | None,
    initial_stage: ProgressStage = "download",
) -> tuple[int, str]:
    """Run a child process, relay useful progress, and return (code, output_tail)."""
    if initial_stage not in ("download", "transcribe"):
        raise ValueError(f"unknown progress stage: {initial_stage}")
    child_env = _prepare_child_env(env)
    baseline = _dir_size_bytes(_hf_hub_cache_dir(child_env))
    progress = _Progress(initial_stage)
    tail: deque[str] = deque(maxlen=80)

    proc = subprocess.Popen(
        cmd,
        env=child_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        errors="replace",
    )
    threads = [
        threading.Thread(target=_monitor_hf_cache, args=(progress, child_env, baseline, total_hint), daemon=True),
        threading.Thread(target=_inference_heartbeat, args=(progress,), daemon=True),
        threading.Thread(target=_relay_subprocess_output, args=(proc, progress, tail), daemon=True),
    ]
    for t in threads:
        t.start()
    returncode = proc.wait()
    progress.stop.set()
    for t in threads:
        t.join(timeout=2)
    return returncode, "\n".join(tail)
