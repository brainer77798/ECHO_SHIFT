"""
ECHO//SHIFT - Central Game Settings and Configuration
"""

GAME_TITLE = "ECHO//SHIFT"
VERSION = "1.0.0"

# Display & Window
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
TARGET_FPS = 60
FULLSCREEN = False

# Color Palette (Neon Sci-Fi Aesthetic)
BACKGROUND = (7, 20, 33)          # #071421 Near-black navy
GRID_COLOR = (15, 35, 49)          # Subtle grid lines
BORDER_COLOR = (28, 83, 99)        # Arena wall borders
WHITE = (240, 245, 250)            # Cool white text/highlights
MUTED = (115, 140, 160)            # Secondary blue-gray text
DARK_OVERLAY = (5, 12, 22, 215)    # Modal backdrop

# Player Colors (Up to 4 Co-op Players)
PLAYER_COLORS = [
    (54, 241, 205),   # Player 1: Bright Cyan (#36F1CD)
    (255, 184, 76),   # Player 2: Bright Amber (#FFB84C)
    (93, 226, 110),   # Player 3: Emerald Green (#5DE26E)
    (255, 110, 199),  # Player 4: Neon Pink (#FF6EC7)
]
PLAYER_COLOR = PLAYER_COLORS[0]

# Echo & Energy Colors
ECHO_COLOR = (139, 114, 255)       # Electric Violet (#8B72FF)
ECHO_TRAIL_COLOR = (180, 160, 255) # Lighter violet
SHARD_COLOR = (255, 220, 90)       # Golden energy shard

# Enemy & Hazard Colors
ENEMY_COLOR = (255, 82, 99)        # Red (#FF5263)
ENEMY_SECONDARY = (160, 32, 54)
BOSS_CORE_COLOR = (255, 45, 75)
DANGER_ZONE_COLOR = (255, 50, 70, 70)

# Gameplay Balance
PLAYER_RADIUS = 16
PLAYER_SPEED = 240.0
PLAYER_MAX_HEALTH = 100

# Weapons & Projectiles
SHOT_SPEED = 620.0
SHOT_COOLDOWN = 0.18
SHOT_RADIUS = 4
PLAYER_SHOT_DAMAGE = 1.0

# Dash
DASH_DISTANCE = 115.0
DASH_COOLDOWN = 1.2
DASH_DURATION = 0.16

# Echo System (Core Hook)
RECORDING_SECONDS = 5.0            # Last 5.0 seconds recorded
RECORDING_SAMPLE_RATE = 25.0       # Samples per second (dt ~0.04s)
MAX_ECHOES_PER_PLAYER = 2          # Maximum active echoes per player
ECHO_COOLDOWN = 2.5                # Cooldown between creating echoes
ECHO_DAMAGE_MULTIPLIER = 0.55      # 55% of standard player damage
ECHO_POST_REPLAY_HOLD_TIME = 2.5   # Seconds echo persists at end to hold plates
ECHO_FADE_WARNING_TIME = 1.0       # Flashing / fade warning before despawning

# Network Settings
DEFAULT_PORT = 42424
NETWORK_TICK_RATE = 30             # Server ticks per second
MAX_CLIENTS = 4
MAX_PACKET_BYTES = 65536
PROTOCOL_VERSION = 1
