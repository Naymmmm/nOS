#!/usr/bin/env python3
"""nosface-notify — D-Bus notification daemon (GTK3 + gtk-layer-shell)."""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GtkLayerShell', '0.1')
from gi.repository import Gtk, Gdk, GLib, GtkLayerShell

import os
import threading
import dbus
import dbus.service
import dbus.mainloop.glib


THEME    = os.environ.get('NOS_THEME', 'light')
CSS_FILE = os.path.join(os.path.dirname(__file__), 'style.css')

NOTIF_WIDTH   = 340
NOTIF_TIMEOUT = 5000   # ms default


class NotifCard(Gtk.Box):
    def __init__(self, summary: str, body: str, icon: str, on_close):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.get_style_context().add_class('notif-card')

        # Icon
        img = Gtk.Image.new_from_icon_name(
            icon or 'dialog-information-symbolic', Gtk.IconSize.DIALOG)
        img.set_pixel_size(36)
        img.get_style_context().add_class('notif-icon')
        self.pack_start(img, False, False, 0)

        # Text
        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.pack_start(text_box, True, True, 0)

        title = Gtk.Label(label=summary, xalign=0)
        title.set_ellipsize(3)   # PANGO_ELLIPSIZE_END
        title.get_style_context().add_class('notif-title')
        text_box.pack_start(title, False, False, 0)

        if body:
            desc = Gtk.Label(label=body, xalign=0)
            desc.set_ellipsize(3)
            desc.set_line_wrap(True)
            desc.set_max_width_chars(32)
            desc.get_style_context().add_class('notif-body')
            text_box.pack_start(desc, False, False, 0)

        # Close button
        close_btn = Gtk.Button(label='✕')
        close_btn.get_style_context().add_class('notif-close')
        close_btn.set_relief(Gtk.ReliefStyle.NONE)
        close_btn.connect('clicked', lambda _: on_close())
        self.pack_end(close_btn, False, False, 0)

        self.set_margin_top(4)
        self.set_margin_bottom(4)
        self.set_margin_start(8)
        self.set_margin_end(8)


class NotifWindow(Gtk.Window):
    def __init__(self):
        super().__init__()
        self.set_title('nosface-notify')
        self.set_decorated(False)
        self.set_app_paintable(True)

        provider = Gtk.CssProvider()
        provider.load_from_path(CSS_FILE)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.get_style_context().add_class('nos-notify')
        self.get_style_context().add_class(f'theme-{THEME}')

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP,   True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP,   40)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, 12)

        self.set_size_request(NOTIF_WIDTH, -1)

        self.vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.vbox.get_style_context().add_class('notif-stack')
        self.add(self.vbox)

        self._cards: dict[int, NotifCard] = {}
        self._next_id = 1

        self.show_all()

    def add_notification(self, summary: str, body: str,
                         icon: str, timeout_ms: int) -> int:
        nid = self._next_id
        self._next_id += 1

        def remove():
            self.remove_notification(nid)

        card = NotifCard(summary, body, icon, remove)
        self._cards[nid] = card
        self.vbox.pack_start(card, False, False, 0)
        card.show_all()

        ms = timeout_ms if timeout_ms > 0 else NOTIF_TIMEOUT
        GLib.timeout_add(ms, remove)
        return nid

    def remove_notification(self, nid: int):
        card = self._cards.pop(nid, None)
        if card:
            self.vbox.remove(card)


class NosNotifyDaemon(dbus.service.Object):
    INTERFACE = 'org.freedesktop.Notifications'
    PATH      = '/org/freedesktop/Notifications'

    def __init__(self, window: NotifWindow):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SessionBus()
        bus.request_name(self.INTERFACE)
        super().__init__(bus, self.PATH)
        self.window = window

    @dbus.service.method(INTERFACE,
                         in_signature='susssasa{sv}i', out_signature='u')
    def Notify(self, app_name, replaces_id, app_icon,
               summary, body, actions, hints, expire_timeout):
        return GLib.idle_add(lambda: self.window.add_notification(
            str(summary), str(body), str(app_icon), int(expire_timeout)))

    @dbus.service.method(INTERFACE, in_signature='u', out_signature='')
    def CloseNotification(self, nid):
        GLib.idle_add(lambda: self.window.remove_notification(int(nid)))

    @dbus.service.method(INTERFACE, in_signature='', out_signature='as')
    def GetCapabilities(self):
        return ['body', 'icon-static', 'persistence']

    @dbus.service.method(INTERFACE,
                         in_signature='', out_signature='ssss')
    def GetServerInformation(self):
        return ('nosface-notify', 'Nosface', '0.1', '1.2')


def main():
    window = NotifWindow()
    window.connect('destroy', Gtk.main_quit)
    try:
        daemon = NosNotifyDaemon(window)
    except dbus.exceptions.DBusException as e:
        print(f'Warning: Could not register D-Bus name: {e}')
    Gtk.main()


if __name__ == '__main__':
    main()
