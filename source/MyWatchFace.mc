// ─────────────────────────────────────────────────────────────────────────────
// MyWatchFace.mc  –  Garmin Instinct 2X / 3 Solar Optimized
//
// Layout (top → bottom):
//   Upper-left    │  [24x24 Weather Icon] + temperature (y≈0) inline using FONT_SMALL
//   Porthole ring │  cx=143 cy=32 r=30  →  steps (top, 1Hz)  ·  HR (bottom, 1Hz)
//   ─────────────────────────────────────────────────────────────────────────
//   TIME          │  centered, FONT_NUMBER_THAI_HOT, cy≈82
//   Hijri date    │  "DD MONTHNAME YYYY"  (month ≤ 7 chars)  centered
//   Gregorian     │  "EEE YYYYMMDD"  centered
//   Solar event   │  "LABEL HH:MM"  centered (SUNR / SUNS / NOON / MIDN)
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
// Custom 24x24 Vector Weather Icons (Scaled for FONT_SMALL)
// ─────────────────────────────────────────────────────────────────────────────
module MiniVectorIcons {

    // Upgraded 24x24 Sun (Center anchor at 12,12)
    function drawSun24(dc, x, y) {
        dc.setPenWidth(2); // Thickened lines to match FONT_SMALL
        dc.drawCircle(x + 12, y + 12, 6); // Sun core

        dc.setPenWidth(1);
        // Cardinal rays
        dc.drawLine(x + 12, y + 1,  x + 12, y + 4);  // Top
        dc.drawLine(x + 12, y + 20, x + 12, y + 23); // Bottom
        dc.drawLine(x + 1,  y + 12, x + 4,  y + 12); // Left
        dc.drawLine(x + 20, y + 12, x + 23, y + 12); // Right

        // Intercardinal rays
        dc.drawLine(x + 5,  y + 5,  x + 7,  y + 7);   // Top-Left
        dc.drawLine(x + 19, y + 5,  x + 17, y + 7);   // Top-Right
        dc.drawLine(x + 5,  y + 19, x + 7,  y + 17);  // Bottom-Left
        dc.drawLine(x + 19, y + 19, x + 17, y + 17);  // Bottom-Right
    }

    // Upgraded 24x24 Cloud path structure
    function drawCloud24(dc, x, y) {
        dc.setPenWidth(2);
        dc.drawCircle(x + 6,  y + 15, 4);
        dc.drawCircle(x + 12, y + 9,  6);
        dc.drawCircle(x + 18, y + 14, 4);

        // Wipe internal overlaps with a solid fill block
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 5, y + 11, 14, 8);
        dc.fillRectangle(x + 9, y + 8,  6,  6);

        // Main bottom foundation frame baseline
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x + 6, y + 19, x + 18, y + 19);
    }

    // Upgraded 24x24 Cloud + Rain drops
    function drawRain24(dc, x, y) {
        drawCloud24(dc, x, y);
        dc.setPenWidth(1);
        dc.drawLine(x + 9,  y + 20, x + 8,  y + 23);
        dc.drawLine(x + 14, y + 20, x + 13, y + 23);
    }

    // Upgraded 24x24 Cloud + Lightning strike path
    function drawLightning24(dc, x, y) {
        drawCloud24(dc, x, y);
        dc.setPenWidth(1);
        dc.drawLine(x + 12, y + 19, x + 9,  y + 22);
        dc.drawLine(x + 9,  y + 22, x + 13, y + 22);
        dc.drawLine(x + 13, y + 22, x + 10, y + 25);
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
    const Y_SOLAR_EVENT = 146;
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

    function onPartialUpdate(getDc) {
        updateActivityData();
        refreshCachedHeartRate();

        getDc.setClip(CLIP_X, CLIP_Y, CLIP_W, CLIP_H);

        getDc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        getDc.fillRectangle(CLIP_X, CLIP_Y, CLIP_W, CLIP_H);

        drawPortholeContents(getDc);

        getDc.clearClip();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Main draw (Full screen redraw executed on the minute boundary)
    // ─────────────────────────────────────────────────────────────────────────

    function onUpdate(dc) {
        // Refresh porthole data on every update for 1Hz responsiveness
        updateActivityData();
        refreshCachedHeartRate();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawTime(dc);          // ① large centered time digits
        drawUpperLeftWeather(dc); // ② Inline 24x24 Weather Vector Icon + FONT_SMALL Temp
        drawPortholeFrame(dc); // ③ ring base layout
        drawPortholeContents(dc); // Draws dynamic fields inside the ring
        drawCenterDates(dc);   // ④ hijri · gregorian · clear text solar event (below time)
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
    // ② Upper Left Corner — Inline 24x24 Weather Vector Icon & FONT_SMALL Temp
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

        var iconX = 34;
        var iconY = 2; // Set to absolute upper boundary to clear space for FONT_SMALL height

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        switch (conditionCode) {
            case 0:  // CLEAR
            case 23: // MOSTLY_CLEAR
                MiniVectorIcons.drawSun24(dc, iconX, iconY);
                break;

            case 1:  // PARTLY_CLOUDY
            case 2:  // MOSTLY_CLOUDY
            case 20: // CLOUDY
            case 22: // PARTLY_CLOUDY_NIGHT
            case 24: // MOSTLY_CLEAR_NIGHT
                MiniVectorIcons.drawCloud24(dc, iconX, iconY);
                break;

            case 3:  // RAIN
            case 11: // SCATTERED_SHOWERS
            case 14: // LIGHT_RAIN
            case 15: // HEAVY_RAIN
            case 25: // LIGHT_SHOWERS
            case 26: // SHOWERS
            case 27: // HEAVY_SHOWERS
                MiniVectorIcons.drawRain24(dc, iconX, iconY);
                break;

            case 6:  // THUNDERSTORMS
            case 12: // SCATTERED_THUNDERSTORMS
                MiniVectorIcons.drawLightning24(dc, iconX, iconY);
                break;

            default:
                MiniVectorIcons.drawCloud24(dc, iconX, iconY);
                break;
        }

        // Horizontal tracker slides exactly 24 pixels + inline padding wide
        var textX = iconX + 24 + 4;
        dc.drawText(textX, 2, Graphics.FONT_SMALL, tempStr, Graphics.TEXT_JUSTIFY_LEFT);
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
                    Graphics.FONT_XTINY, hrStr + "h",
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
        var combinedSolarString = displayLabel + " " + eventTimeStr;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_SOLAR_EVENT, Graphics.FONT_XTINY, combinedSolarString, Graphics.TEXT_JUSTIFY_CENTER);
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
