extends Control

const DATA_PATH       := "res://game_data/game_data.json"
const PERSISTENT_PATH := "user://persistent.json"

var story_data:   Dictionary = {}
var characters:   Array = []
var backgrounds:  Array = []
var nodes:        Array = []
var edges:        Array = []
var locales_list: Array = []

var current_node_id:  String = ""
var current_locale:   String = ""   # "" = default language
var current_bgm_url:  String = ""
var tex_cache:        Dictionary = {}
var flags:            Dictionary = {}
var persistent:       Dictionary = {}
var nvl_bg_id:        String = "__init__"
var cg_mode:          bool   = false
var cg_node_id:       String = ""
var active_stage:     Dictionary = {}  # char_id -> { sprite, x, scale, emotion, url }

# Optional scene nodes — add these to Game.tscn if you want the feature:
#   SaveBtn   (Button)  — player presses to save
#   SaveNotify (Label)  — brief "Сохранено" flash
var save_btn:    Button = null
var save_notify: Label  = null

@onready var background:        TextureRect    = $Background
@onready var bg_color:          ColorRect      = $BGColor
@onready var stage_layer:       Control        = $Stage
@onready var cg_overlay:        TextureRect    = $CGOverlay
@onready var chapter_overlay:   Control        = $ChapterOverlay
@onready var chapter_label:     Label          = $ChapterOverlay/ChapterLabel
@onready var nvl_panel:         Control        = $NVLPanel
@onready var nvl_scroll:        ScrollContainer = $NVLPanel/NVLScroll
@onready var nvl_content:       VBoxContainer  = $NVLPanel/NVLScroll/NVLContent
@onready var nvl_next_btn:      Button         = $NVLPanel/NVLNextBtn
@onready var dialog_panel:      Panel          = $DialogPanel
@onready var char_name:         Label          = $DialogPanel/CharName
@onready var dialog_text:       Label          = $DialogPanel/DialogText
@onready var next_btn:          Button         = $DialogPanel/NextBtn
@onready var choices_container: VBoxContainer  = $ChoicesContainer
@onready var achievement_popup: Control        = $AchievementPopup
@onready var ach_name_label:    Label          = $AchievementPopup/AchName
@onready var bgm:               AudioStreamPlayer = $BGM
@onready var back_btn:          Button         = $BackBtn

func _ready() -> void:
	next_btn.pressed.connect(_on_next)
	nvl_next_btn.pressed.connect(_on_next)
	back_btn.pressed.connect(_on_back)
	bgm.finished.connect(func():
		if current_bgm_url != "" and bgm.stream != null:
			bgm.play()
	)
	save_btn    = get_node_or_null("SaveBtn")
	save_notify = get_node_or_null("SaveNotify")
	if save_btn:
		save_btn.pressed.connect(_save_game)
	if save_notify:
		save_notify.visible = false
	_load_persistent()
	_load_data()

# ---- Persistent save / load ----

func _load_persistent() -> void:
	if FileAccess.file_exists(PERSISTENT_PATH):
		var f = FileAccess.open(PERSISTENT_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			persistent = parsed
	flags          = persistent.get("flags",   {})
	current_locale = persistent.get("locale",  "")

func _save_persistent() -> void:
	persistent["flags"] = flags
	var f = FileAccess.open(PERSISTENT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(persistent, "\t"))
	f.close()

# ---- Data loading ----

func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		dialog_text.text = "Файл game_data/game_data.json не найден.\nЭкспортируйте историю из редактора."
		next_btn.visible = false
		return

	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null:
		dialog_text.text = "Ошибка чтения game_data.json"
		return

	story_data   = parsed
	characters   = story_data.get("characters",  [])
	backgrounds  = story_data.get("backgrounds", [])
	locales_list = story_data.get("locales",     [])

	var story = story_data.get("story", {})
	nodes = story.get("nodes", [])
	edges = story.get("edges", [])

	for n in nodes:
		if n.get("type") == "start":
			current_node_id = n.get("id", "")
			break

	if current_node_id == "":
		dialog_text.text = "Узел 'Старт' не найден в истории."
		return

	# Resume from manual save if available
	var sv = persistent.get("save", {})
	var sv_node: String = sv.get("node_id", "")
	if sv_node != "" and not _get_node(sv_node).is_empty():
		current_node_id = sv_node
		current_bgm_url = sv.get("bgm_url", "")
	_advance(current_node_id)

# ---- Advance ----

func _advance(node_id: String) -> void:
	current_node_id = node_id
	var node = _get_node(node_id)
	if node.is_empty():
		_show_end("Узел не найден: " + node_id)
		return

	var ntype: String = node.get("type", "")
	match ntype:
		"start":
			var next = _next_node(node_id, "out")
			if next != "": _advance(next)
			else: _show_end("История пуста — соедините Старт с диалогом.")
		"dialog":
			if node.get("nvl", false): _show_nvl_dialog(node)
			else: _show_dialog(node)
		"choice":      _show_choice(node)
		"scene":       _show_scene(node)
		"chapter":     _show_chapter(node)
		"set_flag":    _show_set_flag(node)
		"branch_flag": _show_branch_flag(node)
		"achievement": _show_achievement_node(node)
		"gallery_cg":  _show_gallery_cg_node(node)
		"end":         _show_end_node(node)
		_:             _show_end("Неизвестный тип узла: " + ntype)

# ---- Node handlers ----

func _show_dialog(node: Dictionary) -> void:
	_clear_nvl()
	_apply_node_bgm(node)
	_set_background(node.get("background_id", ""))
	_transition_stage(_get_stage(node))

	var speaker_id: String = node.get("speaker_id", "")
	var cdata = _get_char(speaker_id)
	char_name.text  = cdata.get("name", "") if not cdata.is_empty() else ""
	dialog_text.text = _node_text(node, "text")

	dialog_panel.visible    = true
	next_btn.visible        = true
	choices_container.visible = false
	nvl_panel.visible       = false

func _show_nvl_dialog(node: Dictionary) -> void:
	_apply_node_bgm(node)
	var bg_id: String = node.get("background_id", "")
	if bg_id != nvl_bg_id:
		_clear_nvl()
		nvl_bg_id = bg_id
		_set_background(bg_id)
	_transition_stage(_get_stage(node))

	var speaker_id: String = node.get("speaker_id", "")
	var cdata = _get_char(speaker_id)
	var name_str  = cdata.get("name", "") if not cdata.is_empty() else ""
	var text_str  = _node_text(node, "text")

	var lbl := Label.new()
	lbl.text = (name_str + ": " if name_str != "" else "") + text_str
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if name_str != "":
		lbl.add_theme_color_override("font_color", Color(0.77, 0.67, 1.0, 1.0))
	nvl_content.add_child(lbl)

	nvl_panel.visible         = true
	nvl_next_btn.visible      = true
	dialog_panel.visible      = false
	choices_container.visible = false
	current_node_id           = node.get("id", "")

	# Scroll to bottom next frame
	call_deferred("_nvl_scroll_bottom")

func _nvl_scroll_bottom() -> void:
	nvl_scroll.scroll_vertical = nvl_scroll.get_v_scroll_bar().max_value

func _clear_nvl() -> void:
	for child in nvl_content.get_children():
		child.queue_free()
	nvl_panel.visible = false
	nvl_bg_id = "__init__"

func _show_choice(node: Dictionary) -> void:
	_clear_nvl()
	_apply_node_bgm(node)
	_set_background(node.get("background_id", ""))
	_transition_stage(_get_stage(node))

	char_name.text  = ""
	dialog_text.text = _node_text(node, "question")
	next_btn.visible = false
	dialog_panel.visible = true

	for child in choices_container.get_children():
		child.queue_free()

	var choices: Array = node.get("choices", [])
	choices_container.visible = choices.size() > 0

	for i in choices.size():
		var btn := Button.new()
		btn.text = _locale_choice_text(node, i)
		btn.theme_override_font_sizes["font_size"] = 14
		btn.custom_minimum_size = Vector2(0, 44)
		var ci = i
		btn.pressed.connect(func(): _on_choice(node.get("id",""), ci))
		choices_container.add_child(btn)

func _show_scene(node: Dictionary) -> void:
	_clear_nvl()
	_apply_node_bgm(node)
	_set_background(node.get("background_id", ""))
	_transition_stage(_get_stage(node))
	dialog_panel.visible    = false
	choices_container.visible = false
	var next = _next_node(node.get("id", ""), "out")
	if next != "": _advance(next)
	else: _show_end("Scene-нода ни к чему не ведёт.")

func _show_chapter(node: Dictionary) -> void:
	_clear_nvl()
	_apply_node_bgm(node)
	if node.get("background_id", "") != "":
		_set_background(node.get("background_id", ""))
	chapter_label.text = _node_text(node, "title")
	chapter_overlay.visible = true
	chapter_overlay.modulate.a = 0.0
	dialog_panel.visible    = false
	choices_container.visible = false

	var tw = create_tween()
	tw.tween_property(chapter_overlay, "modulate:a", 1.0, 0.8)
	tw.tween_interval(2.0)
	tw.tween_property(chapter_overlay, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func():
		chapter_overlay.visible = false
		var next = _next_node(node.get("id",""), "out")
		if next != "": _advance(next)
		else: _show_end("Глава: следующий узел не найден.")
	)

func _show_set_flag(node: Dictionary) -> void:
	var fname: String = node.get("flag_name",  "")
	var fval:  String = str(node.get("flag_value", ""))
	if fname != "":
		flags[fname] = fval
		_save_persistent()
	var next = _next_node(node.get("id",""), "out")
	if next != "": _advance(next)
	else: _show_end("set_flag: следующий узел не найден.")

func _show_branch_flag(node: Dictionary) -> void:
	var fname:  String = node.get("flag_name",  "")
	var fval:   String = str(node.get("flag_value", "true"))
	var actual: String = str(flags.get(fname, ""))
	var port_idx = 0 if actual == fval else 1
	var next = _next_node(node.get("id",""), "choice", port_idx)
	if next != "": _advance(next)
	else: _show_end("branch_flag: нет следующего узла для порта " + str(port_idx))

func _show_achievement_node(node: Dictionary) -> void:
	var ach_id:   String = node.get("achievement_id",  "")
	var ach_name: String = _node_text(node, "achievement_name")

	if ach_id != "":
		if not persistent.has("achievements"):
			persistent["achievements"] = {}
		if not persistent["achievements"].has(ach_id):
			persistent["achievements"][ach_id] = {
				"name": ach_name,
				"unlocked_at": Time.get_datetime_string_from_system()
			}
			_save_persistent()
			_show_achievement_popup(ach_name)

	var next = _next_node(node.get("id",""), "out")
	if next != "": _advance(next)
	else: _show_end("achievement: следующий узел не найден.")

func _show_achievement_popup(name_str: String) -> void:
	ach_name_label.text = name_str
	achievement_popup.visible = true
	achievement_popup.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(achievement_popup, "modulate:a", 1.0, 0.4)
	tw.tween_interval(3.0)
	tw.tween_property(achievement_popup, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): achievement_popup.visible = false)

func _show_gallery_cg_node(node: Dictionary) -> void:
	var cg_id:       String = node.get("cg_id",      "")
	var cg_name:     String = _node_text(node, "cg_name")
	var cg_game_url: String = node.get("cg_game_url", "")

	if cg_id != "":
		if not persistent.has("gallery"):
			persistent["gallery"] = {}
		if not persistent["gallery"].has(cg_id):
			persistent["gallery"][cg_id] = {
				"name": cg_name, "url": cg_game_url,
				"unlocked_at": Time.get_datetime_string_from_system()
			}
			_save_persistent()

	if cg_game_url != "":
		var tex = _load_tex("res://" + cg_game_url)
		if tex:
			cg_overlay.texture = tex
			cg_overlay.visible = true
			dialog_panel.visible    = false
			choices_container.visible = false
			next_btn.visible        = true
			cg_mode    = true
			cg_node_id = node.get("id", "")
			return

	var next = _next_node(node.get("id",""), "out")
	if next != "": _advance(next)
	else: _show_end("gallery_cg: следующий узел не найден.")

func _show_end_node(node: Dictionary) -> void:
	var ending_id:   String = node.get("ending_id",  "")
	var ending_name: String = _node_text(node, "ending_name")

	if ending_id != "":
		if not persistent.has("endings"):
			persistent["endings"] = {}
		if not persistent["endings"].has(ending_id):
			persistent["endings"][ending_id] = {
				"name": ending_name,
				"unlocked_at": Time.get_datetime_string_from_system()
			}
			_save_persistent()

	var msg = "Конец."
	if ending_name != "":
		var count = persistent.get("endings", {}).size()
		msg = ending_name + "\n\n[Концовка получена — всего: %d]" % count
	elif ending_id != "":
		msg = "Концовка: " + ending_id

	_show_end(msg)

# ---- Navigation ----

func _on_choice(node_id: String, choice_index: int) -> void:
	var next = _next_node(node_id, "choice", choice_index)
	if next != "": _advance(next)
	else: _show_end("Этот выбор ни к чему не ведёт.")

func _on_next() -> void:
	if cg_mode:
		cg_mode = false
		cg_overlay.visible = false
		next_btn.visible   = false
		var next = _next_node(cg_node_id, "out")
		if next != "": _advance(next)
		else: _show_end("Конец.")
		return
	var next = _next_node(current_node_id, "out")
	if next != "": _advance(next)
	else: _show_end("Конец.")

func _show_end(msg: String) -> void:
	_clear_nvl()
	char_name.text  = ""
	dialog_text.text = msg
	next_btn.visible = false
	choices_container.visible = false
	dialog_panel.visible = true
	_clear_stage()

func _save_game() -> void:
	persistent["save"] = { "node_id": current_node_id, "bgm_url": current_bgm_url }
	_save_persistent()
	if save_notify:
		save_notify.text    = "Сохранено"
		save_notify.visible = true
		var tw = create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(func(): save_notify.visible = false)

func _on_back() -> void:
	if ResourceLoader.exists("res://scenes/Main.tscn"):
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
	else:
		get_tree().quit()

# ---- BGM ----

func _apply_node_bgm(node: Dictionary) -> void:
	var url: String = str(node.get("bgm_game_url", node.get("bgm_url", "")))
	if url == "":
		return   # No change — keep current track playing
	if url == "__stop__":
		current_bgm_url = ""
		bgm.stop()
		return
	if url == current_bgm_url:
		return   # Same track — don't restart
	current_bgm_url = url
	var stream = _load_audio_stream(url if url.begins_with("res://") else "res://" + url)
	if stream:
		bgm.stream = stream
		bgm.play()

func _load_audio_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	if path.ends_with(".mp3"):
		var stream = AudioStreamMP3.new()
		var f = FileAccess.open(path, FileAccess.READ)
		stream.data = f.get_buffer(f.get_length())
		f.close()
		return stream
	if path.ends_with(".ogg"):
		var stream = AudioStreamOggVorbis.load_from_file(path)
		return stream
	if path.ends_with(".wav"):
		var stream = AudioStreamWAV.new()
		# WAV loading via AudioStreamWAV.load_from_file is not available in GDScript;
		# use ResourceLoader as fallback
		var res = ResourceLoader.load(path)
		if res is AudioStream:
			return res
		return null
	var res = ResourceLoader.load(path)
	if res is AudioStream:
		return res
	return null

# ---- Localization ----

func _node_text(node: Dictionary, key: String) -> String:
	if current_locale != "":
		var locs = node.get("locales", {})
		if locs.has(current_locale):
			var v = locs[current_locale].get(key, "")
			if v != null and str(v) != "":
				return str(v)
	return str(node.get(key, ""))

func _locale_choice_text(node: Dictionary, index: int) -> String:
	if current_locale != "":
		var locs = node.get("locales", {})
		if locs.has(current_locale):
			var ct = locs[current_locale].get("choices_text", [])
			if index < ct.size() and str(ct[index]) != "":
				return str(ct[index])
	var choices: Array = node.get("choices", [])
	if index < choices.size():
		return str(choices[index].get("text", "..."))
	return "..."

# ---- Helpers ----

func _get_node(id: String) -> Dictionary:
	for n in nodes:
		if n.get("id") == id: return n
	return {}

func _get_char(id: String) -> Dictionary:
	for c in characters:
		if c.get("id") == id: return c
	return {}

func _get_bg(id: String) -> Dictionary:
	for b in backgrounds:
		if b.get("id") == id: return b
	return {}

func _get_stage(node: Dictionary) -> Array:
	var stage = node.get("stage", [])
	if stage is Array: return stage
	return []

func _next_node(from_id: String, port: String, choice_index: int = -1) -> String:
	for e in edges:
		if e.get("fromNode") != from_id: continue
		if port == "out" and e.get("fromPort") == "out":
			return e.get("toNode", "")
		if port == "choice" and e.get("fromPort") == "choice" and int(e.get("choiceIndex", -1)) == choice_index:
			return e.get("toNode", "")
	return ""

func _set_background(bg_id: String) -> void:
	if bg_id == "":
		background.visible = false; bg_color.visible = true; return
	var bdata = _get_bg(bg_id)
	if bdata.is_empty():
		background.visible = false; bg_color.visible = true; return
	var game_url: String = bdata.get("gameUrl", "")
	if game_url == "":
		background.visible = false; bg_color.visible = true; return
	var tex = _load_tex("res://" + game_url)
	if tex:
		background.texture = tex; background.visible = true; bg_color.visible = false
	else:
		background.visible = false; bg_color.visible = true

func _clear_stage() -> void:
	for child in stage_layer.get_children():
		child.queue_free()
	active_stage.clear()

func _transition_stage(stage: Array) -> void:
	var new_ids: Array = []
	for entry in stage:
		var cid: String = entry.get("character_id", "")
		if cid != "": new_ids.append(cid)

	# Fade out removed characters
	var to_remove: Array = []
	for char_id in active_stage:
		if char_id not in new_ids:
			to_remove.append(char_id)
	for char_id in to_remove:
		var info = active_stage[char_id]
		var sprite: TextureRect = info["sprite"]
		active_stage.erase(char_id)
		var tw = create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.3)
		tw.tween_callback(sprite.queue_free)

	# Add / update characters
	for entry in stage:
		var char_id: String  = entry.get("character_id", "")
		var emotion: String  = entry.get("emotion", "")
		var x_percent: float = float(entry.get("x", 50))
		var scale_pct: float = clampf(float(entry.get("scale", 80)), 20.0, 150.0)
		if char_id == "": continue
		var art = _resolve_art(char_id, emotion)
		if art == null: continue
		var game_url: String = art.get("gameUrl", "")
		if game_url == "": continue
		var tex = _load_tex("res://" + game_url)
		if tex == null: continue

		var new_al  = x_percent / 100.0
		var new_ar  = x_percent / 100.0
		var new_at  = 1.0 - scale_pct / 100.0

		if active_stage.has(char_id):
			var info         = active_stage[char_id]
			var sprite: TextureRect = info["sprite"]
			var old_x: float        = info["x"]
			var old_sc: float       = info["scale"]
			var old_em: String      = info["emotion"]
			var old_url: String     = info["url"]
			active_stage[char_id] = { "sprite": sprite, "x": x_percent, "scale": scale_pct, "emotion": emotion, "url": game_url }

			if old_em != emotion or old_url != game_url:
				var em_tw = create_tween()
				em_tw.tween_property(sprite, "modulate:a", 0.0, 0.2)
				em_tw.tween_callback(func(): sprite.texture = tex)
				em_tw.tween_property(sprite, "modulate:a", 1.0, 0.2)

			if old_x != x_percent or old_sc != scale_pct:
				var pos_tw = create_tween()
				pos_tw.set_parallel(true)
				pos_tw.tween_property(sprite, "anchor_left",  new_al,  0.35)
				pos_tw.tween_property(sprite, "anchor_right", new_ar,  0.35)
				pos_tw.tween_property(sprite, "anchor_top",   new_at,  0.35)
		else:
			var sprite := TextureRect.new()
			sprite.texture       = tex
			sprite.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sprite.anchor_left   = new_al
			sprite.anchor_right  = new_ar
			sprite.anchor_top    = new_at
			sprite.anchor_bottom = 1.0
			sprite.offset_left   = -200.0
			sprite.offset_right  = 200.0
			sprite.offset_top    = 0.0
			sprite.offset_bottom = 0.0
			sprite.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			sprite.modulate.a    = 0.0
			stage_layer.add_child(sprite)
			active_stage[char_id] = { "sprite": sprite, "x": x_percent, "scale": scale_pct, "emotion": emotion, "url": game_url }
			var tw = create_tween()
			tw.tween_property(sprite, "modulate:a", 1.0, 0.3)

func _resolve_art(char_id: String, emotion: String):
	if char_id == "": return null
	var cdata = _get_char(char_id)
	if cdata.is_empty(): return null
	var arts: Array = cdata.get("arts", [])
	for a in arts:
		if a.get("emotion") == emotion: return a
	if arts.size() > 0: return arts[0]
	return null

func _load_tex(path: String) -> Texture2D:
	if tex_cache.has(path): return tex_cache[path]
	if not FileAccess.file_exists(path): return null
	var img := Image.new()
	if img.load(path) != OK: return null
	var tex := ImageTexture.create_from_image(img)
	tex_cache[path] = tex
	return tex
