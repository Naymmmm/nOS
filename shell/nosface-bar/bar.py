#!/usr/bin/env python3
"""nosface-bar — macOS-style top menubar (GTK3 + gtk-layer-shell)."""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GtkLayerShell', '0.1')
from gi.repository import Gtk, GLib, Gdk, GtkLayerShell

import os
import subprocess
import datetime
import threading


THEME = os.environ.get('NOS_THEME', 'dark')
CSS_FILE = os.path.join(os.path.dirname(__file__), 'style.css')


class StatusArea(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.get_style_context().add_class('status-area')

        self.clock_label = Gtk.Label()
        self.clock_label.get_style_context().add_class('clock')
        self.pack_start(self.clock_label, False, False, 0)

        self._update_clock()
        GLib.timeout_add_seconds(1, self._update_clock)

    def _update_clock(self):
        now = datetime.datetime.now()
        self.clock_label.set_text(now.strftime('%a %b %-d  %-I:%M %p'))
        return True


class AppMenuArea(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        self.get_style_context().add_class('app-menu-area')

        apple_btn = Gtk.Button(label='')
        apple_btn.get_style_context().add_class('apple-btn')
        apple_btn.connect('clicked', self._on_apple_clicked)
        self.pack_start(apple_btn, False, False, 0)

        self.app_name = Gtk.Label(label='Nosface')
        self.app_name.get_style_context().add_class('app-name')
        self.pack_start(self.app_name, False, False, 8)

    def _on_apple_clicked(self, btn):
        # Launch application launcher
        subprocess.Popen(['nosface-launcher'])

    def set_active_app(self, name: str):
        self.app_name.set_text(name)


class SystemTray(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.get_style_context().add_class('system-tray')

        for icon_name in ('network-wireless-symbolic',
                          'audio-volume-medium-symbolic',
                          'battery-full-symbolic'):
            icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.SMALL_TOOLBAR)
            btn = Gtk.Button()
            btn.set_relief(Gtk.ReliefStyle.NONE)
            btn.add(icon)
            btn.get_style_context().add_class('tray-btn')
            self.pack_start(btn, False, False, 0)


class NosBar(Gtk.Window):
    def __init__(self):
        super().__init__()
        self.set_title('nosface-bar')
        self.set_decorated(False)

        # Load CSS
        provider = Gtk.CssProvider()
        provider.load_from_path(CSS_FILE)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.get_style_context().add_class('nos-bar')
        self.get_style_context().add_class(f'theme-{THEME}')

        # Layer shell setup
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_exclusive_zone(self, 32)

        self.set_size_request(-1, 32)

        # Layout: [AppMenu | ... | Clock/Status | Tray]
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.add(hbox)

        self.app_area = AppMenuArea()
        hbox.pack_start(self.app_area, False, False, 0)

        # Spacer
        spacer = Gtk.Box()
        hbox.pack_start(spacer, True, True, 0)

        self.status = StatusArea()
        hbox.pack_start(self.status, False, False, 0)

        # Another spacer
        spacer2 = Gtk.Box()
        hbox.pack_start(spacer2, True, True, 0)

        self.tray = SystemTray()
        hbox.pack_end(self.tray, False, False, 8)

        self.show_all()


def main():
    bar = NosBar()
    bar.connect('destroy', Gtk.main_quit)
    Gtk.main()


if __name__ == '__main__':
    main()
