extends Node
## Installed only in the separate simulator capture project, never in release.
const I18n = preload("res://i18n.gd")
var game: Node
var output := "user://store-capture"

func _ready() -> void:
	call_deferred("capture")

func capture() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://main.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	game.muted = true
	await get_tree().create_timer(3.0).timeout
	for locale in ["en", "ko"]:
		I18n.locale = locale
		game.start_campaign(0)
		game.rng.seed = 8675309
		# Exercise normal gameplay with virtual joystick movement and upgrades.
		for step in range(520):
			if game.state == "upgrade": game.choose_upgrade(step % 3)
			if game.state != "playing": break
			game.mobile_ui.movement = Vector2(cos(step * 0.013), sin(step * 0.013))
			game._tick(0.05)
			game._tick_effects(0.05)
		game.mobile_ui.movement = Vector2.ZERO
		await screenshot(locale, "01-gameplay")
		game.state = "sector_map"
		await screenshot(locale, "02-sectors")
		game.state = "hangar"
		await screenshot(locale, "03-hangar")
	var done := FileAccess.open(output + "/complete.json", FileAccess.WRITE)
	done.store_string(JSON.stringify({"platform": OS.get_name(), "screen_size": str(DisplayServer.screen_get_size()), "viewport_size": str(get_viewport().get_visible_rect().size), "safe_area": str(DisplayServer.get_display_safe_area()), "screenshots": 6}))
	done.close()
	get_tree().quit()

func screenshot(locale: String, page: String) -> void:
	game.mobile_ui.refresh()
	game.queue_redraw()
	for frame in range(10): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	# Capture the actual native app framebuffer. Simulator hardware screenshots
	# can include a rotated device mask or a letterboxed UIKit presentation.
	var framebuffer := get_viewport().get_texture().get_image()
	framebuffer.convert(Image.FORMAT_RGB8)
	assert(framebuffer.save_png(output + "/" + locale + "-" + page + ".png") == OK)
	var marker := FileAccess.open(output + "/ready.json", FileAccess.WRITE)
	marker.store_string(JSON.stringify({"name": locale + "-" + page, "state": game.state, "locale": I18n.locale, "platform": OS.get_name(), "capture_method": "native iOS viewport framebuffer", "width": framebuffer.get_width(), "height": framebuffer.get_height()}))
	marker.close()
	var timeout := Time.get_ticks_msec() + 60000
	while not FileAccess.file_exists(output + "/ack"):
		if Time.get_ticks_msec() > timeout:
			push_error("Screenshot host timeout")
			get_tree().quit(2)
			return
		await get_tree().create_timer(0.1).timeout
	DirAccess.remove_absolute(output + "/ack")
