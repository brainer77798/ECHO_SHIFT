extends Node
## Centralised configuration: physics layers, palette and tuning values.
## Everything gameplay-relevant that a designer may want to tweak lives here.

# --- Physics layers (bit masks, see project.godot [layer_names]) -------------
const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_ECHO := 8
const L_PPROJ := 16
const L_EPROJ := 32
const L_TRIGGER := 64
const L_HAZARD := 128

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1

# --- World grid --------------------------------------------------------------
const TILE := 2.0
const WALL_H := 5.0

# --- Palette -------------------------------------------------------------------
const C_CYAN := Color(0.10, 0.90, 1.00)
const C_BLUE := Color(0.15, 0.45, 1.00)
const C_RED := Color(1.00, 0.16, 0.20)
const C_ORANGE := Color(1.00, 0.50, 0.12)
const C_AMBER := Color(1.00, 0.78, 0.22)
const C_GREEN := Color(0.25, 1.00, 0.55)
const C_VIOLET := Color(0.62, 0.30, 1.00)
const C_WHITE := Color(0.92, 0.97, 1.00)
const C_METAL := Color(0.16, 0.19, 0.24)

# --- Player ----------------------------------------------------------------------
const PLAYER_MAX_HEALTH := 100.0
const PLAYER_SPEED := 6.5
const PLAYER_ACCEL := 48.0
const PLAYER_FRICTION := 60.0
const PLAYER_RADIUS := 0.38
const PLAYER_HEIGHT := 1.8
const GRAVITY := 28.0

const DASH_SPEED := 19.0
const DASH_TIME := 0.20
const DASH_COOLDOWN := 1.10
const DASH_IFRAMES := 0.26

const BLASTER_DAMAGE := 12.0
const BLASTER_COOLDOWN := 0.17
const BLASTER_SPEED := 62.0
const BLASTER_RANGE := 70.0
const HEAT_PER_SHOT := 7.0
const HEAT_COOL_RATE := 34.0
const HEAT_COOL_DELAY := 0.35
const HEAT_MAX := 100.0
const HEAT_RECOVER := 35.0

# --- Echo ------------------------------------------------------------------------
const ECHO_MAX_ACTIVE := 2
const ECHO_RECORD_TIME := 5.0
const ECHO_BUFFER_CAPACITY_TIME := 10.0   # allocated seconds (upgrade ceiling)
const ECHO_MIN_RECORD := 1.0
const ECHO_BASE_DAMAGE_MULT := 0.55
const ECHO_BASE_LINGER := 3.0
const ECHO_LURE_FACTOR := 0.65            # enemies treat echoes as this much "closer"

# --- Upgrades ---------------------------------------------------------------------
const UPGRADES := {
	"hull": {"name": "Reinforced Plating", "desc": "+25 maximum health per level.", "max": 4, "costs": [35, 60, 95, 140]},
	"blaster": {"name": "Overcharged Blaster", "desc": "+15% blaster damage and slightly faster fire rate per level.", "max": 4, "costs": [40, 70, 105, 150]},
	"dash": {"name": "Servo Overdrive", "desc": "Dash cooldown shortened by 0.18s per level.", "max": 3, "costs": [45, 80, 120]},
	"buffer": {"name": "Chrono Buffer", "desc": "Records 1.0s more of your actions per level.", "max": 3, "costs": [50, 90, 140]},
	"echo": {"name": "Echo Resonance", "desc": "Echo damage +10% and echoes linger 1.2s longer per level.", "max": 3, "costs": [45, 85, 125]},
}

# --- Chapter metadata ---------------------------------------------------------------
const CHAPTERS := [
	{"title": "THE ARRIVAL", "sub": "Outer Facility", "scene": "res://scenes/levels/chapter_1.tscn"},
	{"title": "RESEARCH DIVISION", "sub": "Laboratory Wing", "scene": "res://scenes/levels/chapter_2.tscn"},
	{"title": "SECURITY GRID", "sub": "Surveillance Core", "scene": "res://scenes/levels/chapter_3.tscn"},
	{"title": "BROKEN CORE", "sub": "Experimental Chambers", "scene": "res://scenes/levels/chapter_4.tscn"},
	{"title": "THE FINAL ECHO", "sub": "Chrono Core Chamber", "scene": "res://scenes/levels/chapter_5.tscn"},
]

const SAVE_VERSION := 1
const NET_PORT := 42424
const NET_MAX_PLAYERS := 4
