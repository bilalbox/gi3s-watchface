# Instinct 3 Solar Arabic watch face (gi3s)

An Arabic-only Connect IQ watch face for the **Garmin Instinct 3 Solar 45mm**: stacked Noto Kufi Arabic-Indic time, dual calendar (Hijri + Gregorian) without years, weekday, temperature in م°, and an activity porthole.

> **Note:** Source is intentionally monolithic in a single `MyWatchFace.mc` file for easy sharing and review.

Garmin `developer_key.pem` / `.der` stay local (gitignored). Never force-add them.

## Layout

```
┌─────────────────────────────────────┐
│                         ╭─  ٩٠  ─╮ │
│ ▌ ١٩                    │ ٧٤٣٦  │ │
│ ▌ ١٨                    م°٢٧     │
│ ▌                                   │
│ ▌          الخميس                   │
│ ▌       ربيع الأول  ١٤              │
│ ▌          أغسطس  ٢٧                │
│         ▓▓▓▓▓▓░░░░░░░               │ battery
└─────────────────────────────────────┘
   └ body battery
```

Porthole legend is position (HR top, steps below). Date rows are month + day, day
on the right, with both rows sharing one right seam.

The display is a 176×176 **semi-octagon**, not a circle — the corners are rounded
chamfers, so the usable span narrows sharply top and bottom. Both bars are inset to
the panel's actually-visible span rather than drawn edge to edge; drawn full width
they would be invisible below ~20 % and saturated above ~78 %.

## Features

### Time

- **Stacked 24 h** — `HH` over `MM` (no colon)
- **Noto Kufi Arabic-Indic digits** — *tabular* ٠–٩ sprites, dark + light
- Both rows share one 62 px width, so the hour and minute always align. With
  proportional sprites (٠–٩ ran 9–30 px) the two independently-centred rows sat up
  to 21 px apart at times like 11:33.
- Positioned upper-left toward center (clears the porthole)

### Weekday

- Full Arabic name, centered (`الأحد` … `السبت`)
- Sunrise/sunset are not shown

### Dates

- **Hijri** — full month name + day (no year)
- **Gregorian** — `يناير`…`ديسمبر` + day (no year), rendered ~12 % smaller than
  Hijri so the two calendars read as a hierarchy
- **Hijri offset** — configurable ±2 days (Settings → Hijri date shift)
- **Color theme** — dark (default) or light

### Temperature

- Unit then number: the logical `°م` reverses in an RTL run, so it paints as `م°`
  at the left with the number to its right — `م°٢٧`. Centred on the porthole axis.
- Rounded, not truncated: −0.6 °C reads `-1`
- A negative keeps its sign with the number as one LTR block: `م°-٤٠`
- Missing data draws `م°--`
- Weather condition icons are not shown

### Activity porthole (upper-right)

- **Heart rate** (top, `xs` tier) and **steps** (below, `md` tier), numbers only
- Steps stay exact at every value: past 9999 the row drops to the `xs` tier so five
  digits still clear the circle
- Missing HR draws `--`
- Geometry comes from `WatchUi.getSubscreen()`, not a hardcoded centre

### Battery bar

- 4 px bar at the bottom, proportional fill across the visible span (x 40–135)
- Body Battery bar on the left edge, spanning its visible run (y 36–139)

## Power efficiency

All UI updates run on a **single 60-second timer**.

| Mechanism | Detail |
|-----------|--------|
| Minute tick | `Timer` every 60 s; refreshes steps, HR, dates, weather cache, then full redraw |
| Cached weather | `Weather.getCurrentConditions()` at most every 15 min |
| Cached battery | `System.getSystemStats()` at most every 5 min |
| No background service | No `Background` permission |
| No partial updates | Full 176×176 redraw once per minute only |

## Modules

| Module | Purpose |
|--------|---------|
| `Theme` | `colorMode` property, palette, dark/light resource selection |
| `GlyphSet` | One tabular sprite tier: uniform digit cells, optional symbols |
| `Glyphs` | The four tiers, plus the stacked-time helper |
| `ArabicLabels` | Current Hijri month, Gregorian month, and weekday bitmaps |
| `HijriHelpers` | Tabular Hijri conversion |
| `TimeHelpers` | Hour/minute formatting for stacked time |

### Sprite tiers

Cell sizes are **derived** by the generator from the widest ink it actually renders,
never hardcoded, so changing the font or a target height stays correct.

| Tier | Cell | Used by |
|------|------|---------|
| `digit_` | 30×37 | Stacked clock |
| `sm_` | 14×17 | Hijri day |
| `md_` | 11×13 | Steps (≤ 9999), temperature (+ `-`, `°`, `م`) |
| `xs_` | 9×11 | Heart rate, Gregorian day, steps (≥ 10000) |

Sprites regenerate via [`scripts/generate-arabic-assets.ps1`](scripts/generate-arabic-assets.ps1) from [Noto Kufi Arabic Bold](https://fonts.google.com/noto/specimen/Noto+Kufi+Arabic) (OFL).

## Settings

| Where | What |
|-------|------|
| On watch | Long-press **UP** → Customize → **Watch face settings** → Hijri date shift or Color theme |
| Garmin Connect / Express | App settings: Hijri date adjustment, Color theme (dark / light) |

Settings menus stay **English**. Default theme is **dark**.

## Permissions

| Permission | Used for |
|------------|----------|
| `UserProfile` | User profile data |
| `positioning` | Weather location |
| `SensorHistory` | Heart rate history fallback |

## Building

### Prerequisites

1. [Connect IQ SDK](https://developer.garmin.com/connect-iq/connect-iq-basics/getting-started/)
2. `developer_key.der` in the project root

### Assets

```shell
powershell -ExecutionPolicy Bypass -File scripts/generate-arabic-assets.ps1
```

### Build

```shell
monkeyc -o watchface.prg -d instinct3solar45mm -y developer_key.der -f monkey.jungle
```

### Simulator

```shell
connectiq
monkeydo watchface.prg instinct3solar45mm
```

## Installation

1. Connect the watch via USB
2. Copy `watchface.prg` to `GARMIN/APPS/`
3. Select the watch face in watch settings

## Screenshot

![Watch face preview](watchface_preview.png)

## License

MIT — see [LICENSE](LICENSE).
