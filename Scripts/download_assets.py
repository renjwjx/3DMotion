#!/usr/bin/env python3
"""Download and verify the offline 3DBody joint-muscle action library.

The HAR is used only as captured data. Authentication and login requests are
intentionally ignored: every file used by the viewer is a public static asset.
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from collections import OrderedDict
from pathlib import Path
from typing import Any, Iterable, Optional


SITE_ROOT = "https://musclemee.3dbody.com/foundation_action_new/"
THUMBNAIL_ROOT = "https://www.3dbody.com/h/foundation_action/static/ava/jpg/"
STATIC_HOST = "musclemee.3dbody.com"
USER_AGENT = "Body3DMac-Offline-Archiver/1.0"
TRANSPARENT_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+X0Y6WQAAAABJRU5ErkJggg=="
)

FIXED_OFFLINE_ASSETS = [
    "static/build/gif/gif.worker.js",
    "static/gltf/draco/draco_decoder.js",
    "static/gltf/draco/draco_wasm_wrapper.js",
    "static/gltf/draco/draco_decoder.wasm",
]


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    project_dir = script_dir.parent
    default_har = project_dir.parent / "资料" / "SpiderProxy-20261012-202930.har"
    default_output = project_dir / "Sources" / "Body3DMac" / "Resources" / "Web"

    parser = argparse.ArgumentParser()
    parser.add_argument("--har", type=Path, default=default_har)
    parser.add_argument("--output", type=Path, default=default_output)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def load_har(path: Path) -> dict[str, Any]:
    with path.open("rb") as stream:
        return json.load(stream)


def response_bytes(entry: dict[str, Any]) -> Optional[bytes]:
    content = entry.get("response", {}).get("content", {})
    text = content.get("text")
    if text is None or text == "":
        return None
    if content.get("encoding") == "base64":
        return base64.b64decode(text)
    return text.encode("utf-8")


def extract_metadata(har: dict[str, Any]) -> list[dict[str, Any]]:
    for entry in har["log"]["entries"]:
        if urllib.parse.urlsplit(entry["request"]["url"]).path.endswith("processed_data.json"):
            payload = response_bytes(entry)
            if payload:
                metadata = json.loads(payload)
                if len(metadata) != 70:
                    raise RuntimeError(f"预期 70 个动作，实际 {len(metadata)} 个")
                return metadata
    raise RuntimeError("HAR 中没有 processed_data.json")


def static_paths_from_har(har: dict[str, Any]) -> set[str]:
    paths: set[str] = set()
    for entry in har["log"]["entries"]:
        request_url = urllib.parse.urlsplit(entry["request"]["url"])
        if request_url.hostname != STATIC_HOST:
            continue
        path = request_url.path
        prefix = "/foundation_action_new/"
        if not path.startswith(prefix):
            continue
        relative = path[len(prefix) :]
        if not relative:
            paths.add("index.html")
            continue
        if relative.startswith(("static/action/", "static/camera/", "static/img/pifuAlphaMap/", "static/img/gugeAlphaMap/")):
            continue
        if relative.startswith("static/"):
            paths.add(relative)
    return paths


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".part")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def request_bytes(url: str, attempts: int = 4) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    last_error: Optional[Exception] = None
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                if response.status != 200:
                    raise RuntimeError(f"HTTP {response.status}: {url}")
                return response.read()
        except (OSError, urllib.error.URLError, urllib.error.HTTPError) as error:
            last_error = error
            if attempt + 1 < attempts:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"下载失败：{url}：{last_error}")


def download_one(task: tuple[str, Path, bool, bool]) -> dict[str, Any]:
    url, destination, force, optional_png = task
    if not force and destination.exists() and destination.stat().st_size > 0:
        payload = destination.read_bytes()
        status = "placeholder" if optional_png and payload == TRANSPARENT_PNG else "cached"
        return manifest_record(url, destination, payload, status)

    try:
        payload = request_bytes(url, attempts=1 if optional_png else 4)
        status = "downloaded"
    except RuntimeError as error:
        if optional_png and "404" in str(error):
            payload = TRANSPARENT_PNG
            status = "placeholder"
        else:
            raise
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".part")
    temporary.write_bytes(payload)
    temporary.replace(destination)
    return manifest_record(url, destination, payload, status)


def manifest_record(url: str, destination: Path, payload: bytes, status: str) -> dict[str, Any]:
    return {
        "path": destination.as_posix(),
        "url": url,
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "status": status,
    }


def run_downloads(tasks: Iterable[tuple[str, Path, bool, bool]], workers: int) -> list[dict[str, Any]]:
    task_list = list(tasks)
    results: list[dict[str, Any]] = []
    failures: list[str] = []
    completed = 0
    total = len(task_list)

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        future_to_task = {executor.submit(download_one, task): task for task in task_list}
        for future in concurrent.futures.as_completed(future_to_task):
            url, destination, _, _ = future_to_task[future]
            completed += 1
            try:
                record = future.result()
                results.append(record)
                print(f"[{completed:>3}/{total}] {record['status']:<10} {destination.name} ({record['bytes']:,} B)")
            except Exception as error:
                failures.append(f"{url}: {error}")
                print(f"[{completed:>3}/{total}] FAILED    {destination}: {error}", file=sys.stderr)

    if failures:
        raise RuntimeError("\n".join(failures))
    return results


def derive_openssl_key_and_iv(password: bytes) -> tuple[bytes, bytes]:
    material = b""
    previous = b""
    while len(material) < 40:
        previous = hashlib.md5(previous + password).digest()
        material += previous
    return material[:24], material[24:40]


def decode_action(path: Path) -> dict[str, Any]:
    encrypted = path.read_bytes()
    if len(encrypted) <= 8:
        raise RuntimeError(f"模型文件过短：{path}")
    key, iv = derive_openssl_key_and_iv(encrypted[:8])
    process = subprocess.run(
        ["openssl", "enc", "-d", "-aes-192-cbc", "-K", key.hex(), "-iv", iv.hex()],
        input=encrypted[8:],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if process.returncode != 0:
        raise RuntimeError(f"AES 解包失败：{path.name}: {process.stderr.decode('utf-8', 'replace')}")
    return json.loads(zlib.decompress(process.stdout))


def external_model_assets(action_paths: Iterable[Path]) -> set[str]:
    assets: set[str] = set()
    for action_path in action_paths:
        model = decode_action(action_path)
        if model.get("asset", {}).get("version") != "2.0":
            raise RuntimeError(f"不是 glTF 2.0：{action_path}")
        for image in model.get("images", []):
            uri = image.get("uri", "")
            parsed = urllib.parse.urlsplit(uri)
            if not uri or parsed.scheme == "data" or uri.startswith(("/", "..")):
                continue
            assets.add(uri)
        for buffer in model.get("buffers", []):
            uri = buffer.get("uri", "")
            parsed = urllib.parse.urlsplit(uri)
            if not uri or parsed.scheme == "data" or uri.startswith(("/", "..")):
                continue
            assets.add(uri)
    return assets


def css_dependencies(web_root: Path) -> set[str]:
    dependencies: set[str] = set()
    for css_path in web_root.rglob("*.css"):
        text = css_path.read_text(encoding="utf-8", errors="replace")
        for value in re.findall(r"url\((?:['\"])?([^)'\"]+)", text):
            if value.startswith(("data:", "http://", "https://", "#")):
                continue
            relative = (css_path.parent / value).resolve().relative_to(web_root.resolve())
            dependencies.add(relative.as_posix())
    return dependencies


def validate_png(path: Path) -> None:
    if path.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"PNG 校验失败：{path}")


def validate_jpeg(path: Path) -> None:
    data = path.read_bytes()
    if not data.startswith(b"\xff\xd8\xff"):
        raise RuntimeError(f"JPEG 校验失败：{path}")


def validate_image(path: Path) -> None:
    data = path.read_bytes()
    if not (data.startswith(b"\xff\xd8\xff") or data.startswith(b"\x89PNG\r\n\x1a\n")):
        raise RuntimeError(f"图片校验失败：{path}")


def category_summary(metadata: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: OrderedDict[str, dict[str, Any]] = OrderedDict()
    for item in metadata:
        group = grouped.setdefault(
            item["nounsCN"],
            {"nameCN": item["nounsCN"], "nameEN": item["nounsEN"], "count": 0, "ids": []},
        )
        group["count"] += 1
        group["ids"].append(item["id"])
    return list(grouped.values())


def main() -> None:
    args = parse_args()
    har = load_har(args.har)
    metadata = extract_metadata(har)
    web_root = args.output.resolve()
    web_root.mkdir(parents=True, exist_ok=True)
    write_json(web_root / "static/data/processed_data.json", metadata)
    write_json(web_root / "catalog-summary.json", category_summary(metadata))

    ids = [int(item["id"]) for item in metadata]
    if len(ids) != len(set(ids)):
        raise RuntimeError("动作 ID 有重复")

    tasks: list[tuple[str, Path, bool, bool]] = []
    for action_id in ids:
        required_paths = [f"static/action/{action_id}", f"static/camera/{action_id}.json"]
        mask_paths = [
            f"static/img/pifuAlphaMap/{action_id}.png",
            f"static/img/gugeAlphaMap/{action_id}.png",
        ]
        tasks.extend((urllib.parse.urljoin(SITE_ROOT, path), web_root / path, args.force, False) for path in required_paths)
        tasks.extend((urllib.parse.urljoin(SITE_ROOT, path), web_root / path, args.force, True) for path in mask_paths)
        tasks.append((f"{THUMBNAIL_ROOT}{action_id}.jpg", web_root / f"thumbnails/{action_id}.jpg", args.force, False))

    frontend_paths = static_paths_from_har(har) | set(FIXED_OFFLINE_ASSETS)
    frontend_paths.add("index.html")
    tasks.extend((urllib.parse.urljoin(SITE_ROOT, path), web_root / path, args.force, False) for path in sorted(frontend_paths))

    print(f"下载第一阶段：{len(ids)} 个模型及页面资源，共 {len(tasks)} 个文件")
    records = run_downloads(tasks, args.workers)

    action_paths = [web_root / f"static/action/{action_id}" for action_id in ids]
    model_assets = external_model_assets(action_paths)
    dependency_paths = model_assets | css_dependencies(web_root)
    dependency_tasks = [
        (urllib.parse.urljoin(SITE_ROOT, f"static/action/{path}"), web_root / "static/action" / path, args.force, False)
        for path in sorted(model_assets)
    ]
    dependency_tasks.extend(
        (urllib.parse.urljoin(SITE_ROOT, path), web_root / path, args.force, False)
        for path in sorted(css_dependencies(web_root))
    )

    if dependency_tasks:
        print(f"下载第二阶段：模型/CSS 引用资源 {len(dependency_tasks)} 个")
        records.extend(run_downloads(dependency_tasks, args.workers))

    for action_id in ids:
        validate_png(web_root / f"static/img/pifuAlphaMap/{action_id}.png")
        validate_png(web_root / f"static/img/gugeAlphaMap/{action_id}.png")
        validate_image(web_root / f"thumbnails/{action_id}.jpg")
        with (web_root / f"static/camera/{action_id}.json").open("rb") as stream:
            camera = json.load(stream)
            if not isinstance(camera, list):
                raise RuntimeError(f"相机文件格式错误：{action_id}")

    for asset in model_assets:
        validate_image(web_root / "static/action" / asset)

    for record in records:
        record["path"] = Path(record["path"]).relative_to(web_root).as_posix()

    unique_records = {record["path"]: record for record in records}
    manifest_records = sorted(unique_records.values(), key=lambda record: record["path"])
    manifest = {
        "sourceHAR": args.har.name,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "actionCount": len(ids),
        "categoryCount": len(category_summary(metadata)),
        "externalModelAssets": sorted(model_assets),
        "files": manifest_records,
        "totalBytes": sum(record["bytes"] for record in manifest_records),
    }
    write_json(web_root / "download-manifest.json", manifest)
    print(
        f"完成：{manifest['actionCount']} 个动作，{len(manifest_records)} 个文件，"
        f"{manifest['totalBytes'] / 1024 / 1024:.1f} MiB"
    )


if __name__ == "__main__":
    main()
