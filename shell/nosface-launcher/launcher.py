#!/usr/bin/env python3
"""nosface-launcher — Spotlight-style application launcher (GTK3 + gtk-layer-shell)."""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GtkLayerShell', '0.1')
from gi.repository import Gtk, Gdk, GLib, GtkLayerShell, Gio

import os
import subprocess


THEME    = os.environ.get('NOS_THEME', 'dark')
CSS_FILE = os.path.join(os.path.dirname(__file__), 'style.css')


def get_desktop_apps():
    """Return list of (name, icon, exec) from .desktop files."""
    apps = []
    seen = set()
    dirs = [
        '/usr/share/applications',
        os.path.expanduser('~/.local/share/applications'),
    ]
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if not f.endswith('.desktop'):
                continue
            path = os.path.join(d, f)
            try:
                app = Gio.DesktopAppInfo.new_from_filename(path)
                if app and app.should_show() and app.get_name() not in seen:
                    seen.add(app.get_name())
                    icon = app.get_string('Icon') or 'application-x-executable'
                    exe  = app.get_string('Exec') or ''
                    # strip %u %f etc.
                    exe = ' '.join(p for p in exe.split() if not p.startswith('%'))
                    apps.append((app.get_name(), icon, exe))
            except Exception:
                pass
    return sorted(apps, key=lambda x: x[0].lower())


class ResultRow(Gtk.ListBoxRow):
    def __init__(self, name: str, icon: str, exe: str):
        super().__init__()
        self.exe  = exe
        self.name = name

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        hbox.set_margin_top(4)
        hbox.set_margin_bottom(4)
        hbox.set_margin_start(8)
        hbox.set_margin_end(8)
        self.add(hbox)

        img = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR)
        img.set_pixel_size(32)
        hbox.pack_start(img, False, False, 0)

        label = Gtk.Label(label=name, xalign=0)
        label.get_style_context().add_class('result-label')
        hbox.pack_start(label, True, True, 0)

        self.get_style_context().add_class('result-row')

    def launch(self):
        if self.exe:
            try:
                subprocess.Popen(self.exe.split())
            except Exception as e:
                print(f'Launch error: {e}')


class NosLauncher(Gtk.Window):
    def __init__(self):
        super().__init__()
        self.set_title('nosface-launcher')
        self.set_decorated(False)
        self.set_app_paintable(True)
        self._all_apps = get_desktop_apps()

        # CSS
        provider = Gtk.CssProvider()
        provider.load_from_path(CSS_FILE)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.get_style_context().add_class('nos-launcher')
        self.get_style_context().add_class(f'theme-{THEME}')

        # Layer shell — overlay centered
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_keyboard_mode(self,
            GtkLayerShell.KeyboardMode.EXCLUSIVE)

        # Layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        vbox.get_style_context().add_class('launcher-box')
        self.add(vbox)

        self.entry = Gtk.Entry()
        self.entry.set_placeholder_text('Search apps…')
        self.entry.get_style_context().add_class('launcher-entry')
        self.entry.connect('changed', self._on_search_changed)
        self.entry.connect('key-press-event', self._on_key_press)
        vbox.pack_start(self.entry, False, False, 0)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_max_content_height(320)
        scroll.set_propagate_natural_height(True)
        vbox.pack_start(scroll, True, True, 0)

        self.listbox = Gtk.ListBox()
        self.listbox.get_style_context().add_class('result-list')
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.listbox.connect('row-activated', self._on_row_activated)
        scroll.add(self.listbox)

        self.set_size_request(560, -1)

        # Close on Escape / click outside
        self.add_events(Gdk.EventMask.KEY_PRESS_MASK)
        self.connect('key-press-event', self._on_window_key)

        self._populate('')
        self.show_all()
        self.entry.grab_focus()

    def _populate(self, query: str):
        for child in self.listbox.get_children():
            self.listbox.remove(child)
        q = query.strip().lower()
        shown = 0
        for name, icon, exe in self._all_apps:
            if q and q not in name.lower():
                continue
            row = ResultRow(name, icon, exe)
            self.listbox.add(row)
            shown += 1
            if shown >= 12:
                break
        self.listbox.show_all()
        first = self.listbox.get_row_at_index(0)
        if first:
            self.listbox.select_row(first)

    def _on_search_changed(self, entry):
        self._populate(entry.get_text())

    def _on_row_activated(self, listbox, row):
        row.launch()
        self.destroy()

    def _on_key_press(self, entry, event):
        if event.keyval == Gdk.KEY_Return:
            sel = self.listbox.get_selected_row()
            if sel:
                sel.launch()
                self.destroy()
        elif event.keyval == Gdk.KEY_Down:
            cur = self.listbox.get_selected_row()
            if cur:
                nxt = self.listbox.get_row_at_index(cur.get_index() + 1)
                if nxt:
                    self.listbox.select_row(nxt)
        elif event.keyval == Gdk.KEY_Up:
            cur = self.listbox.get_selected_row()
            if cur and cur.get_index() > 0:
                prv = self.listbox.get_row_at_index(cur.get_index() - 1)
                if prv:
                    self.listbox.select_row(prv)

    def _on_window_key(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.destroy()


def main():
    win = NosLauncher()
    win.connect('destroy', Gtk.main_quit)
    Gtk.main()


if __name__ == '__main__':
    main()
