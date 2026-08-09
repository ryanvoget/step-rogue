extends CanvasLayer

const JOYSTICK_RADIUS := 58.0 # move/fire rings — sized to fit inside the bottom border band
                               # (between the raised map wall and the screen bottom)
const KNOB_RADIUS     := 26.0
const DEAD_ZONE       := 10.0

# ── Move joystick (left) ───────────────────────────────────────────────────
var _joy_center:  Vector2 = Vector2.ZERO
var _joy_touch:   int = -1
var _knob_offset: Vector2 = Vector2.ZERO

# ── Aim joystick (right) ───────────────────────────────────────────────────
var _aim_center:  Vector2 = Vector2.ZERO
var _aim_touch:   int = -1
var _aim_offset:  Vector2 = Vector2.ZERO

# ── Equipment control (above the fire button): a tap-button for placeables (Turret),
# or a drag-to-aim/release-to-throw joystick for throwables (Blast Grenade) ────────────
const DEPLOY_BUTTON_RADIUS := 32.0
const THROW_RADIUS         := 72.0 # joystick ring radius for throwables. Bigger = LESS sensitive:
                                    # the aim direction is the exact angle from ring-centre to the
                                    # finger, so a larger ring means more finger travel per degree,
                                    # making it easier to fine-tune where a grenade is guided.
const THROW_KNOB_RADIUS    := 22.0
const DEPLOY_TOUCH_RADIUS  := THROW_RADIUS + 6.0 # tap-catch radius, kept close to the drawn ring
                                    # so it doesn't overlap the fire joystick zone or the health
                                    # bar / heal button it sits beside
var _deploy_center: Vector2 = Vector2.ZERO
var _deploy_touch:  int = -1
var _throw_offset:  Vector2 = Vector2.ZERO

# ── Sniper Rifle Blaster charge bar (replaces the aim joystick/attack button entirely
# when equipped — see GameManager.sniper_* and player.gd's set_sniper_stats) ───────────────
const SNIPER_BAR_WIDTH  := 32.0
const SNIPER_BAR_HEIGHT := 144.0 # matches the aim joystick's ~144px (JOYSTICK_RADIUS*2) footprint
const SNIPER_BAR_TOUCH_MARGIN := 20.0 # extra tap-zone padding around the drawn bar

# ── Heal button (Small Heal Vial, Passive Health Regen Vials, Stim Shot, Heal Dispenser
# Farm), centered between the move and aim joysticks — a one-shot tap, like the placeable
# equipment button ────────────────────────────────────────────────────────────────────────
const HEAL_BUTTON_RADIUS := 30.0
const HEAL_TOUCH_MARGIN  := 12.0 # small catch margin around the blue button — kept tight so it
                                  # doesn't bleed into the green control on its left or the fire
                                  # joystick zone on its right
var _heal_center: Vector2 = Vector2.ZERO
var _heal_touch:  int = -1

# ── Speed Boost Battery (equipment), in the same slot as the deploy button/throw joystick
# above — see item_registry.gd's battery field docs. A tap-button while ready (drawn like
# _draw_deploy_button); once activated, replaced by a bar (this const's footprint) that
# depletes then recharges, non-interactive the whole time ──────────────────────────────────
const BATTERY_BAR_WIDTH  := 28.0
const BATTERY_BAR_HEIGHT := 64.0

# ── Shared "mana bar above the button/joystick" style, same slot as the deploy button — used
# by any equipment with a non-regenerating resource (Force Push Bracelet's hold joystick,
# Temporary Invincible Battery's tap button, ...). Stays visible the whole time (unlike the
# battery bar, which replaces the button) — the button/joystick just greys out at zero mana ──
const EQUIPMENT_BAR_WIDTH  := 64.0
const EQUIPMENT_BAR_HEIGHT := 18.0
const EQUIPMENT_BAR_GAP    := 22.0 # gap between the button/ring's edge and the bar above it
const EQUIPMENT_BAR_ALPHA           := 0.5  # base opacity while mana remains
const EQUIPMENT_BAR_DEPLETED_ALPHA  := 0.25 # dimmer once mana hits zero, per spec

var _draw_node: Node2D = null
var _ready_done := false
var _was_shield_active := false # tracks the falling edge so a shield breaking gets one final redraw

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_draw_node = Node2D.new()
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	call_deferred("_init_positions")

func _process(_delta: float) -> void:
	# The charge bar fills continuously (driven by player.gd every physics frame), independent
	# of any touch event, so it needs its own redraw trigger rather than the event-driven
	# queue_redraw() calls everything else here uses.
	if GameManager.sniper_equipped:
		_draw_node.queue_redraw()
	# Same reasoning as the sniper bar above — the battery bar fills/depletes continuously
	# (driven by player.gd's _tick_battery every physics frame), independent of touch events.
	if GameManager.equipment_battery and GameManager.battery_state != GameManager.BATTERY_READY:
		_draw_node.queue_redraw()
	# Same reasoning again — the mana bar drains continuously while held (player.gd's
	# _tick_force_push every physics frame).
	if GameManager.equipment_force_push and GameManager.force_push_held:
		_draw_node.queue_redraw()
	# Same reasoning again — the mana bar drains continuously while active (player.gd's
	# _tick_invincible every physics frame).
	if GameManager.equipment_invincible and GameManager.invincible_active:
		_draw_node.queue_redraw()
	# Shield HP only changes on discrete damage hits rather than continuously, but polling
	# here (instead of wiring a signal from player.gd's take_damage) keeps the bar in sync
	# within a frame with no extra cross-file plumbing, consistent with the bars above.
	# Godot's _draw() output persists on the canvas until the next queue_redraw() — a shield
	# breaking is a one-frame transition (active -> gone entirely, since _heal_active hides it
	# once broken), and polling only "while active" means the exact frame it breaks never gets
	# a redraw to reflect that, so the stale "still active" bar/button sticks around until some
	# unrelated touch/redraw happens to catch it up. Redrawing once more on the falling edge
	# (was active, now isn't) forces _draw() to run with the now-hidden state immediately.
	var shield_active_now := GameManager.shield_equipped and GameManager.shield_active
	if shield_active_now or _was_shield_active:
		_draw_node.queue_redraw()
	_was_shield_active = shield_active_now
	# Safety net: if a touch release for the equipment joystick was ever missed (has happened
	# on iOS with interrupted touches), self-correct every frame instead of leaving the aim
	# preview line (or force push joystick) stuck showing/active with no finger actually down.
	if _deploy_touch == -1:
		if GameManager.aim_preview_active or GameManager.aim_preview_dir.length() > 0.0:
			GameManager.aim_preview_active = false
			GameManager.aim_preview_dir = Vector2.ZERO
			GameManager.aim_preview_fraction = 0.0
			_draw_node.queue_redraw()
		if GameManager.force_push_held or GameManager.force_push_dir.length() > 0.0:
			GameManager.force_push_held = false
			GameManager.force_push_dir = Vector2.ZERO
			_draw_node.queue_redraw()

# Landscape control row along the bottom strip (below the raised map wall): move joystick far
# left, fire joystick far right, the green equipment control in the middle-left, and the blue
# heal button to its right. Their touch zones (see _in_move_zone/_in_aim_zone/_in_deploy_zone)
# are kept tight to each control so the centrally-placed green control and the fire joystick
# can't steal each other's touches.
func _init_positions() -> void:
	var vp := get_viewport().get_visible_rect().size
	# Move/fire joysticks are vertically centered in the bottom border band (between the map's
	# bottom wall edge ~352 and the screen bottom 480 → y ≈ 416). The blue heal button and green
	# equipment control flank the centered health bar, sitting just outside its left/right edges
	# and a touch lower (aligned with the bar, y ≈ 438).
	_joy_center    = Vector2(vp.x * 0.13,  vp.y * 0.867)
	_aim_center    = Vector2(vp.x * 0.87,  vp.y * 0.867)
	_heal_center   = Vector2(vp.x * 0.328, vp.y * 0.912)
	_deploy_center = Vector2(vp.x * 0.690, vp.y * 0.912)
	_ready_done = true
	_draw_node.queue_redraw()

# Move/aim joystick catch zones — narrowed to the bottom outer corners (instead of full left/
# right halves) so the middle of the bottom strip is reserved for the green equipment control
# and blue heal button, whose own tight radius zones are checked first.
const MOVE_ZONE_MAX_X := 0.24 # touches left of this fraction (bottom half) grab the move stick
const AIM_ZONE_MIN_X  := 0.76 # touches right of this fraction (bottom half) grab the aim stick

func _in_move_zone(pos: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	return pos.x < vp.x * MOVE_ZONE_MAX_X and pos.y >= vp.y * 0.5

func _in_aim_zone(pos: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	return pos.x >= vp.x * AIM_ZONE_MIN_X and pos.y >= vp.y * 0.5

# True while there's a placeable/throwable/mine/barrier/summon equipment item that hasn't been
# used yet this run (world.gd sets equipment_deployed after one use; sandbox.gd may not, to
# allow repeat testing), OR a battery/force_push/hoverboard/invincible-type equipment item —
# all four are repeatable/persistent (no equipment_deployed one-shot flag applies to any of
# them), so they're always "active" once equipped.
func _deploy_active() -> bool:
	# Battery is a persistent, repeatable item (recharge model): always present once equipped —
	# the button shows while READY, the bar while ACTIVE/RECHARGING (see _draw at BATTERY_READY).
	if GameManager.equipment_battery:
		return true
	if GameManager.equipment_force_push or GameManager.equipment_hoverboard or GameManager.equipment_invincible:
		return true
	return (GameManager.equipment_placeable or GameManager.equipment_throwable or GameManager.equipment_mine \
		or GameManager.equipment_barrier or GameManager.equipment_summon) and not GameManager.equipment_deployed

# True only while there's a heal_item defensive item equipped that hasn't been used yet this
# run (world.gd sets heal_item_deployed after one use; sandbox.gd may not, to allow repeat
# testing — same pattern as _deploy_active()). Shield Barriers are the exception: they stay
# visible for as long as the shield is active (not just until first tapped), only disappearing
# once shield_broken — see item_registry.gd's shield field docs.
func _heal_active() -> bool:
	if GameManager.shield_equipped:
		return not GameManager.shield_broken
	return GameManager.heal_item_equipped and not GameManager.heal_item_deployed

# ── Input ─────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _ready_done:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(e: InputEventScreenTouch) -> void:
	# While a game popup is open (e.g. the every-5-rooms reward choice), new presses belong to
	# the popup's buttons, not the game controls — releases still fall through so any control
	# held when the popup opened cleans up normally.
	if e.pressed and GameManager.ui_popup_open:
		return
	if e.pressed:
		# Sniper: once armed, ANY touch anywhere fires at that point — checked before
		# move/aim/deploy zones entirely so an armed shot can never be misread as movement.
		if GameManager.sniper_armed:
			GameManager.sniper_armed = false
			GameManager.sniper_fire_requested.emit(e.position)
			_draw_node.queue_redraw()
			return
		if GameManager.sniper_equipped:
			# Only a tap on the full bar arms it; the left half still moves the player
			# normally while charging (movement only locks once armed, above).
			if GameManager.sniper_charge >= GameManager.sniper_charge_time \
					and _in_sniper_bar(e.position):
				GameManager.sniper_armed = true
				_draw_node.queue_redraw()
			elif _joy_touch == -1 and _in_move_zone(e.position):
				_joy_touch = e.index
				_update_joystick(e.position)
			return
		if _deploy_touch == -1 and _deploy_active() and _in_deploy_zone(e.position) \
				and not (GameManager.equipment_battery and GameManager.battery_state != GameManager.BATTERY_READY) \
				and not (GameManager.equipment_force_push and GameManager.force_push_mana <= 0.0) \
				and not (GameManager.equipment_invincible and GameManager.invincible_mana <= 0.0):
			_deploy_touch = e.index
			if GameManager.equipment_battery:
				GameManager.battery_activate_requested.emit()
				_draw_node.queue_redraw()
			elif GameManager.equipment_force_push:
				_update_force_push(e.position)
			elif GameManager.equipment_placeable or GameManager.equipment_mine or GameManager.equipment_barrier \
					or GameManager.equipment_hoverboard or GameManager.equipment_invincible or GameManager.equipment_summon:
				_press_deploy_button()
			else:
				_throw_offset = Vector2.ZERO
				GameManager.aim_preview_active = GameManager.equipment_aim_preview
				GameManager.aim_preview_dir = Vector2.ZERO
				GameManager.aim_preview_fraction = 0.0
				_draw_node.queue_redraw()
		elif _heal_touch == -1 and _heal_active() and e.position.distance_to(_heal_center) <= HEAL_BUTTON_RADIUS + HEAL_TOUCH_MARGIN:
			_heal_touch = e.index
			_press_heal_button()
		elif _joy_touch == -1 and _in_move_zone(e.position):
			_joy_touch = e.index
			_update_joystick(e.position)
		elif _aim_touch == -1 and _in_aim_zone(e.position):
			_aim_touch = e.index
			if GameManager.melee_equipped:
				_press_attack_button()
			elif GameManager.thrown_melee_equipped:
				# Aim-and-release (like the equipment throw joystick), not hold-to-fire —
				# just start tracking the drag; the throw itself happens on release below.
				_aim_offset = Vector2.ZERO
				_draw_node.queue_redraw()
			else:
				_update_aim(e.position)
	else:
		if e.index == _joy_touch:
			_joy_touch   = -1
			_knob_offset = Vector2.ZERO
			_release_move_actions()
			_draw_node.queue_redraw()
		elif e.index == _aim_touch:
			_aim_touch  = -1
			if GameManager.thrown_melee_equipped:
				# No drag past the dead zone means no clear direction was chosen, so the
				# throw is cancelled rather than guessing one — same rule as the grenade.
				if _aim_offset.length() >= DEAD_ZONE:
					GameManager.thrown_melee_throw_requested.emit(_aim_offset.angle())
			else:
				GameManager.mobile_aim_dir = Vector2.ZERO
				Input.action_release("shoot")
			_aim_offset = Vector2.ZERO
			_draw_node.queue_redraw()
		elif e.index == _deploy_touch:
			_deploy_touch = -1
			# Throwables fire on release, in whatever direction the joystick was dragged —
			# independent of movement/weapon-aim direction. No drag past the dead zone means
			# no clear direction was chosen, so the throw is cancelled rather than guessing one.
			if GameManager.equipment_throwable and _throw_offset.length() >= DEAD_ZONE:
				var throw_fraction := _throw_offset.length() / THROW_RADIUS
				GameManager.deploy_equipment_requested.emit(_throw_offset.angle(), throw_fraction)
			_throw_offset = Vector2.ZERO
			GameManager.aim_preview_active = false
			GameManager.aim_preview_dir = Vector2.ZERO
			GameManager.aim_preview_fraction = 0.0
			# Force Push Bracelet stops channeling the instant the joystick is released, same as
			# releasing a beam weapon's fire input.
			GameManager.force_push_held = false
			GameManager.force_push_dir = Vector2.ZERO
			_draw_node.queue_redraw()
		elif e.index == _heal_touch:
			_heal_touch = -1
			_draw_node.queue_redraw()

func _handle_drag(e: InputEventScreenDrag) -> void:
	if GameManager.ui_popup_open:
		return
	if e.index == _joy_touch:
		_update_joystick(e.position)
	elif e.index == _deploy_touch and GameManager.equipment_throwable:
		var delta := e.position - _deploy_center
		if delta.length() > THROW_RADIUS:
			delta = delta.normalized() * THROW_RADIUS
		_throw_offset = delta
		if GameManager.equipment_aim_preview:
			GameManager.aim_preview_dir = delta.normalized() if delta.length() >= DEAD_ZONE else Vector2.ZERO
			GameManager.aim_preview_fraction = delta.length() / THROW_RADIUS
		_draw_node.queue_redraw()
	elif e.index == _deploy_touch and GameManager.equipment_force_push:
		_update_force_push(e.position)
	elif e.index == _aim_touch and GameManager.thrown_melee_equipped:
		var delta := e.position - _aim_center
		if delta.length() > JOYSTICK_RADIUS:
			delta = delta.normalized() * JOYSTICK_RADIUS
		_aim_offset = delta
		_draw_node.queue_redraw()
	elif e.index == _aim_touch and not GameManager.melee_equipped:
		# Melee's right control is a plain press button — dragging the finger around
		# while held has no directional influence, unlike the ranged aim joystick.
		_update_aim(e.position)

func _update_joystick(pos: Vector2) -> void:
	var delta := pos - _joy_center
	if delta.length() > JOYSTICK_RADIUS:
		delta = delta.normalized() * JOYSTICK_RADIUS
	_knob_offset = delta
	_apply_move(delta)
	_draw_node.queue_redraw()

# Force Push Bracelet's joystick: aiming works like the main aim joystick (push past the dead
# zone in a direction to channel that way; release or fall back under the dead zone and it
# stops), not a hold-anywhere button — called on both press (so an initial off-center touch
# aims immediately) and drag. Won't (re-)enable holding once mana is empty, so a lingering
# drag on a depleted bracelet doesn't flicker force_push_held on/off against _tick_force_push.
func _update_force_push(pos: Vector2) -> void:
	var delta := pos - _deploy_center
	if delta.length() > THROW_RADIUS:
		delta = delta.normalized() * THROW_RADIUS
	_throw_offset = delta
	if delta.length() >= DEAD_ZONE and GameManager.force_push_mana > 0.0:
		GameManager.force_push_dir = delta.normalized()
		GameManager.force_push_held = true
	else:
		GameManager.force_push_dir = Vector2.ZERO
		GameManager.force_push_held = false
	_draw_node.queue_redraw()

# Melee weapons attack in the direction the player is facing/moving (see player.gd's
# mobile fallback), not a joystick direction — so pressing just holds "shoot", no offset.
func _press_attack_button() -> void:
	_aim_offset = Vector2.ZERO
	GameManager.mobile_aim_dir = Vector2.ZERO
	Input.action_press("shoot")
	_draw_node.queue_redraw()

# One-shot tap (placeables only — Turret deploys at the player's position, no direction
# needed, so the angle argument is unused downstream). world.gd's handler sets
# GameManager.equipment_deployed synchronously during this emit(), so the button reflects
# the used-up state as soon as we redraw.
func _press_deploy_button() -> void:
	GameManager.deploy_equipment_requested.emit(0.0, 1.0)
	_draw_node.queue_redraw()

# One-shot tap. world.gd/sandbox.gd's handler sets GameManager.heal_item_deployed
# synchronously during this emit() (world.gd only — sandbox.gd allows repeat testing), so the
# button reflects the used-up state as soon as we redraw.
func _press_heal_button() -> void:
	GameManager.heal_item_requested.emit()
	_draw_node.queue_redraw()

func _update_aim(pos: Vector2) -> void:
	var delta := pos - _aim_center
	if delta.length() > JOYSTICK_RADIUS:
		delta = delta.normalized() * JOYSTICK_RADIUS
	_aim_offset = delta
	if delta.length() >= DEAD_ZONE:
		GameManager.mobile_aim_dir = delta.normalized()
		Input.action_press("shoot")
	else:
		GameManager.mobile_aim_dir = Vector2.ZERO
		Input.action_release("shoot")
	_draw_node.queue_redraw()

func _apply_move(offset: Vector2) -> void:
	_release_move_actions()
	if offset.length() < DEAD_ZONE:
		return
	var n := offset.normalized()
	if n.x >  0.3: Input.action_press("move_right")
	if n.x < -0.3: Input.action_press("move_left")
	if n.y >  0.3: Input.action_press("move_down")
	if n.y < -0.3: Input.action_press("move_up")

func _release_move_actions() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)

func _in_sniper_bar(pos: Vector2) -> bool:
	var half_w := SNIPER_BAR_WIDTH / 2.0 + SNIPER_BAR_TOUCH_MARGIN
	var half_h := SNIPER_BAR_HEIGHT / 2.0 + SNIPER_BAR_TOUCH_MARGIN
	var local := pos - _aim_center
	return absf(local.x) <= half_w and absf(local.y) <= half_h

# A tight circular catch zone around the green equipment control, kept close to the drawn ring
# so it can't steal touches meant for the neighbouring heal button or the fire joystick.
func _in_deploy_zone(pos: Vector2) -> bool:
	return pos.distance_to(_deploy_center) <= DEPLOY_TOUCH_RADIUS

# ── Drawing ───────────────────────────────────────────────────────────────

func _on_draw() -> void:
	if not _ready_done:
		return

	# ── Move joystick (left) — hidden while the sniper is armed, since movement is locked
	# and drawing it would suggest it still does something ──
	if not GameManager.sniper_armed:
		var knob := _joy_center + _knob_offset
		_draw_node.draw_circle(_joy_center, JOYSTICK_RADIUS, Color(1, 1, 1, 0.08))
		_draw_node.draw_arc(_joy_center, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.5)
		_draw_node.draw_circle(_joy_center, 5.0, Color(1, 1, 1, 0.25))
		var knob_col := Color(1, 1, 1, 0.70) if _joy_touch != -1 else Color(1, 1, 1, 0.45)
		_draw_node.draw_circle(knob, KNOB_RADIUS, knob_col)

	# ── Right control: charge bar (sniper), attack button (melee), or aim joystick (ranged) ──
	if GameManager.sniper_equipped:
		_draw_sniper_bar()
	elif GameManager.melee_equipped:
		_draw_attack_button()
	else:
		_draw_aim_joystick()

	# ── Equipment control, above the fire button: tap-button (placeable), drag-to-aim
	# joystick (throwable), button/bar cycle (battery), two-tap place/detonate (mine),
	# hold-to-channel button + mana bar (force_push), two-tap trail placement (barrier),
	# plain on/off toggle button (hoverboard), or tap-toggle button + mana bar (invincible) ──
	if _deploy_active():
		if GameManager.equipment_battery:
			if GameManager.battery_state == GameManager.BATTERY_READY:
				_draw_deploy_button()
			else:
				_draw_battery_bar()
		elif GameManager.equipment_mine:
			_draw_mine_button()
		elif GameManager.equipment_force_push:
			_draw_force_push_control()
		elif GameManager.equipment_barrier:
			_draw_barrier_button()
		elif GameManager.equipment_hoverboard:
			_draw_hoverboard_button()
		elif GameManager.equipment_invincible:
			_draw_invincible_control()
		elif GameManager.equipment_summon:
			_draw_summon_button()
		elif GameManager.equipment_throwable:
			_draw_throw_joystick()
		else:
			_draw_deploy_button()

	# ── Heal button, centered between the move and aim joysticks — plain tap button, or
	# button + HP bar underneath for a Shield Barrier ──
	if _heal_active():
		if GameManager.shield_equipped:
			_draw_shield_control()
		else:
			_draw_heal_button()

func _draw_aim_joystick() -> void:
	var aim_knob  := _aim_center + _aim_offset
	var is_firing := _aim_touch != -1 and (GameManager.mobile_aim_dir.length() > 0.0 \
		or (GameManager.thrown_melee_equipped and _aim_offset.length() >= DEAD_ZONE))
	var rim_col   := Color(1.0, 0.55, 0.2, 0.90) if is_firing else Color(1.0, 0.45, 0.15, 0.55)
	var knob2_col := Color(1.0, 0.55, 0.15, 0.85) if _aim_touch != -1 else Color(1.0, 0.45, 0.15, 0.45)
	_draw_node.draw_circle(_aim_center, JOYSTICK_RADIUS, Color(1.0, 0.4, 0.1, 0.08))
	_draw_node.draw_arc(_aim_center, JOYSTICK_RADIUS, 0.0, TAU, 48, rim_col, 2.5)
	_draw_node.draw_circle(_aim_center, 5.0, Color(1.0, 0.5, 0.2, 0.25))
	_draw_node.draw_circle(aim_knob, KNOB_RADIUS, knob2_col)

const ATTACK_BUTTON_RADIUS := 30.0 # sits inside the (now smaller) JOYSTICK_RADIUS ring

# Fills bottom-up as GameManager.sniper_charge approaches sniper_charge_time. Color signals
# state: blue while charging, gold once full and tappable to arm, pulsing red once armed and
# waiting for the fire-tap (see _handle_touch's sniper_armed branch).
func _draw_sniper_bar() -> void:
	var half_w := SNIPER_BAR_WIDTH / 2.0
	var half_h := SNIPER_BAR_HEIGHT / 2.0
	var top_left := _aim_center - Vector2(half_w, half_h)
	var full_rect := Rect2(top_left, Vector2(SNIPER_BAR_WIDTH, SNIPER_BAR_HEIGHT))

	_draw_node.draw_rect(full_rect, Color(1, 1, 1, 0.08))
	_draw_node.draw_rect(full_rect, Color(1, 1, 1, 0.4), false, 2.0)

	var frac := clampf(GameManager.sniper_charge / maxf(GameManager.sniper_charge_time, 0.001), 0.0, 1.0)
	var fill_h := SNIPER_BAR_HEIGHT * frac
	var fill_rect := Rect2(top_left + Vector2(0, SNIPER_BAR_HEIGHT - fill_h), Vector2(SNIPER_BAR_WIDTH, fill_h))

	var fill_col: Color
	if GameManager.sniper_armed:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 80.0)
		fill_col = Color(0.95, 0.2, 0.15, pulse)
	elif frac >= 1.0:
		fill_col = Color(0.95, 0.8, 0.2, 0.95)
	else:
		fill_col = Color(0.4, 0.65, 1.0, 0.8)
	_draw_node.draw_rect(fill_rect, fill_col)

func _draw_attack_button() -> void:
	var pressed  := _aim_touch != -1
	var ring_col := Color(0.95, 0.15, 0.15, 0.9) if pressed else Color(0.85, 0.15, 0.15, 0.55)
	var fill_col := Color(1.0, 0.2, 0.2, 0.95) if pressed else Color(0.85, 0.15, 0.15, 0.7)
	_draw_node.draw_circle(_aim_center, JOYSTICK_RADIUS, Color(0.8, 0.1, 0.1, 0.08))
	_draw_node.draw_arc(_aim_center, JOYSTICK_RADIUS, 0.0, TAU, 48, ring_col, 2.5)
	_draw_node.draw_circle(_aim_center, ATTACK_BUTTON_RADIUS, fill_col)

func _draw_deploy_button() -> void:
	var pressed  := _deploy_touch != -1
	var ring_col := Color(0.25, 0.9, 0.55, 0.9) if pressed else Color(0.2, 0.75, 0.45, 0.6)
	var fill_col := Color(0.3, 1.0, 0.6, 0.95) if pressed else Color(0.2, 0.75, 0.45, 0.75)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, Color(0.2, 0.8, 0.5, 0.08))
	_draw_node.draw_arc(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, 0.0, TAU, 32, ring_col, 2.5)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS, fill_col)

# Dennis's summon button — same geometry as _draw_deploy_button, but gold instead of green, and
# labeled with GameManager.summon_label ("SUMMON DENNIS") since a plain colored circle alone
# wouldn't communicate what a one-time summon button does the way it does for a placeable
# turret. One-shot per run, same as _draw_deploy_button.
func _draw_summon_button() -> void:
	var pressed  := _deploy_touch != -1
	var ring_col := Color(1.0, 0.85, 0.15, 0.9) if pressed else Color(0.9, 0.75, 0.1, 0.65)
	var fill_col := Color(1.0, 0.9, 0.25, 0.95) if pressed else Color(0.9, 0.75, 0.1, 0.8)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, Color(1.0, 0.85, 0.15, 0.08))
	_draw_node.draw_arc(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, 0.0, TAU, 32, ring_col, 2.5)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS, fill_col)
	var half_w := DEPLOY_BUTTON_RADIUS + 30.0
	_draw_node.draw_string(ThemeDB.fallback_font, _deploy_center - Vector2(half_w, 4.0), GameManager.summon_label,
		HORIZONTAL_ALIGNMENT_CENTER, half_w * 2.0, 10, Color(0.15, 0.1, 0.0, 0.95))

# Detonator Mine's button — same geometry as _draw_deploy_button, but a red/orange shade while
# GameManager.mine_state == MINE_ARMED to signal "placed, tap again to detonate" (vs. the
# normal green while READY, meaning "tap to place").
func _draw_mine_button() -> void:
	var armed   := GameManager.mine_state == GameManager.MINE_ARMED
	var pressed := _deploy_touch != -1
	var glow_col: Color
	var ring_col: Color
	var fill_col: Color
	if armed:
		glow_col = Color(0.9, 0.2, 0.1, 0.10)
		ring_col = Color(0.95, 0.3, 0.15, 0.9) if pressed else Color(0.9, 0.25, 0.1, 0.65)
		fill_col = Color(1.0, 0.35, 0.15, 0.95) if pressed else Color(0.9, 0.25, 0.1, 0.8)
	else:
		glow_col = Color(0.2, 0.8, 0.5, 0.08)
		ring_col = Color(0.25, 0.9, 0.55, 0.9) if pressed else Color(0.2, 0.75, 0.45, 0.6)
		fill_col = Color(0.3, 1.0, 0.6, 0.95) if pressed else Color(0.2, 0.75, 0.45, 0.75)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, glow_col)
	_draw_node.draw_arc(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, 0.0, TAU, 32, ring_col, 2.5)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS, fill_col)

# Deployable Barrier Wall's button — identical color scheme to _draw_mine_button (per spec):
# green while READY (tap to start tracing), red/orange while PLACING (tap again to stop early
# and finalize; the traced line itself is drawn by barrier_wall.gd out in the level, not here).
func _draw_barrier_button() -> void:
	var placing := GameManager.barrier_state == GameManager.BARRIER_PLACING
	var pressed := _deploy_touch != -1
	var glow_col: Color
	var ring_col: Color
	var fill_col: Color
	if placing:
		glow_col = Color(0.9, 0.2, 0.1, 0.10)
		ring_col = Color(0.95, 0.3, 0.15, 0.9) if pressed else Color(0.9, 0.25, 0.1, 0.65)
		fill_col = Color(1.0, 0.35, 0.15, 0.95) if pressed else Color(0.9, 0.25, 0.1, 0.8)
	else:
		glow_col = Color(0.2, 0.8, 0.5, 0.08)
		ring_col = Color(0.25, 0.9, 0.55, 0.9) if pressed else Color(0.2, 0.75, 0.45, 0.6)
		fill_col = Color(0.3, 1.0, 0.6, 0.95) if pressed else Color(0.2, 0.75, 0.45, 0.75)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, glow_col)
	_draw_node.draw_arc(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, 0.0, TAU, 32, ring_col, 2.5)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS, fill_col)

# Hoverboard's button — plain on/off toggle, no timer/bar. Green while unmounted (tap to
# mount), blue while mounted (tap to dismount) — a distinct color from mine/barrier's
# red/orange "armed" shade, since this isn't a pending-action warning, just a persistent state.
func _draw_hoverboard_button() -> void:
	var mounted := GameManager.hoverboard_active
	var pressed := _deploy_touch != -1
	var glow_col: Color
	var ring_col: Color
	var fill_col: Color
	if mounted:
		glow_col = Color(0.2, 0.55, 0.95, 0.10)
		ring_col = Color(0.3, 0.7, 1.0, 0.9) if pressed else Color(0.25, 0.6, 0.9, 0.65)
		fill_col = Color(0.35, 0.75, 1.0, 0.95) if pressed else Color(0.25, 0.6, 0.9, 0.8)
	else:
		glow_col = Color(0.2, 0.8, 0.5, 0.08)
		ring_col = Color(0.25, 0.9, 0.55, 0.9) if pressed else Color(0.2, 0.75, 0.45, 0.6)
		fill_col = Color(0.3, 1.0, 0.6, 0.95) if pressed else Color(0.2, 0.75, 0.45, 0.75)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, glow_col)
	_draw_node.draw_arc(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, 0.0, TAU, 32, ring_col, 2.5)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS, fill_col)

# Temporary Invincible Battery: a plain tap-toggle button (greys out once mana is empty,
# green when off, purple when active) plus a mana bar above it — same layout as Force Push
# Bracelet's but sized around a button (DEPLOY_BUTTON_RADIUS) instead of a joystick ring.
func _draw_invincible_control() -> void:
	var mana: float = GameManager.invincible_mana
	var mana_max: float = maxf(GameManager.invincible_mana_max, 0.001)
	var frac := clampf(mana / mana_max, 0.0, 1.0)
	var depleted := mana <= 0.0
	var active := GameManager.invincible_active and not depleted
	var pressed := _deploy_touch != -1

	var glow_col: Color
	var ring_col: Color
	var fill_col: Color
	if depleted:
		glow_col = Color(0.5, 0.5, 0.5, 0.04)
		ring_col = Color(0.5, 0.5, 0.5, 0.5)
		fill_col = Color(0.4, 0.4, 0.4, 0.6)
	elif active:
		glow_col = Color(0.6, 0.2, 1.0, 0.10)
		ring_col = Color(0.75, 0.4, 1.0, 0.9) if pressed else Color(0.65, 0.3, 1.0, 0.7)
		fill_col = Color(0.8, 0.45, 1.0, 0.95) if pressed else Color(0.7, 0.35, 1.0, 0.85)
	else:
		glow_col = Color(0.2, 0.8, 0.5, 0.08)
		ring_col = Color(0.25, 0.9, 0.55, 0.9) if pressed else Color(0.2, 0.75, 0.45, 0.6)
		fill_col = Color(0.3, 1.0, 0.6, 0.95) if pressed else Color(0.2, 0.75, 0.45, 0.75)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, glow_col)
	_draw_node.draw_arc(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, 0.0, TAU, 32, ring_col, 2.5)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS, fill_col)

	var bar_alpha := EQUIPMENT_BAR_DEPLETED_ALPHA if depleted else EQUIPMENT_BAR_ALPHA
	var half_w := EQUIPMENT_BAR_WIDTH / 2.0
	var half_h := EQUIPMENT_BAR_HEIGHT / 2.0
	var bar_center := _deploy_center - Vector2(0, DEPLOY_BUTTON_RADIUS + EQUIPMENT_BAR_GAP + half_h)
	var top_left := bar_center - Vector2(half_w, half_h)
	var full_rect := Rect2(top_left, Vector2(EQUIPMENT_BAR_WIDTH, EQUIPMENT_BAR_HEIGHT))

	_draw_node.draw_rect(full_rect, Color(1, 1, 1, 0.08))
	_draw_node.draw_rect(full_rect, Color(0.75, 0.4, 1.0, bar_alpha), false, 2.0)
	var fill_rect := Rect2(top_left, Vector2(EQUIPMENT_BAR_WIDTH * frac, EQUIPMENT_BAR_HEIGHT))
	_draw_node.draw_rect(fill_rect, Color(0.7, 0.3, 1.0, bar_alpha))

	var label := str(int(round(mana)))
	_draw_node.draw_string(ThemeDB.fallback_font, bar_center - Vector2(12, -5), label,
		HORIZONTAL_ALIGNMENT_CENTER, 24, 14, Color(1, 1, 1, minf(bar_alpha + 0.3, 1.0)))

# Force Push Bracelet: a drag-to-aim joystick (same footprint/style as _draw_throw_joystick)
# that greys out once mana is empty, plus a mana bar above it that's always visible — fills
# left-to-right, shows the current mana as a number, and dims from EQUIPMENT_BAR_ALPHA to
# EQUIPMENT_BAR_DEPLETED_ALPHA once empty (border/fill/text; the background stays fixed).
func _draw_force_push_control() -> void:
	var mana: float = GameManager.force_push_mana
	var mana_max: float = maxf(GameManager.force_push_mana_max, 0.001)
	var frac := clampf(mana / mana_max, 0.0, 1.0)
	var depleted := mana <= 0.0
	var held := GameManager.force_push_held and not depleted

	var knob := _deploy_center + (_throw_offset if not depleted else Vector2.ZERO)
	var rim_col: Color
	var knob_col: Color
	if depleted:
		rim_col = Color(0.5, 0.5, 0.5, 0.5)
		knob_col = Color(0.4, 0.4, 0.4, 0.6)
	else:
		rim_col = Color(0.35, 0.95, 0.45, 0.9) if held else Color(0.3, 0.8, 0.4, 0.6)
		knob_col = Color(0.4, 1.0, 0.5, 0.95) if held else Color(0.3, 0.8, 0.4, 0.75)
	_draw_node.draw_circle(_deploy_center, THROW_RADIUS, Color(0.3, 0.9, 0.4, 0.04 if depleted else 0.08))
	_draw_node.draw_arc(_deploy_center, THROW_RADIUS, 0.0, TAU, 32, rim_col, 2.5)
	_draw_node.draw_circle(_deploy_center, 4.0, Color(0.3, 0.9, 0.4, 0.25))
	_draw_node.draw_circle(knob, THROW_KNOB_RADIUS, knob_col)

	var bar_alpha := EQUIPMENT_BAR_DEPLETED_ALPHA if depleted else EQUIPMENT_BAR_ALPHA
	var half_w := EQUIPMENT_BAR_WIDTH / 2.0
	var half_h := EQUIPMENT_BAR_HEIGHT / 2.0
	var bar_center := _deploy_center - Vector2(0, THROW_RADIUS + EQUIPMENT_BAR_GAP + half_h)
	var top_left := bar_center - Vector2(half_w, half_h)
	var full_rect := Rect2(top_left, Vector2(EQUIPMENT_BAR_WIDTH, EQUIPMENT_BAR_HEIGHT))

	_draw_node.draw_rect(full_rect, Color(1, 1, 1, 0.08))
	_draw_node.draw_rect(full_rect, Color(0.4, 1.0, 0.5, bar_alpha), false, 2.0)
	var fill_rect := Rect2(top_left, Vector2(EQUIPMENT_BAR_WIDTH * frac, EQUIPMENT_BAR_HEIGHT))
	_draw_node.draw_rect(fill_rect, Color(0.35, 0.95, 0.45, bar_alpha))

	var label := str(int(round(mana)))
	_draw_node.draw_string(ThemeDB.fallback_font, bar_center - Vector2(12, -5), label,
		HORIZONTAL_ALIGNMENT_CENTER, 24, 14, Color(1, 1, 1, minf(bar_alpha + 0.3, 1.0)))

func _draw_throw_joystick() -> void:
	var knob      := _deploy_center + _throw_offset
	var pressed   := _deploy_touch != -1
	var rim_col   := Color(0.25, 0.9, 0.55, 0.9) if pressed else Color(0.2, 0.75, 0.45, 0.6)
	var knob_col  := Color(0.3, 1.0, 0.6, 0.95) if pressed else Color(0.2, 0.75, 0.45, 0.75)
	_draw_node.draw_circle(_deploy_center, THROW_RADIUS, Color(0.2, 0.8, 0.5, 0.08))
	_draw_node.draw_arc(_deploy_center, THROW_RADIUS, 0.0, TAU, 32, rim_col, 2.5)
	_draw_node.draw_circle(_deploy_center, 4.0, Color(0.2, 0.8, 0.5, 0.25))
	_draw_node.draw_circle(knob, THROW_KNOB_RADIUS, knob_col)

# Speed Boost Battery, once activated: a vertical bar (same style/footprint as the sniper
# charge bar) in place of the button, non-interactive. Bright green and draining top-down
# while ACTIVE (the boost is live); dim while RECHARGING (filling back up, bottom-up, until
# the button reappears at battery_state == BATTERY_READY).
func _draw_battery_bar() -> void:
	var half_w := BATTERY_BAR_WIDTH / 2.0
	var half_h := BATTERY_BAR_HEIGHT / 2.0
	var top_left := _deploy_center - Vector2(half_w, half_h)
	var full_rect := Rect2(top_left, Vector2(BATTERY_BAR_WIDTH, BATTERY_BAR_HEIGHT))

	_draw_node.draw_rect(full_rect, Color(0.2, 0.8, 0.5, 0.08))
	_draw_node.draw_rect(full_rect, Color(0.3, 1.0, 0.6, 0.4), false, 2.0)

	var frac: float = GameManager.battery_charge
	var fill_h := BATTERY_BAR_HEIGHT * frac
	var fill_rect := Rect2(top_left + Vector2(0, BATTERY_BAR_HEIGHT - fill_h), Vector2(BATTERY_BAR_WIDTH, fill_h))
	var is_active := GameManager.battery_state == GameManager.BATTERY_ACTIVE
	var fill_col := Color(0.3, 1.0, 0.6, 0.9) if is_active else Color(0.45, 0.65, 0.55, 0.75)
	_draw_node.draw_rect(fill_rect, fill_col)

func _draw_heal_button() -> void:
	var pressed  := _heal_touch != -1
	var ring_col := Color(0.25, 0.55, 0.95, 0.9) if pressed else Color(0.2, 0.45, 0.85, 0.6)
	var fill_col := Color(0.3, 0.65, 1.0, 0.95) if pressed else Color(0.2, 0.45, 0.85, 0.75)
	_draw_node.draw_circle(_heal_center, HEAL_BUTTON_RADIUS + 10.0, Color(0.2, 0.5, 0.9, 0.08))
	_draw_node.draw_arc(_heal_center, HEAL_BUTTON_RADIUS + 10.0, 0.0, TAU, 32, ring_col, 2.5)
	_draw_node.draw_circle(_heal_center, HEAL_BUTTON_RADIUS, fill_col)

# Shield Barrier: same button as _draw_heal_button, but stays a steady "armed" blue once
# active (a repeat tap does nothing) instead of only reacting to the current touch, plus a
# small HP bar underneath once active showing the remaining absorb pool — both the button and
# bar disappear together once the shield breaks (see _heal_active).
func _draw_shield_control() -> void:
	var active := GameManager.shield_active
	var pressed := _heal_touch != -1
	var ring_col := Color(0.25, 0.55, 0.95, 0.9) if (pressed or active) else Color(0.2, 0.45, 0.85, 0.6)
	var fill_col := Color(0.3, 0.65, 1.0, 0.95) if (pressed or active) else Color(0.2, 0.45, 0.85, 0.75)
	_draw_node.draw_circle(_heal_center, HEAL_BUTTON_RADIUS + 10.0, Color(0.2, 0.5, 0.9, 0.08))
	_draw_node.draw_arc(_heal_center, HEAL_BUTTON_RADIUS + 10.0, 0.0, TAU, 32, ring_col, 2.5)
	_draw_node.draw_circle(_heal_center, HEAL_BUTTON_RADIUS, fill_col)

	# The HP bar shows for as long as the shield hasn't broken (_heal_active already gates
	# calling this function on that), whether currently toggled on or off, so the remaining
	# pool is always visible — just dimmer while off, since it isn't absorbing anything then.
	var bar_alpha := EQUIPMENT_BAR_ALPHA if active else EQUIPMENT_BAR_DEPLETED_ALPHA
	var frac := clampf(GameManager.shield_hp / maxf(GameManager.shield_hp_max, 0.001), 0.0, 1.0)
	var half_w := EQUIPMENT_BAR_WIDTH / 2.0
	var half_h := EQUIPMENT_BAR_HEIGHT / 2.0
	var bar_center := _heal_center + Vector2(0, HEAL_BUTTON_RADIUS + EQUIPMENT_BAR_GAP + half_h)
	var top_left := bar_center - Vector2(half_w, half_h)
	var full_rect := Rect2(top_left, Vector2(EQUIPMENT_BAR_WIDTH, EQUIPMENT_BAR_HEIGHT))

	_draw_node.draw_rect(full_rect, Color(1, 1, 1, 0.08))
	_draw_node.draw_rect(full_rect, Color(0.3, 0.65, 1.0, bar_alpha), false, 2.0)
	var fill_rect := Rect2(top_left, Vector2(EQUIPMENT_BAR_WIDTH * frac, EQUIPMENT_BAR_HEIGHT))
	_draw_node.draw_rect(fill_rect, Color(0.3, 0.65, 1.0, bar_alpha))

	var label := str(int(round(GameManager.shield_hp)))
	_draw_node.draw_string(ThemeDB.fallback_font, bar_center - Vector2(12, -5), label,
		HORIZONTAL_ALIGNMENT_CENTER, 24, 14, Color(1, 1, 1, minf(bar_alpha + 0.3, 1.0)))
