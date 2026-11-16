extends Node
## Plays the sound files of `art/sound/` (phase G-7). It plays what `core/sound_model.gd` says and makes no sound of its own: every sound
## is a file, rendered at build time (docs/godot-client-plan.md, "Sound").
##
## One looping player for the tune and a small pool for the event sounds. The loop flag and the loop end are set in the `.import` files
## (see the README, "Sound files"), so the stream loops by itself. Nothing exists while sound is off: no player node, no stream in
## memory, no effect on the master bus. The app stays light beside an agent (choice 13 of the plan). When sound turns on, the players
## are made and the five event sounds are loaded (about 150 KB). A tune is loaded when it is chosen, and it is freed when another one is
## chosen or sound turns off (a tune is 1.8 to 3 MB).
##
## Each file carries its own gentle limiter from the mockup's mixer. Two files that play together can add up above full scale, so a
## limiter on the master bus (`AudioEffectHardLimiter`) catches the sum. It is added when sound turns on and removed when it turns off.

const SoundModel := preload("res://src/core/sound_model.gd")

const FOLDER := "res://art/sound/"
## How many event sounds can sound at once. A sound that has no free player is dropped.
const POOL_SIZE := 4
## The volume of the tune player in dB. The files carry the mix of the mockup, and the tune and an event sound can add up above full scale
## (`tools/sound-levels.mjs` measures how far). 3 dB of headroom cut the start times at which
## oberek and the flop go over full scale from 2.9% to 0.7%.
## Nobody has listened to it: a person decides whether the tune is too quiet.
const MUSIC_VOLUME_DB := -3.0
## The master limiter: where it stops the level, in dB below full scale, and how fast it lets go, in seconds.
const LIMITER_CEILING_DB := -1.0
const LIMITER_RELEASE := 0.1
## The master bus.
const BUS := "Master"

## The name of the tune that plays or is loaded, or "".
var tune_loaded: String = ""
## How many event sounds were started. For tests.
var plays: int = 0
## Files that could not be loaded. For tests and for a note to the person.
var failures: PackedStringArray = []

var _music: AudioStreamPlayer = null
var _pool: Array[AudioStreamPlayer] = []
var _events: Dictionary = { }
var _limiter: AudioEffect = null
var _paused: bool = false


## True while the players exist (sound is on).
func running() -> bool:
	return _music != null


## The tune player has a stream and plays.
func music_playing() -> bool:
	return _music != null and _music.playing


## The place of the master limiter in the effects of the master bus, or -1 when it is not there (sound is off).
func limiter_index() -> int:
	if _limiter == null:
		return -1
	var bus: int = AudioServer.get_bus_index(BUS)
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == _limiter:
			return i
	return -1


## Makes the players do what the model says. Call it after any change of the model (compare `SoundModel.version`).
func apply(model: SoundModel) -> void:
	if not model.on:
		_shutdown()
		return
	_start()
	var wanted: String = model.tune
	if wanted == "":
		_stop_music()
	elif wanted != tune_loaded or not _music.playing:
		_start_music(wanted)
	if model.events:
		_load_events()
	else:
		_free_events()


## Starts one event sound. Nothing happens while sound is off, or when the sound is not loaded.
func play_event(sound_name: String) -> void:
	if not running() or not _events.has(sound_name):
		return
	for player in _pool:
		if not player.playing:
			player.stream = _events[sound_name]
			player.play()
			# the pause belongs to the playback, so it is set after play() (a player with no playback does not keep it)
			player.stream_paused = _paused
			plays += 1
			return


## Pauses or resumes all sounds (the clock of a demo is paused).
func set_paused(paused: bool) -> void:
	_paused = paused
	if _music != null:
		_music.stream_paused = paused
		for player in _pool:
			if player.playing:
				player.stream_paused = paused


func _exit_tree() -> void:
	_shutdown()


# ---------------------------------------------------------------- inside

func _start() -> void:
	if _music != null:
		return
	_music = AudioStreamPlayer.new()
	_music.bus = BUS
	_music.volume_db = MUSIC_VOLUME_DB
	add_child(_music)
	for i in POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_pool.append(player)
	var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
	limiter.ceiling_db = LIMITER_CEILING_DB
	limiter.release = LIMITER_RELEASE
	_limiter = limiter
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS), _limiter)


func _shutdown() -> void:
	if _music == null:
		return
	var at: int = limiter_index()
	if at >= 0:
		AudioServer.remove_bus_effect(AudioServer.get_bus_index(BUS), at)
	_limiter = null
	for player in _pool:
		player.stop()
		player.stream = null
		player.queue_free()
	_pool.clear()
	_music.stop()
	_music.stream = null
	_music.queue_free()
	_music = null
	_events.clear()
	tune_loaded = ""


func _start_music(tune_name: String) -> void:
	var stream: AudioStream = _load(tune_name)
	if stream == null:
		_stop_music()
		return
	# a new stream replaces the old one, which is freed when nothing else holds it; play() starts from the beginning
	_music.stream = stream
	_music.play()
	_music.stream_paused = _paused
	tune_loaded = tune_name


func _stop_music() -> void:
	_music.stop()
	_music.stream = null
	tune_loaded = ""


func _load_events() -> void:
	for sound_name in SoundModel.EVENT_SOUNDS:
		if _events.has(sound_name):
			continue
		var stream: AudioStream = _load(sound_name)
		if stream != null:
			_events[sound_name] = stream


func _free_events() -> void:
	for player in _pool:
		player.stop()
		player.stream = null
	_events.clear()


func _load(sound_name: String) -> AudioStream:
	var path: String = "%s%s.wav" % [FOLDER, sound_name]
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		failures.append(path)
		push_warning("Cannot load the sound file %s" % path)
	return stream
