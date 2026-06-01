// ─────────────────────────────────────────────────────────────────────────────
// MyWatchFace.mc  –  Garmin Instinct 2X / 3 Solar Optimized
//
// Layout (top → bottom):
//   Upper-left    │  [24x24 Weather PNG] + temperature (y≈0) inline using FONT_SMALL
//   Porthole ring │  cx=143 cy=40 r=30  →  HR (top)  ·  steps (center)
//   ─────────────────────────────────────────────────────────────────────────
//   TIME          │  stacked HH/MM, Source Code Pro Bold bitmap digits (28×40), cy≈76
//   DOW           │  "SUN" etc · FONT_XTINY · under porthole · inline w/ minutes
//   Hijri date    │  "DD MONTHNAME YYYY"  (month ≤ 7 chars)  centered
//   Gregorian     │  "DD MMM YYYY"  centered
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
// Clock digits — per-digit Source Code Pro Bold bitmap sprites (28×40 px)
// ─────────────────────────────────────────────────────────────────────────────
module ClockDigits {

    const GAP = 4;   // px between digit cells

    var digit0 = null;
    var digit1 = null;
    var digit2 = null;
    var digit3 = null;
    var digit4 = null;
    var digit5 = null;
    var digit6 = null;
    var digit7 = null;
    var digit8 = null;
    var digit9 = null;

    function init() as Void {
        if (digit0 != null) { return; }
        digit0 = WatchUi.loadResource(Rez.Drawables.digit_0) as BitmapResource;
        digit1 = WatchUi.loadResource(Rez.Drawables.digit_1) as BitmapResource;
        digit2 = WatchUi.loadResource(Rez.Drawables.digit_2) as BitmapResource;
        digit3 = WatchUi.loadResource(Rez.Drawables.digit_3) as BitmapResource;
        digit4 = WatchUi.loadResource(Rez.Drawables.digit_4) as BitmapResource;
        digit5 = WatchUi.loadResource(Rez.Drawables.digit_5) as BitmapResource;
        digit6 = WatchUi.loadResource(Rez.Drawables.digit_6) as BitmapResource;
        digit7 = WatchUi.loadResource(Rez.Drawables.digit_7) as BitmapResource;
        digit8 = WatchUi.loadResource(Rez.Drawables.digit_8) as BitmapResource;
        digit9 = WatchUi.loadResource(Rez.Drawables.digit_9) as BitmapResource;
    }

    function bitmapForDigit(d as Number) as BitmapResource or Null {
        switch (d) {
            case 0: return digit0;
            case 1: return digit1;
            case 2: return digit2;
            case 3: return digit3;
            case 4: return digit4;
            case 5: return digit5;
            case 6: return digit6;
            case 7: return digit7;
            case 8: return digit8;
            case 9: return digit9;
        }
        return null;
    }

    function digitWidth() as Number {
        init();
        return digit0.getWidth();
    }

    function digitHeight() as Number {
        init();
        return digit0.getHeight();
    }

    function digitGap() as Number {
        return GAP;
    }

    function measureTextWidth(text as String) as Number {
        var n = text.length();
        if (n <= 0) { return 0; }
        return n * digitWidth() + (n - 1) * digitGap();
    }

    function charToDigit(ch as String) as Number {
        if (ch.equals("0")) { return 0; }
        if (ch.equals("1")) { return 1; }
        if (ch.equals("2")) { return 2; }
        if (ch.equals("3")) { return 3; }
        if (ch.equals("4")) { return 4; }
        if (ch.equals("5")) { return 5; }
        if (ch.equals("6")) { return 6; }
        if (ch.equals("7")) { return 7; }
        if (ch.equals("8")) { return 8; }
        if (ch.equals("9")) { return 9; }
        return -1;
    }

    function drawText(dc, text as String, cx, yTop) as Void {
        init();
        var totalW = measureTextWidth(text);
        var x = cx - totalW / 2;
        var step = digitWidth() + digitGap();
        var len  = text.length();

        for (var i = 0; i < len; i++) {
            var d = charToDigit(text.substring(i, i + 1));
            if (d >= 0) {
                var bmp = bitmapForDigit(d);
                if (bmp != null) {
                    dc.drawBitmap(x, yTop, bmp);
                }
            }
            x += step;
        }
    }

    function stackHeight(stackGap as Number) as Number {
        return digitHeight() * 2 + stackGap;
    }

    function drawStacked24h(dc, hourStr as String, minStr as String, cx, cyCenter, stackGap as Number) as Void {
        var rowH   = digitHeight();
        var totalH = stackHeight(stackGap);
        var hourY  = cyCenter - totalH / 2;
        var minY   = hourY + rowH + stackGap;

        drawText(dc, hourStr, cx, hourY);
        drawText(dc, minStr, cx, minY);
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

    function gregorianMonthName(month as Number) as String {
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Time formatting helpers
// ─────────────────────────────────────────────────────────────────────────────

module TimeHelpers {

    function getHourMinute24(clockTime) as Dictionary {
        return {
            :hour => clockTime.hour.format("%02d"),
            :min  => clockTime.min.format("%02d")
        };
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

    var cachedSteps = 0;

    var cachedGregorianInfo = null;
    var iconHeart = null;
    var iconSteps = null;

    // Porthole geometry
    const PORTHOLE_CX = 143;
    const PORTHOLE_CY = 40;
    const PORTHOLE_R  = 30;
    const PORTHOLE_ICON_GAP = 2;
    const Y_PORTHOLE_HR     = PORTHOLE_CY - 20;
    const Y_PORTHOLE_STEPS  = PORTHOLE_CY;

    // Vertical layout constants (pixels from top of 176 px display)
    // Time stack: 2×40 px rows + 6 px gap = 86 px; CY_TIME is stack vertical center
    const CY_TIME         = 76;    // +10 px up from prior anchor (86)
    const TIME_STACK_GAP  = 6;
    const TIME_CX_OFFSET  = -20;   // +10 px further left from prior nudge (-10)
    const Y_HIJRI         = 128;
    const Y_GREGORIAN     = 148;
    const Y_BATTERY_BAR = 172;
    const H_BATTERY_BAR = 4;

    function initialize() {
        WatchFace.initialize();
        timer = new Timer.Timer();
        ClockDigits.init();
        iconHeart = WatchUi.loadResource(Rez.Drawables.icon_heart) as BitmapResource;
        iconSteps = WatchUi.loadResource(Rez.Drawables.icon_steps) as BitmapResource;
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
    // Main draw (once per minute via onMinuteUiTick)
    // ─────────────────────────────────────────────────────────────────────────

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawTime(dc);          // ① large centered time digits
        drawWeekdayByPorthole(dc); // ①b DOW inline with minutes, under porthole
        drawUpperLeftWeather(dc); // ② 24x24 weather PNG + FONT_SMALL temp
        drawPortholeFrame(dc); // ③ ring base layout
        drawPortholeContents(dc); // Draws dynamic fields inside the ring
        drawCenterDates(dc);   // ④ hijri · gregorian (below time)
        drawBatteryBar(dc);    // ⑤ thin horizontal bar at very bottom
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ① Time
    // ─────────────────────────────────────────────────────────────────────────

    function drawTime(dc) {
        var parts   = TimeHelpers.getHourMinute24(System.getClockTime());
        var hourStr = parts[:hour] as String;
        var minStr  = parts[:min] as String;
        var cx      = dc.getWidth() / 2 + TIME_CX_OFFSET;

        ClockDigits.drawStacked24h(dc, hourStr, minStr, cx, CY_TIME, TIME_STACK_GAP);
    }

    function getMinuteRowCenterY() as Number {
        var rowH   = ClockDigits.digitHeight();
        var totalH = ClockDigits.stackHeight(TIME_STACK_GAP);
        var hourY  = CY_TIME - totalH / 2;
        var minY   = hourY + rowH + TIME_STACK_GAP;
        return minY + rowH / 2;
    }

    function drawWeekdayByPorthole(dc) {
        var g = cachedGregorianInfo;
        if (g == null) { g = Gregorian.info(Time.now(), Time.FORMAT_SHORT); }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            PORTHOLE_CX,
            getMinuteRowCenterY(),
            Graphics.FONT_XTINY,
            HijriHelpers.weekdayAbbr(g.day_of_week),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ② Upper Left Corner — 24x24 weather PNG + FONT_SMALL temp
    // ─────────────────────────────────────────────────────────────────────────

    function getWeatherIconResource(conditionCode as Number) as ResourceId {
        switch (conditionCode) {
            case 0:  // CLEAR
            case 23: // MOSTLY_CLEAR
                return Rez.Drawables.weather_sun;

            case 3:  // RAIN
            case 11: // SCATTERED_SHOWERS
            case 14: // LIGHT_RAIN
            case 15: // HEAVY_RAIN
            case 25: // LIGHT_SHOWERS
            case 26: // SHOWERS
            case 27: // HEAVY_SHOWERS
                return Rez.Drawables.weather_rain;

            case 6:  // THUNDERSTORMS
            case 12: // SCATTERED_THUNDERSTORMS
                return Rez.Drawables.weather_storm;

            default:
                return Rez.Drawables.weather_cloud;
        }
    }

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
        var iconY = 2;

        var icon = WatchUi.loadResource(getWeatherIconResource(conditionCode)) as BitmapResource;
        dc.drawBitmap(iconX, iconY, icon);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var textX = iconX + 24 + 4;
        dc.drawText(textX, 2, Graphics.FONT_SMALL, tempStr, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ③ Porthole frame & contents
    // ─────────────────────────────────────────────────────────────────────────

    function drawPortholeFrame(dc) {
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(PORTHOLE_CX, PORTHOLE_CY, PORTHOLE_R,
                   Graphics.ARC_CLOCKWISE, 90, 91);
    }

    function drawPortholeMetric(dc, cx, y, icon as BitmapResource, valueStr as String) as Void {
        var iconW  = icon.getWidth();
        var iconH  = icon.getHeight();
        var dims   = dc.getTextDimensions(valueStr, Graphics.FONT_XTINY);
        var textW  = dims[0];
        var totalW = iconW + PORTHOLE_ICON_GAP + textW;
        var leftX  = cx - totalW / 2;
        var iconY  = y - iconH / 2;

        dc.drawBitmap(leftX, iconY, icon);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            leftX + iconW + PORTHOLE_ICON_GAP,
            y,
            Graphics.FONT_XTINY,
            valueStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function drawPortholeContents(dc) {
        drawPortholeMetric(dc, PORTHOLE_CX, Y_PORTHOLE_HR, iconHeart, cachedHrDisplay);
        drawPortholeMetric(dc, PORTHOLE_CX, Y_PORTHOLE_STEPS, iconSteps, cachedSteps.toString());
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

        var gregorianLine = g.day.format("%02d") + " " +
                            HijriHelpers.gregorianMonthName(g.month) + " " +
                            g.year.toString();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_HIJRI,     Graphics.FONT_XTINY, hijriLine,     Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, Y_GREGORIAN, Graphics.FONT_XTINY, gregorianLine, Graphics.TEXT_JUSTIFY_CENTER);
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
        if (info != null && info.steps != null) {
            cachedSteps = info.steps;
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
