extends "res://scripts/goblin.gd"
## The troll: a goblin the size of a house. Brown, massive, and swinging a heavy
## wooden club with the hardest knockback in the game. He reuses the goblin's
## arena chase brain (find the nearest player on the disc, close in, swing) but:
##
##  - his club hits FAR harder and reaches farther, and he's slow;
##  - because he's so big he does NOT ragdoll when hit. A player's blow just
##    SHOVES him back a little, with no immunity window -- so the only way to
##    beat him is to gang up and shove him off the arena edge into the pit.

const CLUB_KNOCKBACK := 22.0    # revolver is 16; the club is the hardest hit
const CLUB_RANGE := 4.8         # a giant's reach
const CLUB_COOLDOWN := 2.2      # slow, telegraphed swings
const TROLL_CHASE_MULT := 0.85  # lumbering; slower than a goblin's scramble

# Getting hit shoves him: a brief burst of backward velocity that his AI is
# locked out of overriding until it decays. No immunity, so hits stack and a
# team can walk him to the edge.
const SHOVE_SCALE := 0.6        # backward speed per point of incoming knockback
const SHOVE_TIME := 0.35        # how long the shove overrides his walk
const SHOVE_DECEL := 18.0

@onready var club: Node3D = $Mesh/ClubPivot

var _shove_timer := 0.0


func _ready() -> void:
	super()
	arena_mode = true
	add_to_group("troll")
	attack_range = CLUB_RANGE
	attack_cooldown_time = CLUB_COOLDOWN
	attack_knockback = CLUB_KNOCKBACK
	chase_speed_mult = TROLL_CHASE_MULT


func _ai(delta: float) -> void:
	# While being shoved, coast backward and ignore the chase until it decays.
	if _shove_timer > 0.0:
		_shove_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, SHOVE_DECEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, SHOVE_DECEL * delta)
		return
	super(delta)


func _attack(_prey: Node3D, dir: Vector3) -> void:
	_play_club.rpc()
	_prey.apply_knockback(dir, attack_knockback)


## Server-side hit response. No ragdoll, no immunity: just a shove backward that
## his walk can't cancel until it fades.
func apply_knockback(dir: Vector3, power: float) -> void:
	if not multiplayer.is_server():
		return
	if frozen:
		return
	var flat := (dir * Vector3(1, 0, 1)).normalized()
	velocity.x = flat.x * power * SHOVE_SCALE
	velocity.z = flat.z * power * SHOVE_SCALE
	_shove_timer = SHOVE_TIME


## Cosmetic club swing, broadcast to every peer (same pattern as the goblin stab).
@rpc("authority", "call_local", "reliable")
func _play_club() -> void:
	if club == null:
		return
	var tween := create_tween()
	club.rotation.x = 0.0
	tween.tween_property(club, "rotation:x", 1.6, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(club, "rotation:x", 0.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
