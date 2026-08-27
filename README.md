# My Watch Face for Garmin Instinct 3 Solar 45mm

An Arabic-only Connect IQ watch face for the **Garmin Instinct 3 Solar 45mm**: stacked Noto Kufi Arabic-Indic time, dual calendar (Hijri + Gregorian) without years, weekday, temperature in °م, and an activity porthole.

> **Note:** Source is intentionally monolithic in a single `MyWatchFace.mc` file for easy sharing and review.

## Layout

```
┌─────────────────────────────────────┐
│                         ╭─  ٨٠  ─╮ │
│   ١٤                    │  ١٢٣٤  │ │
│   ٣٥                    ٢٣°م     │
│                                     │
│            الخميس                   │
│         جمادى الآخرة  ١٥            │
│            أغسطس  ٢٧                │
│▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░│ battery
└─────────────────────────────────────┘
```

Porthole legend is position (HR top, steps below). Date rows are month + day, day on the right.

## Features

### Time

- **Stacked 24 h** — `HH` over `MM` (no colon)
- **Noto Kufi Arabic-Indic digits** — proportional ٠–٩ sprites, dark + light
- Positioned upper-left toward center (clears the porthole)

### Weekday

- Full Arabic name, centered (`الأحد` … `السبت`)
- Sunrise/sunset are not shown

### Dates

- **Hijri** — full month name + day (no year)
- **Gregorian** — `يناير`…`ديسمبر` + day (no year)
- **Hijri offset** — configurable ±2 days (Settings → Hijri date shift)
- **Color theme** — dark (default) or light

### Temperature

- Arabic-Indic digits + `°م` under the porthole
- Missing data draws `--°م`
- Weather condition icons are not shown

### Activity porthole (upper-right)

- **Heart rate** (top) and **steps** (below), numbers only
- Missing HR draws `--`

### Battery bar

- 4 px bar at the bottom, proportional fill
- Body Battery bar on the left edge

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
| `ClockDigits` | Large proportional Arabic-Indic time digits |
| `SmallDigits` | Small digits, minus, degree, `م` for dates / porthole / temp |
| `ArabicLabels` | Current Hijri month, Gregorian month, and weekday bitmaps |
| `HijriHelpers` | Tabular Hijri conversion |
| `TimeHelpers` | Hour/minute formatting for stacked time |

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
