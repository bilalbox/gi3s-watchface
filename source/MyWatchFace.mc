// ─────────────────────────────────────────────────────────────────────────────
// MyWatchFace.mc  –  Garmin Instinct 2X Solar  (176 × 176 px)
//
// Layout (top → bottom):
//   Upper-left    │  steps (y≈2)  ·  heart rate (y≈18)
//   Porthole ring │  cx=143 cy=32 r=30  →  temp (top)  ·  4-letter cond (bottom)
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

    // ── Hijri month names ─────────────────────────────────────────────────────
    // Max 7 characters; space-separated for multi-word names (e.g. "DHU QID").
    function hijriMonthName(month as Number) as String {
        switch (month) {
            case 1:  return "MUHARR";   // Muharram        (6)
            case 2:  return "SAFAR";    // Safar           (5)
            case 3:  return "RAB AWL";  // Rabi' al-Awwal  (7)
            case 4:  return "RAB THN";  // Rabi' al-Thani  (7)
            case 5:  return "JUM AWL";  // Jumada al-Awwal (7)
            case 6:  return "JUM THN";  // Jumada al-Thani (7)
            case 7:  return "RAJAB";    // Rajab           (5)
            case 8:  return "SHABAN";   // Sha'ban         (6)
            case 9:  return "RAMADAN";  // Ramadan         (7)
            case 10: return "SHAWWAL";  // Shawwal         (7)
            case 11: return "DHU QID";  // Dhu al-Qi'dah   (7)
            case 12: return "DHU HIJ";  // Dhu al-Hijjah   (7)
            default: return "-------";
        }
    }

    // ── Day-of-week abbreviations ─────────────────────────────────────────────
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

    // Format a Unix-epoch seconds value as HH:MM (24 h, local time)
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

    // ── Timer ─────────────────────────────────────────────────────────────────
    var timer;

    // ── Heart rate ────────────────────────────────────────────────────────────
    const HEART_RATE_PLACEHOLDER = "--";
    var cachedHrDisplay = HEART_RATE_PLACEHOLDER;

    // ── Weather ───────────────────────────────────────────────────────────────
    var lastWeatherFetchTime     = 0;
    var cachedConditions         = null;
    const WEATHER_UPDATE_INTERVAL = 15 * 60;  // seconds

    // ── System stats (battery) ────────────────────────────────────────────────
    var lastSystemStatsFetchTime = 0;
    var cachedSystemStats        = null;
    const SYSTEM_STATS_UPDATE_INTERVAL = 5 * 60;  // seconds

    // ── Activity ──────────────────────────────────────────────────────────────
    var cachedSteps         = 0;
    var cachedDistanceCm    = 0.0;
    var cachedCalories      = 0;
    var cachedFloorsClimbed = 0;
    var cachedMoveBarLevel  = 0;

    // ── Date cache ────────────────────────────────────────────────────────────
    var cachedGregorianInfo = null;

    // ── Porthole geometry ─────────────────────────────────────────────────────
    // Upper-right circle showing weather.  Position unchanged from original.
    const PORTHOLE_CX = 143;
    const PORTHOLE_CY = 32;
    const PORTHOLE_R  = 30;

    // ── Vertical layout constants (pixels from top of 176 px display) ─────────
    // Time font (FONT_NUMBER_THAI_HOT) is ~56 px tall; VCENTER at CY_TIME
    // places top ≈ CY_TIME-28, bottom ≈ CY_TIME+28.
    const CY_TIME       = 90;   // time vertical centre
    const Y_HIJRI       = 110;  // hijri date line top
    const Y_GREGORIAN   = 128;  // gregorian date line top
    const Y_SOLAR_LABEL = 146;  // solar event label + time top
    const Y_BATTERY_BAR = 172;  // battery bar top  (176 - 4 = 172)
    const H_BATTERY_BAR = 4;    // battery bar height

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

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
    // Main draw
    // ─────────────────────────────────────────────────────────────────────────

    function onUpdate(dc) {
        // Clear screen
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawTime(dc);         // ① large centered time digits
        drawPorthole(dc);     // ② ring + weather (temp + condition)
        drawUpperLeft(dc);    // ③ steps + heart rate (top-left)
        drawCenterDates(dc);  // ④ hijri · gregorian · solar event (below time)
        drawBatteryBar(dc);   // ⑤ thin horizontal bar at very bottom
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
    // ② Porthole ring + weather
    //    Temp on top (FONT_XTINY), 4-letter condition below (FONT_TINY)
    //    Falls back to just the ring when weather is unavailable.
    // ─────────────────────────────────────────────────────────────────────────

    function drawPorthole(dc) {
        // Ring
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(PORTHOLE_CX, PORTHOLE_CY, PORTHOLE_R,
                   Graphics.ARC_CLOCKWISE, 90, 91);

        if (!(Toybox has :Weather) || cachedConditions == null) { return; }

        // Temperature – degrees symbol via Unicode U+00B0
        var tempStr = "--\u00B0C";
        if (cachedConditions.temperature != null) {
            tempStr = cachedConditions.temperature.toFloat().format("%d") + "\u00B0C";
        }

        // 4-letter weather condition code
        var condStr = "----";
        if (cachedConditions.condition != null) {
            condStr = conditionLabel(cachedConditions.condition.toNumber());
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        // Top line: temperature  (same y as original solar label)
        dc.drawText(PORTHOLE_CX, PORTHOLE_CY - 22,
                    Graphics.FONT_XTINY, tempStr,
                    Graphics.TEXT_JUSTIFY_CENTER);
        // Bottom line: condition  (same y as original solar time, FONT_TINY for emphasis)
        dc.drawText(PORTHOLE_CX, PORTHOLE_CY - 2,
                    Graphics.FONT_TINY, condStr,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ③ Upper-left – steps + heart rate
    //    Cascade inward from the corner (mirror of the original top-left style)
    // ─────────────────────────────────────────────────────────────────────────

    function drawUpperLeft(dc) {
        var stepsLine = cachedSteps.toString() + " STP";
        var hrLine    = cachedHrDisplay         + " BPM";

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(36, 2,  Graphics.FONT_XTINY, stepsLine, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(36, 18, Graphics.FONT_XTINY, hrLine,    Graphics.TEXT_JUSTIFY_LEFT);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ④ Center column below time
    //    Hijri date → Gregorian date → solar event label → solar event time
    // ─────────────────────────────────────────────────────────────────────────

    function drawCenterDates(dc) {
        var cx = dc.getWidth() / 2;

        var g = cachedGregorianInfo;
        if (g == null) { g = Gregorian.info(Time.now(), Time.FORMAT_SHORT); }

        // ── Hijri date: "DD MONTHNAME YYYY" ──────────────────────────────────
        var hijri    = HijriHelpers.gregorianToHijri(g.year, g.month, g.day, getHijriDayOffset());
        var hijriDay = hijri[:day].toNumber().format("%02d");
        var hijriMon = HijriHelpers.hijriMonthName(hijri[:month].toNumber());
        var hijriYr  = hijri[:year].toNumber().toString();
        var hijriLine = hijriDay + " " + hijriMon + " " + hijriYr;

        // ── Gregorian date: "EEE YYYYMMDD" ───────────────────────────────────
        var dow = HijriHelpers.weekdayAbbr(g.day_of_week);
        var gregorianLine = dow + " " + g.year.toString() +
                            g.month.format("%02d") + g.day.format("%02d");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_HIJRI,     Graphics.FONT_XTINY, hijriLine,     Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, Y_GREGORIAN, Graphics.FONT_XTINY, gregorianLine, Graphics.TEXT_JUSTIFY_CENTER);

        // ── Solar event (logic identical to original porthole) ────────────────
        drawSolarEvent(dc, cx);
    }

    // Solar-event logic — determine the nearest notable solar event and draw its
    // label + clock time centred at the given cx.
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

        // Derived events for the day
        var noonSec            = srSec + (ssSec - srSec) / 2;
        var midnightTonightSec = ssSec + ((srSec + 86400) - ssSec) / 2;
        var midnightPrevSec    = midnightTonightSec - 86400;

        var eventTimes  = [midnightPrevSec, srSec, noonSec, ssSec, midnightTonightSec];
        var eventLabels = ["MIDN", "SUNR", "NOON", "SUNS", "MIDN"];
        var count       = eventTimes.size();

        // Find the most-recently-passed event
        var pastIdx = -1;
        for (var i = 0; i < count; i++) {
            if (eventTimes[i] <= nowSec) { pastIdx = i; }
        }

        var displayLabel  = "";
        var eventEpochSec = 0;

        if (pastIdx == -1) {
            // All events still in the future (edge case)
            displayLabel  = eventLabels[0];
            eventEpochSec = eventTimes[0];
        } else {
            var elapsed = nowSec - eventTimes[pastIdx];
            if (elapsed <= 3600) {
                // Within 1 hour after a past event → show that event
                displayLabel  = eventLabels[pastIdx];
                eventEpochSec = eventTimes[pastIdx];
            } else {
                // Show the next upcoming event
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
    //    Dark-gray background across full width; white fill proportional to %.
    // ─────────────────────────────────────────────────────────────────────────

    function drawBatteryBar(dc) {
        var w = dc.getWidth();

        var pct = 0.0;
        if (cachedSystemStats != null) {
            pct = cachedSystemStats.battery.toFloat() / 100.0;
        }
        var fillW = (w.toFloat() * pct).toNumber();

        // Empty background
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, Y_BATTERY_BAR, w, H_BATTERY_BAR);

        // Filled portion
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
        // 1. Try ActivityMonitor heart-rate history (last 60 s)
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

        // 2. Try live Activity info
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            cachedHrDisplay = info.currentHeartRate.toString();
            return;
        }

        // 3. Try SensorHistory (older firmware path)
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

    // ─────────────────────────────────────────────────────────────────────────
    // Weather condition → 4-character display code
    // Uses numeric literals so it compiles on any firmware that has the
    // Weather module, regardless of which CONDITION_* symbols are available.
    //
    // Reference: Garmin ConnectIQ SDK — Toybox.Weather.Conditions enum
    // ─────────────────────────────────────────────────────────────────────────

    function conditionLabel(code as Number) as String {
        switch (code) {
            case 0:  return "CLIR";  //  0  CLEAR
            case 1:  return "PCLD";  //  1  PARTLY_CLOUDY
            case 2:  return "MCLD";  //  2  MOSTLY_CLOUDY
            case 3:  return "RAIN";  //  3  RAIN
            case 4:  return "SNOW";  //  4  SNOW
            case 5:  return "WNDY";  //  5  WINDY
            case 6:  return "TSTM";  //  6  THUNDERSTORMS
            case 7:  return "WMIX";  //  7  WINTRY_MIX
            case 8:  return "FOGG";  //  8  FOG
            case 9:  return "HAZY";  //  9  HAZY
            case 10: return "HAIL";  // 10  HAIL
            case 11: return "SHWR";  // 11  SCATTERED_SHOWERS
            case 12: return "TSTM";  // 12  SCATTERED_THUNDERSTORMS
            case 13: return "PRCP";  // 13  UNKNOWN_PRECIPITATION
            case 14: return "LRNI";  // 14  LIGHT_RAIN
            case 15: return "HRNI";  // 15  HEAVY_RAIN
            case 16: return "LSNW";  // 16  LIGHT_SNOW
            case 17: return "HSNW";  // 17  HEAVY_SNOW
            case 18: return "SLSH";  // 18  LIGHT_RAIN_SNOW
            case 19: return "HSLH";  // 19  HEAVY_RAIN_SNOW
            case 20: return "CLDY";  // 20  CLOUDY
            case 21: return "SLSH";  // 21  RAIN_SNOW
            case 22: return "PCLN";  // 22  PARTLY_CLOUDY_NIGHT
            case 23: return "MCLR";  // 23  MOSTLY_CLEAR
            case 24: return "MCLN";  // 24  MOSTLY_CLEAR_NIGHT
            case 25: return "LSHR";  // 25  LIGHT_SHOWERS
            case 26: return "SHWR";  // 26  SHOWERS
            case 27: return "HSHR";  // 27  HEAVY_SHOWERS
            case 28: return "LSNS";  // 28  LIGHT_SNOW_SHOWERS
            case 29: return "SNWS";  // 29  SNOW_SHOWERS
            case 30: return "HSNS";  // 30  HEAVY_SNOW_SHOWERS
            case 31: return "LRAS";  // 31  LIGHT_RAIN_AND_SNOW
            case 32: return "HRAS";  // 32  HEAVY_RAIN_AND_SNOW
            case 33: return "DUST";  // 33  DUST
            case 34: return "SAND";  // 34  SAND
            case 35: return "SSTM";  // 35  SANDSTORM
            case 36: return "VASH";  // 36  ASH  (volcanic)
            case 37: return "SQAL";  // 37  SQUALL
            case 38: return "DRZL";  // 38  DRIZZLE
            case 39: return "TRND";  // 39  TORNADO
            case 40: return "TSTR";  // 40  TROPICAL_STORM
            case 41: return "HURC";  // 41  HURRICANE
            case 42: return "CRAN";  // 42  CLOUDS_AND_RAIN
            case 43: return "SNTH";  // 43  SNOW_AND_THUNDER
            case 44: return "SMOK";  // 44  SMOKE
            case 45: return "ICEY";  // 45  ICE
            default: return "----";
        }
    }
}
