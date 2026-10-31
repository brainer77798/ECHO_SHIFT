# ECHO//SHIFT (legacy Python/Pygame prototype — superseded)

> **This document describes an earlier prototype, not the current game.** ECHO//SHIFT is now a 3D Godot 4
> project at the repository root — see `../README.md` and `../PROGRESS.md` for the current, maintained game and
> its build status. This folder and README are kept only as historical/design reference (e.g. the LAN co-op
> protocol described below was fully working here before the Godot rewrite, which is why it's a useful reference
> for re-implementing co-op in Godot). Nothing below is being actively maintained.

**ECHO//SHIFT** is a top-down, neon sci-fi cooperative action-puzzle game built with Python and Pygame. Set inside a fractured temporal research facility overrun by rogue security automata and a reactor intelligence known as **THE WARDEN**, players harness temporal replication to fight, solve environmental puzzles, and stabilize the reactor core.

---

## 1. The Core Hook: The Echo System

Every player continuously records the last **5.0 seconds** of their movements, aiming directions, dash actions, and weapons fire into a bounded simulation buffer.

- **Projection (`E` key):** Pressing `E` projects a holographic, electric-violet **Echo** of yourself starting at your past recorded location.
- **Chronological Replay:** The Echo faithfully replays your past movement and discharges weapons with your recorded firing vectors and timings.
- **Combat Assistance:** Echo projectiles deal balanced damage (**55%** of standard player damage) and draw enemy aggression, enabling flanking tactics against shielded enemies.
- **Puzzle Solving:** Echoes interact with real puzzle physics—activating floor **Pressure Plates** and temporal switches. After replay completes, the Echo holds its final position for **2.5 seconds** with a visual fade warning, keeping gates open while you maneuver elsewhere.
- **Authoritative Balance:** Each player can maintain at most **2 active Echoes**; projecting a third automatically replaces the oldest.

---

## 2. Game Modes

### A. Single-Player (Offline)
- Play through all 3 campaign levels alone without any network connection required.
- Full offline simulation of movement, Echo projection, puzzle solving, combat waves, and boss encounters.

### B. Local Network Co-Op (LAN, 2–4 Players)
- Connect 2 to 4 human players over the local area network using IPv4.
- **Server-Authoritative Architecture:** The server controls all physics, enemy AI, projectile collisions, health, damage, shard collection, puzzle locks, and score awards.
- **Cheating & Exploit Prevention:** Clients submit only validated control inputs (movement vectors, aim angles, action triggers). The server rejects arbitrary coordinates, fabricated kills, or spoofed scores.
- **Robust TCP Protocol:** Operates over newline-delimited JSON with streaming buffer framing, supporting packet reassembly, partial reads, and graceful disconnect cleanup.
- **Independent Echoes:** Each connected player maintains their own independent identity, health bar, color palette, and Echo slots.
- **Co-op Revives:** Downed teammates can be revived by standing nearby before the temporal collapse countdown expires.

---

## 3. Controls

| Input | Action |
|---|---|
| **W, A, S, D** / Arrows | Move operative (normalized diagonal speed) |
| **Mouse Cursor** | Aim weapon and crosshair |
| **Left Mouse Button** | Discharge plasma pulse rifle |
| **E** | **Project Temporal Echo (Core Hook)** |
| **Space** / **Left Shift** | Tactical dash (high speed, brief invulnerability) |
| **Esc** | Pause game / In-game tactical menu |
| **R** | Restart level after defeat |

---

## 4. Campaign Levels

1. **Level 1: The Training Vault**
   - Introduces movement, aiming, firing, and Echo creation.
   - Teaches players to project an Echo on a floor pressure plate to hold open a heavy security bulkhead door while advancing through.
   - Combat wave against Hunter Drones.
2. **Level 2: The Security Grid**
   - Features tactical pillar cover and introduces two new enemy archetypes:
     - **Sentries:** Ranged turrets with visible charging laser telegraphs.
     - **Armored Brutes:** Heavy automatons with frontal energy shields requiring flanking maneuvers or Echo distractions.
   - Dual temporal pressure plates requiring coordinated activation.
   - Collect 3 Temporal Energy Shards to unlock the transit portal.
3. **Level 3: The Broken Core (The Warden Boss)**
   - Multi-phase encounter against The Warden:
     - **Phase 1 (100%–60% HP):** 3-way aimed plasma barrages and drone reinforcements.
     - **Phase 2 (60%–30% HP):** Impervious temporal shield activated. Operatives and Echoes must hold down the **Temporal Disruptor Plates** to breach the shield and expose the core!
     - **Phase 3 (30%–0% HP):** Overdrive spiral barrages with exposed core.
   - Defeating The Warden unlocks the victory screen and final operational score summary.

---

## 5. Installation and Setup

### Prerequisites
- Windows 10/11
- Python 3.10+ (Python 3.12 included in local `.venv`)

### Virtual Environment Setup
If not already configured, create and activate a virtual environment:
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

---

## 6. How to Launch and Play

### Quick Launch Batch Scripts
- **Solo Mode:** Double-click `run_solo.bat`
- **Host LAN Server:** Double-click `run_server.bat`
- **Game Client:** Double-click `run_client.bat`

### Manual Terminal Commands

#### 1. Launch Single-Player Mode
```powershell
.\.venv\Scripts\python.exe main.py
```
Click **SINGLE PLAYER** on the main menu.

#### 2. Host a LAN Co-Op Game
You can host a game directly in the GUI or via the dedicated server CLI:
- **In-Game GUI:** Launch `main.py` and click **HOST LAN CO-OP**. The game will start an authoritative server and automatically connect you.
- **Dedicated Server CLI:**
  ```powershell
  .\.venv\Scripts\python.exe server.py --host 0.0.0.0 --port 42424
  ```
  The server console displays your machine's local IP address (e.g., `192.168.1.50:42424`).

#### 3. Join a LAN Game as a Second Player
1. Launch the game on a second computer (or a second terminal window on the same machine):
   ```powershell
   .\.venv\Scripts\python.exe main.py
   ```
2. Click **JOIN LAN GAME**.
3. Enter the Host IP address (or `127.0.0.1` if testing on the same PC), Port `42424`, and your player codename.
4. Click **CONNECT & JOIN**.

---

## 7. Windows Firewall & Networking Notes

When hosting or joining over a local network:
1. Ensure both computers are on the same local subnet / Wi-Fi network.
2. If Windows Defender Firewall displays a prompt, select **Allow access for Private networks**.
3. Do not disable Windows Firewall. If connection fails, check that TCP port `42424` is permitted inbound on the host machine.

---

## 8. Audio System

ECHO//SHIFT includes a procedural synthesizer that generates retro-futuristic sound effects in-memory (plasma shots, Echo warp whoosh, hits, explosions, switch clicks, and alarms).
- **Zero external audio files required.**
- **Automatic Fallback:** If audio hardware is absent or muted, the game runs silently without crashing.

---

## 9. Automated Testing

Run the full automated test suite covering Echo recording and playback, directional shields, collision detection, level progression, single-award scoring, and multi-client headless LAN server synchronization:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

To compile all Python source files:
```powershell
.\.venv\Scripts\python.exe -m compileall -x "\.venv" .
```
