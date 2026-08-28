// ─────────────────────────────────────────────────────────────────────────────
// MyWatchFace.mc  –  Garmin Instinct 3 Solar 45 mm
//
// Layout (top → bottom):
//   Porthole      │  HR (upper, xs) · steps (lower, md; xs past 9999), numbers only
//   TIME          │  stacked HH/MM, tabular Arabic-Indic digits, cy≈59
//   Temperature   │  م° unit then LTR number · centred on the porthole axis
//   Weekday       │  full Arabic name bitmap · centred
//   Hijri date    │  month bitmap + day  (no year)
//   Gregorian     │  month bitmap + day  (no year, ~12 % smaller than Hijri)
//   Battery bar   │  bottom, inset to the panel's visible span
//   Body battery  │  left edge, inset to the panel's visible span
//
// Panel geometry (measured, not assumed):
//   The display is a 176×176 *semi-octagon*, not a circle. Corners are rounded
//   chamfers, so the usable span narrows sharply toward the top and bottom. Two
//   consequences drive the constants below:
//     · At y=172 only x 38–137 is on-panel, and y=175 does not exist at all.
//       A bar drawn 0…175 is invisible below 22 % and saturated above 78 %.
//     · At the Gregorian row's bottom edge (y=166) the panel spans only x 29–146,
//       which is what caps DATE_SEAM_MAX.
//
// Digit tiers are *tabular*: every glyph in a set shares one cell width, so a
// multi-digit string never changes width as its value changes. Without this the
// stacked hour and minute rows, centred independently, sat up to 21 px apart.
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

    // NOTE: this panel is 1 bpp - its palette is black and white only. Any grey
    // snaps to one of the two, so a "grey track" for the bars renders as either
    // invisible (dark theme) or solid (light theme). Both bars therefore draw a
    // foreground outline as their track and fill proportionally inside it.
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
//   clock : stacked HH/MM              sm : Hijri day
//   md    : porthole steps, temperature xs : porthole HR, Gregorian day
// ─────────────────────────────────────────────────────────────────────────────

module Glyphs {
    var clock = null;
    var sm    = null;
    var md    = null;
    var xs    = null;

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

    // Stacked 24 h time. Both rows share one tabular width, so they align exactly.
    function drawStacked24h(dc, hourStr as String, minStr as String,
                            cx as Number, cyCenter as Number, stackGap as Number) as Void {
        var rowH   = clock.cellHeight();
        var hourY  = cyCenter - (rowH * 2 + stackGap) / 2;
        clock.drawCentered(dc, hourStr, cx, hourY + rowH / 2);
        clock.drawCentered(dc, minStr,  cx, hourY + rowH + stackGap + rowH / 2);
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
    var cachedHijri = null;

    // Porthole — resolved from WatchUi.getSubscreen(); literals are the fallback
    // for the 45 mm / 50 mm panel (62×62 box at x=113, y=0 → centre 143.5, 31.5).
    const PORTHOLE_CX_FALLBACK = 144;
    const PORTHOLE_CY_FALLBACK = 31;
    var portholeCx = PORTHOLE_CX_FALLBACK;
    var portholeCy = PORTHOLE_CY_FALLBACK;
    // Rows sit ±8 px from the porthole centre. With the xs (h=11) and md (h=13)
    // tiers that puts the two-row block at y 17.5–45.5, centred on 31.5, and keeps
    // both rows inside a 55.3 px chord.
    const PORTHOLE_HR_DY    = -8;
    const PORTHOLE_STEPS_DY = 8;

    // Vertical layout (px from the top of the 176 px display). Spacing is budgeted
    // against the *tallest* bitmap in each set, so no month/weekday combination can
    // collide: clock 20–98, weekday 102–124, Hijri 127–147, Gregorian 150–166.
    const CY_TIME         = 59;
    const TIME_STACK_GAP  = 4;
    const TIME_CX_OFFSET  = -26;
    const Y_TEMP          = 92;
    const Y_WEEKDAY       = 113;
    const Y_HIJRI         = 137;
    const Y_GREGORIAN     = 158;
    const DATE_MONTH_GAP  = 6;
    // Both date rows share this right edge. Capped because the Gregorian row's own
    // bottom (y=166) only spans x 29–146 — a wider seam would clip the day digits.
    const DATE_SEAM_MAX   = 144;

    // Bars are inset to the panel's visible span so 0-100 % maps onto real pixels,
    // and kept 2-3 px clear of the chamfer so a small difference between the SDK
    // bezel mask and the physical panel cannot clip them. Each is a 1 px outline
    // (the track) with a proportional fill inside - see the note in Theme.
    const X_BATTERY_BAR = 42;
    const W_BATTERY_BAR = 92;
    const Y_BATTERY_BAR = 170;
    const H_BATTERY_BAR = 4;
    const X_BODY_BATTERY_BAR = 6;
    const W_BODY_BATTERY_BAR = 4;
    const Y_BODY_BATTERY_TOP = 38;
    const H_BODY_BATTERY_BAR = 100;
    const MIN_BB_FILL_PX = 5;
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
        // Converted once here rather than per draw call.
        cachedHijri = HijriHelpers.gregorianToHijri(g.year, g.month, g.day, getHijriDayOffset());
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
        Glyphs.ensureAll(mode);

        var g = cachedGregorianInfo;
        if (g == null) {
            g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            cachedGregorianInfo = g;
        }
        var hijri = cachedHijri;
        if (hijri == null) {
            hijri = HijriHelpers.gregorianToHijri(g.year, g.month, g.day, getHijriDayOffset());
            cachedHijri = hijri;
        }
        // One ensure per draw, shared by the weekday and both date rows.
        var hijriMonth = (hijri as Dictionary)[:month] as Number;
        ArabicLabels.ensure(hijriMonth.toNumber(), g.month, g.day_of_week, mode);

        var bg = Theme.backgroundForMode(mode);
        var fg = Theme.foregroundForMode(mode);
        dc.setColor(bg, bg);
        dc.clear();
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        drawTime(dc);
        drawTemperature(dc);
        drawPortholeContents(dc);
        drawWeekday(dc);
        drawCenterDates(dc, g, hijri);
        drawBodyBatteryBar(dc, fg);
        drawBatteryBar(dc, fg);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ① Time
    // ─────────────────────────────────────────────────────────────────────────

    function drawTime(dc) {
        var parts   = TimeHelpers.getHourMinute24(System.getClockTime());
        var cx      = dc.getWidth() / 2 + TIME_CX_OFFSET;
        Glyphs.drawStacked24h(dc, parts[:hour] as String, parts[:min] as String,
                              cx, CY_TIME, TIME_STACK_GAP);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ② Temperature under the porthole
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
            // Round rather than truncate: -0.6 °C should read -1, not 0.
            var c = Math.round(cachedConditions.temperature.toFloat()).toNumber();
            numStr = c.format("%d");
        }
        Glyphs.md.drawCentered(dc, "m*" + numStr, portholeCx, Y_TEMP);
    }

    function drawWeekday(dc) {
        var bmp = ArabicLabels.dowBmp;
        if (bmp == null) { return; }
        dc.drawBitmap(
            dc.getWidth() / 2 - bmp.getWidth() / 2,
            Y_WEEKDAY - bmp.getHeight() / 2,
            bmp
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ③ Porthole — position is the legend (HR above, steps below)
    // ─────────────────────────────────────────────────────────────────────────

    function drawPortholeContents(dc) {
        Glyphs.xs.drawCentered(dc, cachedHrDisplay, portholeCx, portholeCy + PORTHOLE_HR_DY);
        var steps = cachedSteps.toString();
        stepsGlyphSet(steps).drawCentered(dc, steps, portholeCx, portholeCy + PORTHOLE_STEPS_DY);
    }

    // Steps are always exact. Five digits do not fit the md tier, so past 9999 the
    // row drops to xs: 5 cells = 45 px inside a 56.7 px chord.
    //
    // This replaced an earlier plan to abbreviate 10 000+ as thousands-plus-decimal
    // (12.3). Rendered at 13 px the Arabic decimal separator is an 8-pixel mark and
    // Arabic-Indic zero is an 11-pixel mark at the same height - so 12.3 read as
    // 1203, a 10x misread. Dropping a tier keeps the count exact and unambiguous.
    function stepsGlyphSet(text as String) {
        return (text.length() > 4) ? Glyphs.xs : Glyphs.md;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ④ Date rows — shared right seam, block centred
    //
    // In RTL display order a row reads [month][gap][day], so the day's right edge
    // is the natural reading anchor. Both rows are aligned to one seam, and the
    // wider row is what centres the block.
    // ─────────────────────────────────────────────────────────────────────────

    function drawCenterDates(dc, g, hijri) {
        var cx = dc.getWidth() / 2;
        var hijriBmp = ArabicLabels.hijriBmp;
        var gregBmp  = ArabicLabels.gregBmp;

        var hijriDay = ((hijri as Dictionary)[:day] as Number).toNumber().format("%02d");
        var gregDay  = g.day.format("%02d");

        var hijriW = (hijriBmp == null) ? 0
                   : hijriBmp.getWidth() + DATE_MONTH_GAP + Glyphs.sm.measure(hijriDay);
        var gregW  = (gregBmp == null) ? 0
                   : gregBmp.getWidth() + DATE_MONTH_GAP + Glyphs.xs.measure(gregDay);

        var blockW = (hijriW > gregW) ? hijriW : gregW;
        var seam = cx + blockW / 2;
        if (seam > DATE_SEAM_MAX) { seam = DATE_SEAM_MAX; }

        if (hijriBmp != null) {
            drawDateRow(dc, hijriBmp, hijriDay, Glyphs.sm, seam, Y_HIJRI);
        }
        if (gregBmp != null) {
            drawDateRow(dc, gregBmp, gregDay, Glyphs.xs, seam, Y_GREGORIAN);
        }
    }

    function drawDateRow(dc, monthBmp, dayStr as String, set, xRight as Number, yMid as Number) as Void {
        set.drawRight(dc, dayStr, xRight, yMid);
        var dayW = set.measure(dayStr);
        var mw = monthBmp.getWidth();
        dc.drawBitmap(xRight - dayW - DATE_MONTH_GAP - mw, yMid - monthBmp.getHeight() / 2, monthBmp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ⑤ Body battery bar (left edge)
    // ─────────────────────────────────────────────────────────────────────────

    function drawBodyBatteryBar(dc, fg as Number) {
        var bbValue = null;
        if (DEBUG_BODY_BATTERY >= 0) {
            bbValue = DEBUG_BODY_BATTERY;
        } else if (cachedBodyBattery != null) {
            bbValue = cachedBodyBattery;
        }
        dc.setPenWidth(1);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(X_BODY_BATTERY_BAR, Y_BODY_BATTERY_TOP,
                         W_BODY_BATTERY_BAR, H_BODY_BATTERY_BAR);
        if (bbValue == null || bbValue <= 0) { return; }
        // Fill the 2 px channel inside the outline, growing upward from the base.
        var innerH = H_BODY_BATTERY_BAR - 2;
        var fillH = (innerH.toFloat() * bbValue.toFloat() / 100.0).toNumber();
        if (fillH < MIN_BB_FILL_PX) { fillH = MIN_BB_FILL_PX; }
        if (fillH > innerH) { fillH = innerH; }
        dc.fillRectangle(X_BODY_BATTERY_BAR + 1,
                         Y_BODY_BATTERY_TOP + H_BODY_BATTERY_BAR - 1 - fillH,
                         W_BODY_BATTERY_BAR - 2, fillH);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ⑥ Battery bar
    // ─────────────────────────────────────────────────────────────────────────

    function drawBatteryBar(dc, fg as Number) {
        var pct = 0.0;
        if (cachedSystemStats != null) {
            pct = cachedSystemStats.battery.toFloat() / 100.0;
        }
        dc.setPenWidth(1);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(X_BATTERY_BAR, Y_BATTERY_BAR, W_BATTERY_BAR, H_BATTERY_BAR);
        // Fill the 2 px channel inside the outline, growing from the left.
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
