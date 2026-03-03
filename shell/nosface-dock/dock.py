#!/usr/bin/env python3
"""nosface-dock — bottom floating dock with magnification (GTK3 + gtk-layer-shell)."""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GtkLayerShell', '0.1')
from gi.repository import Gtk, Gdk, GLib, GtkLayerShell

import os
import subprocess
import math


THEME   = os.environ.get('NOS_THEME', 'light')
CSS_FILE = os.path.join(os.path.dirname(__file__), 'style.css')

# Default dock apps: (name, icon, command)
DEFAULT_APPS = [
    ('Finder',    'system-file-manager',    'thunar'),
    ('Terminal',  'utilities-terminal',     'alacritty'),
    ('Firefox',   'web-browser',            'firefox'),
    ('Settings',  'preferences-system',     'nos-settings'),
    ('Editor',    'text-editor',            'gedit'),
    ('Music',     'audio-player',           'rhythmbox'),
]

BASE_ICON_SIZE = 60
MAX_ICON_SIZE  = 88
MAGNIFY_RANGE  = 100   # px from icon center that affects magnification


class DockIcon(Gtk.EventBox):
    def __init__(self, name: str, icon_name: str, command: str):
        super().__init__()
        self.name    = name
        self.command = command
        self._base   = BASE_ICON_SIZE
        self._size   = BASE_ICON_SIZE

        self.get_style_context().add_class('dock-icon-box')

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(vbox)

        # Tooltip ABOVE icon (macOS style)
        self.tooltip = Gtk.Label(label=name)
        self.tooltip.get_style_context().add_class('dock-tooltip')
        self.tooltip.set_no_show_all(True)
        vbox.pack_start(self.tooltip, False, False, 0)

        self.img = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.DIALOG)
        self.img.set_pixel_size(BASE_ICON_SIZE)
        self.img.get_style_context().add_class('dock-icon')
        vbox.pack_start(self.img, False, False, 4)

        # Running indicator dot below icon
        self.dot = Gtk.Label(label='•')
        self.dot.get_style_context().add_class('dock-dot')
        self.dot.set_no_show_all(True)
        vbox.pack_start(self.dot, False, False, 0)

        self.connect('button-press-event', self._on_click)
        self.connect('enter-notify-event', self._on_enter)
        self.connect('leave-notify-event', self._on_leave)

    def set_magnification(self, cursor_x: float):
        """Compute icon size based on cursor distance (cosine falloff)."""
        alloc = self.get_allocation()
        cx = alloc.x + alloc.width / 2
        dist = abs(cursor_x - cx)
        if dist < MAGNIFY_RANGE:
            t = math.cos(dist / MAGNIFY_RANGE * math.pi / 2)
            self._size = int(self._base + t * (MAX_ICON_SIZE - self._base))
        else:
            self._size = self._base
        self.img.set_pixel_size(self._size)

    def reset_magnification(self):
        self._size = self._base
        self.img.set_pixel_size(self._base)

    def _on_click(self, widget, event):
        if event.button == 1:
            try:
                subprocess.Popen(self.command.split())
            except Exception as e:
                print(f'Could not launch {self.command}: {e}')
            self._bounce()

    def _bounce(self):
        """Simple CSS bounce animation via class toggling."""
        ctx = self.img.get_style_context()
        ctx.add_class('bounce')
        GLib.timeout_add(400, lambda: ctx.remove_class('bounce'))

    def _on_enter(self, widget, event):
        self.tooltip.show()

    def _on_leave(self, widget, event):
        self.tooltip.hide()
        self.reset_magnification()


class NosDock(Gtk.Window):
    def __init__(self):
        super().__init__()
        self.set_title('nosface-dock')
        self.set_decorated(False)
        self.set_app_paintable(True)

        # Load CSS
        provider = Gtk.CssProvider()
        provider.load_from_path(CSS_FILE)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.get_style_context().add_class('nos-dock')
        self.get_style_context().add_class(f'theme-{THEME}')

        # Layer shell
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, 16)
        GtkLayerShell.set_exclusive_zone(self, -1)   # don't reserve space

        # Content
        outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        outer.get_style_context().add_class('dock-outer')
        self.add(outer)

        self.icon_row = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.icon_row.get_style_context().add_class('dock-row')
        outer.pack_start(self.icon_row, False, False, 0)

        self.icons: list[DockIcon] = []
        for name, icon, cmd in DEFAULT_APPS:
            di = DockIcon(name, icon, cmd)
            self.icon_row.pack_start(di, False, False, 0)
            self.icons.append(di)

        # Magnification tracking
        self.add_events(Gdk.EventMask.POINTER_MOTION_MASK |
                        Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.connect('motion-notify-event', self._on_motion)
        self.connect('leave-notify-event',  self._on_leave)

        self.show_all()

    def _on_motion(self, widget, event):
        for icon in self.icons:
            icon.set_magnification(event.x_root)

    def _on_leave(self, widget, event):
        for icon in self.icons:
            icon.reset_magnification()


def main():
    dock = NosDock()
    dock.connect('destroy', Gtk.main_quit)
    Gtk.main()


if __name__ == '__main__':
    main()
