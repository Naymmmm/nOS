project('noscomp', 'c',
  version: '0.1.0',
  license: 'MIT',
  default_options: [
    'c_std=c11',
    'warning_level=2',
    'werror=false',
  ],
)

cc = meson.get_compiler('c')

wlroots      = dependency('wlroots', version: '>= 0.17')
wayland_srv  = dependency('wayland-server')
wayland_protos = dependency('wayland-protocols')
xkbcommon    = dependency('xkbcommon')
libinput     = dependency('libinput')
pixman       = dependency('pixman-1')
egl          = dependency('egl')
glesv2       = dependency('glesv2')
math         = cc.find_library('m', required: true)

wayland_scanner = find_program('wayland-scanner')

add_project_arguments(
  '-DWLR_USE_UNSTABLE',
  '-D_POSIX_C_SOURCE=200809L',
  language: 'c',
)

# ---- Generate protocol headers ----

# xdg-shell (from system wayland-protocols)
xdg_shell_xml = wayland_protos.get_variable('pkgdatadir') / 'stable/xdg-shell/xdg-shell.xml'

xdg_shell_h = custom_target('xdg-shell-protocol.h',
  input:   xdg_shell_xml,
  output:  'xdg-shell-protocol.h',
  command: [wayland_scanner, 'server-header', '@INPUT@', '@OUTPUT@'],
)

# wlr-layer-shell (bundled XML from wlroots)
layer_shell_xml = files('protocol/wlr-layer-shell-unstable-v1.xml')

layer_shell_h = custom_target('wlr-layer-shell-unstable-v1-protocol.h',
  input:   layer_shell_xml,
  output:  'wlr-layer-shell-unstable-v1-protocol.h',
  command: [wayland_scanner, 'server-header', '@INPUT@', '@OUTPUT@'],
)

proto_headers = [xdg_shell_h, layer_shell_h]
proto_inc = include_directories('.')   # build dir, where generated headers land

# ---- Sources ----

sources = [
  files(
    'src/main.c',
    'src/server.c',
    'src/output.c',
    'src/scene.c',
    'src/xdg_shell.c',
    'src/layer_shell.c',
    'src/xwayland.c',
    'src/input.c',
    'src/cursor.c',
    'src/blur.c',
    'src/shadow.c',
    'src/animation.c',
    'src/wobble.c',
    'src/decoration.c',
  ),
  proto_headers,
]

executable('noscomp',
  sources,
  include_directories: [
    include_directories('include'),
    proto_inc,
  ],
  dependencies: [
    wlroots,
    wayland_srv,
    wayland_protos,
    xkbcommon,
    libinput,
    pixman,
    egl,
    glesv2,
    math,
  ],
  install: true,
  install_dir: get_option('bindir'),
)
