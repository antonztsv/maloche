# dmgbuild settings, the window layout goes into .DS_Store without Finder or AppleScript
import os.path

app = defines.get("app", "build/maloche.app")  # noqa: F821, defines is injected by dmgbuild
name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_size = 128
window_rect = ((200, 200), (540, 360))
icon_locations = {name: (140, 170), "Applications": (400, 170)}
