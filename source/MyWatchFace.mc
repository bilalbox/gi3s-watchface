// ─────────────────────────────────────────────────────────────────────────────
// MyWatchFace.mc  –  Garmin Instinct 2X / 3 Solar Optimized
//
// Layout (top → bottom):
//   Porthole      │  upper-right  →  HR (top)  ·  steps (center)  ·  numbers only
//   TIME          │  stacked HH/MM, Noto Kufi Arabic-Indic digits, cy≈64
//   Temperature   │  Arabic-Indic °م · centered under porthole
//   Weekday       │  full Arabic name bitmap · centered
//   Hijri date    │  month bitmap + day  (no year)
//   Gregorian     │  month bitmap + day  (no year)
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
import Toybox.System;
import Toybox.Weather;
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
// Clock digits — proportional Noto Kufi Arabic-Indic sprites

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

    function digitHeight() as Number {
        return digit0.getHeight();
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

    function measureTextWidth(text as String) as Number {
        var n = text.length();
        var w = 0;
        var seen = false;
        for (var i = 0; i < n; i++) {
            var d = charToDigit(text.substring(i, i + 1));
            if (d < 0) { continue; }
            var bmp = bitmapForDigit(d);
            if (bmp == null) { continue; }
            if (seen) { w += GAP; }
            w += bmp.getWidth();
            seen = true;
        }
        return w;
    }

    function drawText(dc, text as String, cx, yTop) as Void {
        var x = cx - measureTextWidth(text) / 2;
        var len = text.length();
        var seen = false;
        for (var i = 0; i < len; i++) {
            var d = charToDigit(text.substring(i, i + 1));
            if (d < 0) { continue; }
            var bmp = bitmapForDigit(d);
            if (bmp == null) { continue; }
            if (seen) { x += GAP; }
            dc.drawBitmap(x, yTop, bmp);
            x += bmp.getWidth();
            seen = true;
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
// Small Arabic-Indic glyphs — dates, porthole, temperature

// ─────────────────────────────────────────────────────────────────────────────

module SmallDigits {
    const GAP = 1;
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
    var minus = null;
    var degree = null;
    var meem = null;

    function loadDigit(d as Number, mode as Number) as BitmapResource {
        switch (d) {
            case 0: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_0, Rez.Drawables.sm_0_light, mode)) as BitmapResource;
            case 1: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_1, Rez.Drawables.sm_1_light, mode)) as BitmapResource;
            case 2: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_2, Rez.Drawables.sm_2_light, mode)) as BitmapResource;
            case 3: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_3, Rez.Drawables.sm_3_light, mode)) as BitmapResource;
            case 4: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_4, Rez.Drawables.sm_4_light, mode)) as BitmapResource;
            case 5: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_5, Rez.Drawables.sm_5_light, mode)) as BitmapResource;
            case 6: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_6, Rez.Drawables.sm_6_light, mode)) as BitmapResource;
            case 7: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_7, Rez.Drawables.sm_7_light, mode)) as BitmapResource;
            case 8: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_8, Rez.Drawables.sm_8_light, mode)) as BitmapResource;
            case 9: return WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_9, Rez.Drawables.sm_9_light, mode)) as BitmapResource;
        }
        return digit0;
    }

    function ensure(mode as Number) as Void {
        if (digit0 != null && cachedColorMode == mode) { return; }
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
        minus = WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_minus, Rez.Drawables.sm_minus_light, mode)) as BitmapResource;
        degree = WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_degree, Rez.Drawables.sm_degree_light, mode)) as BitmapResource;
        meem = WatchUi.loadResource(Theme.pickResource(Rez.Drawables.sm_meem, Rez.Drawables.sm_meem_light, mode)) as BitmapResource;
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

    function glyphHeight() as Number {
        return digit0.getHeight();
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

    function glyphForChar(ch as String) as BitmapResource or Null {
        if (ch.equals("-")) { return minus; }
        var d = charToDigit(ch);
        if (d < 0) { return null; }
        return bitmapForDigit(d);
    }

    function measureAscii(text as String) as Number {
        var n = text.length();
        var w = 0;
        var seen = false;
        for (var i = 0; i < n; i++) {
            var bmp = glyphForChar(text.substring(i, i + 1));
            if (bmp == null) { continue; }
            if (seen) { w += GAP; }
            w += bmp.getWidth();
            seen = true;
        }
        return w;
    }

    function drawAsciiLeft(dc, text as String, x, yTop) as Number {
        var n = text.length();
        var seen = false;
        for (var i = 0; i < n; i++) {
            var bmp = glyphForChar(text.substring(i, i + 1));
            if (bmp == null) { continue; }
            if (seen) { x += GAP; }
            dc.drawBitmap(x, yTop, bmp);
            x += bmp.getWidth();
            seen = true;
        }
        return x;
    }

    function drawAsciiCentered(dc, text as String, cx, yMid) as Void {
        var yTop = yMid - glyphHeight() / 2;
        drawAsciiLeft(dc, text, cx - measureAscii(text) / 2, yTop);
    }

    function blit(dc, bmp as BitmapResource, x, yMid) as Number {
        dc.drawBitmap(x, yMid - bmp.getHeight() / 2, bmp);
        return x + bmp.getWidth() + GAP;
    }

    function drawTemp(dc, celsius as Number or Null, cx, yMid) as Void {
        var numStr = "--";
        if (celsius != null) {
            numStr = (celsius as Number).format("%d");
        }
        var w = measureAscii(numStr) + GAP + degree.getWidth() + GAP + meem.getWidth();
        var x = cx - w / 2;
        x = drawAsciiLeft(dc, numStr, x, yMid - glyphHeight() / 2);
        x += GAP;
        x = blit(dc, degree, x, yMid);
        blit(dc, meem, x, yMid);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arabic month and weekday bitmaps (current values only)

// ─────────────────────────────────────────────────────────────────────────────

module ArabicLabels {
    var cachedMode = -1;
    var cachedHijriMonth = -1;
    var cachedGregMonth = -1;
    var cachedDow = -1;
    var hijriBmp = null;
    var gregBmp = null;
    var dowBmp = null;

    function hijriId(month as Number, mode as Number) as ResourceId {
        switch (month) {
            case 1:  return Theme.pickResource(Rez.Drawables.hijri_1, Rez.Drawables.hijri_1_light, mode);
            case 2:  return Theme.pickResource(Rez.Drawables.hijri_2, Rez.Drawables.hijri_2_light, mode);
            case 3:  return Theme.pickResource(Rez.Drawables.hijri_3, Rez.Drawables.hijri_3_light, mode);
            case 4:  return Theme.pickResource(Rez.Drawables.hijri_4, Rez.Drawables.hijri_4_light, mode);
            case 5:  return Theme.pickResource(Rez.Drawables.hijri_5, Rez.Drawables.hijri_5_light, mode);
            case 6:  return Theme.pickResource(Rez.Drawables.hijri_6, Rez.Drawables.hijri_6_light, mode);
            case 7:  return Theme.pickResource(Rez.Drawables.hijri_7, Rez.Drawables.hijri_7_light, mode);
            case 8:  return Theme.pickResource(Rez.Drawables.hijri_8, Rez.Drawables.hijri_8_light, mode);
            case 9:  return Theme.pickResource(Rez.Drawables.hijri_9, Rez.Drawables.hijri_9_light, mode);
            case 10: return Theme.pickResource(Rez.Drawables.hijri_10, Rez.Drawables.hijri_10_light, mode);
            case 11: return Theme.pickResource(Rez.Drawables.hijri_11, Rez.Drawables.hijri_11_light, mode);
            default: return Theme.pickResource(Rez.Drawables.hijri_12, Rez.Drawables.hijri_12_light, mode);
        }
    }

    function gregId(month as Number, mode as Number) as ResourceId {
        switch (month) {
            case 1:  return Theme.pickResource(Rez.Drawables.greg_1, Rez.Drawables.greg_1_light, mode);
            case 2:  return Theme.pickResource(Rez.Drawables.greg_2, Rez.Drawables.greg_2_light, mode);
            case 3:  return Theme.pickResource(Rez.Drawables.greg_3, Rez.Drawables.greg_3_light, mode);
            case 4:  return Theme.pickResource(Rez.Drawables.greg_4, Rez.Drawables.greg_4_light, mode);
            case 5:  return Theme.pickResource(Rez.Drawables.greg_5, Rez.Drawables.greg_5_light, mode);
            case 6:  return Theme.pickResource(Rez.Drawables.greg_6, Rez.Drawables.greg_6_light, mode);
            case 7:  return Theme.pickResource(Rez.Drawables.greg_7, Rez.Drawables.greg_7_light, mode);
            case 8:  return Theme.pickResource(Rez.Drawables.greg_8, Rez.Drawables.greg_8_light, mode);
            case 9:  return Theme.pickResource(Rez.Drawables.greg_9, Rez.Drawables.greg_9_light, mode);
            case 10: return Theme.pickResource(Rez.Drawables.greg_10, Rez.Drawables.greg_10_light, mode);
            case 11: return Theme.pickResource(Rez.Drawables.greg_11, Rez.Drawables.greg_11_light, mode);
            default: return Theme.pickResource(Rez.Drawables.greg_12, Rez.Drawables.greg_12_light, mode);
        }
    }

    function dowId(dayOfWeek as Number, mode as Number) as ResourceId {
        switch (dayOfWeek) {
            case 1: return Theme.pickResource(Rez.Drawables.dow_1, Rez.Drawables.dow_1_light, mode);
            case 2: return Theme.pickResource(Rez.Drawables.dow_2, Rez.Drawables.dow_2_light, mode);
            case 3: return Theme.pickResource(Rez.Drawables.dow_3, Rez.Drawables.dow_3_light, mode);
            case 4: return Theme.pickResource(Rez.Drawables.dow_4, Rez.Drawables.dow_4_light, mode);
            case 5: return Theme.pickResource(Rez.Drawables.dow_5, Rez.Drawables.dow_5_light, mode);
            case 6: return Theme.pickResource(Rez.Drawables.dow_6, Rez.Drawables.dow_6_light, mode);
            default: return Theme.pickResource(Rez.Drawables.dow_7, Rez.Drawables.dow_7_light, mode);
        }
    }

    function ensure(hijriMonth as Number, gregMonth as Number, dayOfWeek as Number, mode as Number) as Void {
        if (cachedMode != mode) {
            hijriBmp = null;
            gregBmp = null;
            dowBmp = null;
            cachedHijriMonth = -1;
            cachedGregMonth = -1;
            cachedDow = -1;
            cachedMode = mode;
        }
        if (hijriBmp == null || cachedHijriMonth != hijriMonth) {
            hijriBmp = WatchUi.loadResource(hijriId(hijriMonth, mode)) as BitmapResource;
            cachedHijriMonth = hijriMonth;
        }
        if (gregBmp == null || cachedGregMonth != gregMonth) {
            gregBmp = WatchUi.loadResource(gregId(gregMonth, mode)) as BitmapResource;
            cachedGregMonth = gregMonth;
        }
        if (dowBmp == null || cachedDow != dayOfWeek) {
            dowBmp = WatchUi.loadResource(dowId(dayOfWeek, mode)) as BitmapResource;
            cachedDow = dayOfWeek;
        }
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
    var loadedAssetColorMode = -1;
    // Porthole layout
    const PORTHOLE_CX = 144;
    const Y_PORTHOLE_HR = 20;
    const Y_PORTHOLE_STEPS = 44;
    const Y_PORTHOLE_BOTTOM = 70;
    // Vertical layout constants (pixels from top of 176 px display)
    const CY_TIME         = 64;
    const TIME_STACK_GAP  = 4;
    const TIME_CX_OFFSET  = -26;
    const Y_TEMP          = 92;
    const Y_WEEKDAY       = 116;
    const Y_HIJRI         = 138;
    const Y_GREGORIAN     = 156;
    const DATE_MONTH_GAP  = 6;
    const Y_BATTERY_BAR = 172;
    const H_BATTERY_BAR = 4;
    const X_BODY_BATTERY_BAR = 4;
    const W_BODY_BATTERY_BAR = 4;
    const MIN_BB_FILL_PX = 5;
    const DEBUG_BODY_BATTERY = -1; // hardcoded % for layout debug; set to -1 for live data

    function initialize() {
        WatchFace.initialize();
        timer = new Timer.Timer();
    }

    function ensureThemeAssets(mode as Number) as Void {
        ClockDigits.ensure(mode);
        SmallDigits.ensure(mode);
        loadedAssetColorMode = mode;
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
        drawTemperature(dc);
        drawPortholeContents(dc);
        drawWeekday(dc, mode);
        drawCenterDates(dc, mode);
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
    // ② Temperature under porthole

    // ─────────────────────────────────────────────────────────────────────────

    function drawTemperature(dc) {
        var celsius = null;
        if (Toybox has :Weather && cachedConditions != null && cachedConditions.temperature != null) {
            celsius = cachedConditions.temperature.toFloat().toNumber();
        }
        SmallDigits.drawTemp(dc, celsius, PORTHOLE_CX, Y_TEMP);
    }

    function drawWeekday(dc, mode as Number) {
        var g = cachedGregorianInfo;
        if (g == null) { g = Gregorian.info(Time.now(), Time.FORMAT_SHORT); }
        var hijri = HijriHelpers.gregorianToHijri(g.year, g.month, g.day, getHijriDayOffset());
        ArabicLabels.ensure(
            hijri[:month].toNumber(),
            g.month,
            g.day_of_week,
            mode
        );
        var bmp = ArabicLabels.dowBmp;
        if (bmp == null) { return; }
        dc.drawBitmap(
            dc.getWidth() / 2 - bmp.getWidth() / 2,
            Y_WEEKDAY - bmp.getHeight() / 2,
            bmp
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ③ Porthole contents — position is the legend (HR top, steps below)

    // ─────────────────────────────────────────────────────────────────────────

    function drawPortholeContents(dc) {
        SmallDigits.drawAsciiCentered(dc, cachedHrDisplay, PORTHOLE_CX, Y_PORTHOLE_HR);
        SmallDigits.drawAsciiCentered(dc, cachedSteps.toString(), PORTHOLE_CX, Y_PORTHOLE_STEPS);
    }

    function drawDateRow(dc, monthBmp as BitmapResource, dayStr as String, cx, yMid) as Void {
        var dayW = SmallDigits.measureAscii(dayStr);
        var dayH = SmallDigits.glyphHeight();
        var mw = monthBmp.getWidth();
        var mh = monthBmp.getHeight();
        var total = mw + DATE_MONTH_GAP + dayW;
        var x = cx - total / 2;
        dc.drawBitmap(x, yMid - mh / 2, monthBmp);
        SmallDigits.drawAsciiLeft(dc, dayStr, x + mw + DATE_MONTH_GAP, yMid - dayH / 2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ④ Center column below time

    // ─────────────────────────────────────────────────────────────────────────

    function drawCenterDates(dc, mode as Number) {
        var cx = dc.getWidth() / 2;
        var g = cachedGregorianInfo;
        if (g == null) { g = Gregorian.info(Time.now(), Time.FORMAT_SHORT); }
        var hijri = HijriHelpers.gregorianToHijri(g.year, g.month, g.day, getHijriDayOffset());
        ArabicLabels.ensure(
            hijri[:month].toNumber(),
            g.month,
            g.day_of_week,
            mode
        );
        if (ArabicLabels.hijriBmp != null) {
            drawDateRow(dc, ArabicLabels.hijriBmp, hijri[:day].toNumber().format("%02d"), cx, Y_HIJRI);
        }
        if (ArabicLabels.gregBmp != null) {
            drawDateRow(dc, ArabicLabels.gregBmp, g.day.format("%02d"), cx, Y_GREGORIAN);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ⑤ Body battery bar (left edge)

    // ─────────────────────────────────────────────────────────────────────────

    function drawBodyBatteryBar(dc, fg as Number, accent as Number) {
        var barH = Y_BATTERY_BAR;
        var bbValue = null;
        if (DEBUG_BODY_BATTERY >= 0) {
            bbValue = DEBUG_BODY_BATTERY;
        } else if (cachedBodyBattery != null) {
            bbValue = cachedBodyBattery;
        }
        dc.setPenWidth(1);
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(X_BODY_BATTERY_BAR, 0, W_BODY_BATTERY_BAR, barH);
        if (bbValue != null && bbValue > 0) {
            var fillH = (barH.toFloat() * bbValue.toFloat() / 100.0).toNumber();
            if (fillH < MIN_BB_FILL_PX) {
                fillH = MIN_BB_FILL_PX;
            }
            if (fillH > barH) {
                fillH = barH;
            }
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
