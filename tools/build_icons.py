"""
앱 아이콘/스플래시용 PNG 생성기.

원본 `assets/icons/pharm_tally_app_icon.original.png` 의 흰 배경을 투명
처리한 뒤 실제 그림 영역만 잘라내어 정사각형 캔버스 위에 비율별로
다시 배치한다.

1. 런처 아이콘용 표준 PNG       (그림이 캔버스의 약 94% 차지)
   - 안드로이드 11 이하·iOS·Windows 의 일반 아이콘으로 사용.
2. 어댑티브 아이콘 foreground   (그림이 캔버스의 약 78% 차지)
   - 안드로이드 12+ 어댑티브 아이콘 시스템 마스크(원형/스쿼클) 안에서
     "흰 배경에 그림이 가득 찬" 느낌으로 보이게.
3. 스플래시 이미지              (정사각형 캔버스 전체 흰 배경 + 가운데
   아이콘 + 그 아래 'Developed by HSM of Orc Holdings' 텍스트)
   - flutter_native_splash 와 BrandSplash 위젯이 시각적으로 동일해
     보이도록, 네이티브 스플래시에서도 텍스트가 미리 합성된 이미지를
     사용한다. 안드로이드 12+ 의 원형 마스크에서는 텍스트가 잘릴 수
     있지만, main() 의 비동기 최적화 덕에 네이티브 스플래시는 매우 짧게
     보이고 곧바로 Dart 스플래시(BrandSplash) 로 자연스럽게 이어진다.

모든 출력은 1024x1024 PNG. flutter_launcher_icons / flutter_native_splash
가 알아서 mipmap 해상도별로 다시 리사이즈한다.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent.parent
ICONS_DIR = ROOT / "assets" / "icons"
# 최초 1회 백업된 원본을 입력으로 사용. 백업이 없으면 현재 파일을 백업한다.
SRC_ORIGINAL = ICONS_DIR / "pharm_tally_app_icon.original.png"
SRC_CURRENT = ICONS_DIR / "pharm_tally_app_icon.png"
OUT_DIR = ICONS_DIR

# 결과 캔버스 크기.
SIZE = 1024


def _whiten_to_transparent(img: Image.Image, near_white: int = 245) -> Image.Image:
    """배경의 흰색을 투명으로 바꿔서 다음 단계의 bbox 계산이 가능하게 한다.

    원본 PNG 는 알파가 전부 255 인 "흰 배경 + 그림" 구조라서 그대로는
    여백을 자를 수 없다. RGB 각 채널이 모두 [near_white] 이상인 픽셀을
    투명 픽셀로 변환한다.
    """
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if r >= near_white and g >= near_white and b >= near_white:
                px[x, y] = (255, 255, 255, 0)
    return img


def _trim_alpha(img: Image.Image, threshold: int = 16) -> Image.Image:
    """알파 채널을 보고 실제 그림이 차지하는 사각형만 잘라낸다.

    안티앨리어싱으로 가장자리에 알파값이 1~2 수준으로 깔린 픽셀이 있으면
    `getbbox` 가 전체 캔버스를 돌려준다. 그래서 먼저 알파를 [threshold]
    로 잘라낸 뒤 bbox 를 구한다.
    """
    img = img.convert("RGBA")
    alpha = img.split()[-1]
    visible = alpha.point(lambda v: 255 if v >= threshold else 0)
    bbox = visible.getbbox()
    if bbox is None:
        return img
    return img.crop(bbox)


def _fit_into_square(content: Image.Image, fill_ratio: float) -> Image.Image:
    """투명 정사각형 캔버스에 [content] 를 비율 [fill_ratio] 만큼 차지하도록 배치."""
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    target = int(SIZE * fill_ratio)
    w, h = content.size
    scale = target / max(w, h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    resized = content.resize((nw, nh), Image.LANCZOS)
    x = (SIZE - nw) // 2
    y = (SIZE - nh) // 2
    canvas.paste(resized, (x, y), resized)
    return canvas


def _load_font(pt: int) -> ImageFont.ImageFont:
    """윈도우 기본 폰트 중 하나를 사용. 없으면 PIL 기본 폰트로 폴백."""
    candidates = [
        r"C:\Windows\Fonts\segoeuib.ttf",  # Segoe UI Bold
        r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\arial.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, pt)
            except Exception:
                continue
    return ImageFont.load_default()


def _make_splash_icon_only(trimmed: Image.Image) -> Image.Image:
    """흰 배경 + 가운데 아이콘만 있는 스플래시 이미지. 텍스트 없음.

    안드로이드 12+ 의 windowSplashScreenIcon 은 시스템이 자동으로 원형/스
    쿼클 마스크를 씌운다. 마스크의 안전영역은 240dp 캔버스 중 가운데
    ~30% (약 72dp). 마스크에 그림이 잘리지 않게 splash 이미지의 아이콘을
    캔버스의 **55%** 이하로 작게 둬서, 시스템 마스크 안에 통째로 들어가게
    한다. (시스템이 표시하는 실제 아이콘 크기는 240dp · 0.55 ≈ 132dp.)
    Dart 의 BrandSplash 도 같은 132dp 로 그려져 두 화면의 아이콘이 같은
    위치·같은 크기로 보이게 된다.
    """
    canvas = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    target = int(SIZE * 0.55)
    w, h = trimmed.size
    scale = target / max(w, h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    icon = trimmed.resize((nw, nh), Image.LANCZOS)
    x = (SIZE - nw) // 2
    y = (SIZE - nh) // 2
    canvas.paste(icon, (x, y), icon)
    return canvas


def _make_splash(trimmed: Image.Image, tagline: str) -> Image.Image:
    """흰 배경 + 가운데 아이콘 + 그 아래 태그라인 텍스트의 스플래시 이미지."""
    canvas = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))

    # 아이콘: 캔버스의 48% 차지하도록 가운데에서 약간 위에 배치.
    target = int(SIZE * 0.48)
    w, h = trimmed.size
    scale = target / max(w, h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    icon = trimmed.resize((nw, nh), Image.LANCZOS)
    icon_x = (SIZE - nw) // 2
    icon_y = (SIZE - nh) // 2 - int(SIZE * 0.04)
    canvas.paste(icon, (icon_x, icon_y), icon)

    # 텍스트: 아이콘 하단으로부터 6% 아래 간격.
    draw = ImageDraw.Draw(canvas)
    font = _load_font(int(SIZE * 0.038))
    bbox = draw.textbbox((0, 0), tagline, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    text_x = (SIZE - text_w) // 2
    text_y = icon_y + nh + int(SIZE * 0.05)
    # 아주 길어서 캔버스 밖으로 나가면 마지막 줄을 줄여서 안 잘리게.
    if text_x < 0 or text_y + text_h > SIZE:
        font = _load_font(int(SIZE * 0.030))
        bbox = draw.textbbox((0, 0), tagline, font=font)
        text_w = bbox[2] - bbox[0]
        text_h = bbox[3] - bbox[1]
        text_x = (SIZE - text_w) // 2
    draw.text((text_x, text_y), tagline, fill=(80, 80, 80, 255), font=font)
    return canvas


def main() -> None:
    if SRC_ORIGINAL.exists():
        src = SRC_ORIGINAL
    elif SRC_CURRENT.exists():
        # 백업이 없는 경우(스크립트 최초 실행 직전에 사람이 이미지를 교체한
        # 상황 등): 현재 파일을 백업으로 복사해 두고 그걸 입력으로 사용한다.
        import shutil

        shutil.copyfile(SRC_CURRENT, SRC_ORIGINAL)
        src = SRC_ORIGINAL
    else:
        raise SystemExit(f"원본 이미지 없음: {SRC_CURRENT}")

    original = Image.open(src)
    transparent = _whiten_to_transparent(original)
    trimmed = _trim_alpha(transparent)
    print(
        f"원본 {original.size} → 트리밍 후 {trimmed.size} "
        f"(흰 배경 제거 + 여백 잘라내어 그림만 추출)"
    )

    # 1) 런처용: 캔버스의 94% 차지 → iOS·Windows·구버전 안드로이드에서 가득 차게.
    launcher = _fit_into_square(trimmed, 0.94)
    launcher_path = OUT_DIR / "pharm_tally_app_icon.png"
    launcher.save(launcher_path, "PNG")
    print(f"→ {launcher_path}")

    # 2) 어댑티브 foreground: 캔버스의 78% 차지 → 안드로이드 12+ 의 스쿼클
    #    마스크에서 흰 배경 안에 그림이 가득 차 보이게.
    fg = _fit_into_square(trimmed, 0.78)
    fg_path = OUT_DIR / "pharm_tally_app_icon_foreground.png"
    fg.save(fg_path, "PNG")
    print(f"→ {fg_path}")

    # 3) 스플래시: 흰 배경 + 가운데 아이콘만 (텍스트는 Dart 의 BrandSplash 가
    #    표시한다). 네이티브 스플래시에 텍스트를 합성해 두면 안드로이드 12+
    #    시스템 마스크와 Dart 스플래시 텍스트가 별도로 그려지면서 "글자가
    #    작아졌다 커졌다" 두 번 보이는 현상이 생긴다. 텍스트는 Dart 한 곳에서만
    #    그려서 그 점프를 없앤다.
    splash = _make_splash_icon_only(trimmed)
    splash_path = OUT_DIR / "pharm_tally_splash.png"
    splash.save(splash_path, "PNG")
    print(f"→ {splash_path}")


if __name__ == "__main__":
    main()
