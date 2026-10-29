project(
    'coucou-wingpanel-indicator',
    'vala', 'c',
    version: '0.1.0',
    meson_version: '>=0.57.0'
)

wingpanel_dep = dependency('wingpanel')
indicators_dir = wingpanel_dep.get_variable('indicatorsdir')

# Same warning flags as the indicators that ship with the desktop; the module is
# loaded into the panel, so it must not export anything but get_indicator().
add_project_arguments(['-DGETTEXT_PACKAGE="coucou-wingpanel-indicator"'], language: 'c')

shared_module(
    'coucou',
    'src/Indicator.vala',
    dependencies: [
        dependency('glib-2.0'),
        dependency('gobject-2.0'),
        dependency('gmodule-2.0'),
        dependency('gtk+-3.0'),
        dependency('json-glib-1.0'),
        dependency('gee-0.8'),
        wingpanel_dep,
    ],
    install: true,
    install_dir: indicators_dir,
)
