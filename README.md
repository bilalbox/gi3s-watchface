# My Watch Face for Garmin Instinct 3 Solar 45mm

A Connect IQ watch face for the **Garmin Instinct 3 Solar 45mm** with stacked custom time digits, dual-calendar dates, weather, and a live activity porthole.

> **Note:** Source is intentionally monolithic in a single `MyWatchFace.mc` file for easy sharing and review.

## Layout

```
┌─────────────────────────────────────┐
│ [weather] 12°C          ╭─ steps ─╮ │
│                         │    0s     │ │
│   HH                    ╰─  HR ────╯ │
│   MM              SUN               │
│                                     │
│        15 DHU HIJ 1447              │
│        31 MAY 2026                  │
│▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░│ battery
└─────────────────────────────────────┘
```

## Features

### Time

- **Stacked 24 h** — `HH` over `MM` (no colon)
- **Custom poly-path digits** — block outlines, 4 px stroke, slashed zero (2 px slash)
- Positioned upper-left toward center; minutes row aligned with weekday label

### Dates

- **Hijri** — `DD MONTHNAME YYYY` (e.g. `15 DHU HIJ 1447`)
- **Gregorian** — `DD MMM YYYY` (e.g. `31 MAY 2026`)
- **Weekday** — `SUN` / `MON` / … in `FONT_XTINY`, under the porthole, vertically aligned with the minutes row
- **Hijri offset** — configurable ±2 days (Settings → Hijri date shift)

### Weather (upper-left)

- 24×24 **1-bit PNG sprites** (sun / cloud / rain / storm) + temperature in °C
- Refreshed at most every **15 minutes**

### Activity porthole (upper-right)

- **Heart rate** — heart icon + value (upper porthole, partial updates every **5 seconds**)
- **Steps** — 12×12 shoeprint icon + count (porthole vertical center, 1 Hz partial updates)
- Only the 64×64 px clip region is redrawn at 1 Hz; the rest of the face updates once per minute

### Battery bar

- 4 px bar at the bottom, proportional fill

## Power efficiency

| Mechanism | Detail |
|-----------|--------|
| Minute tick | `Timer` fires every 60 s for time, dates, weather, and full redraw |
| Partial updates | Clipped to porthole only (~64×64 px), not the full 176×176 screen |
| HR throttling | HR history queried every 5 s in partial updates, not every frame |
| Cached weather | `Weather.getCurrentConditions()` at most every 15 min |
| Cached battery | `System.getSystemStats()` at most every 5 min |
| No background service | `Background` permission removed — no wake-ups when face is inactive |
| Draw from cache | Full `onUpdate` reads cached values; sensor APIs not called per redraw |

## Modules

| Module | Purpose |
|--------|---------|
| `PolyTimeDigits` | Block-outline poly-path digit renderer |
| `HijriHelpers` | Hijri calendar + date label helpers |
| `TimeHelpers` | Hour/minute formatting for stacked time |

Weather icons are 24×24 PNGs in [`resources/images/`](resources/images/) (regenerate via [`scripts/generate-weather-icons.ps1`](scripts/generate-weather-icons.ps1)).

Porthole metric icons (`icon_heart.png` 10×10, `icon_steps.png` 12×12) regenerate via [`scripts/generate-porthole-icons.ps1`](scripts/generate-porthole-icons.ps1).

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
