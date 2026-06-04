# My Watch Face for Garmin Instinct 3 Solar 45mm

A Connect IQ watch face for the **Garmin Instinct 3 Solar 45mm** with stacked Source Code Pro Bold time digits, dual-calendar dates, weather, and an activity porthole.

> **Note:** Source is intentionally monolithic in a single `MyWatchFace.mc` file for easy sharing and review.

## Layout

```
┌─────────────────────────────────────┐
│ [weather] 12°C          ╭─ ♥ 80 ─╮ │
│                         │ 👣 1234 │ │
│   HH              SUN               │
│   MM                                │
│                                     │
│        15 DHU HIJ 1447              │
│        31 MAY 2026                  │
│▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░│ battery
└─────────────────────────────────────┘
```

## Features

### Time

- **Stacked 24 h** — `HH` over `MM` (no colon)
- **Source Code Pro Bold bitmap digits** — 10 per-digit 28×40 sprites (binarized for MIP)
- Positioned upper-left toward center; minutes row aligned with weekday label

### Dates

- **Hijri** — `DD MONTHNAME YYYY` (e.g. `15 DHU HIJ 1447`)
- **Gregorian** — `DD MMM YYYY` (e.g. `31 MAY 2026`)
- **Weekday** — `SUN` / `MON` / `THU` / … as Black Ops One bitmaps (24 px font, auto-sized cell), under the porthole, aligned with the minutes row
- **Hijri offset** — configurable ±2 days (Settings → Hijri date shift)
- **Color theme** — dark (default) or light background with matching text and bitmap ink

### Weather (upper-left)

- 24×24 **1-bit PNG sprites** (7 categories: clear, partly cloudy, cloudy, wind, rain, storm, snow) + temperature in °C
- Hand-drawn pixel icons tuned for MIP readability; Garmin condition codes map to 7 buckets (fog → cloudy, wintry mix → snow, etc.)
- Refreshed at most every **15 minutes**

### Activity porthole (upper-right)

- **Heart rate** — heart icon + value (upper porthole)
- **Steps** — shoeprint icon + count (porthole vertical center)
- Updated on the same **once-per-minute** tick as the rest of the face

### Battery bar

- 4 px bar at the bottom, proportional fill

## Power efficiency

All UI updates run on a **single 60-second timer** — no sub-minute partial redraws.

| Mechanism | Detail |
|-----------|--------|
| Minute tick | `Timer` fires every 60 s; refreshes steps, HR, dates, weather cache, then full redraw |
| Cached weather | `Weather.getCurrentConditions()` at most every 15 min |
| Cached battery | `System.getSystemStats()` at most every 5 min |
| No background service | No `Background` permission — no wake-ups when face is inactive |
| No partial updates | Full 176×176 redraw once per minute only |

## Modules

| Module | Purpose |
|--------|---------|
| `Theme` | `colorMode` property, palette colors, dark/light resource selection |
| `ClockDigits` | Black Ops One per-digit bitmap renderer for stacked time |
| `WeekdaySprites` | Black Ops One 3-letter weekday bitmaps (Garmin DOW 1–7) |
| `HijriHelpers` | Hijri calendar + date label helpers |
| `TimeHelpers` | Hour/minute formatting for stacked time |

Clock digit sprites (`digit_0.png` … `digit_9.png`, 36×48, plus `*_light.png` for light theme) regenerate via [`scripts/generate-clock-digits.ps1`](scripts/generate-clock-digits.ps1) using [Black Ops One](https://fonts.google.com/specimen/Black+Ops+One) (OFL).

Weekday sprites (`weekday_sun.png` … `weekday_sat.png`, plus `*_light.png`) regenerate via [`scripts/generate-weekday-sprites.ps1`](scripts/generate-weekday-sprites.ps1) (same font, 24 px, 3-letter labels; cell width fits `WED`/`MON`).

Weather icons are 24×24 hand-drawn PNGs in [`resources/images/`](resources/images/) (regenerate via [`scripts/generate-weather-icons.ps1`](scripts/generate-weather-icons.ps1); each icon has a `_light` variant).

Porthole metric icons (`icon_heart.png` 10×10, `icon_steps.png` 12×12, plus `_light` variants) regenerate via [`scripts/generate-porthole-icons.ps1`](scripts/generate-porthole-icons.ps1).

## Settings

| Where | What |
|-------|------|
| On watch | Long-press **UP** → Customize → **Watch face settings** → Hijri date shift or Color theme |
| Garmin Connect / Express | App settings: Hijri date adjustment, Color theme (dark / light list) |

Default theme is **dark** (unchanged look for existing installs).

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
