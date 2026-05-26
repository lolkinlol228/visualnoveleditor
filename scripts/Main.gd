extends Control

const GAME_SCENE: String = "res://scenes/Game.tscn"
const MENU_BACKGROUND: String = "res://game_data/backgrounds/main_menu_day_lake.png"
const PERSISTENT_PATH: String = "user://persistent.json"
const SAVE_SLOT_COUNT: int = 99
const SETTINGS_PANEL_SIZE: Vector2 = Vector2(580.0, 388.0)
const GALLERY_PANEL_SIZE: Vector2 = Vector2(600.0, 400.0)
const LOAD_PANEL_SIZE: Vector2 = Vector2(620.0, 440.0)

var persistent: Dictionary = {}
var settings: Dictionary = {}
var modal_panels: Array[Control] = []

@onready var background: TextureRect = $Background
@onready var command_frame: Panel = $CommandFrame
@onready var modal_shade: ColorRect = $ModalShade
@onready var menu_vbox: VBoxContainer = $MenuVBox
@onready var title_label: Label = $MenuVBox/Title
@onready var title_rule: ColorRect = $MenuVBox/TitleRule
@onready var new_game_button: Button = $MenuVBox/NewGameButton
@onready var load_button: Button = $MenuVBox/LoadButton
@onready var gallery_button: Button = $MenuVBox/GalleryButton
@onready var settings_button: Button = $MenuVBox/SettingsButton
@onready var exit_button: Button = $MenuVBox/ExitButton
@onready var status_label: Label = $MenuVBox/StatusLabel
@onready var settings_panel: Panel = $SettingsPanel
@onready var gallery_panel: Panel = $GalleryPanel
@onready var load_panel: Panel = $LoadPanel
@onready var master_volume_slider: HSlider = $SettingsPanel/MasterVolumeSlider
@onready var window_mode_button: Button = $SettingsPanel/WindowModeButton
@onready var gallery_list: VBoxContainer = $GalleryPanel/Scroll/List
@onready var load_slots_list: VBoxContainer = $LoadPanel/Scroll/List

func _ready() -> void:
	modal_panels = [settings_panel, gallery_panel, load_panel]
	_load_menu_background()
	_load_persistent()
	_apply_settings()
	_wire_buttons()
	_style_interface()
	_apply_responsive_layout()
	_start_soft_motion()
	_refresh_state()
	new_game_button.grab_focus()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_responsive_layout()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and modal_shade.visible:
		_close_modal()
		get_viewport().set_input_as_handled()

func _wire_buttons() -> void:
	new_game_button.pressed.connect(func(): _start_game(true))
	load_button.pressed.connect(_open_load_slots)
	gallery_button.pressed.connect(_open_gallery)
	settings_button.pressed.connect(func(): _show_modal(settings_panel))
	exit_button.pressed.connect(func(): get_tree().quit())
	window_mode_button.pressed.connect(_toggle_window_mode)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	$SettingsPanel/CloseButton.pressed.connect(_close_modal)
	$GalleryPanel/CloseButton.pressed.connect(_close_modal)
	$LoadPanel/CloseButton.pressed.connect(_close_modal)

func _load_menu_background() -> void:
	var img: Image = Image.new()
	if img.load(MENU_BACKGROUND) == OK:
		background.texture = ImageTexture.create_from_image(img)

func _load_persistent() -> void:
	persistent = {}
	if FileAccess.file_exists(PERSISTENT_PATH):
		var file: FileAccess = FileAccess.open(PERSISTENT_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			persistent = parsed as Dictionary

	var saved_settings: Variant = persistent.get("settings", {})
	if saved_settings is Dictionary:
		settings = saved_settings as Dictionary
	else:
		settings = {}
	if not settings.has("master_volume"):
		settings["master_volume"] = 85.0
	if not settings.has("fullscreen"):
		settings["fullscreen"] = false

func _save_persistent() -> void:
	persistent["settings"] = settings
	persistent["save_slots"] = _get_save_slots()
	var file: FileAccess = FileAccess.open(PERSISTENT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(persistent, "\t"))
	file.close()

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

func _slot_has_data(slot: Variant) -> bool:
	if not (slot is Dictionary):
		return false
	var slot_dictionary: Dictionary = slot as Dictionary
	return str(slot_dictionary.get("node_id", "")) != ""

func _has_save() -> bool:
	for slot in _get_save_slots():
		if _slot_has_data(slot):
			return true
	return false

func _refresh_state() -> void:
	load_button.disabled = not _has_save()
	status_label.text = ""
	_update_window_mode_text()

func _start_game(clear_save: bool) -> void:
	if clear_save:
		persistent.erase("pending_load_slot")
		_save_persistent()
	get_tree().change_scene_to_file(GAME_SCENE)

func _open_load_slots() -> void:
	if not _has_save():
		status_label.text = "Нет сохранений."
		return
	_populate_load_slots()
	_show_modal(load_panel)

func _populate_load_slots() -> void:
	for child in load_slots_list.get_children():
		child.queue_free()

	var slots: Array = _get_save_slots()
	for i in range(SAVE_SLOT_COUNT):
		var button: Button = _make_load_slot_button(i, slots[i])
		button.pressed.connect(_load_game_from_slot.bind(i))
		load_slots_list.add_child(button)

func _make_load_slot_button(slot_index: int, slot: Variant) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 104)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = ""
	button.disabled = not _slot_has_data(slot)
	button.clip_contents = true
	_style_menu_button(button)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12.0
	row.offset_top = 10.0
	row.offset_right = -12.0
	row.offset_bottom = -10.0
	row.add_theme_constant_override("separation", 14)
	button.add_child(row)

	row.add_child(_make_slot_preview(slot))

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

func _load_game_from_slot(slot_index: int) -> void:
	var slots: Array = _get_save_slots()
	if slot_index < 0 or slot_index >= slots.size() or not _slot_has_data(slots[slot_index]):
		return
	persistent["pending_load_slot"] = slot_index
	persistent["last_save_slot"] = slot_index
	persistent["save"] = slots[slot_index]
	_save_persistent()
	get_tree().change_scene_to_file(GAME_SCENE)

func _open_gallery() -> void:
	_populate_gallery()
	_show_modal(gallery_panel)

func _show_modal(panel: Control) -> void:
	for item in modal_panels:
		item.visible = false
		item.modulate.a = 1.0
	modal_shade.visible = true
	panel.visible = true
	panel.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)

func _close_modal() -> void:
	for item in modal_panels:
		item.visible = false
	modal_shade.visible = false
	new_game_button.grab_focus()

func _populate_gallery() -> void:
	for child in gallery_list.get_children():
		child.queue_free()

	var entries: Array[String] = []
	var gallery: Variant = persistent.get("gallery", {})
	if gallery is Dictionary:
		var gallery_dictionary: Dictionary = gallery as Dictionary
		for key in gallery_dictionary.keys():
			var gallery_item: Variant = gallery_dictionary[key]
			if gallery_item is Dictionary:
				var gallery_item_dictionary: Dictionary = gallery_item as Dictionary
				entries.append("CG: " + str(gallery_item_dictionary.get("name", key)))
			else:
				entries.append("CG: " + str(key))

	var endings: Variant = persistent.get("endings", {})
	if endings is Dictionary:
		var endings_dictionary: Dictionary = endings as Dictionary
		for key in endings_dictionary.keys():
			var ending_item: Variant = endings_dictionary[key]
			if ending_item is Dictionary:
				var ending_item_dictionary: Dictionary = ending_item as Dictionary
				entries.append("Концовка: " + str(ending_item_dictionary.get("name", key)))
			else:
				entries.append("Концовка: " + str(key))

	var achievements: Variant = persistent.get("achievements", {})
	if achievements is Dictionary:
		var achievements_dictionary: Dictionary = achievements as Dictionary
		for key in achievements_dictionary.keys():
			var achievement_item: Variant = achievements_dictionary[key]
			if achievement_item is Dictionary:
				var achievement_item_dictionary: Dictionary = achievement_item as Dictionary
				entries.append("Достижение: " + str(achievement_item_dictionary.get("name", key)))
			else:
				entries.append("Достижение: " + str(key))

	if entries.is_empty():
		gallery_list.add_child(_make_gallery_label("Пока пусто. Открытые CG, концовки и достижения появятся здесь."))
		return

	for entry in entries:
		gallery_list.add_child(_make_gallery_label(entry))

func _make_gallery_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.94, 0.91, 0.86, 0.96))
	label.add_theme_font_size_override("font_size", 15)
	return label

func _apply_settings() -> void:
	var volume: float = float(settings.get("master_volume", 85.0))
	master_volume_slider.value = volume
	_apply_master_volume(volume)

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
	if window_mode_button == null:
		return
	var fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if fullscreen:
		window_mode_button.text = "Полный экран"
	else:
		window_mode_button.text = "Оконный режим"

func _style_interface() -> void:
	_style_frame(command_frame, Color(0.045, 0.045, 0.075, 0.76), Color(0.98, 0.9, 0.82, 0.36))
	for panel in modal_panels:
		_style_frame(panel, Color(0.045, 0.04, 0.065, 0.96), Color(1.0, 0.9, 0.74, 0.46))

	var settings_group_names: Array[String] = ["AudioGroup", "SystemGroup"]
	for group_name in settings_group_names:
		var group_node: Node = settings_panel.get_node_or_null(group_name)
		if group_node is Panel:
			_style_frame(group_node as Panel, Color(0.095, 0.085, 0.115, 0.88), Color(1.0, 0.9, 0.74, 0.24))

	var settings_title_names: Array[String] = ["Title", "AudioGroupTitle", "SystemGroupTitle"]
	for label_name in settings_title_names:
		var title_node: Node = settings_panel.get_node_or_null(label_name)
		if title_node is Label:
			var label: Label = title_node as Label
			label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.76, 1.0))
			label.add_theme_color_override("font_outline_color", Color(0.02, 0.018, 0.035, 0.95))
			label.add_theme_constant_override("outline_size", 2)

	for button in [new_game_button, load_button, gallery_button, settings_button, exit_button]:
		_style_menu_button(button, button == new_game_button)
	_style_menu_button(window_mode_button, false)
	_style_menu_button($SettingsPanel/CloseButton, false, true)
	_style_menu_button($GalleryPanel/CloseButton, false, true)
	_style_menu_button($LoadPanel/CloseButton, false, true)

	menu_vbox.add_theme_constant_override("separation", 9)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.82, 1.0))
	title_label.add_theme_color_override("font_shadow_color", Color(0.09, 0.07, 0.12, 0.68))
	title_label.add_theme_color_override("font_outline_color", Color(0.035, 0.032, 0.055, 0.92))
	title_label.add_theme_constant_override("shadow_offset_x", 1)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.add_theme_constant_override("outline_size", 2)
	title_label.add_theme_font_size_override("font_size", 36)
	title_rule.color = Color(0.95, 0.82, 0.68, 0.72)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.66, 0.9))

func _apply_responsive_layout() -> void:
	if settings_panel == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var margin: float = clampf(min(viewport_size.x, viewport_size.y) * 0.04, 12.0, 32.0)
	_layout_menu_for_viewport(viewport_size, margin)
	_layout_scaled_center_panel(settings_panel, SETTINGS_PANEL_SIZE, margin)
	_layout_scaled_center_panel(gallery_panel, GALLERY_PANEL_SIZE, margin)
	_layout_scaled_center_panel(load_panel, LOAD_PANEL_SIZE, margin)

func _layout_menu_for_viewport(viewport_size: Vector2, margin: float) -> void:
	var frame_width: float = min(420.0, max(1.0, viewport_size.x - margin * 2.0))
	var frame_left: float = clampf(64.0, margin, max(margin, viewport_size.x - frame_width - margin))
	var top_anchor: float = 0.15
	var bottom_anchor: float = 0.85
	if viewport_size.y < 640.0:
		top_anchor = 0.08
		bottom_anchor = 0.94

	command_frame.anchor_top = top_anchor
	command_frame.anchor_bottom = bottom_anchor
	command_frame.offset_left = frame_left
	command_frame.offset_top = 0.0
	command_frame.offset_right = frame_left + frame_width
	command_frame.offset_bottom = 0.0

	var inner_margin: float = clampf(frame_width * 0.10, 24.0, 40.0)
	var menu_width: float = max(1.0, frame_width - inner_margin * 2.0)
	menu_vbox.anchor_top = top_anchor + 0.045
	menu_vbox.anchor_bottom = bottom_anchor - 0.035
	menu_vbox.offset_left = frame_left + inner_margin
	menu_vbox.offset_top = 0.0
	menu_vbox.offset_right = frame_left + frame_width - inner_margin
	menu_vbox.offset_bottom = 0.0

	var title_size: int = int(round(clampf(frame_width * 0.085, 30.0, 38.0)))
	var button_font_size: int = int(round(clampf(frame_width * 0.039, 15.0, 17.0)))
	var button_height: float = clampf(viewport_size.y * 0.058, 38.0, 44.0)
	title_label.add_theme_font_size_override("font_size", title_size)
	menu_vbox.add_theme_constant_override("separation", int(round(clampf(viewport_size.y * 0.012, 7.0, 10.0))))
	for button in [new_game_button, load_button, gallery_button, settings_button, exit_button]:
		button.custom_minimum_size = Vector2(menu_width, button_height)
		button.add_theme_font_size_override("font_size", button_font_size)

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

func _style_frame(panel: Panel, bg: Color, border: Color) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	style.content_margin_left = 22
	style.content_margin_right = 22
	panel.add_theme_stylebox_override("panel", style)

func _style_menu_button(button: Button, primary: bool = false, centered: bool = false) -> void:
	if centered:
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var normal: StyleBoxFlat = StyleBoxFlat.new()
	if primary:
		normal.bg_color = Color(0.96, 0.9, 0.84, 0.24)
		normal.border_color = Color(1.0, 0.89, 0.76, 0.48)
	else:
		normal.bg_color = Color(0.95, 0.89, 0.82, 0.11)
		normal.border_color = Color(1.0, 0.92, 0.84, 0.24)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 7
	normal.corner_radius_top_right = 7
	normal.corner_radius_bottom_right = 7
	normal.corner_radius_bottom_left = 7
	normal.content_margin_left = 18
	normal.content_margin_right = 18

	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 0.93, 0.86, 0.2)
	hover.border_color = Color(1.0, 0.88, 0.72, 0.52)

	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.9, 0.78, 0.72, 0.24)

	var disabled: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.18, 0.18, 0.22, 0.13)
	disabled.border_color = Color(0.7, 0.7, 0.76, 0.1)

	var focus: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(1.0, 0.92, 0.82, 0.2)
	focus.border_color = Color(1.0, 0.91, 0.76, 0.68)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color(0.98, 0.93, 0.86, 0.98))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.9, 1.0))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.96, 0.9, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.9, 0.78, 0.72, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.72, 0.72, 0.78, 0.42))
	button.add_theme_color_override("font_outline_color", Color(0.035, 0.032, 0.055, 0.82))
	button.add_theme_constant_override("outline_size", 1)
	var font_size: int = 15
	if centered:
		font_size = 14
	button.add_theme_font_size_override("font_size", font_size)

func _start_soft_motion() -> void:
	var frame_tw: Tween = create_tween()
	frame_tw.set_loops()
	frame_tw.tween_property(command_frame, "modulate:a", 0.88, 2.2)
	frame_tw.tween_property(command_frame, "modulate:a", 1.0, 2.2)

	var rule_tw: Tween = create_tween()
	rule_tw.set_loops()
	rule_tw.tween_property(title_rule, "modulate:a", 0.55, 1.8)
	rule_tw.tween_property(title_rule, "modulate:a", 1.0, 1.8)
