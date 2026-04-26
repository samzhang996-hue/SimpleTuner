#!/usr/bin/env python3
"""
Extract training frames from local videos.

Examples:
    python scripts/datasets/extract_frames_from_mp4s.py
    python scripts/datasets/extract_frames_from_mp4s.py --fps 1 --caption-template "sks person"
    python scripts/datasets/extract_frames_from_mp4s.py --prune-non-video
"""

import argparse
import logging
import re
import shutil
import subprocess
import sys
from pathlib import Path


VIDEO_EXTENSIONS = {
    ".avi",
    ".m4v",
    ".mkv",
    ".mov",
    ".mp4",
    ".mpeg",
    ".mpg",
    ".webm",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Extract image frames from videos in mp4s/ for LoRA datasets.")
    parser.add_argument("--input-dir", type=Path, default=Path("mp4s"), help="Directory containing source videos.")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("datasets/frames"),
        help="Directory where extracted frames will be written.",
    )
    parser.add_argument("--fps", type=float, default=0.5, help="Frames per second to extract. Default: 0.5.")
    parser.add_argument("--recursive", action="store_true", help="Search input-dir recursively for videos.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing extracted frames.")
    parser.add_argument("--dry-run", action="store_true", help="Print planned work without extracting or deleting.")
    parser.add_argument(
        "--image-format",
        choices=("jpg", "png", "webp"),
        default="jpg",
        help="Output image format. Default: jpg.",
    )
    parser.add_argument("--jpeg-quality", type=int, default=2, help="FFmpeg JPEG quality for jpg output, 2 is high quality.")
    parser.add_argument(
        "--max-side",
        type=int,
        default=0,
        help="Resize so the longest side is at most this value. 0 keeps original frame size.",
    )
    parser.add_argument(
        "--caption-template",
        default="",
        help="Optional caption text written beside each frame. Supports {video} and {frame}.",
    )
    parser.add_argument(
        "--prune-non-video",
        action="store_true",
        help="Delete non-video files found under input-dir. Directories are left alone.",
    )
    return parser.parse_args()


def slugify(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "_", value.strip())
    slug = slug.strip("._-")
    return slug or "video"


def require_ffmpeg() -> str:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("ffmpeg is required. Install ffmpeg before running this script.")
    return ffmpeg


def iter_input_files(input_dir: Path, recursive: bool) -> list[Path]:
    if not input_dir.exists():
        raise FileNotFoundError(f"Input directory does not exist: {input_dir}")
    if not input_dir.is_dir():
        raise NotADirectoryError(f"Input path is not a directory: {input_dir}")

    iterator = input_dir.rglob("*") if recursive else input_dir.iterdir()
    return sorted(path for path in iterator if path.is_file())


def split_video_and_other_files(files: list[Path]) -> tuple[list[Path], list[Path]]:
    videos = []
    non_videos = []
    for path in files:
        if path.suffix.lower() in VIDEO_EXTENSIONS:
            videos.append(path)
        else:
            non_videos.append(path)
    return videos, non_videos


def build_video_output_dir(output_dir: Path, input_dir: Path, video_path: Path) -> Path:
    try:
        relative_parent = video_path.parent.relative_to(input_dir)
    except ValueError:
        relative_parent = Path()
    parts = [slugify(part) for part in relative_parent.parts]
    parts.append(slugify(video_path.stem))
    return output_dir.joinpath(*parts)


def build_filter(fps: float, max_side: int) -> str:
    if fps <= 0:
        raise ValueError("--fps must be greater than 0")

    filters = [f"fps={fps:g}"]
    if max_side > 0:
        filters.append("scale='if(gt(iw,ih),min(iw,{0}),-2)':'if(gt(ih,iw),min(ih,{0}),-2)'".format(max_side))
    return ",".join(filters)


def extract_frames(
    ffmpeg: str,
    video_path: Path,
    output_dir: Path,
    image_format: str,
    filters: str,
    jpeg_quality: int,
    overwrite: bool,
    dry_run: bool,
) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    frame_pattern = output_dir / f"{slugify(video_path.stem)}_%06d.{image_format}"
    existing = set(output_dir.glob(f"{slugify(video_path.stem)}_*.{image_format}"))

    cmd = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-y" if overwrite else "-n",
        "-i",
        str(video_path),
        "-vf",
        filters,
    ]
    if image_format == "jpg":
        cmd.extend(["-q:v", str(jpeg_quality)])
    cmd.append(str(frame_pattern))

    logging.info("Extracting %s -> %s", video_path, output_dir)
    if dry_run:
        logging.info("Dry run command: %s", " ".join(cmd))
        return []

    subprocess.run(cmd, check=True)
    return sorted(set(output_dir.glob(f"{slugify(video_path.stem)}_*.{image_format}")) - existing)


def write_captions(frames: list[Path], caption_template: str, video_path: Path, dry_run: bool) -> None:
    if not caption_template:
        return

    for frame in frames:
        caption = caption_template.format(video=video_path.stem, frame=frame.stem)
        caption_path = frame.with_suffix(".txt")
        logging.info("Writing caption %s", caption_path)
        if not dry_run:
            caption_path.write_text(caption + "\n", encoding="utf-8")


def prune_non_video_files(files: list[Path], dry_run: bool) -> None:
    for path in files:
        logging.info("Deleting non-video file from input directory: %s", path)
        if not dry_run:
            path.unlink()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    args = parse_args()

    try:
        ffmpeg = require_ffmpeg()
        files = iter_input_files(args.input_dir, args.recursive)
        videos, non_videos = split_video_and_other_files(files)

        if non_videos and args.prune_non_video:
            prune_non_video_files(non_videos, args.dry_run)
        elif non_videos:
            logging.warning(
                "Ignoring %d non-video file(s) in %s. Re-run with --prune-non-video to delete them.",
                len(non_videos),
                args.input_dir,
            )

        if not videos:
            logging.warning("No video files found in %s", args.input_dir)
            return 0

        filters = build_filter(args.fps, args.max_side)
        total_frames = 0
        for video_path in videos:
            video_output_dir = build_video_output_dir(args.output_dir, args.input_dir, video_path)
            frames = extract_frames(
                ffmpeg=ffmpeg,
                video_path=video_path,
                output_dir=video_output_dir,
                image_format=args.image_format,
                filters=filters,
                jpeg_quality=args.jpeg_quality,
                overwrite=args.overwrite,
                dry_run=args.dry_run,
            )
            write_captions(frames, args.caption_template, video_path, args.dry_run)
            total_frames += len(frames)

        logging.info("Done. Created %d new frame(s).", total_frames)
        return 0
    except subprocess.CalledProcessError as exc:
        logging.error("ffmpeg failed with exit code %s", exc.returncode)
        return exc.returncode or 1
    except Exception as exc:
        logging.error("%s", exc)
        return 1


if __name__ == "__main__":
    sys.exit(main())
