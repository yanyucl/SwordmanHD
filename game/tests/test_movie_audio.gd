# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 过场视频声音 (w5 项 5, 原版 实测): 不受音乐/音效开关影响 (Master 总线), 增益 +6.2 dB, Esc 立即停。


func test_video_bus_and_gain():
	var src := FileAccess.get_file_as_string("res://scripts/movie_scene.gd")
	check(src.contains('_player.bus = "Master"'), "视频走 Master 总线 (原版音乐/音效开关关掉视频照响)")
	check(not src.contains('_player.bus = "Music"'), "不再走 Music 总线")
	near(float(load("res://scripts/movie_scene.gd").VIDEO_GAIN_DB), 6.2, 0.01, "视频增益 +6.2 dB (原版实测, Logo rms 原版 -9.59 / 复刻 -9.70)")
	check(src.contains("_player.stop()"), "跳过时立即 stop (原版 Esc 后约 0.2 秒内静音)")


## 视频自带声音: 播放期间暂停在响的场景音乐, 播完接着放 (法术视频 / 诸物炼化原先和战场 / 营地音乐叠在一起); 剧本暂停着的不动
func test_scene_music_paused_while_movie_plays():
	var root := (Engine.get_main_loop() as SceneTree).root
	var host := Node.new()
	root.add_child(host)
	var mus := SceneMusic.new(host)
	var a := AudioStreamPlayer.new()
	var b := AudioStreamPlayer.new()
	for p in [a, b]:
		p.stream = AudioStreamGenerator.new()
		p.add_to_group(SceneMusic.GROUP)
		host.add_child(p)
		p.play()
	b.stream_paused = true   # 剧本暂停着
	var m: Control = MovieScene.create(["Movie/__no_such_movie__"], func(): pass)
	root.add_child(m)   # 开播: 找不到文件的这段要到下一帧才跳过
	check(a.stream_paused, "在响的音乐暂停")
	check(b.stream_paused, "剧本暂停着的仍暂停")
	m._next()   # 队列放完
	check(not a.stream_paused, "播完接着放")
	check(b.stream_paused, "剧本暂停着的不被接回")
	m.free()
	host.free()
	check(mus != null, "SceneMusic 可用")
