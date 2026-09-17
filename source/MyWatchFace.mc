// ─────────────────────────────────────────────────────────────────────────────
// MyWatchFace.mc  –  Garmin Instinct 3 Solar 45 mm
//
// Layout A (top → bottom), 176×176 semi-octagon:
//   Header  y=15…70   │  left: weekday + Gregorian date; porthole: weather + temp
//   Divider y=75…85   │  Hijri month + day, centred (the long row; uses gutters)
//   Time    y=90…135  │  single-row HH:MM, tabular Arabic-Indic, centred
//   Shelf   y=140…168 │  steps + body battery, then a slim battery gauge
//
// Panel geometry (measured, not assumed):
//   The display is a 176×176 *semi-octagon*, not a circle. Corners are rounded
//   chamfers, so the usable span narrows sharply toward the top and bottom.
//   The top-right corner is the hardware porthole, so that chamfer is not cut.
//     · At y=172 only x 38–137 is on-panel, and y=175 does not exist at all.
//       A bar drawn 0…175 is invisible below 22 % and saturated above 78 %.
//     · Gregorian sits in the header because even أغسطس + day is ~76 px and
//       clears the porthole. Hijri (up to ~125 px) uses the full divider span.
//
// Digit tiers are *tabular*: every glyph in a set shares one cell width, so a
// multi-digit string never changes width as its value changes.
// ─────────────────────────────────────────────────────────────────────────────

import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Time.Gregorian;
import Toybox.Lang;
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

    // NOTE: this panel is 1 bpp - its palette is black and white only. Any grey
    // snaps to one of the two, so a "grey track" for the gauge would render as
    // either invisible (dark theme) or solid (light theme). The battery bar
    // therefore draws a foreground outline as its track and fills inside it.
}

// ─────────────────────────────────────────────────────────────────────────────
// GlyphSet — one tabular sprite tier
//
// Slots 0-9 are the digits and always share a cell width. Slots 10+ are optional
// symbols that keep their natural width. Callers address symbols through ASCII
// stand-ins so no source file needs non-ASCII string literals:
//     '-' → minus     '*' → degree     'm' → meem
// ─────────────────────────────────────────────────────────────────────────────

const G_MINUS  = 10;
const G_DEGREE = 11;
const G_MEEM   = 12;

class GlyphSet {
    private var _darkIds as Array<ResourceId>;
    private var _lightIds as Array<ResourceId>;
    private var _bmps as Array<BitmapResource> or Null;
    private var _mode as Number;
    private var _gap as Number;

    function initialize(darkIds as Array<ResourceId>, lightIds as Array<ResourceId>, gap as Number) {
        _darkIds  = darkIds;
        _lightIds = lightIds;
        _gap      = gap;
        _bmps     = null;
        _mode     = -1;
    }

    // Lazy: a tier costs nothing until something actually draws with it.
    function ensure(mode as Number) as Void {
        if (_bmps != null && _mode == mode) {
            return;
        }
        _mode = mode;
        var src = (mode == Theme.MODE_LIGHT) ? _lightIds : _darkIds;
        var n = src.size();
        var b = new Array<BitmapResource>[n];
        for (var i = 0; i < n; i++) {
            b[i] = WatchUi.loadResource(src[i]) as BitmapResource;
        }
        _bmps = b;
    }

    function at(idx as Number) as BitmapResource or Null {
        var b = _bmps;
        if (b == null || idx < 0 || idx >= b.size()) {
            return null;
        }
        return b[idx];
    }

    function cellWidth() as Number {
        var b = at(0);
        return (b == null) ? 0 : b.getWidth();
    }

    function cellHeight() as Number {
        var b = at(0);
        return (b == null) ? 0 : b.getHeight();
    }

    function indexForChar(ch as String) as Number {
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
        if (ch.equals("-")) { return G_MINUS; }
        if (ch.equals("*")) { return G_DEGREE; }
        if (ch.equals("m")) { return G_MEEM; }
        return -1;
    }

    function measure(text as String) as Number {
        var n = text.length();
        var w = 0;
        var seen = false;
        for (var i = 0; i < n; i++) {
            var bmp = at(indexForChar(text.substring(i, i + 1)));
            if (bmp == null) { continue; }
            if (seen) { w += _gap; }
            w += bmp.getWidth();
            seen = true;
        }
        return w;
    }

    function drawLeft(dc, text as String, x as Number, yTop as Number) as Number {
        var n = text.length();
        var seen = false;
        for (var i = 0; i < n; i++) {
            var bmp = at(indexForChar(text.substring(i, i + 1)));
            if (bmp == null) { continue; }
            if (seen) { x += _gap; }
            dc.drawBitmap(x, yTop, bmp);
            x += bmp.getWidth();
            seen = true;
        }
        return x;
    }

    function drawCentered(dc, text as String, cx as Number, yMid as Number) as Void {
        drawLeft(dc, text, cx - measure(text) / 2, yMid - cellHeight() / 2);
    }

    // Right-aligned: used for the date rows, where the shared seam is the anchor.
    function drawRight(dc, text as String, xRight as Number, yMid as Number) as Void {
        drawLeft(dc, text, xRight - measure(text), yMid - cellHeight() / 2);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The four tiers
//   clock : inline HH:MM               sm : Hijri day
//   md    : shelf steps, temperature    xs : Gregorian day, 5-digit steps
// ─────────────────────────────────────────────────────────────────────────────

module Glyphs {
    var clock = null;
    var sm    = null;
    var md    = null;
    var xs    = null;
    const COLON_W   = 6;
    const COLON_DOT = 4;

    function build() as Void {
        clock = new GlyphSet(
            [Rez.Drawables.digit_0, Rez.Drawables.digit_1, Rez.Drawables.digit_2,
             Rez.Drawables.digit_3, Rez.Drawables.digit_4, Rez.Drawables.digit_5,
             Rez.Drawables.digit_6, Rez.Drawables.digit_7, Rez.Drawables.digit_8,
             Rez.Drawables.digit_9],
            [Rez.Drawables.digit_0_light, Rez.Drawables.digit_1_light, Rez.Drawables.digit_2_light,
             Rez.Drawables.digit_3_light, Rez.Drawables.digit_4_light, Rez.Drawables.digit_5_light,
             Rez.Drawables.digit_6_light, Rez.Drawables.digit_7_light, Rez.Drawables.digit_8_light,
             Rez.Drawables.digit_9_light],
            2);

        sm = new GlyphSet(
            [Rez.Drawables.sm_0, Rez.Drawables.sm_1, Rez.Drawables.sm_2, Rez.Drawables.sm_3,
             Rez.Drawables.sm_4, Rez.Drawables.sm_5, Rez.Drawables.sm_6, Rez.Drawables.sm_7,
             Rez.Drawables.sm_8, Rez.Drawables.sm_9],
            [Rez.Drawables.sm_0_light, Rez.Drawables.sm_1_light, Rez.Drawables.sm_2_light,
             Rez.Drawables.sm_3_light, Rez.Drawables.sm_4_light, Rez.Drawables.sm_5_light,
             Rez.Drawables.sm_6_light, Rez.Drawables.sm_7_light, Rez.Drawables.sm_8_light,
             Rez.Drawables.sm_9_light],
            0);

        md = new GlyphSet(
            [Rez.Drawables.md_0, Rez.Drawables.md_1, Rez.Drawables.md_2, Rez.Drawables.md_3,
             Rez.Drawables.md_4, Rez.Drawables.md_5, Rez.Drawables.md_6, Rez.Drawables.md_7,
             Rez.Drawables.md_8, Rez.Drawables.md_9,
             Rez.Drawables.md_minus, Rez.Drawables.md_degree, Rez.Drawables.md_meem],
            [Rez.Drawables.md_0_light, Rez.Drawables.md_1_light, Rez.Drawables.md_2_light,
             Rez.Drawables.md_3_light, Rez.Drawables.md_4_light, Rez.Drawables.md_5_light,
             Rez.Drawables.md_6_light, Rez.Drawables.md_7_light, Rez.Drawables.md_8_light,
             Rez.Drawables.md_9_light,
             Rez.Drawables.md_minus_light, Rez.Drawables.md_degree_light,
             Rez.Drawables.md_meem_light],
            1);

        xs = new GlyphSet(
            [Rez.Drawables.xs_0, Rez.Drawables.xs_1, Rez.Drawables.xs_2, Rez.Drawables.xs_3,
             Rez.Drawables.xs_4, Rez.Drawables.xs_5, Rez.Drawables.xs_6, Rez.Drawables.xs_7,
             Rez.Drawables.xs_8, Rez.Drawables.xs_9],
            [Rez.Drawables.xs_0_light, Rez.Drawables.xs_1_light, Rez.Drawables.xs_2_light,
             Rez.Drawables.xs_3_light, Rez.Drawables.xs_4_light, Rez.Drawables.xs_5_light,
             Rez.Drawables.xs_6_light, Rez.Drawables.xs_7_light, Rez.Drawables.xs_8_light,
             Rez.Drawables.xs_9_light],
            0);
    }

    function ensureAll(mode as Number) as Void {
        if (clock == null) {
            build();
        }
        clock.ensure(mode);
        sm.ensure(mode);
        md.ensure(mode);
        xs.ensure(mode);
    }

    // Single-row 24 h time. Colon is two filled squares — there is no colon sprite.
    function drawInline24h(dc, hourStr as String, minStr as String,
                           cx as Number, yTop as Number) as Void {
        var gap    = 2;
        var hhW    = clock.measure(hourStr);
        var mmW    = clock.measure(minStr);
        var total  = hhW + gap + COLON_W + gap + mmW;
        var x      = cx - total / 2;
        var rowH   = clock.cellHeight();
        clock.drawLeft(dc, hourStr, x, yTop);
        var colX = x + hhW + gap;
        var dotX = colX + (COLON_W - COLON_DOT) / 2;
        dc.fillRectangle(dotX, yTop + 10, COLON_DOT, COLON_DOT);
        dc.fillRectangle(dotX, yTop + rowH - 10 - COLON_DOT, COLON_DOT, COLON_DOT);
        clock.drawLeft(dc, minStr, colX + COLON_W + gap, yTop);
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
    var lastWeatherFetchTime     = 0;
    var cachedConditions         = null;
    const WEATHER_UPDATE_INTERVAL = 15 * 60;
    var lastSystemStatsFetchTime = 0;
    var cachedSystemStats        = null;
    const SYSTEM_STATS_UPDATE_INTERVAL = 5 * 60;
    var cachedSteps = 0;
    var cachedBodyBattery = null;
    var cachedGregorianInfo = null;

    // Porthole — resolved from WatchUi.getSubscreen(); literals are the fallback
    // for the 45 mm / 50 mm panel (62×62 box at x=113, y=0 → centre 143.5, 31.5).
    const PORTHOLE_CX_FALLBACK = 144;
    const PORTHOLE_CY_FALLBACK = 31;
    var portholeCx = PORTHOLE_CX_FALLBACK;
    var portholeCy = PORTHOLE_CY_FALLBACK;

    // Layout A. Weekday and Gregorian are left-aligned; time and Hijri are centred.
    const CHAMFER         = 38;
    const X_HEADER        = 24;
    const Y_WEEKDAY       = 18;
    const Y_GREGORIAN     = 55;
    const Y_HIJRI         = 80;
    const X_DIVIDER_MIN   = 20;
    const X_DIVIDER_MAX   = 156;
    const Y_TIME          = 94;
    const Y_SHELF         = 146;
    const DATE_MONTH_GAP  = 6;

    // Gauge sits on the shelf, inset to the panel's visible span so 0-100 % maps
    // onto real pixels. 1 px outline track, proportional fill — see Theme.
    const X_BATTERY_BAR = 42;
    const W_BATTERY_BAR = 92;
    const Y_BATTERY_BAR = 162;
    const H_BATTERY_BAR = 4;
    const DEBUG_BODY_BATTERY = -1; // hardcoded % for layout debug; -1 for live data

    function initialize() {
        WatchFace.initialize();
        timer = new Timer.Timer();
        resolveSubscreen();
    }

    // The porthole is a real hardware region; ask for it rather than assuming.
    function resolveSubscreen() as Void {
        if (!(WatchUi has :getSubscreen)) { return; }
        var s = WatchUi.getSubscreen();
        if (s == null) { return; }
        portholeCx = s.x + s.width / 2;
        portholeCy = s.y + s.height / 2;
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
        var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        cachedGregorianInfo = g;
        // Hijri is converted in onUpdate from the live offset so Connect / on-watch
        // settings cannot leave a stale month on screen until the next minute tick.
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
        refreshCachedBodyBattery();
        WatchUi.requestUpdate();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Main draw (once per minute via onMinuteUiTick)
    // ─────────────────────────────────────────────────────────────────────────

    function onUpdate(dc) {
        var mode = Theme.getColorMode();
        Glyphs.ensureAll(mode);

        var g = cachedGregorianInfo;
        if (g == null) {
            g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            cachedGregorianInfo = g;
        }
        var hijri = HijriHelpers.gregorianToHijri(g.year, g.month, g.day, getHijriDayOffset());
        // One ensure per draw, shared by the weekday and both date rows.
        var hijriMonth = (hijri as Dictionary)[:month] as Number;
        ArabicLabels.ensure(hijriMonth.toNumber(), g.month, g.day_of_week, mode);

        var bg = Theme.backgroundForMode(mode);
        var fg = Theme.foregroundForMode(mode);
        dc.setColor(bg, bg);
        dc.clear();
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        drawWeekday(dc);
        drawHeaderGregorian(dc, g);
        drawWeatherIcon(dc);
        drawTemperature(dc);
        drawHijriDivider(dc, hijri);
        drawTime(dc);
        drawShelfMetrics(dc);
        drawBatteryBar(dc, fg);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ① Time
    // ─────────────────────────────────────────────────────────────────────────

    function drawTime(dc) {
        var parts = TimeHelpers.getHourMinute24(System.getClockTime());
        Glyphs.drawInline24h(dc, parts[:hour] as String, parts[:min] as String,
                             dc.getWidth() / 2, Y_TIME);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Temperature in the porthole
    //
    // RTL expression, LTR number. The unit is logically [°][م]; in a right-to-left
    // run those reverse, so the unit paints as م° at the left and the number sits
    // to its right, reading left-to-right as usual: م°٢٧
    //
    // The sign travels with the number rather than the expression, so a negative
    // reads م°-٤٠ - the whole "-40" stays one left-to-right block.
    // ─────────────────────────────────────────────────────────────────────────

    function drawTemperature(dc) {
        var numStr = "--";
        if (Toybox has :Weather && cachedConditions != null && cachedConditions.temperature != null) {
            var c = Math.round(cachedConditions.temperature.toFloat()).toNumber();
            numStr = c.format("%d");
        }
        Glyphs.md.drawCentered(dc, "m*" + numStr, portholeCx, portholeCy + 11);
    }

    function drawWeekday(dc) {
        var bmp = ArabicLabels.dowBmp;
        if (bmp == null) { return; }
        dc.drawBitmap(X_HEADER, Y_WEEKDAY, bmp);
    }

    // 1-bit porthole weather. No PNG budget: filled circles and squares only.
    // kind: -1 none, 0 sun, 1 cloud, 2 rain, 3 storm, 4 snow.
    function weatherIconKind() as Number {
        if (!(Toybox has :Weather) || cachedConditions == null || cachedConditions.condition == null) {
            return -1;
        }
        var c = cachedConditions.condition as Number;
        // Storm
        if ((Weather has :CONDITION_THUNDERSTORMS) && c == Weather.CONDITION_THUNDERSTORMS) { return 3; }
        if ((Weather has :CONDITION_SCATTERED_THUNDERSTORMS) && c == Weather.CONDITION_SCATTERED_THUNDERSTORMS) { return 3; }
        if ((Weather has :CONDITION_CHANCE_OF_THUNDERSTORMS) && c == Weather.CONDITION_CHANCE_OF_THUNDERSTORMS) { return 3; }
        if ((Weather has :CONDITION_TORNADO) && c == Weather.CONDITION_TORNADO) { return 3; }
        if ((Weather has :CONDITION_HURRICANE) && c == Weather.CONDITION_HURRICANE) { return 3; }
        if ((Weather has :CONDITION_TROPICAL_STORM) && c == Weather.CONDITION_TROPICAL_STORM) { return 3; }
        // Rain
        if ((Weather has :CONDITION_RAIN) && c == Weather.CONDITION_RAIN) { return 2; }
        if ((Weather has :CONDITION_LIGHT_RAIN) && c == Weather.CONDITION_LIGHT_RAIN) { return 2; }
        if ((Weather has :CONDITION_HEAVY_RAIN) && c == Weather.CONDITION_HEAVY_RAIN) { return 2; }
        if ((Weather has :CONDITION_SHOWERS) && c == Weather.CONDITION_SHOWERS) { return 2; }
        if ((Weather has :CONDITION_SCATTERED_SHOWERS) && c == Weather.CONDITION_SCATTERED_SHOWERS) { return 2; }
        if ((Weather has :CONDITION_LIGHT_SHOWERS) && c == Weather.CONDITION_LIGHT_SHOWERS) { return 2; }
        if ((Weather has :CONDITION_HEAVY_SHOWERS) && c == Weather.CONDITION_HEAVY_SHOWERS) { return 2; }
        if ((Weather has :CONDITION_DRIZZLE) && c == Weather.CONDITION_DRIZZLE) { return 2; }
        if ((Weather has :CONDITION_FREEZING_RAIN) && c == Weather.CONDITION_FREEZING_RAIN) { return 2; }
        if ((Weather has :CONDITION_HAIL) && c == Weather.CONDITION_HAIL) { return 2; }
        if ((Weather has :CONDITION_CHANCE_OF_SHOWERS) && c == Weather.CONDITION_CHANCE_OF_SHOWERS) { return 2; }
        if ((Weather has :CONDITION_CLOUDY_CHANCE_OF_RAIN) && c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN) { return 2; }
        if ((Weather has :CONDITION_UNKNOWN_PRECIPITATION) && c == Weather.CONDITION_UNKNOWN_PRECIPITATION) { return 2; }
        // Snow / mixed
        if ((Weather has :CONDITION_SNOW) && c == Weather.CONDITION_SNOW) { return 4; }
        if ((Weather has :CONDITION_LIGHT_SNOW) && c == Weather.CONDITION_LIGHT_SNOW) { return 4; }
        if ((Weather has :CONDITION_HEAVY_SNOW) && c == Weather.CONDITION_HEAVY_SNOW) { return 4; }
        if ((Weather has :CONDITION_FLURRIES) && c == Weather.CONDITION_FLURRIES) { return 4; }
        if ((Weather has :CONDITION_SLEET) && c == Weather.CONDITION_SLEET) { return 4; }
        if ((Weather has :CONDITION_WINTRY_MIX) && c == Weather.CONDITION_WINTRY_MIX) { return 4; }
        if ((Weather has :CONDITION_ICE) && c == Weather.CONDITION_ICE) { return 4; }
        if ((Weather has :CONDITION_ICE_SNOW) && c == Weather.CONDITION_ICE_SNOW) { return 4; }
        if ((Weather has :CONDITION_RAIN_SNOW) && c == Weather.CONDITION_RAIN_SNOW) { return 4; }
        if ((Weather has :CONDITION_LIGHT_RAIN_SNOW) && c == Weather.CONDITION_LIGHT_RAIN_SNOW) { return 4; }
        if ((Weather has :CONDITION_HEAVY_RAIN_SNOW) && c == Weather.CONDITION_HEAVY_RAIN_SNOW) { return 4; }
        if ((Weather has :CONDITION_CHANCE_OF_SNOW) && c == Weather.CONDITION_CHANCE_OF_SNOW) { return 4; }
        if ((Weather has :CONDITION_CHANCE_OF_RAIN_SNOW) && c == Weather.CONDITION_CHANCE_OF_RAIN_SNOW) { return 4; }
        if ((Weather has :CONDITION_CLOUDY_CHANCE_OF_SNOW) && c == Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW) { return 4; }
        if ((Weather has :CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW) && c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW) { return 4; }
        // Sun / clear
        if ((Weather has :CONDITION_CLEAR) && c == Weather.CONDITION_CLEAR) { return 0; }
        if ((Weather has :CONDITION_FAIR) && c == Weather.CONDITION_FAIR) { return 0; }
        if ((Weather has :CONDITION_PARTLY_CLEAR) && c == Weather.CONDITION_PARTLY_CLEAR) { return 0; }
        if ((Weather has :CONDITION_MOSTLY_CLEAR) && c == Weather.CONDITION_MOSTLY_CLEAR) { return 0; }
        if ((Weather has :CONDITION_THIN_CLOUDS) && c == Weather.CONDITION_THIN_CLOUDS) { return 0; }
        return 1;
    }

    function drawWeatherIcon(dc) as Void {
        var kind = weatherIconKind();
        if (kind < 0) { return; }
        var cx = portholeCx;
        var cy = portholeCy - 9;
        if (kind == 0) {
            dc.fillCircle(cx, cy, 3);
            dc.fillRectangle(cx - 1, cy - 8, 2, 3);
            dc.fillRectangle(cx - 1, cy + 5, 2, 3);
            dc.fillRectangle(cx - 8, cy - 1, 3, 2);
            dc.fillRectangle(cx + 5, cy - 1, 3, 2);
            dc.fillRectangle(cx - 6, cy - 6, 2, 2);
            dc.fillRectangle(cx + 4, cy - 6, 2, 2);
            dc.fillRectangle(cx - 6, cy + 4, 2, 2);
            dc.fillRectangle(cx + 4, cy + 4, 2, 2);
            return;
        }
        if (kind == 3) {
            dc.fillRectangle(cx - 1, cy - 6, 2, 5);
            dc.fillRectangle(cx - 4, cy - 1, 5, 2);
            dc.fillRectangle(cx - 1, cy + 1, 2, 6);
            return;
        }
        if (kind == 4) {
            dc.fillRectangle(cx - 1, cy - 5, 2, 10);
            dc.fillRectangle(cx - 5, cy - 1, 10, 2);
            dc.fillRectangle(cx - 3, cy - 3, 2, 2);
            dc.fillRectangle(cx + 1, cy + 1, 2, 2);
            return;
        }
        dc.fillCircle(cx - 3, cy + 1, 4);
        dc.fillCircle(cx + 3, cy, 5);
        dc.fillCircle(cx, cy - 2, 4);
        if (kind == 2) {
            dc.fillRectangle(cx - 4, cy + 6, 1, 3);
            dc.fillRectangle(cx,     cy + 7, 1, 3);
            dc.fillRectangle(cx + 4, cy + 6, 1, 3);
        }
    }

    // Steps stay exact. Five digits do not fit the md tier, so past 9999 the
    // row drops to xs. The Arabic decimal separator at this size reads as a
    // zero, so abbreviation is not an option.
    function stepsGlyphSet(text as String) {
        return (text.length() > 4) ? Glyphs.xs : Glyphs.md;
    }

    function drawHeaderGregorian(dc, g) {
        var gregBmp = ArabicLabels.gregBmp;
        if (gregBmp == null) { return; }
        var gregDay = g.day.format("%02d");
        var gregW = gregBmp.getWidth() + DATE_MONTH_GAP + Glyphs.xs.measure(gregDay);
        drawDateRow(dc, gregBmp, gregDay, Glyphs.xs, X_HEADER + gregW, Y_GREGORIAN);
    }

    function drawHijriDivider(dc, hijri) {
        var hijriBmp = ArabicLabels.hijriBmp;
        if (hijriBmp == null) { return; }
        var hijriDay = ((hijri as Dictionary)[:day] as Number).toNumber().format("%02d");
        var hijriW = hijriBmp.getWidth() + DATE_MONTH_GAP + Glyphs.sm.measure(hijriDay);
        var seam = dc.getWidth() / 2 + hijriW / 2;
        if (seam > X_DIVIDER_MAX) { seam = X_DIVIDER_MAX; }
        if (seam - hijriW < X_DIVIDER_MIN) { seam = X_DIVIDER_MIN + hijriW; }
        drawDateRow(dc, hijriBmp, hijriDay, Glyphs.sm, seam, Y_HIJRI);
    }

    function drawDateRow(dc, monthBmp, dayStr as String, set, xRight as Number, yMid as Number) as Void {
        set.drawRight(dc, dayStr, xRight, yMid);
        var dayW = set.measure(dayStr);
        var mw = monthBmp.getWidth();
        dc.drawBitmap(xRight - dayW - DATE_MONTH_GAP - mw, yMid - monthBmp.getHeight() / 2, monthBmp);
    }

    function visibleLeft(y as Number) as Number {
        var left = 0;
        if (y < CHAMFER) { left = CHAMFER - y; }
        if (y > 175 - CHAMFER) {
            var inset = y - (175 - CHAMFER);
            if (inset > left) { left = inset; }
        }
        return left;
    }

    function visibleRight(y as Number) as Number {
        if (y > 175 - CHAMFER) {
            return 175 - (y - (175 - CHAMFER));
        }
        return 175;
    }

    function drawShelfMetrics(dc) {
        var steps = cachedSteps.toString();
        var set = stepsGlyphSet(steps);
        var L = visibleLeft(Y_SHELF);
        var R = visibleRight(Y_SHELF);
        var leftCx  = L + (88 - L) / 2;
        var rightCx = 88 + (R - 88) / 2;
        set.drawCentered(dc, steps, leftCx, Y_SHELF + set.cellHeight() / 2);

        var bbStr = "--";
        if (DEBUG_BODY_BATTERY >= 0) {
            bbStr = DEBUG_BODY_BATTERY.format("%d");
        } else if (cachedBodyBattery != null) {
            bbStr = (cachedBodyBattery as Number).format("%d");
        }
        Glyphs.md.drawCentered(dc, bbStr, rightCx, Y_SHELF + Glyphs.md.cellHeight() / 2);
    }

    function drawBatteryBar(dc, fg as Number) {
        var pct = 0.0;
        if (cachedSystemStats != null) {
            pct = cachedSystemStats.battery.toFloat() / 100.0;
        }
        dc.setPenWidth(1);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(X_BATTERY_BAR, Y_BATTERY_BAR, W_BATTERY_BAR, H_BATTERY_BAR);
        var innerW = W_BATTERY_BAR - 2;
        var fillW = (innerW.toFloat() * pct).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(X_BATTERY_BAR + 1, Y_BATTERY_BAR + 1,
                             fillW, H_BATTERY_BAR - 2);
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
