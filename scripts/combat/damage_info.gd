class_name DamageInfo
extends RefCounted
## Describes one instance of damage. Any node with take_damage(info: DamageInfo) is damageable.

var amount := 10.0
var team := Cfg.TEAM_PLAYER        # team of the attacker
var source: Node = null            # node that dealt the damage (player, echo, enemy, hazard)
var source_player: Node = null     # the Player responsible (an Echo points at its owner)
var from_echo := false
var direction := Vector3.ZERO
var point := Vector3.ZERO
var knockback := 0.0
var kind := "blaster"              # blaster | melee | explosion | hazard | boss

static func make(p_amount: float, p_team: int, p_source: Node = null, p_kind := "blaster") -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = p_amount
	d.team = p_team
	d.source = p_source
	d.kind = p_kind
	return d
