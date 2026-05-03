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

    function gregorianMonthAbbr(month as Number) as String {
        switch (month) {
            case 1:  return "JAN";
            case 2:  return "FEB";
            case 3:  return "MAR";
            case 4:  return "APR";
            case 5:  return "MAY";
            case 6:  return "JUN";
            case 7:  return "JUL";
            case 8:  return "AUG";
            case 9:  return "SEP";
            case 10: return "OCT";
            case 11: return "NOV";
            case 12: return "DEC";
            default: return "---";
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
            default: return "";
        }
    }

    function hijriMonthAbbr(month as Number) as String {
        switch (month) {
            case 1:  return "MUH";
            case 2:  return "SAF";
            case 3:  return "RA1";
            case 4:  return "RA2";
            case 5:  return "JU1";
            case 6:  return "JU2";
            case 7:  return "RAJ";
            case 8:  return "SHB";
            case 9:  return "RAM";
            case 10: return "SHW";
            case 11: return "DHQ";
            case 12: return "DHH";
            default: return "---";
        }
    }
}

module TimeHelpers {
    function getFormattedTime24(clockTime) {
        return Lang.format("$1$:$2$", [
            clockTime.hour.format("%02d"),
            clockTime.min.format("%02d")
        ]);
    }
}

class HijriOffsetSettingsMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => "Hijri date shift" });
        addItem(new WatchUi.MenuItem("-2 days",      "Earlier (moon)", 0, {}));
        addItem(new WatchUi.MenuItem("-1 day",        "",              1, {}));
        addItem(new WatchUi.MenuItem("0 (default)",  "Tabular",        2, {}));
        addItem(new WatchUi.MenuItem("+1 day",        "",              3, {}));
        addItem(new WatchUi.MenuItem("+2 days",      "Later (moon)",   4, {}));
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

class MyWatchFace extends WatchUi.WatchFace {
    var timer;

    // Heart rate
    const HEART_RATE_PLACEHOLDER = "--";
    var cachedHrDisplay = HEART_RATE_PLACEHOLDER;

    // Weather / conditions
    var lastWeatherFetchTime = 0;
    var cachedConditions     = null;
    const WEATHER_UPDATE_INTERVAL = 15 * 60;

    // System stats
    var lastSystemStatsFetchTime = 0;
    var cachedSystemStats        = null;
    const SYSTEM_STATS_UPDATE_INTERVAL = 5 * 60;

    // Activity
    var cachedSteps         = 0;
    var cachedDistanceCm    = 0.0;
    var cachedCalories      = 0;
    var cachedFloorsClimbed = 0;

    // Date
    var cachedGregorianInfo = null;

    // Porthole geometry (unchanged from original HR arc)
    const PORTHOLE_CX = 143;
    const PORTHOLE_CY = 32;
    const PORTHOLE_R  = 30;

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // Tick
    // -------------------------------------------------------------------------

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

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawDate(dc);
        drawWeather(dc);
        drawTime(dc);
        drawActivityData(dc);
        drawSolarPorthole(dc);
    }

    // -------------------------------------------------------------------------
    // Data helpers
    // -------------------------------------------------------------------------

    function updateActivityData() {
        var info = ActivityMonitor.getInfo();
        if (info != null) {
            if (info.steps        != null) { cachedSteps        = info.steps; }
            if (info.distance     != null) { cachedDistanceCm   = info.distance; }
            if (info.calories     != null) { cachedCalories     = info.calories; }
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

    // -------------------------------------------------------------------------
    // Solar porthole
    // -------------------------------------------------------------------------

    // Returns a compact hours string: whole hours drop the decimal,
    // fractional hours keep one decimal place.  Sign prepended when negative.
    // e.g. 3.0 → "3"   -0.5 → "-0.5"   1.75 → "1.8"   -12.0 → "-12"
    function formatSolarHours(hours as Float) as String {
            var negative = (hours < 0.0);
            var abs      = negative ? -hours : hours;

            // Round to nearest tenth
            var tenths = (abs * 10.0 + 0.5).toNumber();

            // Integer division and modulo in Monkey C
            var whole  = tenths / 10;
            var frac   = tenths % 10;

            var s;
            if (frac == 0) {
                s = whole.toString();
            } else {
                s = whole.toString() + "." + frac.toString();
            }
            return negative ? ("-" + s) : s;
        }

    function drawSolarPorthole(dc) {
        // Porthole ring — same dark-grey full circle as the original arc
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        // ARC_CLOCKWISE from 90° to 91° sweeps the full 360°
        dc.drawArc(PORTHOLE_CX, PORTHOLE_CY, PORTHOLE_R,
                   Graphics.ARC_CLOCKWISE, 90, 91);

        // Guard: need the Weather API and a valid conditions object
        if (!(Toybox has :Weather) || cachedConditions == null) { return; }

        // 1. Get the location from the weather data
        var location = cachedConditions.observationLocationPosition;
        if (location == null) { return; }

        // 2. Call the Weather API methods to get the times
        var sunrise = Weather.getSunrise(location, Time.now());
        var sunset  = Weather.getSunset(location, Time.now());

        if (sunrise == null || sunset == null) { return; }

        var srSec  = sunrise.value();   // Unix epoch seconds
        var ssSec  = sunset.value();
        var nowSec = Time.now().value();

        // Derived solar events
        // Solar noon = midpoint of daylight
        // Calculated safely to avoid 32-bit integer overflow
        var noonSec = srSec + (ssSec - srSec) / 2;

        // Solar midnight = midpoint of the night (sunset → next sunrise)
        var midnightTonightSec = ssSec + ((srSec + 86400) - ssSec) / 2;

        // Previous midnight (anchors the beginning of today's window)
        var midnightPrevSec = midnightTonightSec - 86400;

        // Ordered list covering the full 24-hour window around today
        var eventTimes  = [midnightPrevSec, srSec, noonSec, ssSec, midnightTonightSec];
        var eventLabels = ["MIDN","SUNR", "NOON","SUNS", "MIDN"];
        var count       = eventTimes.size();

        // ── Find the most-recently-passed event ───────────────────────────────
        var pastIdx = -1;
        for (var i = 0; i < count; i++) {
            if (eventTimes[i] <= nowSec) {
                pastIdx = i;
            }
        }

        var displayLabel = "";
        var displayHours = 0.0;

        if (pastIdx == -1) {
            // All events are in the future (shouldn't happen in normal use)
            displayLabel = eventLabels[0];
            displayHours = (eventTimes[0] - nowSec) / 3600.0;
        } else {
            var elapsed = nowSec - eventTimes[pastIdx];

            if (elapsed <= 3600) {
                // Within 1 hour after a past event → show it with a negative delta
                displayLabel = eventLabels[pastIdx];
                displayHours = -(elapsed / 3600.0);
            } else {
                // Show the next upcoming event
                var nextIdx = pastIdx + 1;
                if (nextIdx >= count) {
                    // Wrapped past the last entry — next is tomorrow's midnight
                    displayLabel = "MIDN";
                    displayHours = (midnightTonightSec + 86400 - nowSec) / 3600.0;
                } else {
                    displayLabel = eventLabels[nextIdx];
                    displayHours = (eventTimes[nextIdx] - nowSec) / 3600.0;
                }
            }
        }

        // ── Render ────────────────────────────────────────────────────────────
        // Top line  (FONT_XTINY): hours since/until  — at y = PORTHOLE_CY - 22
        // Bottom line (FONT_TINY): event label       — at y = PORTHOLE_CY - 2
        // (Same y-coords as the old HR / zone-label pair, fonts swapped per spec)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(PORTHOLE_CX, PORTHOLE_CY - 22,
                    Graphics.FONT_XTINY,
                    formatSolarHours(displayHours),
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(PORTHOLE_CX, PORTHOLE_CY - 2,
                    Graphics.FONT_TINY,
                    displayLabel,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------------------
    // Activity grid  (6 slots, 3 rows × 2 cols)
    // -------------------------------------------------------------------------

    function drawActivityData(dc) {
        var km        = cachedDistanceCm / 100000.0;
        var stepsLine = cachedSteps.toString()        + " STP";
        var distLine  = km.format("%.2f")             + " KM";
        var calLine   = cachedCalories.toString()     + " CAL";
        var hrLine    = cachedHrDisplay               + " BPM";
        var elevLine  = cachedFloorsClimbed.toString() + " FL";

        var batteryLine = "--%";
        if (cachedSystemStats != null) {
            batteryLine = cachedSystemStats.battery.toNumber().toString() + "%";
        }

        var leftX  = 48;
        var rightX = 124;
        var rowY   = 118;
        var rowGap = 16;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX,  rowY,              Graphics.FONT_XTINY, stepsLine,   Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, rowY,              Graphics.FONT_XTINY, distLine,    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(leftX,  rowY + rowGap,     Graphics.FONT_XTINY, calLine,     Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, rowY + rowGap,     Graphics.FONT_XTINY, hrLine,      Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(leftX,  rowY + rowGap * 2, Graphics.FONT_XTINY, batteryLine, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, rowY + rowGap * 2, Graphics.FONT_XTINY, elevLine,    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------------------
    // Date  (Gregorian line + Hijri line)
    // -------------------------------------------------------------------------

    function getHijriDayOffset() as Number {
        var raw = Properties.getValue("hijriDayOffset");
        if (!(raw instanceof Number)) { return 0; }
        var n = raw as Number;
        if (n < -2) { return -2; }
        if (n > 2)  { return 2; }
        return n;
    }

    function drawDate(dc) {
        var g = cachedGregorianInfo;
        if (g == null) { g = Gregorian.info(Time.now(), Time.FORMAT_SHORT); }

        var gregorianLine = HijriHelpers.weekdayAbbr(g.day_of_week) + " " +
                            g.day.toString() + " " +
                            HijriHelpers.gregorianMonthAbbr(g.month);

        var hijri     = HijriHelpers.gregorianToHijri(g.year, g.month, g.day, getHijriDayOffset());
        var hYear     = (hijri[:year].toNumber() % 100).format("%02d");
        var hijriLine = hijri[:day].toNumber().toString() + " " +
                        HijriHelpers.hijriMonthAbbr(hijri[:month].toNumber()) + " " +
                        hYear;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(22, 8,  Graphics.FONT_XTINY, gregorianLine, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(22, 24, Graphics.FONT_XTINY, hijriLine,     Graphics.TEXT_JUSTIFY_LEFT);
    }

    // -------------------------------------------------------------------------
    // Weather
    // -------------------------------------------------------------------------

    function getWeatherConditionLabel(condition) {
        switch (condition) {
            case Weather.CONDITION_CLEAR:                    return "CLEAR";
            case Weather.CONDITION_PARTLY_CLOUDY:            return "P.CLD";
            case Weather.CONDITION_MOSTLY_CLOUDY:            return "M.CLD";
            case Weather.CONDITION_CLOUDY:                   return "CLOUDY";
            case Weather.CONDITION_RAIN:
            case Weather.CONDITION_LIGHT_RAIN:
            case Weather.CONDITION_HEAVY_RAIN:
            case Weather.CONDITION_SHOWERS:
            case Weather.CONDITION_LIGHT_SHOWERS:
            case Weather.CONDITION_HEAVY_SHOWERS:
            case Weather.CONDITION_CHANCE_OF_SHOWERS:
            case Weather.CONDITION_RAIN_SNOW:                return "RAIN";
            case Weather.CONDITION_SNOW:
            case Weather.CONDITION_LIGHT_SNOW:
            case Weather.CONDITION_HEAVY_SNOW:
            case Weather.CONDITION_CHANCE_OF_SNOW:           return "SNOW";
            case Weather.CONDITION_THUNDERSTORMS:
            case Weather.CONDITION_SCATTERED_THUNDERSTORMS:
            case Weather.CONDITION_CHANCE_OF_THUNDERSTORMS:  return "STORM";
            case Weather.CONDITION_FOG:
            case Weather.CONDITION_MIST:                     return "FOG";
            case Weather.CONDITION_DRIZZLE:                  return "DRIZZL";
            case Weather.CONDITION_WINDY:                    return "WIND";
            case Weather.CONDITION_HAZY:
            case Weather.CONDITION_HAZE:                     return "HAZE";
            case Weather.CONDITION_PARTLY_CLEAR:
            case Weather.CONDITION_MOSTLY_CLEAR:
            case Weather.CONDITION_FAIR:                     return "FAIR";
            default:                                         return "-----";
        }
    }

    function drawWeather(dc) {
        if (!(Toybox has :Weather)) { return; }

        var condition = "--";
        var tempStr   = "--°C";

        if (cachedConditions != null) {
            if (cachedConditions.condition != null) {
                condition = getWeatherConditionLabel(cachedConditions.condition);
            }
            if (condition == null || condition.equals("")) {
                condition = "--";
            } else if (condition.length() > 5) {
                condition = condition.substring(0, 5);
            }
            if (cachedConditions.temperature != null) {
                tempStr = cachedConditions.temperature.toFloat().format("%d") + "°C";
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(22, 40, Graphics.FONT_XTINY,
                    condition + " " + tempStr,
                    Graphics.TEXT_JUSTIFY_LEFT);
    }

    // -------------------------------------------------------------------------
    // Time
    // -------------------------------------------------------------------------

    function drawTime(dc) {
        var timeString = TimeHelpers.getFormattedTime24(System.getClockTime());
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2,
            90,
            Graphics.FONT_NUMBER_THAI_HOT,
            timeString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
