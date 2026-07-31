from PIL import Image
from pathlib import Path

src_logo = Path(r"C:\Users\jayms\Downloads\NEW ONE.png")
out = Path(r"C:\repo\RollingAlarm\assets\branding")
out.mkdir(parents=True, exist_ok=True)


def load_rgba(p: Path) -> Image.Image:
    return Image.open(p).convert("RGBA")


def fit_square(im: Image.Image, size: int, bg=(10, 10, 10, 255)) -> Image.Image:
    # Center-crop to square if needed, then composite onto opaque bg and resize.
    w, h = im.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    cropped = im.crop((left, top, left + side, top + side))
    base = Image.new("RGBA", cropped.size, bg)
    base = Image.alpha_composite(base, cropped)
    return base.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")


logo = load_rgba(src_logo)
fav = logo

fit_square(logo, 1024).save(out / "logo_1024.png", optimize=True)
fit_square(logo, 1024).save(out / "logo.png", optimize=True)
fit_square(logo, 512).save(out / "logo_512.png", optimize=True)
fit_square(logo, 1024).save(out / "app_icon.png", optimize=True)


def fav_size(n: int) -> Image.Image:
    return fit_square(fav, n, bg=(10, 10, 10, 255))


for n, name in [
    (16, "favicon-16.png"),
    (32, "favicon-32.png"),
    (48, "favicon-48.png"),
    (64, "favicon-64.png"),
]:
    fav_size(n).save(out / name, optimize=True)

fav_size(32).save(out / "favicon.png", optimize=True)

icons = [fav_size(16), fav_size(32), fav_size(48)]
icons[0].save(
    out / "favicon.ico",
    format="ICO",
    sizes=[(16, 16), (32, 32), (48, 48)],
    append_images=icons[1:],
)

android_sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
res = Path(r"C:\repo\RollingAlarm\android\app\src\main\res")
for folder, size in android_sizes.items():
    dest = res / folder / "ic_launcher.png"
    fit_square(logo, size).save(dest, optimize=True)
    print(f"wrote {dest} ({size})")

print("branding files:")
for p in sorted(out.iterdir()):
    print(f"  {p.name:20} {p.stat().st_size:8d}")
