#!/usr/bin/env python3
"""Dropdown for a waybar module (claude by default, or `claude-menu.py SCRIPT STATE_DIR`): live rows, click one to
run `SCRIPT click ID`. A 6th row field adds a toggle button (that glyph) running
`SCRIPT toggle ID`. Run again to close."""
import os, signal, subprocess, sys
# cursor first, before the slow gi import: the pointer may already be moving away from the icon
CURSOR = subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True).stdout
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, Gdk, GtkLayerShell, GLib

SH = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.config/waybar/claude.sh")
DIR = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "claude-sessions")
PID = os.path.join(DIR, ".menu.pid")

# toggle: second launch closes the open dropdown
try:
    os.kill(int(open(PID).read()), signal.SIGTERM)
    os.remove(PID)
    sys.exit()
except (FileNotFoundError, ValueError, ProcessLookupError):
    pass
open(PID, "w").write(str(os.getpid()))

css = Gtk.CssProvider()
css.load_from_data(b"""
* { font-family: FantasqueSansMono, "Font Awesome 7 Free", sans-serif; font-size: 12px; }
window { background-color: transparent; }
.menu { background-color: #161320; border: 1px solid rgba(223,218,183,0.4); border-radius: 8px; }
button { background: none; background-image: none; border: none; box-shadow: none; outline: none;
         color: #dfdab7; margin: 1px; padding: 2px 8px; border-radius: 4px; }
button:hover { background-color: rgba(255,255,255,0.07); color: #dfdab7; }
button label, button:hover label { color: #dfdab7; text-shadow: none; }
.hover { background-color: rgba(255,255,255,0.07); border-radius: 4px; }
button.main:hover { background-color: transparent; }
.docked { background-color: #4b2a6b; border-radius: 4px; margin: 1px; }
.docked button, .docked button:hover { background-color: transparent; }
button.ctl { font-size: 8px; padding: 0; min-width: 22px; min-height: 0; margin: 1px 0; }
button.ctl:hover, .docked button.ctl:hover { background-color: rgba(255,255,255,0.15); }
""")
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

# Transparent fullscreen layer under the bar: clicks on it close the menu, the menu box floats under the cursor.
win = Gtk.Window()
win.set_visual(win.get_screen().get_rgba_visual())
win.set_app_paintable(True)
GtkLayerShell.init_for_window(win)
GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
for a in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.RIGHT, GtkLayerShell.Edge.BOTTOM, GtkLayerShell.Edge.LEFT):
    GtkLayerShell.set_anchor(win, a, True)
GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.NONE)
right = 8
try:
    import json
    cx = int(CURSOR.split(",")[0])
    for m in json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True).stdout):
        w = m["width"] / m["scale"]
        if m["x"] <= cx < m["x"] + w:
            right = max(8, int(m["x"] + w - cx - 40))
except Exception:
    pass
open(os.path.join(DIR, ".menu.log"), "a").write(f"{CURSOR.strip()} right={right}\n")
outer = Gtk.Overlay(halign=Gtk.Align.END, valign=Gtk.Align.START, margin_end=right, margin_top=2)
# caret: tip 40px from the menu's right edge, where the cursor was (see `right`). It overlaps the
# menu's top border by 1px so the border does not run under it.
caret = Gtk.DrawingArea(halign=Gtk.Align.END, valign=Gtk.Align.START, margin_end=35)  # tip = cursor x - 1
caret.set_size_request(12, 10)
top_docked = [False]  # caret takes the tracked row's color when that row is first
def draw_caret(w, cr):
    cr.move_to(0, 7); cr.line_to(6, 0.5); cr.line_to(12, 7)
    if top_docked[0]:
        cr.set_source_rgba(0x4b/255, 0x2a/255, 0x6b/255, 1); cr.fill()
        cr.rectangle(0, 6.5, 12, 3.5); cr.fill()
    else:
        cr.set_source_rgba(0x16/255, 0x13/255, 0x20/255, 1); cr.fill()
    cr.move_to(0, 6.5); cr.line_to(6, 0.5); cr.line_to(12, 6.5)
    cr.set_source_rgba(223/255, 218/255, 183/255, 0.4); cr.set_line_width(1); cr.stroke()
caret.connect("draw", draw_caret)
menu = Gtk.EventBox(margin_top=6)
menu.set_size_request(340, -1)  # fixed width, titles ellipsize
menu.get_style_context().add_class("menu")
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=2)
menu.add(box)
outer.add(menu)
outer.add_overlay(caret)
win.add(outer)

def quit(*_):
    try: os.remove(PID)
    except FileNotFoundError: pass
    Gtk.main_quit()

def dock(_btn, sid, action="click"):
    subprocess.run([SH, action, sid])
    refresh()  # stays open, row highlight moves

labels = {}  # (sid, docked) -> label, so ticking times never rebuilds hovered buttons
def refresh():
    out = subprocess.run([SH, "rows"], capture_output=True, text=True).stdout
    rows = [l.split("\t", 5) for l in out.splitlines() if l]
    if not rows: quit(); return False
    keys = [(sid, docked) for sid, docked, *_ in rows]
    if keys != list(labels):
        top_docked[0] = rows[0][1] != "0"; caret.queue_draw()
        labels.clear()
        for c in box.get_children(): box.remove(c)
        for sid, docked, *_ in rows:
            b = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
            h = Gtk.Box(spacing=12)
            lbl = Gtk.Label(xalign=0, hexpand=True); lbl.set_ellipsize(3); lbl.set_max_width_chars(1)  # END; natural width capped so the width request holds
            st = Gtk.Label(xalign=0); tm = Gtk.Label(xalign=1)
            h.pack_start(lbl, True, True, 0); h.pack_start(st, False, False, 0)
            h.pack_end(tm, False, False, 0)
            b.add(h)
            row = Gtk.Box()  # controls sit beside the row button: nested buttons never get the click
            row.pack_start(b, True, True, 0)
            b.get_style_context().add_class("main")
            ev = Gtk.EventBox(); ev.add(row)  # hover lights the whole row, controls included
            ev.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
            ev.connect("enter-notify-event", lambda w, e, r=row: r.get_style_context().add_class("hover"))
            ev.connect("leave-notify-event", lambda w, e, r=row: e.detail == Gdk.NotifyType.INFERIOR or r.get_style_context().remove_class("hover"))
            ctl = []
            if len(rows[0]) > 5:
                c = Gtk.Button(relief=Gtk.ReliefStyle.NONE, label="")
                c.get_style_context().add_class("ctl")
                c.connect("clicked", dock, sid, "toggle")
                c.connect("enter-notify-event", lambda w, e: w.get_window().set_cursor(Gdk.Cursor.new_from_name(w.get_display(), "pointer")))
                c.connect("leave-notify-event", lambda w, e: w.get_window().set_cursor(None))
                row.pack_start(c, False, False, 0)
                ctl.append(c.get_child())
            if docked != "0":  # docked: highlighted. "1" is inert, "2" stays clickable
                row.get_style_context().add_class("docked")
            if docked != "1":
                b.connect("clicked", dock, sid)
                b.connect("enter-notify-event", lambda w, e: w.get_window().set_cursor(Gdk.Cursor.new_from_name(w.get_display(), "pointer")))
                b.connect("leave-notify-event", lambda w, e: w.get_window().set_cursor(None))
            box.pack_start(ev, False, False, 0)
            labels[(sid, docked)] = (lbl, st, tm, *ctl)
        box.show_all()
    for (sid, docked, *fields) in rows:
        for w, m in zip(labels[(sid, docked)], fields): w.set_markup(m)
    return True

win.connect("destroy", quit)
menu.connect("button-press-event", lambda *_: True)  # swallow, so only backdrop clicks reach the window
win.connect("button-press-event", quit)
signal.signal(signal.SIGTERM, lambda *_: quit())
refresh()
GLib.timeout_add_seconds(1, refresh)
win.show_all()
Gtk.main()
