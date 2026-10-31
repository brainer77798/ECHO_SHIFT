"""
Streamlit front end for ECHO//SHIFT.

ECHO//SHIFT is a Godot 4 (GDScript) 3D game, not a Python app -- Streamlit has no GDScript
interpreter and no real-time 3D renderer, so it can't run the game's own code directly.
Instead, the Godot project is exported ahead of time to HTML5/WebAssembly (see
`export_presets.cfg` and `static/web_export/`), and this script just serves that exported
build through Streamlit's static-file-serving feature and embeds it in an iframe.

Re-exporting after a game change (from the Godot editor, or headless):
    godot --headless --path . --export-release "Web" static/web_export/index.html

Known limitation: LAN co-op does not work in this embedded build. Browsers can't open raw
UDP/ENet sockets, so multiplayer networking (autoload/net.gd) is unreachable from here --
only the single-player campaign is playable in-browser.
"""

import streamlit as st
import streamlit.components.v1 as components

GAME_URL = "app/static/web_export/index.html"
GAME_HEIGHT = 820

st.set_page_config(page_title="ECHO//SHIFT", page_icon="🜔", layout="wide")

st.title("ECHO//SHIFT")
st.caption(
    "A third-person sci-fi action-adventure built in Godot 4, exported to WebAssembly and "
    "embedded below."
)

st.info(
    "Click inside the game frame once it loads so your keyboard and mouse input reach it. "
    "Audio may stay muted until that first click (browser autoplay policy). This build is "
    "single-player only -- LAN co-op needs real network sockets a browser can't open.",
    icon="ℹ️",
)

components.iframe(src=f"/{GAME_URL}", height=GAME_HEIGHT, scrolling=False)

with st.expander("About ECHO//SHIFT"):
    st.markdown(
        """
You play an Echo-certified operative recovering a research station after a temporal-replay
cascade. Your signature ability is the **Echo**: record your last few seconds of movement,
firing and interaction, then project a holographic replay of yourself to distract enemies,
hold pressure plates, and solve puzzles that need two of "you" at once.

Everything in the game -- geometry, materials, shaders, music, sound effects, UI -- is
generated procedurally in code. There are no imported art or audio assets.

The single-player campaign runs Main Menu &rarr; 5 chapters &rarr; a boss fight &rarr; one of
3 endings.
        """
    )

with st.expander("Controls"):
    st.markdown(
        """
| Input | Action |
|---|---|
| `W A S D` | Move (camera-relative) |
| Mouse | Look / aim |
| Left Mouse | Fire blaster |
| `E` | Interact |
| `Space` (configurable) | Dash (brief invulnerability) |
| configurable | Project Echo |
| `Esc` | Pause |

All bindings are rebindable from the in-game Settings menu (keyboard, mouse, and gamepad are
all supported).
        """
    )

with st.expander("Chapters"):
    st.markdown(
        """
| Chapter | Theme | Puzzle / content highlight |
|---|---|---|
| 1 -- The Arrival | Dock / cargo hall / comms relay | Tutorial + echo-on-plate door puzzle |
| 2 -- Research Division | Laboratory wing | Ordered 3-switch sequence + echo-only guarded plate |
| 3 -- Security Grid | Surveillance core | Camera-watched corridor + 3-relay hub + Armored Brute arena |
| 4 -- Broken Core | Experimental chambers | Dual simultaneous echo-plates (needs both echo slots) |
| 5 -- The Final Echo | Chrono Core chamber | WARDEN boss fight + 3 ending consoles |
        """
    )
