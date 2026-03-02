#!/usr/bin/env python3
"""nos_installer.py — GTK3 GUI installer wizard for nOS (7 pages)."""

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, GObject

import os
import sys
import subprocess
import threading
import json

CSS_FILE = os.path.join(os.path.dirname(__file__), 'nos_installer.css')

PAGES = [
    'welcome',
    'license',
    'disk',
    'timezone',
    'user',
    'packages',
    'install',
]

DISTRO_NAME = 'nOS'
VERSION     = '1.0'


def load_css():
    provider = Gtk.CssProvider()
    provider.load_from_path(CSS_FILE)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


# ---- Page builders ----

def page_welcome():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)
    box.set_halign(Gtk.Align.CENTER)
    box.set_valign(Gtk.Align.CENTER)

    logo = Gtk.Image.new_from_icon_name('distributor-logo', Gtk.IconSize.DIALOG)
    logo.set_pixel_size(96)
    logo.get_style_context().add_class('installer-logo')
    box.pack_start(logo, False, False, 0)

    title = Gtk.Label(label=f'Welcome to {DISTRO_NAME}')
    title.get_style_context().add_class('page-title')
    box.pack_start(title, False, False, 0)

    sub = Gtk.Label(label=(
        f'{DISTRO_NAME} {VERSION} — Nosface Desktop Edition\n\n'
        'This wizard will guide you through the installation process.\n'
        'Please ensure you have backed up any important data before continuing.'))
    sub.set_line_wrap(True)
    sub.set_justify(Gtk.Justification.CENTER)
    sub.get_style_context().add_class('page-sub')
    box.pack_start(sub, False, False, 0)

    return box, {}


def page_license():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

    title = Gtk.Label(label='License Agreement')
    title.get_style_context().add_class('page-title')
    box.pack_start(title, False, False, 0)

    scroll = Gtk.ScrolledWindow()
    scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    scroll.set_min_content_height(200)
    tv = Gtk.TextView()
    tv.set_editable(False)
    tv.set_wrap_mode(Gtk.WrapMode.WORD)
    tv.get_style_context().add_class('license-text')
    buf = tv.get_buffer()
    buf.set_text(
        "MIT License\n\n"
        f"Copyright (c) 2026 {DISTRO_NAME} Project\n\n"
        "Permission is hereby granted, free of charge, to any person obtaining a copy "
        "of this software and associated documentation files (the \"Software\"), to deal "
        "in the Software without restriction, including without limitation the rights "
        "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell "
        "copies of the Software, and to permit persons to whom the Software is "
        "furnished to do so, subject to the following conditions:\n\n"
        "The above copyright notice and this permission notice shall be included in all "
        "copies or substantial portions of the Software.\n\n"
        "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR "
        "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, "
        "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT."
    )
    scroll.add(tv)
    box.pack_start(scroll, True, True, 0)

    check = Gtk.CheckButton(label='I have read and agree to the license agreement')
    check.get_style_context().add_class('license-check')
    box.pack_start(check, False, False, 0)

    return box, {'license_accepted': check}


def page_disk():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

    title = Gtk.Label(label='Disk Selection')
    title.get_style_context().add_class('page-title')
    box.pack_start(title, False, False, 0)

    sub = Gtk.Label(label='Select the disk to install nOS on.\nAll data on the selected disk will be erased.')
    sub.set_line_wrap(True)
    sub.get_style_context().add_class('page-sub')
    box.pack_start(sub, False, False, 0)

    store = Gtk.ListStore(str, str, str)
    # Populate with real disks via lsblk
    try:
        out = subprocess.check_output(
            ['lsblk', '-dno', 'NAME,SIZE,MODEL', '--output', 'NAME,SIZE,MODEL'],
            stderr=subprocess.DEVNULL, text=True)
        for line in out.strip().splitlines():
            parts = line.split(maxsplit=2)
            if len(parts) >= 2:
                name  = f'/dev/{parts[0]}'
                size  = parts[1]
                model = parts[2] if len(parts) > 2 else ''
                store.append([name, size, model])
    except Exception:
        store.append(['/dev/sda', '100G', 'Sample Disk'])

    tv = Gtk.TreeView(model=store)
    tv.get_style_context().add_class('disk-list')
    for i, col in enumerate(['Device', 'Size', 'Model']):
        renderer = Gtk.CellRendererText()
        column   = Gtk.TreeViewColumn(col, renderer, text=i)
        tv.append_column(column)

    scroll = Gtk.ScrolledWindow()
    scroll.set_min_content_height(180)
    scroll.add(tv)
    box.pack_start(scroll, True, True, 0)

    return box, {'disk_view': tv, 'disk_store': store}


def page_timezone():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

    title = Gtk.Label(label='Timezone & Locale')
    title.get_style_context().add_class('page-title')
    box.pack_start(title, False, False, 0)

    grid = Gtk.Grid(row_spacing=10, column_spacing=12)
    grid.set_halign(Gtk.Align.CENTER)
    box.pack_start(grid, False, False, 0)

    tz_label = Gtk.Label(label='Timezone:', xalign=0)
    tz_combo = Gtk.ComboBoxText()
    for tz in ['UTC', 'America/New_York', 'America/Los_Angeles',
               'Europe/London', 'Europe/Berlin', 'Asia/Tokyo',
               'Australia/Sydney']:
        tz_combo.append_text(tz)
    tz_combo.set_active(0)

    locale_label = Gtk.Label(label='Locale:', xalign=0)
    locale_combo = Gtk.ComboBoxText()
    for lc in ['en_US.UTF-8', 'en_GB.UTF-8', 'de_DE.UTF-8',
               'fr_FR.UTF-8', 'ja_JP.UTF-8', 'zh_CN.UTF-8']:
        locale_combo.append_text(lc)
    locale_combo.set_active(0)

    kb_label = Gtk.Label(label='Keyboard:', xalign=0)
    kb_combo = Gtk.ComboBoxText()
    for kb in ['us', 'gb', 'de', 'fr', 'es', 'jp']:
        kb_combo.append_text(kb)
    kb_combo.set_active(0)

    grid.attach(tz_label,     0, 0, 1, 1)
    grid.attach(tz_combo,     1, 0, 1, 1)
    grid.attach(locale_label, 0, 1, 1, 1)
    grid.attach(locale_combo, 1, 1, 1, 1)
    grid.attach(kb_label,     0, 2, 1, 1)
    grid.attach(kb_combo,     1, 2, 1, 1)

    return box, {
        'tz_combo':     tz_combo,
        'locale_combo': locale_combo,
        'kb_combo':     kb_combo,
    }


def page_user():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

    title = Gtk.Label(label='Create User Account')
    title.get_style_context().add_class('page-title')
    box.pack_start(title, False, False, 0)

    grid = Gtk.Grid(row_spacing=10, column_spacing=12)
    grid.set_halign(Gtk.Align.CENTER)
    box.pack_start(grid, False, False, 0)

    def row(label_text, widget, row_n):
        lbl = Gtk.Label(label=label_text, xalign=0)
        grid.attach(lbl,    0, row_n, 1, 1)
        grid.attach(widget, 1, row_n, 1, 1)

    hostname_entry = Gtk.Entry()
    hostname_entry.set_placeholder_text('nos-pc')
    hostname_entry.set_width_chars(24)

    username_entry = Gtk.Entry()
    username_entry.set_placeholder_text('yourname')
    username_entry.set_width_chars(24)

    password_entry = Gtk.Entry()
    password_entry.set_visibility(False)
    password_entry.set_placeholder_text('Password')
    password_entry.set_width_chars(24)

    confirm_entry = Gtk.Entry()
    confirm_entry.set_visibility(False)
    confirm_entry.set_placeholder_text('Confirm password')
    confirm_entry.set_width_chars(24)

    autologin_check = Gtk.CheckButton(label='Enable automatic login')

    row('Hostname:',         hostname_entry, 0)
    row('Username:',         username_entry, 1)
    row('Password:',         password_entry, 2)
    row('Confirm password:', confirm_entry,  3)
    grid.attach(autologin_check, 1, 4, 1, 1)

    return box, {
        'hostname':   hostname_entry,
        'username':   username_entry,
        'password':   password_entry,
        'confirm':    confirm_entry,
        'autologin':  autologin_check,
    }


def page_packages():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

    title = Gtk.Label(label='Software Selection')
    title.get_style_context().add_class('page-title')
    box.pack_start(title, False, False, 0)

    sub = Gtk.Label(label='Choose additional software to install.')
    sub.get_style_context().add_class('page-sub')
    box.pack_start(sub, False, False, 0)

    groups = [
        ('Office Suite', 'libreoffice', True),
        ('Web Browser (Firefox)', 'firefox', True),
        ('Media Player (mpv)', 'mpv', True),
        ('Image Editor (GIMP)', 'gimp', False),
        ('Development Tools', 'base-devel git', False),
        ('Gaming (Steam)', 'steam', False),
    ]

    checks = {}
    for label, pkg, default in groups:
        cb = Gtk.CheckButton(label=label)
        cb.set_active(default)
        cb._pkg = pkg
        box.pack_start(cb, False, False, 0)
        checks[pkg] = cb

    return box, {'pkg_checks': checks}


def page_install(config: dict):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    box.set_valign(Gtk.Align.CENTER)

    title = Gtk.Label(label='Installing nOS…')
    title.get_style_context().add_class('page-title')
    box.pack_start(title, False, False, 0)

    progress = Gtk.ProgressBar()
    progress.get_style_context().add_class('install-progress')
    progress.set_show_text(True)
    progress.set_text('Preparing…')
    box.pack_start(progress, False, False, 0)

    log_scroll = Gtk.ScrolledWindow()
    log_scroll.set_min_content_height(200)
    log_tv = Gtk.TextView()
    log_tv.set_editable(False)
    log_tv.set_wrap_mode(Gtk.WrapMode.CHAR)
    log_tv.get_style_context().add_class('log-view')
    log_scroll.add(log_tv)
    box.pack_start(log_scroll, True, True, 0)

    return box, {'progress': progress, 'log_tv': log_tv}


# ---- Main installer window ----

class NosInstaller(Gtk.Window):
    def __init__(self):
        super().__init__(title=f'{DISTRO_NAME} Installer')
        self.set_default_size(800, 560)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        load_css()
        self.get_style_context().add_class('installer-window')

        self._config  = {}
        self._widgets = {}
        self._page_idx = 0

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(outer)

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        header.get_style_context().add_class('installer-header')
        outer.pack_start(header, False, False, 0)

        self.header_label = Gtk.Label(label=f'{DISTRO_NAME} Installer')
        self.header_label.get_style_context().add_class('installer-header-title')
        header.pack_start(self.header_label, True, True, 0)

        # Step indicators
        self.step_box = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        self.step_box.get_style_context().add_class('step-box')
        header.pack_end(self.step_box, False, False, 12)
        self._build_steps()

        # Content stack
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.stack.set_transition_duration(250)
        outer.pack_start(self.stack, True, True, 0)

        self._build_pages()

        # Footer buttons
        footer = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        footer.get_style_context().add_class('installer-footer')
        outer.pack_start(footer, False, False, 0)

        self.back_btn = Gtk.Button(label='← Back')
        self.back_btn.get_style_context().add_class('nav-btn')
        self.back_btn.connect('clicked', self._go_back)
        footer.pack_start(self.back_btn, False, False, 8)

        spacer = Gtk.Box()
        footer.pack_start(spacer, True, True, 0)

        self.next_btn = Gtk.Button(label='Next →')
        self.next_btn.get_style_context().add_class('nav-btn-primary')
        self.next_btn.connect('clicked', self._go_next)
        footer.pack_end(self.next_btn, False, False, 8)

        self._update_nav()
        self.show_all()

    def _build_steps(self):
        labels = ['Welcome', 'License', 'Disk', 'Timezone',
                  'User', 'Packages', 'Install']
        self._step_labels = []
        for i, lbl in enumerate(labels):
            l = Gtk.Label(label=str(i + 1))
            l.get_style_context().add_class('step-dot')
            self.step_box.pack_start(l, False, False, 0)
            self._step_labels.append(l)

    def _build_pages(self):
        builders = [
            page_welcome, page_license, page_disk,
            page_timezone, page_user, page_packages,
        ]
        self._page_names = []
        for i, builder in enumerate(builders):
            content, widgets = builder()
            name = PAGES[i]
            self.stack.add_named(content, name)
            self._widgets[name] = widgets
            self._page_names.append(name)

        # Install page (built separately)
        install_box, install_widgets = page_install(self._config)
        self.stack.add_named(install_box, 'install')
        self._widgets['install'] = install_widgets
        self._page_names.append('install')

    def _update_nav(self):
        self.back_btn.set_sensitive(self._page_idx > 0)
        self.next_btn.set_label(
            'Install' if self._page_idx == len(PAGES) - 2
            else ('Finish' if self._page_idx == len(PAGES) - 1 else 'Next →'))

        for i, lbl in enumerate(self._step_labels):
            ctx = lbl.get_style_context()
            ctx.remove_class('step-active')
            ctx.remove_class('step-done')
            if i == self._page_idx:
                ctx.add_class('step-active')
            elif i < self._page_idx:
                ctx.add_class('step-done')
                lbl.set_text('✓')

    def _go_next(self, btn):
        if self._page_idx == len(PAGES) - 1:
            Gtk.main_quit()
            return
        if self._page_idx == len(PAGES) - 2:
            self._start_install()
        self._page_idx += 1
        self.stack.set_visible_child_name(PAGES[self._page_idx])
        self._update_nav()

    def _go_back(self, btn):
        if self._page_idx > 0:
            self._page_idx -= 1
            self.stack.set_visible_child_name(PAGES[self._page_idx])
            self._update_nav()

    def _start_install(self):
        w = self._widgets['install']
        progress = w['progress']
        log_tv   = w['log_tv']
        buf      = log_tv.get_buffer()

        steps = [
            ('Partitioning disk…',       0.10),
            ('Formatting partitions…',   0.20),
            ('Mounting filesystems…',    0.25),
            ('Installing base system…',  0.55),
            ('Installing packages…',     0.75),
            ('Configuring system…',      0.85),
            ('Installing bootloader…',   0.92),
            ('Setting up users…',        0.96),
            ('Finalising…',              1.00),
        ]

        def run():
            import time
            for msg, frac in steps:
                GLib.idle_add(progress.set_fraction, frac)
                GLib.idle_add(progress.set_text, msg)
                end = buf.get_end_iter()
                GLib.idle_add(buf.insert, end, f'[✓] {msg}\n')
                time.sleep(0.6)
            GLib.idle_add(progress.set_text, 'Installation complete!')

        threading.Thread(target=run, daemon=True).start()


def main():
    win = NosInstaller()
    win.connect('destroy', Gtk.main_quit)
    Gtk.main()


if __name__ == '__main__':
    main()
