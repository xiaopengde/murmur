"""Central Whisper model metadata and engine-specific resolution for Murmur."""

from __future__ import annotations

DEFAULT_MODEL = "large-v3-turbo"

# One canonical short-name table. ctranslate2 accepts these names directly;
# mlx-whisper needs explicit HuggingFace repo IDs (do not blindly append -mlx).
MODEL_SPECS: dict[str, dict[str, object]] = {
    "tiny": {"size": "约 75MB", "bytes": 75 * 1024**2, "mlx": "mlx-community/whisper-tiny-mlx"},
    "base": {"size": "约 150MB", "bytes": 150 * 1024**2, "mlx": "mlx-community/whisper-base-mlx"},
    "small": {"size": "约 500MB", "bytes": int(0.5 * 1024**3), "mlx": "mlx-community/whisper-small-mlx"},
    "medium": {"size": "约 1GB", "bytes": 1024**3, "mlx": "mlx-community/whisper-medium-mlx"},
    "large-v1": {"size": "约 2.9GB", "bytes": int(2.9 * 1024**3), "mlx": "mlx-community/whisper-large-v1-mlx"},
    "large-v2": {"size": "约 2.9GB", "bytes": int(2.9 * 1024**3), "mlx": "mlx-community/whisper-large-v2-mlx"},
    "large-v3": {"size": "约 2.9GB", "bytes": int(2.9 * 1024**3), "mlx": "mlx-community/whisper-large-v3-mlx"},
    "large-v3-turbo": {"size": "约 1.5GB", "bytes": int(1.5 * 1024**3), "mlx": "mlx-community/whisper-large-v3-turbo"},
}

KNOWN_MODELS = set(MODEL_SPECS)

ONBOARDING_MODEL_CHOICES: tuple[dict[str, str], ...] = (
    {
        "id": "large-v3-turbo",
        "label": "large-v3-turbo（推荐）",
        "description": "质量高、下载约 1.5GB，默认首选",
        "download_hint": "约 1.5GB",
    },
    {
        "id": "large-v3",
        "label": "large-v3",
        "description": "最高质量，下载约 2.9GB，磁盘/网络充足时选",
        "download_hint": "约 2.9GB",
    },
    {
        "id": "medium",
        "label": "medium",
        "description": "CPU 机器更友好，下载约 1GB，质量略降",
        "download_hint": "约 1GB",
    },
    {
        "id": "small",
        "label": "small",
        "description": "更快更省空间（约 500MB），适合试跑",
        "download_hint": "约 500MB",
    },
)


def is_valid_default_model(model: str) -> bool:
    """Validate a persisted default model: known short name or explicit HF repo ID."""
    value = model.strip()
    if not value or any(ch.isspace() for ch in value):
        return False
    return value in KNOWN_MODELS or "/" in value


def resolve_model(name: str | None, engine: str) -> str:
    """Resolve a user-facing model short name for the selected engine."""
    logical_name = (name or DEFAULT_MODEL).strip()
    if logical_name in MODEL_SPECS:
        if engine == "mlx-whisper":
            return str(MODEL_SPECS[logical_name]["mlx"])
        return logical_name
    return logical_name


def model_download_size_hint(model: str) -> str:
    spec = MODEL_SPECS.get(model)
    if spec:
        return str(spec["size"])
    m = model.lower()
    if "turbo" in m:
        return "约 1.5GB"
    if "large" in m:
        return "约 2.9GB"
    if "medium" in m:
        return "约 1GB"
    if "small" in m:
        return "约 500MB"
    if "tiny" in m or "base" in m:
        return "约 75–150MB"
    return "视模型而定"


def model_download_bytes_hint(model: str) -> int | None:
    spec = MODEL_SPECS.get(model)
    if spec:
        return int(spec["bytes"])
    for short_name, candidate in MODEL_SPECS.items():
        if short_name in model.lower():
            return int(candidate["bytes"])
    return None


def transcribe_failure_hint(resolved_model: str, output_tail: str) -> str:
    """Return actionable failure guidance while always showing the resolved model."""
    low = output_tail.lower()
    lines = [
        "❌ 转录失败。",
        f"   resolved model: {resolved_model}",
    ]
    if any(token in low for token in ("401", "403", "404", "repository not found", "repo not found", "not a valid model")):
        lines.extend([
            "   判断：模型仓库不存在、私有，或短名映射错误。",
            "   处理：核对上方 resolved model；如是短名请升级 Murmur，或临时传可访问的完整 HF repo 名。",
        ])
    elif any(token in low for token in ("timed out", "timeout", "connection", "network", "temporary failure", "name resolution", "ssl")):
        lines.extend([
            "   判断：更像是网络 / DNS / TLS / HuggingFace 下载连接问题。",
            "   处理：重试；大陆网络可加 --cn 启用 hf-mirror.com 和清华 PyPI 镜像。",
        ])
    else:
        lines.extend([
            "   常见原因：HuggingFace 下载失败、uv 拉包失败、内存不足或音频格式异常。",
            "   可尝试：--cn、--model medium/small，或查看 docs/troubleshooting.md。",
        ])
    return "\n".join(lines) + "\n"
