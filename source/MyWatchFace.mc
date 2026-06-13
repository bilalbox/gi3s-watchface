// ─────────────────────────────────────────────────────────────────────────────
// MyWatchFace.mc  –  Garmin Instinct 2X / 3 Solar Optimized
//
// Layout (top → bottom):
//   Porthole ring │  cx=143 cy=40 r=30  →  HR (top)  ·  steps (center)
//   TIME          │  stacked HH/MM, Black Ops One bitmap digits (32×42), cy≈74
//   Weather       │  [24×24 icon] + temp · centered under porthole · y≈90
//   Sun / DOW row │  "06:00 FRI 18:00" · FONT_XTINY · centered · y≈110
//   Hijri date    │  "DD MONTHNAME YYYY"  (month ≤ 7 chars)  centered
//   Gregorian     │  "DD MMM YYYY"  centered
//   Battery bar   │  4 px tall · fills from left · proportional to battery %
//   Body battery  │  4 px wide · left inset · fills bottom-up · 0–100 %
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
// Color theme (property colorMode: 0 = dark, 1 = light)
// ─────────────────────────────────────────────────────────────────────────────

module Theme {

    const MODE_DARK  = 0;
    const MODE_LIGHT = 1;

    function getColorMode() as Number {
        var raw = Properties.getValue("colorMode");
        if (raw instanceof Number && (raw as Number) == MODE_LIGHT) {
            return MODE_LIGHT;
        }
        return MODE_DARK;
    }

    function pickResource(darkId, lightId, mode as Number) as ResourceId {
        return (mode == MODE_LIGHT) ? lightId : darkId;
    }

    function backgroundForMode(mode as Number) as Number {
        return (mode == MODE_LIGHT) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
    }

    function foregroundForMode(mode as Number) as Number {
        return (mode == MODE_LIGHT) ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
    }

    function accentForMode(mode as Number) as Number {
        return (mode == MODE_LIGHT) ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Clock digits — per-digit Black Ops One bitmap sprites (32×42 px)
// ─────────────────────────────────────────────────────────────────────────────
module ClockDigits {

    const GAP = 2;   // px between digit cells

    var cachedColorMode = -1;

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

    function loadDigit(d as Number, mode as Number) as BitmapResource {
        switch (d) {
            case 0:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_0, Rez.Drawables.digit_0_light, mode)
                ) as BitmapResource;
            case 1:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_1, Rez.Drawables.digit_1_light, mode)
                ) as BitmapResource;
            case 2:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_2, Rez.Drawables.digit_2_light, mode)
                ) as BitmapResource;
            case 3:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_3, Rez.Drawables.digit_3_light, mode)
                ) as BitmapResource;
            case 4:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_4, Rez.Drawables.digit_4_light, mode)
                ) as BitmapResource;
            case 5:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_5, Rez.Drawables.digit_5_light, mode)
                ) as BitmapResource;
            case 6:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_6, Rez.Drawables.digit_6_light, mode)
                ) as BitmapResource;
            case 7:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_7, Rez.Drawables.digit_7_light, mode)
                ) as BitmapResource;
            case 8:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_8, Rez.Drawables.digit_8_light, mode)
                ) as BitmapResource;
            case 9:
                return WatchUi.loadResource(
                    Theme.pickResource(Rez.Drawables.digit_9, Rez.Drawables.digit_9_light, mode)
                ) as BitmapResource;
        }
        return digit0;
    }

    function ensure(mode as Number) as Void {
        if (digit0 != null && cachedColorMode == mode) {
            return;
        }
        cachedColorMode = mode;
        digit0 = loadDigit(0, mode);
        digit1 = loadDigit(1, mode);
        digit2 = loadDigit(2, mode);
        digit3 = loadDigit(3, mode);
        digit4 = loadDigit(4, mode);
        digit5 = loadDigit(5, mode);
        digit6 = loadDigit(6, mode);
        digit7 = loadDigit(7, mode);
        digit8 = loadDigit(8, mode);
        digit9 = loadDigit(9, mode);
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
        return digit0.getWidth();
    }

    function digitHeight() as Number {
        return digit0.getHeight();
    }

    function measureTextWidth(text as String) as Number {
        var n = text.length();
        if (n <= 0) { return 0; }
        return n * digitWidth() + (n - 1) * GAP;
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
        var totalW = measureTextWidth(text);
        var x = cx - totalW / 2;
        var step = digitWidth() + GAP;
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

    function formatHm(moment) as String {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return info.hour.format("%02d") + ":" + info.min.format("%02d");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings menus – root, Hijri offset, color theme
// ─────────────────────────────────────────────────────────────────────────────

class WatchfaceSettingsMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => "Watch face settings" });
        addItem(new WatchUi.MenuItem("Hijri date shift", null, 0, {}));
        addItem(new WatchUi.MenuItem("Color theme", null, 1, {}));
    }
}

class WatchfaceSettingsDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(menuItem as MenuItem) as Void {
        var rawId = menuItem.getId();
        if (!(rawId instanceof Number)) { return; }
        var id = rawId as Number;
        if (id == 0) {
            WatchUi.pushView(
                new HijriOffsetSettingsMenu(),
                new HijriOffsetMenuDelegate(),
                WatchUi.SLIDE_LEFT
            );
        } else if (id == 1) {
            WatchUi.pushView(
                new ColorThemeSettingsMenu(),
                new ColorThemeMenuDelegate(),
                WatchUi.SLIDE_LEFT
            );
        }
    }
}

class ColorThemeSettingsMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => "Color theme" });
        addItem(new WatchUi.MenuItem("Dark", "Default", 0, {}));
        addItem(new WatchUi.MenuItem("Light", "", 1, {}));
    }
}

class ColorThemeMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(menuItem as MenuItem) as Void {
        var rawId = menuItem.getId();
        if (!(rawId instanceof Number)) { return; }
        Properties.setValue("colorMode", rawId as Number);
        WatchUi.requestUpdate();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

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
        return [ new WatchfaceSettingsMenu(), new WatchfaceSettingsDelegate() ];
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
    var cachedBodyBattery = null;

    var cachedGregorianInfo = null;
    var cachedSunrise = null;
    var cachedSunset  = null;
    var iconHeart = null;
    var iconSteps = null;
    var cachedWeatherIcon = null;
    var cachedWeatherKey = -1;
    var loadedAssetColorMode = -1;

    // Porthole geometry
    const PORTHOLE_CX = 143;
    const PORTHOLE_CY = 40;
    const PORTHOLE_R  = 30;
    const PORTHOLE_ICON_GAP = 2;
    const Y_PORTHOLE_HR     = PORTHOLE_CY - 20;
    const Y_PORTHOLE_STEPS  = PORTHOLE_CY;
    const Y_PORTHOLE_BOTTOM = PORTHOLE_CY + PORTHOLE_R;

    // Vertical layout constants (pixels from top of 176 px display)
    const CY_TIME         = 64;
    const TIME_STACK_GAP  = 4;
    const TIME_CX_OFFSET  = -26;
    const Y_SUN_ROW       = 114;
    const Y_HIJRI         = 132;
    const Y_GREGORIAN     = 150;
    const Y_BATTERY_BAR = 172;
    const H_BATTERY_BAR = 4;
    const X_BODY_BATTERY_BAR = 4;
    const W_BODY_BATTERY_BAR = 4;
    const DEBUG_BODY_BATTERY = -1; // hardcoded % for layout debug; set to -1 for live data

    function initialize() {
        WatchFace.initialize();
        timer = new Timer.Timer();
    }

    function reloadThemedBitmaps(mode as Number) as Void {
        iconHeart = WatchUi.loadResource(
            Theme.pickResource(Rez.Drawables.icon_heart, Rez.Drawables.icon_heart_light, mode)
        ) as BitmapResource;
        iconSteps = WatchUi.loadResource(
            Theme.pickResource(Rez.Drawables.icon_steps, Rez.Drawables.icon_steps_light, mode)
        ) as BitmapResource;
        cachedWeatherIcon = null;
        cachedWeatherKey = -1;
        loadedAssetColorMode = mode;
    }

    function ensureThemeAssets(mode as Number) as Void {
        ClockDigits.ensure(mode);
        if (loadedAssetColorMode != mode) {
            reloadThemedBitmaps(mode);
        }
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
            if (Weather has :getSunrise && cachedConditions != null) {
                var pos = cachedConditions.observationLocationPosition;
                if (pos != null) {
                    var today = Time.now();
                    cachedSunrise = Weather.getSunrise(pos, today);
                    cachedSunset  = Weather.getSunset(pos, today);
                }
            }
        }

        updateActivityData();
        refreshCachedHeartRate();
        refreshCachedBodyBattery();
        WatchUi.requestUpdate();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Main draw (once per minute via onMinuteUiTick)
    // ─────────────────────────────────────────────────────────────────────────

    function onUpdate(dc) {
        var mode = Theme.getColorMode();
        ensureThemeAssets(mode);
        var bg = Theme.backgroundForMode(mode);
        var fg = Theme.foregroundForMode(mode);
        var accent = Theme.accentForMode(mode);

        dc.setColor(bg, bg);
        dc.clear();
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);

        drawTime(dc);
        drawWeatherByPorthole(dc, mode, fg);
        drawPortholeFrame(dc, accent);
        drawPortholeContents(dc, fg);
        drawSunDayRow(dc, fg);
        drawCenterDates(dc, fg);
        drawBodyBatteryBar(dc, fg, accent);
        drawBatteryBar(dc, fg, accent);
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

    // ─────────────────────────────────────────────────────────────────────────
    // ② Weather under porthole — 24×24 icon + FONT_TINY temp
    // ─────────────────────────────────────────────────────────────────────────

    function getWeatherIconResource(conditionCode as Number, mode as Number) as ResourceId {
        switch (conditionCode) {
            case 0:  // CLEAR
            case 22: // PARTLY_CLEAR
            case 23: // MOSTLY_CLEAR
            case 40: // FAIR
                return Theme.pickResource(
                    Rez.Drawables.weather_clear, Rez.Drawables.weather_clear_light, mode
                );

            case 1:  // PARTLY_CLOUDY
            case 2:  // MOSTLY_CLOUDY
            case 52: // THIN_CLOUDS
                return Theme.pickResource(
                    Rez.Drawables.weather_partly_cloudy, Rez.Drawables.weather_partly_cloudy_light, mode
                );

            case 5:  // WINDY
            case 36: // SQUALL
                return Theme.pickResource(
                    Rez.Drawables.weather_wind, Rez.Drawables.weather_wind_light, mode
                );

            case 3:  // RAIN
            case 11: // SCATTERED_SHOWERS
            case 13: // FREEZING_RAIN
            case 14: // LIGHT_RAIN
            case 15: // HEAVY_RAIN
            case 24: // FREEZING_DRIZZLE
            case 25: // LIGHT_SHOWERS
            case 26: // SHOWERS
            case 27: // HEAVY_SHOWERS
            case 31: // DRIZZLE
            case 45: // RAIN_AND_SNOW
            case 49: // SLEET
                return Theme.pickResource(
                    Rez.Drawables.weather_rain, Rez.Drawables.weather_rain_light, mode
                );

            case 6:  // THUNDERSTORMS
            case 10: // HAIL
            case 12: // SCATTERED_THUNDERSTORMS
            case 28: // THUNDERSTORM
            case 32: // TORNADO
            case 38: // VOLCANIC_ASH
            case 41: // HURRICANE
            case 42: // TROPICAL_STORM
                return Theme.pickResource(
                    Rez.Drawables.weather_storm, Rez.Drawables.weather_storm_light, mode
                );

            case 4:  // SNOW
            case 7:  // WINTRY_MIX
            case 16: // LIGHT_SNOW
            case 17: // HEAVY_SNOW
            case 18: // SCATTERED_SNOW
            case 19: // HEAVY_SCATTERED_SNOW
            case 21: // SNOW_AND_RAIN
            case 34: // ICE
            case 43: // BLIZZARD
            case 44: // SCATTERED_SNOW_SHOWERS
            case 46: // SNOW_SHOWERS
            case 47: // HEAVY_SNOW_SHOWERS
            case 48: // FLURRIES
            case 50: // SCATTERED_FLURRIES
            case 51: // HEAVY_SCATTERED_FLURRIES
                return Theme.pickResource(
                    Rez.Drawables.weather_snow, Rez.Drawables.weather_snow_light, mode
                );

            case 8:  // FOG
            case 9:  // HAZY
            case 20: // CLOUDY
            case 29: // MIST
            case 30: // DUST
            case 33: // SMOKE
            case 35: // SAND
            case 37: // SANDSTORM
            case 39: // HAZE
            case 53: // UNKNOWN
            default:
                return Theme.pickResource(
                    Rez.Drawables.weather_cloudy, Rez.Drawables.weather_cloudy_light, mode
                );
        }
    }

    function getCachedWeatherIcon(conditionCode as Number, mode as Number) as BitmapResource {
        var key = mode * 1000 + conditionCode;
        if (cachedWeatherIcon != null && cachedWeatherKey == key) {
            return cachedWeatherIcon;
        }
        cachedWeatherIcon = WatchUi.loadResource(
            getWeatherIconResource(conditionCode, mode)
        ) as BitmapResource;
        cachedWeatherKey = key;
        return cachedWeatherIcon;
    }

    function drawWeatherByPorthole(dc, mode as Number, fg as Number) {
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

        var icon = getCachedWeatherIcon(conditionCode, mode);
        var iconW = icon.getWidth();
        var iconH = icon.getHeight();
        var dims = dc.getTextDimensions(tempStr, Graphics.FONT_TINY);
        var textW = dims[0];
        var gap = 4;
        var totalW = iconW + gap + textW;
        var leftX = PORTHOLE_CX - totalW / 2;
        var cy = (Y_PORTHOLE_BOTTOM + Y_SUN_ROW) / 2;

        dc.drawBitmap(leftX, cy - iconH / 2, icon);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            leftX + iconW + gap,
            cy,
            Graphics.FONT_TINY,
            tempStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function drawSunDayRow(dc, fg as Number) {
        var g = cachedGregorianInfo;
        if (g == null) { g = Gregorian.info(Time.now(), Time.FORMAT_SHORT); }

        var sunriseStr = "--:--";
        var sunsetStr  = "--:--";
        if (cachedSunrise != null) {
            sunriseStr = TimeHelpers.formatHm(cachedSunrise);
        }
        if (cachedSunset != null) {
            sunsetStr = TimeHelpers.formatHm(cachedSunset);
        }

        var line = sunriseStr + " " +
                   HijriHelpers.weekdayAbbr(g.day_of_week) + " " +
                   sunsetStr;

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2,
            Y_SUN_ROW,
            Graphics.FONT_XTINY,
            line,
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ③ Porthole frame & contents
    // ─────────────────────────────────────────────────────────────────────────

    function drawPortholeFrame(dc, accent as Number) {
        dc.setPenWidth(2);
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(PORTHOLE_CX, PORTHOLE_CY, PORTHOLE_R,
                   Graphics.ARC_CLOCKWISE, 90, 91);
    }

    function drawPortholeMetric(dc, cx, y, icon as BitmapResource, valueStr as String, fg as Number) as Void {
        var iconW  = icon.getWidth();
        var iconH  = icon.getHeight();
        var dims   = dc.getTextDimensions(valueStr, Graphics.FONT_XTINY);
        var textW  = dims[0];
        var totalW = iconW + PORTHOLE_ICON_GAP + textW;
        var leftX  = cx - totalW / 2;
        var iconY  = y - iconH / 2;

        dc.drawBitmap(leftX, iconY, icon);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            leftX + iconW + PORTHOLE_ICON_GAP,
            y,
            Graphics.FONT_XTINY,
            valueStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function drawPortholeContents(dc, fg as Number) {
        drawPortholeMetric(dc, PORTHOLE_CX, Y_PORTHOLE_HR, iconHeart, cachedHrDisplay, fg);
        drawPortholeMetric(dc, PORTHOLE_CX, Y_PORTHOLE_STEPS, iconSteps, cachedSteps.toString(), fg);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ④ Center column below time
    // ─────────────────────────────────────────────────────────────────────────

    function drawCenterDates(dc, fg as Number) {
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

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, Y_HIJRI,     Graphics.FONT_XTINY, hijriLine,     Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, Y_GREGORIAN, Graphics.FONT_XTINY, gregorianLine, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ⑤ Body battery bar (left edge)
    // ─────────────────────────────────────────────────────────────────────────

    function drawBodyBatteryBar(dc, fg as Number, accent as Number) {
        var barH = Y_BATTERY_BAR;
        var pct  = 0.0;
        if (DEBUG_BODY_BATTERY >= 0) {
            pct = DEBUG_BODY_BATTERY.toFloat() / 100.0;
        } else if (cachedBodyBattery != null) {
            pct = cachedBodyBattery.toFloat() / 100.0;
        }
        var fillH = (barH.toFloat() * pct).toNumber();

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(X_BODY_BATTERY_BAR, 0, W_BODY_BATTERY_BAR, barH);

        if (fillH > 0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(X_BODY_BATTERY_BAR, barH - fillH, W_BODY_BATTERY_BAR, fillH);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ⑥ Battery bar
    // ─────────────────────────────────────────────────────────────────────────

    function drawBatteryBar(dc, fg as Number, accent as Number) {
        var w = dc.getWidth();
        var pct = 0.0;
        if (cachedSystemStats != null) {
            pct = cachedSystemStats.battery.toFloat() / 100.0;
        }
        var fillW = (w.toFloat() * pct).toNumber();

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, Y_BATTERY_BAR, w, H_BATTERY_BAR);

        if (fillW > 0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
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

    function readBodyBatteryFromIterator(iter) as Number or Null {
        if (iter == null) {
            return null;
        }

        var sample = iter.next();
        while (sample != null) {
            if (sample.data != null) {
                var bb = sample.data;
                var n  = (bb instanceof Float) ? (bb as Float).toNumber() : bb.toNumber();
                if (n >= 0 && n <= 100) {
                    return n;
                }
            }
            sample = iter.next();
        }
        return null;
    }

    function refreshCachedBodyBattery() as Void {
        if (DEBUG_BODY_BATTERY >= 0) {
            return;
        }

        cachedBodyBattery = null;
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getBodyBatteryHistory)) {
            return;
        }

        var bb = readBodyBatteryFromIterator(SensorHistory.getBodyBatteryHistory({
            :period => 1,
            :order  => SensorHistory.ORDER_NEWEST_FIRST
        }));

        if (bb == null) {
            bb = readBodyBatteryFromIterator(SensorHistory.getBodyBatteryHistory({}));
        }

        cachedBodyBattery = bb;
    }
}
