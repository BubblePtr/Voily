app_path = defines["app_path"]
background_path = defines["background_path"]

format = "UDZO"
filesystem = "HFS+"
compression_level = 9

files = [(app_path, "Voily.app")]
symlinks = {"Applications": "/Applications"}
background = background_path

window_rect = ((120, 120), (640, 413))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_sidebar = False
icon_size = 96
text_size = 13
arrange_by = None

icon_locations = {
    "Voily.app": (180, 290),
    "Applications": (470, 290),
}
