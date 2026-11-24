#!/usr/bin/env python3
"""Composites raw Rolling Alarm Google Play screenshots onto dark chronometer
store frames with crisp Inter headlines and sage-teal / coral accents.

Reads raw captures from:
    screenshots/play_store/{phone,tablet_7in,tablet_10in}/*.png
Writes Play Console-ready captioned 9:16 PNGs to:
    screenshots/play_store_captioned/{phone,tablet_7in,tablet_10in}/*.png

Usage:
    python scripts/caption_play_screenshots.py
    python scripts/caption_play_screenshots.py --profiles phone --scenes 01_dashboard 07_paywall
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Dict, List, Tuple

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Nocturnal chronometer design tokens matching lib/styles.dart
BG_CANVAS: Tuple[int, int, int] = (12, 15, 18)        # #0C0F12
SURFACE_BEZEL: Tuple[int, int, int] = (22, 27, 33)    # #161B21
BORDER_RIM: Tuple[int, int, int] = (38, 48, 59)       # #26303B
INK_PRIMARY: Tuple[int, int, int] = (232, 238, 242)   # #E8EEF2
INK_MUTED: Tuple[int, int, int] = (139, 154, 171)     # #8B9AAB
SAGE_TEAL: Tuple[int, int, int] = (46, 196, 166)      # #2EC4A6
SOFT_CORAL: Tuple[int, int, int] = (255, 90, 78)      # #FF5A4E

MAX_PLAY_BYTES = 8 * 1024 * 1024


@dataclass(frozen=True)
class ProfileSpec:
    name: str
    width: int
    height: int
    min_side: int
    max_side: int


@dataclass(frozen=True)
class SceneCopy:
    eyebrow: str
    headline: str
    subcaption: str
    accent: Tuple[int, int, int]


PROFILES: Dict[str, ProfileSpec] = {
    "phone": ProfileSpec("phone", 1080, 1920, 320, 3840),
    "tablet_7in": ProfileSpec("tablet_7in", 1080, 1920, 320, 3840),
    "tablet_10in": ProfileSpec("tablet_10in", 1440, 2560, 1080, 7680),
}

SCENES: Dict[str, SceneCopy] = {
    "01_dashboard": SceneCopy(
        eyebrow="TRUE ROLLING INTERVALS",
        headline="Next Alarm Rolls From Dismissal",
        subcaption="Medication spacing · FIFO 8/6 swings · Daily caps",
        accent=SAGE_TEAL,
    ),
    "02_alarm_ringing": SceneCopy(
        eyebrow="FULL-SCREEN LOCK-SCREEN WAKE",
        headline="Wakes Over Your Lock Screen",
        subcaption="Tactile dismiss & snooze sliders · Never missed",
        accent=SOFT_CORAL,
    ),
    "03_routine_editor": SceneCopy(
        eyebrow="BUILT FOR REAL SCHEDULES",
        headline="FIFO Swings, Daily Caps & Intervals",
        subcaption="8/6, 2/1 & 4-on-4-off rosters with auto R&R parking",
        accent=SAGE_TEAL,
    ),
    "04_routine_summary": SceneCopy(
        eyebrow="AT-A-GLANCE CONTROL",
        headline="Live Cycle & Ring Budget",
        subcaption="Pause, skip, adjust today's cap & share RA1: presets",
        accent=SAGE_TEAL,
    ),
    "05_alarm_logs": SceneCopy(
        eyebrow="DOCTOR & CAREGIVER READY",
        headline="Printable PDF Adherence Logs",
        subcaption="Timestamped dismissals, snoozes, skips & mute history",
        accent=SAGE_TEAL,
    ),
    "06_settings": SceneCopy(
        eyebrow="BUILT TO RING EVERY TIME",
        headline="OEM Battery & Volume Controls",
        subcaption="Guided alarm setup for Samsung, Xiaomi, Oppo & Vivo",
        accent=SAGE_TEAL,
    ),
    "07_paywall": SceneCopy(
        eyebrow="ZERO ADS · ZERO ACCOUNTS",
        headline="100% Offline · Optional Lifetime Pro",
        subcaption="Core routines free forever · One-time Lifetime or flexible plans",
        accent=SAGE_TEAL,
    ),
}


def load_font(fonts_dir: Path, filename: str, size: int) -> ImageFont.FreeTypeFont:
    font_path = fonts_dir / filename
    if not font_path.is_file():
        raise FileNotFoundError(f"Required font not found: {font_path}")
    return ImageFont.truetype(str(font_path), size=size)


def wrap_centered_lines(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    max_width: int,
    max_lines: int = 2,
) -> List[str]:
    """Word-wraps [text] evenly across up to [max_lines] lines within [max_width]."""
    bbox = draw.textbbox((0, 0), text, font=font)
    if (bbox[2] - bbox[0]) <= max_width:
        return [text]

    words = text.split()
    if len(words) <= 1 or max_lines == 1:
        return [text]

    best_split: Tuple[str, str] | None = None
    best_diff = 10**9
    for idx in range(1, len(words)):
        line1 = " ".join(words[:idx])
        line2 = " ".join(words[idx:])
        w1 = draw.textbbox((0, 0), line1, font=font)[2]
        w2 = draw.textbbox((0, 0), line2, font=font)[2]
        if w1 <= max_width and w2 <= max_width:
            diff = abs(w1 - w2)
            if diff < best_diff:
                best_diff = diff
                best_split = (line1, line2)
    if best_split is not None:
        return [best_split[0], best_split[1]]

    # Greedy fallback if a single long phrase needs wrapping
    lines: List[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=font)[2] <= max_width or not current:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines[:max_lines]


def create_rounded_mask(size: Tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (size[0] - 1, size[1] - 1)], radius=radius, fill=255)
    return mask


def add_ambient_glow(
    canvas: Image.Image,
    accent: Tuple[int, int, int],
    scale: float,
) -> Image.Image:
    """Adds a subtle nocturnal radial glow behind the header & bezel top."""
    w, h = canvas.size
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)

    cx = w // 2
    cy = int(260 * scale)
    rx = int(560 * scale)
    ry = int(360 * scale)
    draw.ellipse(
        [(cx - rx, cy - ry), (cx + rx, cy + ry)],
        fill=(accent[0], accent[1], accent[2], 24),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=int(130 * scale)))
    return Image.alpha_composite(canvas.convert("RGBA"), glow)


def render_captioned_screenshot(
    raw_path: Path,
    output_path: Path,
    profile: ProfileSpec,
    copy: SceneCopy,
    fonts_dir: Path,
) -> None:
    w, h = profile.width, profile.height
    scale = w / 1080.0

    canvas = Image.new("RGBA", (w, h), (*BG_CANVAS, 255))
    canvas = add_ambient_glow(canvas, copy.accent, scale)
    draw = ImageDraw.Draw(canvas)

    # Typography sizing scaled cleanly for 1080x1920 and 1440x2560
    eyebrow_font = load_font(fonts_dir, "Inter-SemiBold.ttf", int(round(21 * scale)))
    headline_size = int(round(52 * scale))
    headline_font = load_font(fonts_dir, "Inter-Bold.ttf", headline_size)
    sub_font = load_font(fonts_dir, "Inter-Medium.ttf", int(round(26 * scale)))

    text_max_w = int(w - 112 * scale)

    # Ensure headline fits cleanly within 2 lines (shrink slightly if ever needed)
    while True:
        headline_lines = wrap_centered_lines(draw, copy.headline, headline_font, text_max_w, max_lines=2)
        widest = max(draw.textbbox((0, 0), line, font=headline_font)[2] for line in headline_lines)
        if widest <= text_max_w or headline_size <= int(round(36 * scale)):
            break
        headline_size -= 2
        headline_font = load_font(fonts_dir, "Inter-Bold.ttf", headline_size)

    # Shrink subcaption slightly if ever wider than text_max_w
    sub_size = int(round(26 * scale))
    while draw.textbbox((0, 0), copy.subcaption, font=sub_font)[2] > text_max_w and sub_size > int(round(18 * scale)):
        sub_size -= 1
        sub_font = load_font(fonts_dir, "Inter-Medium.ttf", sub_size)

    # 1. Eyebrow pill with crisp accent dot (composited on dedicated RGBA layer
    #    so translucent fill blends cleanly onto the dark canvas instead of
    #    overwriting canvas alpha before RGB conversion).
    eyebrow_text = copy.eyebrow
    eb_box = draw.textbbox((0, 0), eyebrow_text, font=eyebrow_font)
    eb_w = eb_box[2] - eb_box[0]
    eb_h = eb_box[3] - eb_box[1]

    dot_r = int(round(4.5 * scale))
    dot_gap = int(round(12 * scale))
    pill_pad_x = int(round(22 * scale))
    pill_pad_y = int(round(10 * scale))
    pill_w = eb_w + (dot_r * 2) + dot_gap + (pill_pad_x * 2)
    pill_h = eb_h + (pill_pad_y * 2) + int(round(4 * scale))
    pill_x0 = (w - pill_w) // 2
    pill_y0 = int(round(62 * scale))

    pill_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pill_draw = ImageDraw.Draw(pill_layer)
    pill_draw.rounded_rectangle(
        [(pill_x0, pill_y0), (pill_x0 + pill_w, pill_y0 + pill_h)],
        radius=pill_h // 2,
        fill=(copy.accent[0], copy.accent[1], copy.accent[2], 32),
        outline=(copy.accent[0], copy.accent[1], copy.accent[2], 145),
        width=max(1, int(round(1.5 * scale))),
    )
    dot_cx = pill_x0 + pill_pad_x + dot_r
    dot_cy = pill_y0 + pill_h // 2
    pill_draw.ellipse(
        [(dot_cx - dot_r, dot_cy - dot_r), (dot_cx + dot_r, dot_cy + dot_r)],
        fill=(*copy.accent, 255),
    )
    pill_draw.text(
        (dot_cx + dot_r + dot_gap - eb_box[0], pill_y0 + (pill_h - eb_h) // 2 - eb_box[1]),
        eyebrow_text,
        font=eyebrow_font,
        fill=(*copy.accent, 255),
    )
    canvas = Image.alpha_composite(canvas, pill_layer)
    draw = ImageDraw.Draw(canvas)

    # 2. Headline (1 or 2 centered lines)
    y_cursor = pill_y0 + pill_h + int(round(26 * scale))
    line_gap = int(round(10 * scale))
    for line in headline_lines:
        box = draw.textbbox((0, 0), line, font=headline_font)
        lw = box[2] - box[0]
        lh = box[3] - box[1]
        draw.text(
            ((w - lw) // 2 - box[0], y_cursor - box[1]),
            line,
            font=headline_font,
            fill=(*INK_PRIMARY, 255),
        )
        y_cursor += lh + line_gap

    # 3. Subcaption
    y_cursor += int(round(8 * scale))
    sub_box = draw.textbbox((0, 0), copy.subcaption, font=sub_font)
    sub_w = sub_box[2] - sub_box[0]
    sub_h = sub_box[3] - sub_box[1]
    draw.text(
        ((w - sub_w) // 2 - sub_box[0], y_cursor - sub_box[1]),
        copy.subcaption,
        font=sub_font,
        fill=(*INK_MUTED, 255),
    )
    header_bottom = y_cursor + sub_h

    # 4. Framed, uncropped device screenshot fitted to remaining height
    top_gap = int(round(36 * scale))
    bottom_margin = int(round(42 * scale))
    bezel_pad = int(round(14 * scale))
    outer_radius = int(round(46 * scale))
    inner_radius = int(round(34 * scale))

    avail_h = h - (header_bottom + top_gap) - bottom_margin - (bezel_pad * 2)
    avail_w = w - int(round(96 * scale)) - (bezel_pad * 2)

    with Image.open(raw_path) as raw_img:
        raw_rgba = raw_img.convert("RGBA")
        src_w, src_h = raw_rgba.size
        fit_ratio = min(avail_w / src_w, avail_h / src_h)
        shot_w = int(round(src_w * fit_ratio))
        shot_h = int(round(src_h * fit_ratio))
        resized_shot = raw_rgba.resize((shot_w, shot_h), Image.Resampling.LANCZOS)

    frame_w = shot_w + bezel_pad * 2
    frame_h = shot_h + bezel_pad * 2
    frame_x0 = (w - frame_w) // 2
    # Vertically center gently within the remaining lower band
    band_top = header_bottom + top_gap
    band_h = h - band_top - bottom_margin
    frame_y0 = band_top + max(0, (band_h - frame_h) // 2)

    # Soft dark drop shadow behind chassis
    shadow_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_offset_y = int(round(18 * scale))
    shadow_draw.rounded_rectangle(
        [
            (frame_x0 - int(round(4 * scale)), frame_y0 + shadow_offset_y),
            (frame_x0 + frame_w + int(round(4 * scale)), frame_y0 + frame_h + shadow_offset_y),
        ],
        radius=outer_radius,
        fill=(0, 0, 0, 165),
    )
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=int(round(28 * scale))))
    canvas = Image.alpha_composite(canvas, shadow_layer)

    # Outer dark instrument chassis with subtle accent top rim sheen
    chassis_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    chassis_draw = ImageDraw.Draw(chassis_layer)
    chassis_draw.rounded_rectangle(
        [(frame_x0, frame_y0), (frame_x0 + frame_w, frame_y0 + frame_h)],
        radius=outer_radius,
        fill=(*SURFACE_BEZEL, 255),
        outline=(*BORDER_RIM, 255),
        width=max(2, int(round(2.5 * scale))),
    )
    # Crisp 1px inner screen border
    shot_x0 = frame_x0 + bezel_pad
    shot_y0 = frame_y0 + bezel_pad
    chassis_draw.rounded_rectangle(
        [(shot_x0 - 1, shot_y0 - 1), (shot_x0 + shot_w + 1, shot_y0 + shot_h + 1)],
        radius=inner_radius + 1,
        outline=(18, 22, 28, 255),
        width=max(1, int(round(1.5 * scale))),
    )
    canvas = Image.alpha_composite(canvas, chassis_layer)

    # Paste rounded uncropped screenshot inside chassis
    shot_mask = create_rounded_mask((shot_w, shot_h), inner_radius)
    canvas.paste(resized_shot, (shot_x0, shot_y0), shot_mask)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    final_rgb = canvas.convert("RGB")
    final_rgb.save(output_path, format="PNG", optimize=True)


def validate_output(path: Path, profile: ProfileSpec) -> None:
    size_bytes = path.stat().st_size
    if size_bytes > MAX_PLAY_BYTES:
        raise ValueError(f"{path} exceeds 8 MB Play Console limit ({size_bytes} bytes)")
    with Image.open(path) as img:
        if img.format != "PNG":
            raise ValueError(f"{path} is not a PNG (got {img.format})")
        w, h = img.size
    if (w, h) != (profile.width, profile.height):
        raise ValueError(f"{path} expected {profile.width}x{profile.height}, got {w}x{h}")
    short_side, long_side = min(w, h), max(w, h)
    if short_side < profile.min_side or long_side > profile.max_side:
        raise ValueError(
            f"{path} dimensions {w}x{h} outside Play Console bounds [{profile.min_side}, {profile.max_side}]"
        )
    if long_side * 9 != short_side * 16:
        raise ValueError(f"{path} dimensions {w}x{h} are not an exact 9:16 aspect ratio")


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description="Caption Rolling Alarm Play Store screenshots.")
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=repo_root / "screenshots" / "play_store",
        help="Directory containing raw profile folders (default: screenshots/play_store)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=repo_root / "screenshots" / "play_store_captioned",
        help="Directory for captioned output PNGs (default: screenshots/play_store_captioned)",
    )
    parser.add_argument(
        "--profiles",
        nargs="+",
        choices=list(PROFILES.keys()),
        default=list(PROFILES.keys()),
        help="Display profiles to process",
    )
    parser.add_argument(
        "--scenes",
        nargs="+",
        choices=list(SCENES.keys()),
        default=list(SCENES.keys()),
        help="Scene filenames (without .png) to process",
    )
    args = parser.parse_args()

    fonts_dir = repo_root / "assets" / "fonts"
    generated = 0

    for profile_name in args.profiles:
        profile = PROFILES[profile_name]
        print(f"== Captioning {profile.name} ({profile.width}x{profile.height}) ==")
        for scene_name in args.scenes:
            raw_path = args.input_dir / profile.name / f"{scene_name}.png"
            if not raw_path.is_file():
                raise FileNotFoundError(f"Missing raw screenshot: {raw_path}")
            out_path = args.output_dir / profile.name / f"{scene_name}.png"
            render_captioned_screenshot(
                raw_path=raw_path,
                output_path=out_path,
                profile=profile,
                copy=SCENES[scene_name],
                fonts_dir=fonts_dir,
            )
            validate_output(out_path, profile)
            size_kb = out_path.stat().st_size / 1024.0
            print(f"  OK {out_path.relative_to(repo_root)} ({profile.width}x{profile.height}, {size_kb:.1f} KB)")
            generated += 1

    print(f"Done: {generated} captioned Play Store screenshots validated under {args.output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
