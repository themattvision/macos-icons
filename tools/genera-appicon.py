#!/usr/bin/env python3
"""
Genera l'AppIcon di MacOS Icons componendo gli stessi strati del logo di
macosicons.com (base, quadrato, occhi, bocca) con la geometria dell'icona
ufficiale del sito.

Le percentuali sono relative al lato della base. Il CSS del componente
`.app-logo` di macosicons.com da' i valori di partenza:

    .square { height: 90%; left: 50%; top: 50%; translate: -50% -50% }
    .eye    { height: 18%; top: 18% }   .eye-right { left: 31% }  .eye-left { left: 60% }
    .mouth  { height: 18%; top: 50%; left: 38%; transform: translate(-50%) }

Due avvertenze, entrambe verificate sui pixel della favicon del sito (che e'
l'icona vera e propria, non il logo della pagina):

1. La bocca NON e' centrata sul 38%. Il `translate(-50%)` del CSS viene
   riscritto inline dallo script del parallasse e non ha mai effetto, quindi il
   38% e' il BORDO SINISTRO. Le due letture spostano la bocca di quasi il 18%
   del lato: e' l'errore per cui la faccia sembrava storta.
2. Nell'icona la faccia sta piu' in basso che nel logo della pagina. I valori
   qui sotto sono il risultato di un fit dei sei parametri sui pixel della
   favicon (errore quadratico medio da 1475 a 408).
"""

from pathlib import Path

from PIL import Image, ImageFilter

# MARK: - Percorsi

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "MacOS Icons" / "Assets.xcassets"
APPICON = ASSETS / "AppIcon.appiconset"

LAYERS = {
    "base": ASSETS / "logo-base.imageset" / "logo-base.png",
    "square": ASSETS / "logo-square.imageset" / "logo-square.png",
    "eye": ASSETS / "logo-eye.imageset" / "logo-eye.png",
    "mouth": ASSETS / "logo-mouth.imageset" / "logo-mouth.png",
}

# MARK: - Geometria (frazioni del lato della base)

CANVAS = 1024
CONTENT = 824               # lato della base nella griglia macOS
ORIGIN = (CANVAS - CONTENT) // 2

SQUARE_HEIGHT = 0.90
FEATURE_HEIGHT = 0.1775     # occhi e bocca hanno la stessa altezza
EYE_TOP = 0.2800
EYE_LEFTS = (0.2925, 0.6125)
MOUTH_TOP = 0.5575
MOUTH_LEFT = 0.3925         # bordo sinistro, non centro

# Ombra proiettata, in frazioni del lato della base.
SHADOW_BLUR = 0.028
SHADOW_OFFSET_Y = 0.015
SHADOW_OPACITY = 0.30

# Dimensioni richieste da AppIcon.appiconset: (lato, nome file).
EXPORTS = [
    (16, "icon_16x16@1x.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32@1x.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128@1x.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256@1x.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512@1x.png"), (1024, "icon_512x512@2x.png"),
]


# MARK: - Strati

def load(name: str) -> Image.Image:
    return Image.open(LAYERS[name]).convert("RGBA")


def scaled(image: Image.Image, height: int) -> Image.Image:
    """Ingrandisce mantenendo le proporzioni, con l'altezza come vincolo."""
    width = round(height * image.width / image.height)
    return image.resize((width, height), Image.LANCZOS)


def crisped(image: Image.Image) -> Image.Image:
    """Rialza il contrasto dell'alpha: gli strati neri (occhi, bocca) partono da
    bitmap di 24-86 px e l'ingrandimento ne sfoca il bordo."""
    alpha = image.getchannel("A").point(lambda v: max(0, min(255, round((v - 128) * 2.2 + 128))))
    out = image.copy()
    out.putalpha(alpha)
    return out


def paste(canvas: Image.Image, layer: Image.Image, left: float, top: float) -> None:
    canvas.alpha_composite(layer, (round(ORIGIN + left), round(ORIGIN + top)))


# MARK: - Composizione

def build() -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    base = scaled(load("base"), CONTENT)

    # Ombra: la silhouette della base, sfocata e spostata verso il basso.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    tint = Image.new("RGBA", base.size, (10, 26, 51, 255))
    tint.putalpha(base.getchannel("A"))
    shadow.alpha_composite(tint, (ORIGIN, ORIGIN + round(CONTENT * SHADOW_OFFSET_Y)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(CONTENT * SHADOW_BLUR))
    shadow.putalpha(shadow.getchannel("A").point(lambda v: round(v * SHADOW_OPACITY)))
    canvas.alpha_composite(shadow)

    paste(canvas, base, 0, 0)

    side = round(CONTENT * SQUARE_HEIGHT)
    square = scaled(load("square"), side)
    paste(canvas, square, (CONTENT - square.width) / 2, (CONTENT - side) / 2)

    feature = round(CONTENT * FEATURE_HEIGHT)

    mouth = crisped(scaled(load("mouth"), feature))
    paste(canvas, mouth, CONTENT * MOUTH_LEFT, CONTENT * MOUTH_TOP)

    eye = crisped(scaled(load("eye"), feature))
    for left in EYE_LEFTS:
        paste(canvas, eye, CONTENT * left, CONTENT * EYE_TOP)

    return canvas


def main() -> None:
    icon = build()
    for side, name in EXPORTS:
        out = icon if side == CANVAS else icon.resize((side, side), Image.LANCZOS)
        out.save(APPICON / name)
        print(f"  {name}  {side}x{side}")
    print(f"Scritte {len(EXPORTS)} dimensioni in {APPICON}")


if __name__ == "__main__":
    main()
