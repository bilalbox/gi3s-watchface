// ─────────────────────────────────────────────────────────────────────────────
// MyWatchFace.mc  –  Garmin Instinct 2X / 3 Solar Optimized
//
// Layout (top → bottom):
//   Upper-left    │  [16x16 Icon] + temperature (y≈2) inline using Lucide vectors
//   Porthole ring │  cx=143 cy=32 r=30  →  steps (top, 1Hz)  ·  HR (bottom, 1Hz)
//   ─────────────────────────────────────────────────────────────────────────
//   TIME          │  centered, FONT_NUMBER_THAI_HOT, cy≈82
//   Hijri date    │  "DD MONTHNAME YYYY"  (month ≤ 7 chars)  centered
//   Gregorian     │  "EEE YYYYMMDD"  centered
//   Solar event   │  label (SUNR / SUNS / NOON / MIDN)  centered
//                 │  clock time of that event  centered
//   ─────────────────────────────────────────────────────────────────────────
//   Battery bar   │  4 px tall · fills from left · proportional to battery %
// ─────────────────────────────────────────────────────────────────────────────

import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Time.Gregorian;
import Toybox.Lang;
import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.SensorHistory;
import Toybox.Timer;
import Toybox.Math;
using Toybox.Time;

// ─────────────────────────────────────────────────────────────────────────────
// Lucide-Inspired 16x16 Vector Weather Icons
// ─────────────────────────────────────────────────────────────────────────────
module MiniVectorIcons {

    // Lucide "Sun" re-mapped to a 16x16 canvas grid (Center anchor at 8,8)
    function drawSun(dc, x, y) {
        dc.setPenWidth(1);
        dc.drawCircle(x + 8, y + 8, 4); // Sun center ring

        // Cardinal rays
        dc.drawLine(x + 8, y,      x + 8, y + 2);  // Top
        dc.drawLine(x + 8, y + 14, x + 8, y + 16); // Bottom
        dc.drawLine(x,     y + 8,  x + 2, y + 8);  // Left
        dc.drawLine(x + 14, y + 8,  x + 16, y + 8); // Right

        // Intercardinal rays
        dc.drawLine(x + 3, y + 3,  x + 5, y + 5);  // Top-Left
        dc.drawLine(x + 13, y + 3, x + 11, y + 5); // Top-Right
        dc.drawLine(x + 3, y + 13, x + 5, y + 11); // Bottom-Left
        dc.drawLine(x + 13, y + 13, x + 11, y + 11); // Bottom-Right
    }

    // Lucide "Cloud" compound path structured for a 16x16 viewport
    function drawCloud(dc, x, y) {
        dc.setPenWidth(1);
        // Build the cloud perimeter using larger circular paths
        dc.drawCircle(x + 4, y + 10, 3);
        dc.drawCircle(x + 8, y + 6,  4);
        dc.drawCircle(x + 12, y + 9, 3);

        // Punch out internal overlapping pixels to retain outline styling
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 3, y + 8, 9, 6);
        dc.fillRectangle(x + 6, y + 5, 5, 5);

        // Draw standard flat structural boundary foundation baseline
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x + 4, y + 13, x + 12, y + 13);
    }

    // Lucide "CloudRain" structured drops
    function drawRain(dc, x, y) {
        drawCloud(dc, x, y); // Render 16x16 base footprint

        // 16x16 scale downward parallel drop strokes
        dc.drawLine(x + 6, y + 14, x + 5, y + 16);
        dc.drawLine(x + 10, y + 14, x + 9, y + 16);
    }

    // Lucide "CloudLightning" dynamic zigzag path layout
    function drawLightning(dc, x, y) {
        drawCloud(dc, x, y);

        // Render stylized lightning strikes extending down past y=13 boundary
        dc.drawLine(x + 8, y + 13, x + 6, y + 15);
        dc.drawLine(x + 6, y + 15, x + 9, y + 15);
        dc.drawLine(x + 9, y + 15, x + 7, y + 17);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hijri calendar helpers
// ─────────────────────────────────────────────────────────────────────────────

module HijriHelpers {

    function gregorianToJulianDay(year as Number, month as Number, day as Number) as Number {
        var m = month;
        var y = year;
        if (m < 3) {
            y -= 1;
            m += 12;
        }
        var a = Math.floor(y / 100.0);
        var b = 2 - a + Math.floor(a / 4.0);
        return Math.floor(365.25 * (y + 4716)) +
               Math.floor(30.6001 * (m + 1)) +
               day + b - 1524;
    }

    function julianDayToHijri(jd as Number) as Dictionary {
        var epochAstro = 1948084;
        var shift1     = 8.01 / 60.0;
        var iyear      = 10631.0 / 30.0;
        var cycle      = 10631;
        var z   = jd - epochAstro;
        var cyc = Math.floor(z / cycle.toFloat());
        z = z - cycle * cyc;

        var j  = Math.floor((z - shift1) / iyear);
        var iy = 30 * cyc + j;
        z = z - Math.floor(j * iyear + shift1);
        var im = Math.floor((z + 28.5001) / 29.5);
        if (im == 13) { im = 12; }

        var id = z - Math.floor(29.5001 * im - 29);
        return { :year => iy, :month => im, :day => id };
    }

    function gregorianToHijri(year as Number, month as Number, day as Number, dayOffset as Number) as Dictionary {
        var jd = gregorianToJulianDay(year, month, day) + dayOffset;
        return julianDayToHijri(jd);
    }

    function hijriMonthName(month as Number) as String {
        switch (month) {
            case 1:  return "MUHARR";
            case 2:  return "SAFAR";
            case 3:  return "RAB AWL";
            case 4:  return "RAB THN";
            case 5:  return "JUM AWL";
            case 6:  return "JUM THN";
            case 7:  return "RAJAB";
            case 8:  return "SHABAN";
            case 9:  return "RAMADAN";
            case 10: return "SHAWWAL";
            case 11: return "DHU QID";
            case 12: return "DHU HIJ";
            default: return "-------";
        }
    }

    function weekdayAbbr(dayOfWeek as Number) as String {
        switch (dayOfWeek) {
            case 1: return "SUN";
            case 2: return "MON";
            case 3: return "TUE";
            case 4: return "WED";
            case 5: return "THU";
            case 6: return "FRI";
            case 7: return "SAT";
            default: return "---";
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Time formatting helpers
// ─────────────────────────────────────────────────────────────────────────────

module TimeHelpers {

    function getFormattedTime24(clockTime) {
        return Lang.format("$1$:$2$", [
            clockTime.hour.format("%02d"),
            clockTime.min.format("%02d")
        ]);
    }

    function formatEventTime(epochSec as Number) as String {
        var t    = new Time.Moment(epochSec);
        var info = Gregorian.info(t, Time.FORMAT_SHORT);
        return Lang.format("$1$:$2$", [
            info.hour.format("%02d"),
            info.min.format("%02d")
        ]);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings menu – Hijri day offset  (-2 … +2)
// ─────────────────────────────────────────────────────────────────────────────

class HijriOffsetSettingsMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => "Hijri date shift" });
        addItem(new WatchUi.MenuItem("-2 days",     "Earlier (moon)", 0, {}));
        addItem(new WatchUi.MenuItem("-1 day",      "",               1, {}));
        addItem(new WatchUi.MenuItem("0 (default)", "Tabular",        2, {}));
        addItem(new WatchUi.MenuItem("+1 day",      "",               3, {}));
        addItem(new WatchUi.MenuItem("+2 days",     "Later (moon)",   4, {}));
    }
}

class HijriOffsetMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(menuItem as MenuItem) as Void {
        var rawId = menuItem.getId();
        if (!(rawId instanceof Number)) { return; }
        var offset = (rawId as Number) - 2;
        Properties.setValue("hijriDayOffset", offset);
        WatchUi.requestUpdate();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// App entry point
// ─────────────────────────────────────────────────────────────────────────────

class MyProjectApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [ new MyWatchFace() ];
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return [ new HijriOffsetSettingsMenu(), new HijriOffsetMenuDelegate() ];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Watch-face view
// ─────────────────────────────────────────────────────────────────────────────

class MyWatchFace extends WatchUi.WatchFace {

    var timer;
    const HEART_RATE_PLACEHOLDER = "--";
    var cachedHrDisplay = HEART_RATE_PLACEHOLDER;

    var lastWeatherFetchTime     = 0;
    var cachedConditions         = null;
    const WEATHER_UPDATE_INTERVAL = 15 * 60;

    var lastSystemStatsFetchTime = 0;
    var cachedSystemStats        = null;
    const SYSTEM_STATS_UPDATE_INTERVAL = 5 * 60;

    var cachedSteps         = 0;
    var cachedDistanceCm    = 0.0;
    var cachedCalories      = 0;
    var cachedFloorsClimbed = 0;
    var cachedMoveBarLevel  = 0;

    var cachedGregorianInfo = null;

    // Porthole geometry
    const PORTHOLE_CX = 143;
    const PORTHOLE_CY = 32;
    const PORTHOLE_R  = 30;

    // Bounding Box Clipping Region for 1Hz Partial Updates inside the Porthole
    const CLIP_X = 111; // 143 - 30 - 2
    const CLIP_Y = 0;   // 32 - 30 - 2, rounded up to top of screen boundary
    const CLIP_W = 64;
    const CLIP_H = 64;

    // Vertical layout constants (pixels from top of 176 px display)
    const CY_TIME       = 90;
    const Y_HIJRI       = 110;
    const Y_GREGORIAN   = 128;
    const Y_SOLAR_LABEL = 146;
    const Y_BATTERY_BAR = 172;
    const H_BATTERY_BAR = 4;

    function initialize() {
        WatchFace.initialize();
        timer = new Timer.Timer();
    }

    function onShow() {
        timer.stop();
        onMinuteUiTick();
        timer.start(method(:onMinuteUiTick), 60000, true);
        WatchUi.requestUpdate();
    }

    function onHide() {
        timer.stop();
    }

    function onEnterSleep() {
        timer.stop();
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        onMinuteUiTick();
        timer.start(method(:onMinuteUiTick), 60000, true);
        WatchUi.requestUpdate();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Per-minute update – refresh all cached data, then request a redraw
    // ─────────────────────────────────────────────────────────────────────────

    function onMinuteUiTick() as Void {
        cachedGregorianInfo = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        if (Toybox has :Weather) {
            var now = Time.now().value();
            if (cachedConditions == null ||
                (now - lastWeatherFetchTime) > WEATHER_UPDATE_INTERVAL) {
                var fresh = Weather.getCurrentConditions();
                if (fresh != null) {
                    cachedConditions     = fresh;
                    lastWeatherFetchTime = now;
                }
            }
        }

        updateActivityData();
        refreshCachedHeartRate();
        WatchUi.requestUpdate();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1Hz Partial Update Lifecycle Window
    // ─────────────────────────────────────────────────────────────────────────

    function onPartialUpdate(dc) {
        updateActivityData();
        refreshCachedHeartRate();

        dc.setClip(CLIP_X, CLIP_Y, CLIP_W, CLIP_H);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(CLIP_X, CLIP_Y, CLIP_W, CLIP_H);

        drawPortholeContents(dc);

        dc.clearClip();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Main draw (Full screen redraw executed on the minute boundary)
    // ─────────────────────────────────────────────────────────────────────────

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawTime(dc);          // ① large centered time digits
        drawUpperLeftWeather(dc); // ② Inline 16x16 Vector Icon + Temp
        drawPortholeFrame(dc); // ③ ring base layout
        drawPortholeContents(dc); // Draws dynamic fields inside the ring
        drawCenterDates(dc);   // ④ hijri · gregorian · solar event (below time)
        drawBatteryBar(dc);    // ⑤ thin horizontal bar at very bottom
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ① Time
    // ─────────────────────────────────────────────────────────────────────────

    function drawTime(dc) {
        var timeString = TimeHelpers.getFormattedTime24(System.getClockTime());
        var cx = dc.getWidth() / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx,
            CY_TIME,
            Graphics.FONT_NUMBER_THAI_HOT,
            timeString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ② Upper Left Corner — Inline 16x16 Lucide Vector Icon & Temperature
    // ─────────────────────────────────────────────────────────────────────────

    function drawUpperLeftWeather(dc) {
        var tempStr = "--\u00B0C";
        var conditionCode = -1;

        if (Toybox has :Weather && cachedConditions != null) {
            if (cachedConditions.temperature != null) {
                tempStr = cachedConditions.temperature.toFloat().format("%d") + "\u00B0C";
            }
            if (cachedConditions.condition != null) {
                conditionCode = cachedConditions.condition.toNumber();
            }
        }

        var iconX = 42;
        var iconY = 6; // Shifted 1px higher to visually square with the expanded 16x16 profile

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        switch (conditionCode) {
            case 0:  // CLEAR
            case 23: // MOSTLY_CLEAR
                MiniVectorIcons.drawSun(dc, iconX, iconY);
                break;

            case 1:  // PARTLY_CLOUDY
            case 2:  // MOSTLY_CLOUDY
            case 20: // CLOUDY
            case 22: // PARTLY_CLOUDY_NIGHT
            case 24: // MOSTLY_CLEAR_NIGHT
                MiniVectorIcons.drawCloud(dc, iconX, iconY);
                break;

            case 3:  // RAIN
            case 11: // SCATTERED_SHOWERS
            case 14: // LIGHT_RAIN
            case 15: // HEAVY_RAIN
            case 25: // LIGHT_SHOWERS
            case 26: // SHOWERS
            case 27: // HEAVY_SHOWERS
                MiniVectorIcons.drawRain(dc, iconX, iconY);
                break;

            case 6:  // THUNDERSTORMS
            case 12: // SCATTERED_THUNDERSTORMS
                MiniVectorIcons.drawLightning(dc, iconX, iconY);
                break;

            default:
                MiniVectorIcons.drawCloud(dc, iconX, iconY);
                break;
        }

        // Shift the text tracking right by: 16px (new canvas width) + 5px inline padding
        var textX = iconX + 16 + 6;
        dc.drawText(textX, 2, Graphics.FONT_XTINY, tempStr, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ③ Porthole Frame & Contents (1Hz Target Zone)
    // ─────────────────────────────────────────────────────────────────────────

    function drawPortholeFrame(dc) {
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(PORTHOLE_CX, PORTHOLE_CY, PORTHOLE_R,
                   Graphics.ARC_CLOCKWISE, 90, 91);
    }

    function drawPortholeContents(dc) {
        if (dc has :setClip) {
            drawPortholeFrame(dc);
        }

        var stepsStr = cachedSteps.toString();
        var hrStr    = cachedHrDisplay;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        // Top Line: High-Speed Step Count
        dc.drawText(PORTHOLE_CX, PORTHOLE_CY - 22,
                    Graphics.FONT_XTINY, stepsStr + "s",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Bottom Line: Live Sub-Second Heart Rate Tracker
        dc.drawText(PORTHOLE_CX, PORTHOLE_CY - 2,
                    Graphics.FONT_TINY, hrStr + "h",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ④ Center column below time
    // ─────────────────────────────────────────────────────────────────────────

    function drawCenterDates(dc) {
        var cx = dc.getWidth() / 2;
        var g = cachedGregorianInfo;
        if (g == null) { g = Gregorian.info(Time.now(), Time.FORMAT_SHORT); }

        var hijri    = HijriHelpers.gregorianToHijri(g.year, g.month, g.day, getHijriDayOffset());
        var hijriDay = hijri[:day].toNumber().format("%02d");
        var hijriMon = HijriHelpers.hijriMonthName(hijri[:month].toNumber());
        var hijriYr  = hijri[:year].toNumber().toString();
        var hijriLine = hijriDay + " " + hijriMon + " " + hijriYr;

        var dow = HijriHelpers.weekdayAbbr(g.day_of_week);
        var gregorianLine = dow + " " + g.year.toString() +
                            g.month.format("%02d") + g.day.format("%02d");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_HIJRI,     Graphics.FONT_XTINY, hijriLine,     Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, Y_GREGORIAN, Graphics.FONT_XTINY, gregorianLine, Graphics.TEXT_JUSTIFY_CENTER);

        drawSolarEvent(dc, cx);
    }

    function drawSolarEvent(dc, cx) {
        if (!(Toybox has :Weather) || cachedConditions == null) { return; }

        var location = cachedConditions.observationLocationPosition;
        if (location == null) { return; }

        var sunrise = Weather.getSunrise(location, Time.now());
        var sunset  = Weather.getSunset(location, Time.now());
        if (sunrise == null || sunset == null) { return; }

        var srSec  = sunrise.value();
        var ssSec  = sunset.value();
        var nowSec = Time.now().value();

        var noonSec            = srSec + (ssSec - srSec) / 2;
        var midnightTonightSec = ssSec + ((srSec + 86400) - ssSec) / 2;
        var midnightPrevSec    = midnightTonightSec - 86400;

        var eventTimes  = [midnightPrevSec, srSec, noonSec, ssSec, midnightTonightSec];
        var eventLabels = ["MIDN", "SUNR", "NOON", "SUNS", "MIDN"];
        var count       = eventTimes.size();

        var pastIdx = -1;
        for (var i = 0; i < count; i++) {
            if (eventTimes[i] <= nowSec) { pastIdx = i; }
        }

        var displayLabel  = "";
        var eventEpochSec = 0;

        if (pastIdx == -1) {
            displayLabel  = eventLabels[0];
            eventEpochSec = eventTimes[0];
        } else {
            var elapsed = nowSec - eventTimes[pastIdx];
            if (elapsed <= 3600) {
                displayLabel  = eventLabels[pastIdx];
                eventEpochSec = eventTimes[pastIdx];
            } else {
                var nextIdx = pastIdx + 1;
                if (nextIdx >= count) {
                    displayLabel  = "MIDN";
                    eventEpochSec = midnightTonightSec + 86400;
                } else {
                    displayLabel  = eventLabels[nextIdx];
                    eventEpochSec = eventTimes[nextIdx];
                }
            }
        }

        var eventTimeStr = TimeHelpers.formatEventTime(eventEpochSec);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_SOLAR_LABEL, Graphics.FONT_XTINY, displayLabel + " " + eventTimeStr,  Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ⑤ Battery bar
    // ─────────────────────────────────────────────────────────────────────────

    function drawBatteryBar(dc) {
        var w = dc.getWidth();
        var pct = 0.0;
        if (cachedSystemStats != null) {
            pct = cachedSystemStats.battery.toFloat() / 100.0;
        }
        var fillW = (w.toFloat() * pct).toNumber();

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, Y_BATTERY_BAR, w, H_BATTERY_BAR);

        if (fillW > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, Y_BATTERY_BAR, fillW, H_BATTERY_BAR);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Data helpers
    // ─────────────────────────────────────────────────────────────────────────

    function getHijriDayOffset() as Number {
        var raw = Properties.getValue("hijriDayOffset");
        if (!(raw instanceof Number)) { return 0; }
        var n = raw as Number;
        if (n < -2) { return -2; }
        if (n > 2)  { return 2; }
        return n;
    }

    function updateActivityData() {
        var info = ActivityMonitor.getInfo();
        if (info != null) {
            if (info.moveBarLevel  != null) { cachedMoveBarLevel  = info.moveBarLevel; }
            if (info.steps         != null) { cachedSteps         = info.steps; }
            if (info.distance      != null) { cachedDistanceCm    = info.distance; }
            if (info.calories      != null) { cachedCalories      = info.calories; }
            if (info.metersClimbed != null) {
                cachedFloorsClimbed = ((info.metersClimbed.toFloat() / 3.0) + 0.5).toNumber();
            } else {
                cachedFloorsClimbed = 0;
            }
        } else {
            cachedFloorsClimbed = 0;
        }
        updateSystemStats();
    }

    function updateSystemStats() {
        var now = Time.now().value();
        if (cachedSystemStats == null ||
            (now - lastSystemStatsFetchTime) > SYSTEM_STATS_UPDATE_INTERVAL) {
            var s = System.getSystemStats();
            if (s != null) {
                cachedSystemStats        = s;
                lastSystemStatsFetchTime = now;
            }
        }
    }

    function refreshCachedHeartRate() as Void {
        var iter   = ActivityMonitor.getHeartRateHistory(new Time.Duration(60), false);
        var sample = iter.next();
        while (sample != null) {
            if (sample.heartRate != null &&
                sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                cachedHrDisplay = sample.heartRate.toString();
                return;
            }
            sample = iter.next();
        }

        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            cachedHrDisplay = info.currentHeartRate.toString();
            return;
        }

        if ((Toybox has :SensorHistory) && (SensorHistory has :getHeartRateHistory)) {
            var hrIter = SensorHistory.getHeartRateHistory({
                :period => 1,
                :order  => SensorHistory.ORDER_NEWEST_FIRST
            });
            if (hrIter != null) {
                var hrSample = hrIter.next();
                if (hrSample != null && hrSample.data != null) {
                    cachedHrDisplay = hrSample.data.toNumber().toString();
                    return;
                }
            }
        }

        cachedHrDisplay = HEART_RATE_PLACEHOLDER;
    }
}
