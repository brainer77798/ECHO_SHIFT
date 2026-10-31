extends Node
## Global event bus. Gameplay objects emit here; UI, audio and managers listen.

signal objective_changed(text: String)
signal hud_message(text: String, color: Color, duration: float)
signal dialogue_requested(speaker: String, lines: Array, voice: String)
signal terminal_requested(entry: Dictionary)
signal upgrade_bench_requested
signal player_health_changed(hp: float, max_hp: float)
signal player_damaged(amount: float, from_dir: Vector3)
signal player_died(player: Node)
signal player_respawned
signal echo_created(player: Node, echo: Node)
signal echo_expired(player: Node, echo: Node)
signal echo_replaced(player: Node)
signal echo_failed(reason: String)
signal enemy_defeated(enemy: Node)
signal log_collected(id: String)
signal checkpoint_reached(id: String)
signal chapter_completed(index: int)
signal ending_chosen(kind: String)
signal boss_bar(visible: bool, title: String, ratio: float, phase_text: String)
signal screen_shake(strength: float)
signal screen_flash(color: Color, time: float)
signal interact_prompt(text: String)
signal fragments_changed(total: int)
signal level_ready
signal request_pause
