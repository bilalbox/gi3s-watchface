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
- **Weekday** — `SUN` / `MON` / … in `FONT_XTINY`, under the porthole, vertically aligned with the minutes row
- **Hijri offset** — configurable ±2 days (Settings → Hijri date shift)

### Weather (upper-left)

- 24×24 **1-bit PNG sprites** (sun / cloud / rain / storm) + temperature in °C
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
| `ClockDigits` | Source Code Pro Bold per-digit bitmap renderer for stacked time |
| `HijriHelpers` | Hijri calendar + date label helpers |
| `TimeHelpers` | Hour/minute formatting for stacked time |

Clock digit sprites (`digit_0.png` … `digit_9.png`, 28×40) regenerate via [`scripts/generate-clock-digits.ps1`](scripts/generate-clock-digits.ps1) using [Source Code Pro Bold](https://fonts.google.com/specimen/Source+Code+Pro) (SIL OFL).

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
