#!/usr/bin/env python3
"""nos_setup_wizard.py — First-run setup wizard for Nosface (GTK3)."""

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib

import os
import subprocess

CSS_FILE = os.path.join(os.path.dirname(__file__), 'nos_setup_wizard.css')


def load_css():
    provider = Gtk.CssProvider()
    provider.load_from_path(CSS_FILE)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


# ---- Page factories ----

def wizard_page_welcome():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)
    box.set_halign(Gtk.Align.CENTER)
    box.set_valign(Gtk.Align.CENTER)

    logo = Gtk.Image.new_from_icon_name('user-home', Gtk.IconSize.DIALOG)
    logo.set_pixel_size(80)
    box.pack_start(logo, False, False, 0)

    title = Gtk.Label(label='Welcome to nOS')
    title.get_style_context().add_class('wizard-title')
    box.pack_start(title, False, False, 0)

    desc = Gtk.Label(label=(
        'Let\'s set up your desktop experience.\n'
        'This will only take a minute.'))
    desc.set_justify(Gtk.Justification.CENTER)
    desc.get_style_context().add_class('wizard-desc')
    box.pack_start(desc, False, False, 0)

    return box, {}


def wizard_page_theme():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    box.set_halign(Gtk.Align.CENTER)
    box.set_valign(Gtk.Align.CENTER)

    title = Gtk.Label(label='Choose Your Theme')
    title.get_style_context().add_class('wizard-title')
    box.pack_start(title, False, False, 0)

    theme_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=20)
    box.pack_start(theme_box, False, False, 0)

    dark_btn  = Gtk.ToggleButton(label='🌙  Dark')
    light_btn = Gtk.ToggleButton(label='☀️  Light')
    dark_btn.get_style_context().add_class('theme-btn')
    light_btn.get_style_context().add_class('theme-btn')
    dark_btn.set_active(True)

    def on_dark(btn):
        if btn.get_active():
            light_btn.set_active(False)

    def on_light(btn):
        if btn.get_active():
            dark_btn.set_active(False)

    dark_btn.connect('toggled', on_dark)
    light_btn.connect('toggled', on_light)

    theme_box.pack_start(dark_btn,  False, False, 0)
    theme_box.pack_start(light_btn, False, False, 0)

    return box, {'dark_btn': dark_btn, 'light_btn': light_btn}


def wizard_page_browser():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    box.set_halign(Gtk.Align.CENTER)
    box.set_valign(Gtk.Align.CENTER)

    title = Gtk.Label(label='Default Browser')
    title.get_style_context().add_class('wizard-title')
    box.pack_start(title, False, False, 0)

    browsers = [
        ('Firefox', 'firefox'),
        ('Chromium', 'chromium'),
        ('Brave', 'brave'),
        ('Epiphany (GNOME Web)', 'epiphany'),
    ]

    combo = Gtk.ComboBoxText()
    for name, cmd in browsers:
        combo.append(cmd, name)
    combo.set_active(0)
    combo.get_style_context().add_class('wizard-combo')
    box.pack_start(combo, False, False, 0)

    return box, {'browser_combo': combo}


def wizard_page_privacy():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    box.set_halign(Gtk.Align.CENTER)
    box.set_valign(Gtk.Align.CENTER)

    title = Gtk.Label(label='Privacy Settings')
    title.get_style_context().add_class('wizard-title')
    box.pack_start(title, False, False, 0)

    options = [
        ('Send anonymous crash reports', True),
        ('Enable location services',     False),
        ('Allow app activity tracking',  False),
    ]

    checks = {}
    for label, default in options:
        cb = Gtk.CheckButton(label=label)
        cb.set_active(default)
        cb.get_style_context().add_class('wizard-check')
        box.pack_start(cb, False, False, 0)
        checks[label] = cb

    return box, {'privacy_checks': checks}


def wizard_page_finish():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)
    box.set_halign(Gtk.Align.CENTER)
    box.set_valign(Gtk.Align.CENTER)

    icon = Gtk.Image.new_from_icon_name('emblem-default', Gtk.IconSize.DIALOG)
    icon.set_pixel_size(80)
    box.pack_start(icon, False, False, 0)

    title = Gtk.Label(label='You\'re all set!')
    title.get_style_context().add_class('wizard-title')
    box.pack_start(title, False, False, 0)

    desc = Gtk.Label(label='nOS is ready. Click "Start" to begin.')
    desc.get_style_context().add_class('wizard-desc')
    box.pack_start(desc, False, False, 0)

    return box, {}


WIZARD_PAGES = [
    wizard_page_welcome,
    wizard_page_theme,
    wizard_page_browser,
    wizard_page_privacy,
    wizard_page_finish,
]


class NosSetupWizard(Gtk.Window):
    def __init__(self):
        super().__init__(title='nOS Setup')
        self.set_default_size(580, 440)
        self.set_resizable(False)
        self.set_decorated(False)
        load_css()
        self.get_style_context().add_class('wizard-window')

        self._page_idx = 0
        self._widgets  = []

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(outer)

        # ── Traffic-light titlebar ──────────────────────────────────────────
        titlebar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        titlebar.get_style_context().add_class('wizard-titlebar')
        titlebar.set_valign(Gtk.Align.CENTER)
        outer.pack_start(titlebar, False, False, 0)

        for cls, action in (('traffic-red',    self._on_close),
                             ('traffic-yellow', None),
                             ('traffic-green',  None)):
            dot = Gtk.Button()
            dot.set_size_request(12, 12)
            dot.set_relief(Gtk.ReliefStyle.NONE)
            dot.get_style_context().add_class('traffic-light')
            dot.get_style_context().add_class(cls)
            if action:
                dot.connect('clicked', action)
            titlebar.pack_start(dot, False, False, 0)

        # Stack
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.stack.set_transition_duration(220)
        outer.pack_start(self.stack, True, True, 0)

        for i, builder in enumerate(WIZARD_PAGES):
            content, widgets = builder()
            content.set_margin_top(32)
            content.set_margin_bottom(16)
            content.set_margin_start(32)
            content.set_margin_end(32)
            self.stack.add_named(content, str(i))
            self._widgets.append(widgets)

        # Footer
        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        footer.get_style_context().add_class('wizard-footer')
        outer.pack_start(footer, False, False, 0)

        self.back_btn = Gtk.Button(label='Back')
        self.back_btn.get_style_context().add_class('wizard-nav-btn')
        self.back_btn.connect('clicked', self._go_back)
        footer.pack_start(self.back_btn, False, False, 12)

        spacer = Gtk.Box()
        footer.pack_start(spacer, True, True, 0)

        # Dots
        self.dot_box = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.dot_box.set_halign(Gtk.Align.CENTER)
        footer.pack_start(self.dot_box, False, False, 0)
        self._dots = []
        for _ in WIZARD_PAGES:
            d = Gtk.Label(label='•')
            d.get_style_context().add_class('wizard-dot')
            self.dot_box.pack_start(d, False, False, 0)
            self._dots.append(d)

        spacer2 = Gtk.Box()
        footer.pack_start(spacer2, True, True, 0)

        self.next_btn = Gtk.Button(label='Next')
        self.next_btn.get_style_context().add_class('wizard-nav-btn-primary')
        self.next_btn.connect('clicked', self._go_next)
        footer.pack_end(self.next_btn, False, False, 12)

        self._update_nav()
        self.show_all()

    def _update_nav(self):
        n = len(WIZARD_PAGES)
        self.back_btn.set_sensitive(self._page_idx > 0)
        if self._page_idx == n - 1:
            self.next_btn.set_label('Start')
        else:
            self.next_btn.set_label('Next')
        for i, d in enumerate(self._dots):
            ctx = d.get_style_context()
            ctx.remove_class('dot-active')
            if i == self._page_idx:
                ctx.add_class('dot-active')

    def _go_next(self, btn):
        n = len(WIZARD_PAGES)
        if self._page_idx >= n - 1:
            self._apply_settings()
            self.destroy()
            Gtk.main_quit()
            return
        self._page_idx += 1
        self.stack.set_visible_child_name(str(self._page_idx))
        self._update_nav()

    def _on_close(self, btn):
        self.destroy()
        Gtk.main_quit()

    def _go_back(self, btn):
        if self._page_idx > 0:
            self._page_idx -= 1
            self.stack.set_visible_child_name(str(self._page_idx))
            self._update_nav()

    def _apply_settings(self):
        # Theme
        w_theme = self._widgets[1]
        theme = 'dark' if w_theme['dark_btn'].get_active() else 'light'
        profile = os.path.expanduser('~/.profile')
        try:
            with open(profile, 'a') as f:
                f.write(f'\nexport NOS_THEME={theme}\n')
        except Exception:
            pass

        # Browser (set xdg default)
        w_browser = self._widgets[2]
        browser = w_browser['browser_combo'].get_active_id() or 'firefox'
        try:
            subprocess.run(
                ['xdg-settings', 'set', 'default-web-browser',
                 f'{browser}.desktop'],
                check=False)
        except Exception:
            pass


def main():
    win = NosSetupWizard()
    win.connect('destroy', Gtk.main_quit)
    Gtk.main()


if __name__ == '__main__':
    main()
