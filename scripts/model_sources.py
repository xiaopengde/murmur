"""Model source preparation helpers for Murmur."""

from __future__ import annotations

import os
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

from models import MODEL_SPECS
from progress import run_subprocess_with_progress

ModelSource = str


@dataclass(frozen=True)
class ModelScopeSpec:
    repo: str
    cache_name: str
    size: str
    bytes: int | None
    required_files: tuple[str, ...]
    adapter: str | None = None


MLX_MODELSCOPE_SPECS: dict[str, ModelScopeSpec] = {
    # This ModelScope repo stores the MLX weights as model.safetensors.
    # mlx-whisper 0.4.x expects weights.safetensors or weights.npz.
    "mlx-community/whisper-large-v3-turbo": ModelScopeSpec(
        repo="mlx-community/whisper-large-v3-turbo-4bit",
        cache_name="mlx-community__whisper-large-v3-turbo-4bit",
        size="约 464MB",
        bytes=464 * 1024**2,
        required_files=("model.safetensors", "config.json"),
        adapter="mlx_model_safetensors",
    ),
}


CTRANSLATE2_MODELSCOPE_SPECS: dict[str, ModelScopeSpec] = {
    "large-v3-turbo": ModelScopeSpec(
        repo="mobiuslabsgmbh/faster-whisper-large-v3-turbo",
        cache_name="mobiuslabsgmbh__faster-whisper-large-v3-turbo",
        size="约 1.62GB",
        bytes=int(1.62 * 1024**3),
        required_files=("model.bin", "config.json"),
    ),
    "large-v3": ModelScopeSpec(
        repo="Systran/faster-whisper-large-v3",
        cache_name="Systran__faster-whisper-large-v3",
        size="约 3.09GB",
        bytes=int(3.09 * 1024**3),
        required_files=("model.bin", "config.json"),
    ),
    "large-v2": ModelScopeSpec(
        repo="Systran/faster-whisper-large-v2",
        cache_name="Systran__faster-whisper-large-v2",
        size="约 3.09GB",
        bytes=int(3.09 * 1024**3),
        required_files=("model.bin", "config.json"),
    ),
}


def murmur_model_cache_dir(env: dict[str, str] | None = None) -> Path:
    env = env or {}
    root = env.get("MURMUR_MODEL_CACHE") or os.environ.get("MURMUR_MODEL_CACHE")
    if root:
        return Path(root).expanduser()
    xdg_cache = env.get("XDG_CACHE_HOME") or os.environ.get("XDG_CACHE_HOME")
    if xdg_cache:
        return Path(xdg_cache).expanduser() / "murmur" / "models"
    return Path.home() / ".cache" / "murmur" / "models"


def is_local_model_path(model: str) -> bool:
    value = model.strip()
    return value.startswith(("/", "~", ".")) or Path(value).expanduser().exists()


def _logical_model_name(requested_model: str | None, resolved_model: str, engine: str) -> str:
    requested = (requested_model or "").strip()
    if requested in MODEL_SPECS:
        return requested
    if engine == "mlx-whisper":
        for logical_name, spec in MODEL_SPECS.items():
            if spec.get("mlx") == resolved_model:
                return logical_name
    return requested or resolved_model


def modelscope_spec_for(
    requested_model: str | None,
    resolved_model: str,
    engine: str,
) -> ModelScopeSpec | None:
    if is_local_model_path(resolved_model):
        return None
    if engine == "mlx-whisper":
        return MLX_MODELSCOPE_SPECS.get(resolved_model)
    logical_name = _logical_model_name(requested_model, resolved_model, engine)
    return CTRANSLATE2_MODELSCOPE_SPECS.get(logical_name)


def _modelscope_dir_ready(path: Path, spec: ModelScopeSpec) -> bool:
    if not path.exists():
        return False
    return all((path / name).is_file() for name in spec.required_files)


def _adapt_modelscope_dir(path: Path, spec: ModelScopeSpec) -> None:
    if spec.adapter != "mlx_model_safetensors":
        return
    source = path / "model.safetensors"
    target = path / "weights.safetensors"
    if target.exists() or not source.exists():
        return
    try:
        os.link(source, target)
    except OSError:
        shutil.copy2(source, target)


def prepare_model_from_modelscope(spec: ModelScopeSpec, env: dict[str, str]) -> Path:
    target_dir = murmur_model_cache_dir(env) / spec.cache_name
    target_dir.mkdir(parents=True, exist_ok=True)
    if not _modelscope_dir_ready(target_dir, spec):
        print(f"      📥 ModelScope 模型下载：{spec.repo}（{spec.size}）")
        print(f"      缓存目录：{target_dir}")
        cmd = [
            "uvx",
            "modelscope",
            "download",
            "--model",
            spec.repo,
            "--local_dir",
            str(target_dir),
        ]
        returncode, output_tail = run_subprocess_with_progress(cmd, env, spec.bytes, "download")
        if returncode != 0:
            sys.stderr.write(
                "❌ ModelScope 模型下载失败。\n"
                f"   repo: {spec.repo}\n"
                f"   tail:\n{output_tail[-1500:]}\n"
            )
            sys.exit(4)
    else:
        print(f"      检测到 ModelScope 模型缓存：{target_dir}")
    _adapt_modelscope_dir(target_dir, spec)
    return target_dir


def maybe_prepare_model_source(
    requested_model: str | None,
    resolved_model: str,
    engine: str,
    env: dict[str, str],
    model_source: ModelSource,
    prefer_modelscope: bool,
) -> tuple[str, str]:
    """Resolve a model source and return (model_path_or_id, source_label)."""
    if model_source not in ("auto", "hf", "modelscope"):
        raise ValueError(f"unknown model source: {model_source}")
    if is_local_model_path(resolved_model):
        return str(Path(resolved_model).expanduser()), "local"

    spec = modelscope_spec_for(requested_model, resolved_model, engine)
    use_modelscope = model_source == "modelscope" or (model_source == "auto" and prefer_modelscope and spec is not None)
    if use_modelscope:
        if spec is None:
            sys.stderr.write(
                "❌ 当前模型暂无已验证 ModelScope 映射，不能使用 --model-source modelscope。\n"
                f"   engine: {engine}\n"
                f"   requested model: {requested_model or '(default)'}\n"
                f"   resolved model: {resolved_model}\n"
                "   处理：改用已验证模型 large-v3-turbo，或显式传 --model-source hf 走原模型源。\n"
            )
            sys.exit(4)
        return str(prepare_model_from_modelscope(spec, env)), "modelscope"

    return resolved_model, "hf"
