extends Control

const DATA_PATH: String = "res://game_data/game_data.json"
const PERSISTENT_PATH: String = "user://persistent.json"
const SKIP_HOLD_DELAY: float = 0.35
const SKIP_STEP_INTERVAL: float = 0.055
const SAVE_SLOT_COUNT: int = 99
const SETTINGS_PANEL_SIZE: Vector2 = Vector2(520.0, 640.0)
const SAVE_LOAD_PANEL_SIZE: Vector2 = Vector2(620.0, 460.0)

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
var settings:         Dictionary = {}
var seen_nodes:       Dictionary = {}
var persistent:       Dictionary = {}
var nvl_bg_id:        String = "__init__"
var cg_mode:          bool   = false
var cg_node_id:       String = ""
var active_stage:     Dictionary = {}  # char_id -> { sprite, x, scale, emotion, url }
var current_node_was_seen: bool = false
var text_revealing: bool = false
var reveal_label: Label = null
var reveal_full_text: String = ""
var reveal_visible_chars: float = 0.0
var skip_hold_active: bool = false
var skip_hold_started: bool = false
var skip_hold_timer: float = 0.0
var skip_step_timer: float = 0.0
var save_load_mode: String = "save"

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
@onready var save_btn:          Button         = $DialogPanel/SaveBtn
@onready var settings_btn:      Button         = $DialogPanel/SettingsBtn
@onready var save_notify:       Label          = $DialogPanel/SaveNotify
@onready var choices_container: VBoxContainer  = $ChoicesContainer
@onready var settings_shade:    ColorRect      = $SettingsShade
@onready var settings_panel:    Panel          = $SettingsPanel
@onready var master_volume_slider: HSlider     = $SettingsPanel/MasterVolumeSlider
@onready var text_speed_slider: HSlider        = $SettingsPanel/TextSpeedSlider
@onready var skip_seen_check:   CheckBox       = $SettingsPanel/SkipSeenCheckBox
@onready var window_mode_button: Button        = $SettingsPanel/WindowModeButton
@onready var settings_save_button: Button      = $SettingsPanel/SettingsSaveButton
@onready var settings_load_button: Button      = $SettingsPanel/SettingsLoadButton
@onready var settings_status_label: Label      = $SettingsPanel/SettingsStatusLabel
@onready var settings_close_button: Button     = $SettingsPanel/SettingsCloseButton
@onready var save_load_shade: ColorRect        = $SaveLoadShade
@onready var save_load_panel: Panel            = $SaveLoadPanel
@onready var save_load_title: Label            = $SaveLoadPanel/SaveLoadTitle
@onready var save_slots_list: VBoxContainer    = $SaveLoadPanel/SlotsScroll/SlotsList
@onready var save_load_close_button: Button    = $SaveLoadPanel/SaveLoadCloseButton
@onready var achievement_popup: Control        = $AchievementPopup
@onready var ach_icon: TextureRect             = $AchievementPopup/AchIcon
@onready var ach_icon_fallback: Label          = $AchievementPopup/AchIconFallback
@onready var ach_name_label:    Label          = $AchievementPopup/AchName
@onready var bgm:               AudioStreamPlayer = $BGM
@onready var back_btn:          Button         = $BackBtn

func _ready() -> void:
	next_btn.pressed.connect(_advance_or_finish_text)
	nvl_next_btn.pressed.connect(_advance_or_finish_text)
	back_btn.pressed.connect(_on_back)
	settings_btn.pressed.connect(_open_settings)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	text_speed_slider.value_changed.connect(_on_text_speed_changed)
	skip_seen_check.toggled.connect(_on_skip_seen_toggled)
	window_mode_button.pressed.connect(_toggle_window_mode)
	settings_save_button.pressed.connect(func(): _open_save_slots("save"))
	settings_load_button.pressed.connect(func(): _open_save_slots("load"))
	settings_close_button.pressed.connect(_close_settings)
	save_load_close_button.pressed.connect(_close_save_slots)
	bgm.finished.connect(func():
		if current_bgm_url != "" and bgm.stream != null:
			bgm.play()
	)
	_style_settings_interface()
	_style_dialog_icon_button(settings_btn)
	_apply_responsive_layout()
	_load_persistent()
	_apply_settings()
	_load_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_responsive_layout()

func _process(delta: float) -> void:
	_update_text_reveal(delta)
	_update_seen_skip(delta)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and save_load_panel.visible:
		_close_save_slots()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and settings_panel.visible:
		_close_settings()
		get_viewport().set_input_as_handled()
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if mouse_event.pressed:
		if _is_pointer_over_blocking_control(mouse_event.position):
			return
		if _is_right_skip_zone(mouse_event.position) and bool(settings.get("skip_seen_only", true)):
			skip_hold_active = true
			skip_hold_started = false
			skip_hold_timer = 0.0
			skip_step_timer = 0.0
		else:
			_advance_or_finish_text()
		get_viewport().set_input_as_handled()
	else:
		if _is_pointer_over_blocking_control(mouse_event.position) and not skip_hold_active:
			return
		if skip_hold_active and not skip_hold_started:
			_advance_or_finish_text()
		_stop_seen_skip()
		get_viewport().set_input_as_handled()

# ---- Persistent save / load ----

func _load_persistent() -> void:
	persistent = {}
	if FileAccess.file_exists(PERSISTENT_PATH):
		var f: FileAccess = FileAccess.open(PERSISTENT_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			persistent = parsed as Dictionary

	var saved_flags: Variant = persistent.get("flags", {})
	if saved_flags is Dictionary:
		flags = saved_flags as Dictionary
	else:
		flags = {}

	var saved_settings: Variant = persistent.get("settings", {})
	if saved_settings is Dictionary:
		settings = saved_settings as Dictionary
	else:
		settings = {}

	var saved_seen: Variant = persistent.get("seen_nodes", {})
	if saved_seen is Dictionary:
		seen_nodes = saved_seen as Dictionary
	else:
		seen_nodes = {}

	current_locale = str(persistent.get("locale", ""))
	_apply_default_settings()

func _save_persistent() -> void:
	persistent["flags"] = flags
	persistent["settings"] = settings
	persistent["seen_nodes"] = seen_nodes
	persistent["save_slots"] = _get_save_slots()
	var f: FileAccess = FileAccess.open(PERSISTENT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(persistent, "\t"))
	f.close()

func _apply_default_settings() -> void:
	if not settings.has("master_volume"):
		settings["master_volume"] = 85.0
	if not settings.has("fullscreen"):
		settings["fullscreen"] = false
	if not settings.has("text_speed"):
		settings["text_speed"] = 55.0
	if not settings.has("skip_seen_only"):
		settings["skip_seen_only"] = true

func _get_save_slots() -> Array:
	var slots: Array = []
	var raw_slots: Variant = persistent.get("save_slots", [])
	if raw_slots is Array:
		slots = (raw_slots as Array).duplicate(true)
	while slots.size() < SAVE_SLOT_COUNT:
		slots.append({})
	if slots.size() > SAVE_SLOT_COUNT:
		slots.resize(SAVE_SLOT_COUNT)

	var legacy_save: Variant = persistent.get("save", {})
	if not _slot_has_data(slots[0]) and legacy_save is Dictionary:
		var legacy_dictionary: Dictionary = legacy_save as Dictionary
		if str(legacy_dictionary.get("node_id", "")) != "":
			slots[0] = legacy_dictionary.duplicate(true)
	return slots

func _set_save_slots(slots: Array) -> void:
	while slots.size() < SAVE_SLOT_COUNT:
		slots.append({})
	if slots.size() > SAVE_SLOT_COUNT:
		slots.resize(SAVE_SLOT_COUNT)
	persistent["save_slots"] = slots

func _slot_has_data(slot: Variant) -> bool:
	if not (slot is Dictionary):
		return false
	var slot_dictionary: Dictionary = slot as Dictionary
	return str(slot_dictionary.get("node_id", "")) != ""

func _slot_is_loadable(slot: Variant) -> bool:
	if not _slot_has_data(slot):
		return false
	var slot_dictionary: Dictionary = slot as Dictionary
	var node_id: String = str(slot_dictionary.get("node_id", ""))
	return node_id != "" and not _get_node(node_id).is_empty()

func _apply_settings() -> void:
	master_volume_slider.value = float(settings.get("master_volume", 85.0))
	text_speed_slider.value = float(settings.get("text_speed", 55.0))
	skip_seen_check.button_pressed = bool(settings.get("skip_seen_only", true))
	_apply_master_volume(master_volume_slider.value)
	var fullscreen: bool = bool(settings.get("fullscreen", false))
	var mode: int = DisplayServer.WINDOW_MODE_WINDOWED
	if fullscreen:
		mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(mode)
	_update_window_mode_text()

func _on_master_volume_changed(value: float) -> void:
	settings["master_volume"] = value
	_apply_master_volume(value)
	_save_persistent()

func _on_text_speed_changed(value: float) -> void:
	settings["text_speed"] = value
	_save_persistent()

func _on_skip_seen_toggled(enabled: bool) -> void:
	settings["skip_seen_only"] = enabled
	_save_persistent()

func _apply_master_volume(value: float) -> void:
	var bus: int = AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	if value <= 0.0:
		AudioServer.set_bus_mute(bus, true)
		AudioServer.set_bus_volume_db(bus, -80.0)
	else:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, linear_to_db(value / 100.0))

func _toggle_window_mode() -> void:
	var fullscreen: bool = DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
	settings["fullscreen"] = fullscreen
	var mode: int = DisplayServer.WINDOW_MODE_WINDOWED
	if fullscreen:
		mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(mode)
	_update_window_mode_text()
	_save_persistent()

func _update_window_mode_text() -> void:
	var fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if fullscreen:
		window_mode_button.text = "Полный экран"
	else:
		window_mode_button.text = "Оконный режим"

func _style_settings_interface() -> void:
	settings_shade.color = Color(0.015, 0.012, 0.03, 0.84)
	save_load_shade.color = Color(0.015, 0.012, 0.03, 0.86)
	_style_panel(settings_panel, Color(0.045, 0.04, 0.065, 0.96), Color(1.0, 0.9, 0.74, 0.46))
	_style_panel(save_load_panel, Color(0.045, 0.04, 0.065, 0.96), Color(1.0, 0.9, 0.74, 0.46))

	var group_names: Array[String] = ["AudioGroup", "TextGroup", "SystemGroup", "ProgressGroup"]
	for group_name in group_names:
		var group_node: Node = settings_panel.get_node_or_null(group_name)
		if group_node is Panel:
			_style_panel(group_node as Panel, Color(0.095, 0.085, 0.115, 0.88), Color(1.0, 0.9, 0.74, 0.24))

	var title_names: Array[String] = ["SettingsTitle", "AudioGroupTitle", "TextGroupTitle", "SystemGroupTitle", "ProgressGroupTitle"]
	for label_name in title_names:
		var title_node: Node = settings_panel.get_node_or_null(label_name)
		if title_node is Label:
			var label: Label = title_node as Label
			label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.76, 1.0))
			label.add_theme_color_override("font_outline_color", Color(0.02, 0.018, 0.035, 0.95))
			label.add_theme_constant_override("outline_size", 2)
	save_load_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.76, 1.0))
	save_load_title.add_theme_color_override("font_outline_color", Color(0.02, 0.018, 0.035, 0.95))
	save_load_title.add_theme_constant_override("outline_size", 2)
	_style_settings_button(save_load_close_button, true)

	var control_label_names: Array[String] = ["MasterVolumeLabel", "TextSpeedLabel"]
	for label_name in control_label_names:
		var control_label_node: Node = settings_panel.get_node_or_null(label_name)
		if control_label_node is Label:
			(control_label_node as Label).add_theme_color_override("font_color", Color(0.93, 0.91, 0.87, 0.96))

	skip_seen_check.add_theme_color_override("font_color", Color(0.93, 0.91, 0.87, 0.96))
	skip_seen_check.add_theme_color_override("font_pressed_color", Color(1.0, 0.96, 0.86, 1.0))
	_style_settings_button(window_mode_button)
	_style_settings_button(settings_save_button)
	_style_settings_button(settings_load_button)
	_style_settings_button(settings_close_button, true)
	_style_settings_slider(master_volume_slider)
	_style_settings_slider(text_speed_slider)
	settings_status_label.add_theme_color_override("font_color", Color(0.72, 1.0, 0.78, 1.0))

func _style_panel(panel: Panel, bg: Color, border: Color) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	panel.add_theme_stylebox_override("panel", style)

func _style_settings_button(button: Button, primary: bool = false) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	if primary:
		normal.bg_color = Color(1.0, 0.9, 0.78, 0.18)
		normal.border_color = Color(1.0, 0.9, 0.72, 0.46)
	else:
		normal.bg_color = Color(0.98, 0.9, 0.78, 0.13)
		normal.border_color = Color(1.0, 0.9, 0.72, 0.32)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 7
	normal.corner_radius_top_right = 7
	normal.corner_radius_bottom_right = 7
	normal.corner_radius_bottom_left = 7

	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 0.94, 0.84, 0.24)
	hover.border_color = Color(1.0, 0.9, 0.72, 0.58)

	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.88, 0.72, 0.66, 0.30)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color(1.0, 0.94, 0.86, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.92, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.96, 0.82, 0.72, 1.0))
	button.add_theme_color_override("font_outline_color", Color(0.02, 0.018, 0.035, 0.86))
	button.add_theme_constant_override("outline_size", 1)

func _style_settings_slider(slider: HSlider) -> void:
	var rail: StyleBoxFlat = StyleBoxFlat.new()
	rail.bg_color = Color(0.78, 0.72, 0.66, 0.36)
	rail.border_color = Color(1.0, 0.92, 0.78, 0.22)
	rail.border_width_left = 1
	rail.border_width_top = 1
	rail.border_width_right = 1
	rail.border_width_bottom = 1
	rail.corner_radius_top_left = 6
	rail.corner_radius_top_right = 6
	rail.corner_radius_bottom_right = 6
	rail.corner_radius_bottom_left = 6
	rail.content_margin_top = 5
	rail.content_margin_bottom = 5

	var fill: StyleBoxFlat = rail.duplicate() as StyleBoxFlat
	fill.bg_color = Color(1.0, 0.86, 0.62, 0.92)
	fill.border_color = Color(1.0, 0.94, 0.78, 0.42)

	slider.add_theme_stylebox_override("slider", rail)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.custom_minimum_size = Vector2(0, 28)
	slider.modulate = Color(1.0, 0.98, 0.92, 1.0)

func _style_dialog_icon_button(button: Button) -> void:
	var transparent: StyleBoxFlat = StyleBoxFlat.new()
	transparent.bg_color = Color(0, 0, 0, 0)
	transparent.border_color = Color(0, 0, 0, 0)

	var hover: StyleBoxFlat = StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.92, 0.82, 0.08)
	hover.border_color = Color(1.0, 0.92, 0.82, 0.26)
	hover.border_width_left = 1
	hover.border_width_top = 1
	hover.border_width_right = 1
	hover.border_width_bottom = 1
	hover.corner_radius_top_left = 6
	hover.corner_radius_top_right = 6
	hover.corner_radius_bottom_right = 6
	hover.corner_radius_bottom_left = 6

	var pressed: StyleBoxFlat = hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 0.92, 0.82, 0.14)

	button.add_theme_stylebox_override("normal", transparent)
	button.add_theme_stylebox_override("disabled", transparent)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)

func _apply_responsive_layout() -> void:
	if settings_panel == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var margin: float = clampf(min(viewport_size.x, viewport_size.y) * 0.04, 12.0, 32.0)
	_layout_scaled_center_panel(settings_panel, SETTINGS_PANEL_SIZE, margin)
	_layout_scaled_center_panel(save_load_panel, SAVE_LOAD_PANEL_SIZE, margin)
	_layout_dialog_for_viewport(viewport_size)
	_layout_choices_for_viewport(viewport_size, margin)
	_layout_nvl_for_viewport(viewport_size, margin)

func _layout_scaled_center_panel(panel: Control, base_size: Vector2, margin: float) -> void:
	if panel == null:
		return
	var available_size: Vector2 = get_viewport_rect().size - Vector2(margin * 2.0, margin * 2.0)
	var scale_factor: float = min(1.0, available_size.x / base_size.x, available_size.y / base_size.y)
	scale_factor = max(scale_factor, 0.45)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -base_size.x * 0.5
	panel.offset_top = -base_size.y * 0.5
	panel.offset_right = base_size.x * 0.5
	panel.offset_bottom = base_size.y * 0.5
	panel.pivot_offset = base_size * 0.5
	panel.scale = Vector2(scale_factor, scale_factor)

func _layout_dialog_for_viewport(viewport_size: Vector2) -> void:
	var horizontal_margin: float = clampf(viewport_size.x * 0.035, 12.0, 28.0)
	var bottom_margin: float = clampf(viewport_size.y * 0.028, 10.0, 24.0)
	var dialog_height: float = clampf(viewport_size.y * 0.27, 150.0, 230.0)
	var dialog_padding: float = clampf(viewport_size.x * 0.018, 14.0, 24.0)
	var dialog_font_size: int = int(round(clampf(min(viewport_size.x, viewport_size.y) * 0.028, 19.0, 24.0)))
	var name_font_size: int = int(round(clampf(min(viewport_size.x, viewport_size.y) * 0.025, 18.0, 22.0)))

	dialog_panel.anchor_left = 0.0
	dialog_panel.anchor_top = 1.0
	dialog_panel.anchor_right = 1.0
	dialog_panel.anchor_bottom = 1.0
	dialog_panel.offset_left = horizontal_margin
	dialog_panel.offset_top = -bottom_margin - dialog_height
	dialog_panel.offset_right = -horizontal_margin
	dialog_panel.offset_bottom = -bottom_margin

	char_name.offset_left = dialog_padding
	char_name.offset_top = 10.0
	char_name.offset_right = -64.0
	char_name.offset_bottom = 40.0
	char_name.add_theme_font_size_override("font_size", name_font_size)

	dialog_text.offset_left = dialog_padding
	dialog_text.offset_top = 44.0
	dialog_text.offset_right = -dialog_padding
	dialog_text.offset_bottom = -18.0
	dialog_text.add_theme_font_size_override("font_size", dialog_font_size)

	var icon_size: float = clampf(viewport_size.x * 0.036, 32.0, 42.0)
	settings_btn.offset_left = -icon_size - 12.0
	settings_btn.offset_top = 8.0
	settings_btn.offset_right = -12.0
	settings_btn.offset_bottom = 8.0 + icon_size

func _layout_choices_for_viewport(viewport_size: Vector2, margin: float) -> void:
	var choices_width: float = min(620.0, max(1.0, viewport_size.x - margin * 2.0))
	choices_container.offset_left = -choices_width * 0.5
	choices_container.offset_right = choices_width * 0.5
	choices_container.offset_bottom = -clampf(viewport_size.y * 0.03, 12.0, 26.0)

func _layout_nvl_for_viewport(viewport_size: Vector2, margin: float) -> void:
	nvl_scroll.offset_left = margin + 28.0
	nvl_scroll.offset_top = margin + 16.0
	nvl_scroll.offset_right = -margin - 28.0
	nvl_scroll.offset_bottom = -margin - 40.0

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

	var saved_bgm_url: String = ""
	var pending_slot: int = int(persistent.get("pending_load_slot", -1))
	if pending_slot >= 0:
		flags = {}
		saved_bgm_url = _load_slot_into_state(pending_slot)
		persistent.erase("pending_load_slot")
		_save_persistent()
	else:
		flags = {}
	_advance(current_node_id)
	if saved_bgm_url != "" and current_bgm_url == "":
		_play_bgm_url(saved_bgm_url)

# ---- Advance ----

func _advance(node_id: String) -> void:
	current_node_id = node_id
	current_node_was_seen = _is_node_seen(node_id)
	_mark_node_seen(node_id)
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
	_start_text_reveal(dialog_text, _node_text(node, "text"))

	dialog_panel.visible    = true
	next_btn.visible        = false
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
	var line_text: String = (name_str + ": " if name_str != "" else "") + text_str
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if name_str != "":
		lbl.add_theme_color_override("font_color", Color(0.77, 0.67, 1.0, 1.0))
	nvl_content.add_child(lbl)
	_start_text_reveal(lbl, line_text)

	nvl_panel.visible         = true
	nvl_next_btn.visible      = false
	dialog_panel.visible      = false
	choices_container.visible = false
	current_node_id           = node.get("id", "")

	# Scroll to bottom next frame
	call_deferred("_nvl_scroll_bottom")

func _nvl_scroll_bottom() -> void:
	nvl_scroll.scroll_vertical = nvl_scroll.get_v_scroll_bar().max_value

func _clear_nvl() -> void:
	if reveal_label != null and reveal_label.get_parent() == nvl_content:
		text_revealing = false
		reveal_label = null
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
	_start_text_reveal(dialog_text, _node_text(node, "question"))
	next_btn.visible = false
	dialog_panel.visible = true

	for child in choices_container.get_children():
		child.queue_free()

	var choices: Array = node.get("choices", [])
	choices_container.visible = choices.size() > 0

	for i in choices.size():
		var btn := Button.new()
		btn.text = _locale_choice_text(node, i)
		btn.add_theme_font_size_override("font_size", 17)
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

	var tw: Tween = create_tween()
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
	var ach_icon_url: String = node.get("achievement_icon_game_url", "")

	if ach_id != "":
		if not persistent.has("achievements"):
			persistent["achievements"] = {}
		if not persistent["achievements"].has(ach_id):
			persistent["achievements"][ach_id] = {
				"name": ach_name,
				"icon": ach_icon_url,
				"unlocked_at": Time.get_datetime_string_from_system()
			}
			_save_persistent()
			_show_achievement_popup(ach_name, ach_icon_url)

	var next = _next_node(node.get("id",""), "out")
	if next != "": _advance(next)
	else: _show_end("achievement: следующий узел не найден.")

func _show_achievement_popup(name_str: String, icon_url: String = "") -> void:
	ach_name_label.text = name_str
	ach_icon.texture = null
	ach_icon.visible = false
	ach_icon_fallback.visible = true
	if icon_url != "":
		var tex: Texture2D = _load_tex("res://" + icon_url)
		if tex:
			ach_icon.texture = tex
			ach_icon.visible = true
			ach_icon_fallback.visible = false
	achievement_popup.visible = true
	achievement_popup.modulate.a = 0.0
	var tw: Tween = create_tween()
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
			next_btn.visible        = false
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

func _advance_or_finish_text() -> void:
	if settings_panel.visible or save_load_panel.visible:
		return
	if text_revealing:
		_finish_text_reveal()
		return
	if choices_container.visible:
		return
	if not cg_mode and not dialog_panel.visible and not nvl_panel.visible:
		return
	_on_next()

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
	_start_text_reveal(dialog_text, msg)
	next_btn.visible = false
	choices_container.visible = false
	dialog_panel.visible = true
	_clear_stage()

func _save_game() -> void:
	var slot_index: int = int(persistent.get("last_save_slot", 0))
	if slot_index < 0 or slot_index >= SAVE_SLOT_COUNT:
		slot_index = 0
	await _save_game_to_slot(slot_index)

func _on_back() -> void:
	if ResourceLoader.exists("res://scenes/Main.tscn"):
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
	else:
		get_tree().quit()

# ---- In-game controls ----

func _open_save_slots(mode: String) -> void:
	save_load_mode = mode
	if mode == "load":
		save_load_title.text = "Загрузить сохранение"
	else:
		save_load_title.text = "Сохранить в слот"
	_populate_save_slots()
	save_load_shade.visible = true
	save_load_panel.visible = true

func _close_save_slots() -> void:
	save_load_panel.visible = false
	save_load_shade.visible = false

func _populate_save_slots() -> void:
	for child in save_slots_list.get_children():
		child.queue_free()

	var slots: Array = _get_save_slots()
	for i in range(SAVE_SLOT_COUNT):
		var disabled: bool = save_load_mode == "load" and not _slot_is_loadable(slots[i])
		var button: Button = _make_slot_button(i, slots[i], disabled)
		button.pressed.connect(_on_save_slot_pressed.bind(i))
		save_slots_list.add_child(button)

func _on_save_slot_pressed(slot_index: int) -> void:
	if save_load_mode == "load":
		_load_game_from_slot(slot_index)
	else:
		await _save_game_to_slot(slot_index)

func _make_slot_button(slot_index: int, slot: Variant, disabled: bool) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 104)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = ""
	button.disabled = disabled
	button.clip_contents = true
	_style_slot_button(button)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12.0
	row.offset_top = 10.0
	row.offset_right = -12.0
	row.offset_bottom = -10.0
	row.add_theme_constant_override("separation", 14)
	button.add_child(row)

	var preview_panel: Panel = _make_slot_preview(slot)
	row.add_child(preview_panel)

	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 5)
	row.add_child(text_box)

	var title_label: Label = _make_slot_label(_format_slot_title(slot_index, slot), 15, Color(1.0, 0.93, 0.84, 1.0))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(title_label)

	var meta_label: Label = _make_slot_label(_format_slot_meta(slot), 12, Color(0.82, 0.88, 0.9, 0.78))
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(meta_label)
	return button

func _make_slot_preview(slot: Variant) -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = Vector2(142, 80)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_slot_preview(panel)

	var texture: Texture2D = _load_slot_preview(slot)
	if texture != null:
		var preview: TextureRect = TextureRect.new()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.set_anchors_preset(Control.PRESET_FULL_RECT)
		preview.texture = texture
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		panel.add_child(preview)
	else:
		var placeholder: Label = _make_slot_label("Пусто", 13, Color(0.92, 0.88, 0.82, 0.52))
		placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(placeholder)
	return panel

func _format_slot_title(slot_index: int, slot: Variant) -> String:
	var prefix: String = "Слот %02d" % [slot_index + 1]
	if not _slot_has_data(slot):
		return prefix
	var slot_dictionary: Dictionary = slot as Dictionary
	var title: String = str(slot_dictionary.get("title", ""))
	if title == "":
		title = str(slot_dictionary.get("node_id", ""))
	return prefix + " · " + title

func _format_slot_meta(slot: Variant) -> String:
	if not _slot_has_data(slot):
		return "Свободное место"
	var slot_dictionary: Dictionary = slot as Dictionary
	var saved_at: String = str(slot_dictionary.get("saved_at", ""))
	if saved_at == "":
		return "Сохранение без даты"
	return saved_at

func _make_slot_label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _style_slot_button(button: Button) -> void:
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.95, 0.89, 0.82, 0.10)
	normal.border_color = Color(1.0, 0.92, 0.84, 0.22)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 7
	normal.corner_radius_top_right = 7
	normal.corner_radius_bottom_right = 7
	normal.corner_radius_bottom_left = 7

	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 0.93, 0.86, 0.18)
	hover.border_color = Color(1.0, 0.88, 0.72, 0.48)

	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.9, 0.78, 0.72, 0.24)

	var disabled: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.16, 0.16, 0.2, 0.18)
	disabled.border_color = Color(0.7, 0.7, 0.76, 0.12)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)

func _style_slot_preview(panel: Panel) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.035, 0.06, 0.72)
	style.border_color = Color(1.0, 0.9, 0.78, 0.18)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_right = 5
	style.corner_radius_bottom_left = 5
	panel.add_theme_stylebox_override("panel", style)

func _load_slot_preview(slot: Variant) -> Texture2D:
	if not (slot is Dictionary):
		return null
	var slot_dictionary: Dictionary = slot as Dictionary
	var preview_path: String = str(slot_dictionary.get("preview_path", ""))
	if preview_path == "" or not FileAccess.file_exists(preview_path):
		return null
	var image: Image = Image.new()
	if image.load(preview_path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _save_game_to_slot(slot_index: int) -> void:
	var slots: Array = _get_save_slots()
	if slot_index < 0 or slot_index >= SAVE_SLOT_COUNT:
		return
	var preview_path: String = await _capture_save_preview(slot_index)
	if preview_path == "" and _slot_has_data(slots[slot_index]):
		var previous_slot: Dictionary = slots[slot_index] as Dictionary
		preview_path = str(previous_slot.get("preview_path", ""))
	slots[slot_index] = {
		"node_id": current_node_id,
		"bgm_url": current_bgm_url,
		"flags": flags.duplicate(true),
		"locale": current_locale,
		"title": _current_save_title(),
		"saved_at": Time.get_datetime_string_from_system(),
		"preview_path": preview_path
	}
	_set_save_slots(slots)
	persistent["last_save_slot"] = slot_index
	persistent["save"] = slots[slot_index]
	_save_persistent()
	_populate_save_slots()
	_show_save_notice("Слот %d сохранён" % [slot_index + 1])

func _load_game_from_slot(slot_index: int) -> void:
	var slots: Array = _get_save_slots()
	if slot_index < 0 or slot_index >= slots.size() or not _slot_is_loadable(slots[slot_index]):
		return
	var saved_bgm_url: String = _load_slot_into_state(slot_index)
	if current_node_id == "":
		return
	persistent["last_save_slot"] = slot_index
	persistent["save"] = slots[slot_index]
	_save_persistent()
	_close_save_slots()
	_close_settings()
	cg_mode = false
	cg_overlay.visible = false
	_clear_nvl()
	_clear_stage()
	current_bgm_url = ""
	_advance(current_node_id)
	if saved_bgm_url != "" and current_bgm_url == "":
		_play_bgm_url(saved_bgm_url)

func _load_slot_into_state(slot_index: int) -> String:
	var slots: Array = _get_save_slots()
	if slot_index < 0 or slot_index >= slots.size() or not _slot_is_loadable(slots[slot_index]):
		return ""
	var slot_dictionary: Dictionary = slots[slot_index] as Dictionary
	var node_id: String = str(slot_dictionary.get("node_id", ""))
	current_node_id = node_id
	current_locale = str(slot_dictionary.get("locale", current_locale))
	var saved_flags: Variant = slot_dictionary.get("flags", {})
	if saved_flags is Dictionary:
		flags = (saved_flags as Dictionary).duplicate(true)
	else:
		flags = {}
	return str(slot_dictionary.get("bgm_url", ""))

func _capture_save_preview(slot_index: int) -> String:
	var hidden_items: Array[CanvasItem] = []
	_hide_for_preview(settings_shade, hidden_items)
	_hide_for_preview(settings_panel, hidden_items)
	_hide_for_preview(save_load_shade, hidden_items)
	_hide_for_preview(save_load_panel, hidden_items)
	_hide_for_preview(achievement_popup, hidden_items)
	_hide_for_preview(back_btn, hidden_items)
	_hide_for_preview(save_btn, hidden_items)
	_hide_for_preview(settings_btn, hidden_items)
	_hide_for_preview(next_btn, hidden_items)
	_hide_for_preview(nvl_next_btn, hidden_items)

	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	for item in hidden_items:
		item.visible = true

	if image.get_width() <= 0 or image.get_height() <= 0:
		return ""
	image.resize(320, 180, Image.INTERPOLATE_LANCZOS)
	var path: String = "user://save_slot_%03d.png" % [slot_index + 1]
	if image.save_png(path) != OK:
		return ""
	return path

func _hide_for_preview(item: CanvasItem, hidden_items: Array[CanvasItem]) -> void:
	if item != null and item.visible:
		hidden_items.append(item)
		item.visible = false

func _current_save_title() -> String:
	var node: Dictionary = _get_node(current_node_id)
	if node.is_empty():
		return current_node_id
	var node_type: String = str(node.get("type", ""))
	if node_type == "dialog":
		var text: String = _node_text(node, "text")
		if text != "":
			return _shorten_text(text)
	if node_type == "choice":
		var question: String = _node_text(node, "question")
		if question != "":
			return _shorten_text(question)
	if node_type == "chapter":
		var title: String = _node_text(node, "title")
		if title != "":
			return _shorten_text(title)
	return node_type + " " + current_node_id

func _shorten_text(text: String) -> String:
	var clean: String = text.replace("\n", " ").strip_edges()
	if clean.length() > 42:
		return clean.substr(0, 39) + "..."
	return clean

func _show_save_notice(text: String) -> void:
	save_notify.text = text
	save_notify.visible = true
	settings_status_label.text = text
	var tw: Tween = create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(func():
		save_notify.visible = false
		settings_status_label.text = ""
	)

func _open_settings() -> void:
	settings_status_label.text = ""
	settings_shade.visible = true
	settings_panel.visible = true

func _close_settings() -> void:
	settings_panel.visible = false
	settings_shade.visible = false
	_save_persistent()

func _start_text_reveal(label: Label, text: String) -> void:
	reveal_label = label
	reveal_full_text = text
	reveal_visible_chars = 0.0
	label.text = text
	var speed: float = float(settings.get("text_speed", 55.0))
	if speed >= 119.0 or text.length() == 0:
		label.visible_characters = -1
		text_revealing = false
	else:
		label.visible_characters = 0
		text_revealing = true

func _update_text_reveal(delta: float) -> void:
	if not text_revealing or reveal_label == null:
		return
	var speed: float = float(settings.get("text_speed", 55.0))
	if speed < 1.0:
		speed = 1.0
	reveal_visible_chars += speed * delta
	var visible_count: int = int(floor(reveal_visible_chars))
	if visible_count >= reveal_full_text.length():
		_finish_text_reveal()
	else:
		reveal_label.visible_characters = visible_count

func _finish_text_reveal() -> void:
	if reveal_label != null:
		reveal_label.visible_characters = -1
	text_revealing = false
	reveal_label = null
	reveal_full_text = ""
	reveal_visible_chars = 0.0

func _is_right_skip_zone(pos: Vector2) -> bool:
	return pos.x >= get_viewport_rect().size.x * 0.66

func _update_seen_skip(delta: float) -> void:
	if not skip_hold_active:
		return
	if settings_panel.visible or save_load_panel.visible or choices_container.visible:
		_stop_seen_skip()
		return
	skip_hold_timer += delta
	if skip_hold_timer < SKIP_HOLD_DELAY:
		return
	skip_hold_started = true
	if text_revealing:
		_finish_text_reveal()
		return
	skip_step_timer -= delta
	if skip_step_timer > 0.0:
		return
	skip_step_timer = SKIP_STEP_INTERVAL
	if not _can_skip_current_node():
		_stop_seen_skip()
		return
	_on_next()

func _can_skip_current_node() -> bool:
	if not bool(settings.get("skip_seen_only", true)):
		return false
	if not current_node_was_seen:
		return false
	if _next_node(current_node_id, "out") == "" and not cg_mode:
		return false
	return true

func _stop_seen_skip() -> void:
	skip_hold_active = false
	skip_hold_started = false
	skip_hold_timer = 0.0
	skip_step_timer = 0.0

func _is_pointer_over_blocking_control(pos: Vector2) -> bool:
	if settings_panel.visible or save_load_panel.visible:
		return true
	var blockers: Array[Control] = [next_btn, nvl_next_btn, save_btn, settings_btn, back_btn]
	for child in choices_container.get_children():
		if child is Control:
			blockers.append(child as Control)
	for item in blockers:
		if item != null and item.is_visible_in_tree() and Rect2(item.global_position, item.size).has_point(pos):
			return true
	return false

func _is_node_seen(node_id: String) -> bool:
	return bool(seen_nodes.get(node_id, false))

func _mark_node_seen(node_id: String) -> void:
	if node_id == "":
		return
	if not bool(seen_nodes.get(node_id, false)):
		seen_nodes[node_id] = true
		_save_persistent()

# ---- BGM ----

func _apply_node_bgm(node: Dictionary) -> void:
	var url: String = str(node.get("bgm_game_url", node.get("bgm_url", "")))
	if url == "":
		return   # No change — keep current track playing
	if url == "__stop__":
		current_bgm_url = ""
		bgm.stop()
		return
	if url == current_bgm_url and bgm.stream != null:
		return   # Same track — don't restart
	_play_bgm_url(url)

func _play_bgm_url(url: String) -> void:
	current_bgm_url = url
	var stream: AudioStream = _load_audio_stream(url if url.begins_with("res://") else "res://" + url)
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
