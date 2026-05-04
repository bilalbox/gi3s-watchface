# My Watch Face for Garmin Instinct 3 Solar 45mm

A data-heavy Connect IQ watch face designed for the **Garmin Instinct 3 Solar 45mm** featuring Hijri date support, comprehensive activity metrics, weather information, and solar event tracking.

> **Note:** This project's source code is intentionally kept monolithic in a single `MyWatchFace.mc` file to facilitate easy sharing and analysis within LLM chat contexts. All modules, classes, and logic reside in this one file.

## Features

### Date Display

- **Hijri date**: Day, 3-letter month abbreviation, and 2-digit year (e.g., `26 SHA 29`)
- **Gregorian date**: Weekday (2-letter abbreviation), day, and 3-letter month (e.g., `SU 26 APR`)
- **Hijri adjustment**: Configurable ±2 day offset to align tabular Hijri calculations with local moon sighting

### Time Display

- 24-hour format (`HH:mm`) using large Thai Hot numeric font
- Updates once per minute (no per-second partial updates for power efficiency)

### Heart Rate

- Displays average heart rate from the last 60 seconds of history
- Falls back to live HR or SensorHistory if history is unavailable
- Shows `--` BPM when no valid reading is available

### Activity Metrics

| Position | Metric | Format |
|----------|--------|--------|
| Top-left | Steps | `NNNN STP` |
| Top-right | Distance | `X.XX KM` |
| Middle-left | Calories | `NNN CAL` |
| Middle-right | Heart Rate | `NNN BPM` |
| Bottom-left | Battery | `NN%` |
| Bottom-right | Floors | `NN FL` |

### Weather

- Current condition (5-character label) and temperature in °C
- Updates every 15 minutes when available

### Solar Porthole (Top-right Circular Window)

Displays time until or since the next/previous solar event:

- **Events tracked**: Midnight, Sunrise, Noon, Sunset
- **Display format**: Hours until/until event (negative when within 1 hour past)
- **Example**: `-0.5` with label `SUNR` means 30 minutes past sunrise

## Hijri Date Adjustment

The tabular Hijri calendar may not match local moon sightings. A ±2 day adjustment is available:

1. **On-watch**: Settings → Hijri date shift → Select -2, -1, 0, +1, or +2 days
2. **Garmin Connect/Express**: Set the numeric property in the watch face settings

## Technical Details

### File Structure

```
my-gi3s-watchface/
├── source/
│   └── MyWatchFace.mc    # Single monolithic source file
├── resources/
│   ├── Strings.xml       # App strings and settings
│   └── Drawables.xml     # Drawable resources
├── manifest.xml          # App manifest and permissions
└── monkey.jungle         # Build configuration
```

### Modules in MyWatchFace.mc

| Module | Purpose |
|--------|---------|
| `HijriHelpers` | Gregorian↔Julian day conversion, Hijri date calculation |
| `TimeHelpers` | Time formatting utilities |

### Classes in MyWatchFace.mc

| Class | Purpose |
|-------|---------|
| `HijriOffsetSettingsMenu` | Settings menu for Hijri offset selection |
| `HijriOffsetMenuDelegate` | Handles menu selection and saves offset |
| `MyProjectApp` | Application entry point |
| `MyWatchFace` | Main watch face view with all drawing logic |

### Permissions Required

- `UserProfile` - For user-specific data
- `positioning` - For weather location data
- `SensorHistory` - For heart rate history access

## Building

### Prerequisites

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/connect-iq-basics/getting-started/)
2. Place your `developer_key.der` in the project root

### Build Command

```shell
monkeyc -o watchface.prg -d instinct3solar45mm -y developer_key.der -f monkey.jungle
```

### Emulator Testing

```shell
connectiq
monkeydo watchface.prg instinct3solar45mm
```

## Installation

1. Connect your Instinct 3 Solar 45mm via USB
2. Copy `watchface.prg` to `GARMIN/APPS/` on the device
3. Select the watch face from the watch's settings menu

## Screenshot

![Watch face preview](watchface_preview.png)
