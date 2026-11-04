# SPDX-License-Identifier: GPL-3.0-only
class_name SceneMusic
extends RefCounted
## 场景里的音乐通道 (战场/城镇剧情共用): 通道号 -> AudioStreamPlayer。
## 原版语义: 载入只把曲子装进通道不播放, 播放另有指令 (fade=1 淡入), 暂停/继续/关闭按通道。

## 淡入 / 淡出 (静态观察 动画对照_静态观察.md S0, 战场音乐通道): 音量 25/127 <-> 127/127 线性渐变, 每 2 tick 一步共 26 步 = 52 tick = 2.08 秒 (tick 率按 25Hz, 置信度中)
const FADE_SECS := 2.08
const FADE_LOW := 25.0 / 127.0   # 淡出到这个音量才真暂停; 淡入从这个音量起

## 场景音乐播放器都在这个组里: 过场视频 (MovieScene) 播放期间暂停其中在响的, 播完接着放
const GROUP := "scene_music"

var _host: Node
var _players := {}


func _init(host: Node) -> void:
	_host = host


func load_track(ch: int, num: int) -> void:
	var rel := ThemeAssets.f("music", [num])
	if not Assets.exists(rel):
		push_warning("没有音乐 " + rel)
		return
	var s := Assets.music(rel)
	if s == null:
		return
	var p: AudioStreamPlayer = _players.get(ch)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = "Music"
		p.add_to_group(GROUP)
		_host.add_child(p)
		_players[ch] = p
	p.stop()
	p.remove_meta("resume_pos")
	p.stream = s
	p.set_meta("track", num)   # 验收探针 (scripts/ui_probe.gd) 读: 通道里当前是哪首 Music_NN.mp3
	p.stream_paused = false
	p.volume_db = 0


func start(ch: int, fade := 0) -> void:
	var p: AudioStreamPlayer = _players.get(ch)
	if p == null or p.stream == null:
		return
	p.stream_paused = false
	if fade == 1:
		p.volume_db = linear_to_db(FADE_LOW)
		p.play()
		_fade_to(p, 1.0)
	else:
		p.volume_db = 0
		p.play()


## 载入并立即播放 (场景开场的背景音乐); fade = 1: 淡入 (原版战场进场: 载入后紧接着 fade=1 开播)
func play(ch: int, num: int, fade := 0) -> void:
	load_track(ch, num)
	start(ch, fade)


## 把通道音量线性渐变到 target (0..1); 新的渐变作废旧的
func _fade_to(p: AudioStreamPlayer, target: float, then_pause := false) -> void:
	var old: Variant = p.get_meta("fade_tween") if p.has_meta("fade_tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := _host.create_tween()
	p.set_meta("fade_tween", tw)
	p.set_meta("fade_pause", then_pause)
	tw.tween_method(func(v: float): p.volume_db = linear_to_db(maxf(v, 0.0001)), db_to_linear(p.volume_db), target, FADE_SECS)
	if then_pause:
		tw.tween_callback(func(): p.stream_paused = true)


func close(ch: int) -> void:
	var p: AudioStreamPlayer = _players.get(ch)
	if p != null:
		p.stop()
		p.remove_meta("resume_pos")
		p.stream = null


## 暂停 / 继续。arg (剧本指令的第二个参数): 0 = 硬暂停 / 立即继续 (全音量), 1 = 暂停时线性淡出到 25/127 再停、继续时从 25/127 淡入 (原版 0x2D / 0x2E, 静态观察 S0)。
## 继续时如果这个通道是被 stop_all 停掉的 (放过场视频时), 从停下的位置接着放, 不然只取消暂停标志、什么也不响
func pause(ch: int, paused: bool, arg := 0) -> void:
	var p: AudioStreamPlayer = _players.get(ch)
	if p == null:
		return
	if paused and arg == 1 and p.playing and not p.stream_paused:
		_fade_to(p, FADE_LOW, true)   # 淡出完才真暂停
		return
	var old: Variant = p.get_meta("fade_tween") if p.has_meta("fade_tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	if not paused:
		p.volume_db = linear_to_db(FADE_LOW) if arg == 1 else 0.0
	p.stream_paused = paused
	if not paused and arg == 1:
		_fade_to(p, 1.0)
	if not paused and p.stream != null and not p.playing and p.has_meta("resume_pos"):
		p.play(float(p.get_meta("resume_pos")))
		p.remove_meta("resume_pos")


## 停掉所有通道 (放过场视频等, 视频自带声音)。正在播的记下位置, 之后该通道收到「继续」会接着放 (原版开场: 先放视频, 再暂停/载入别的曲子, 最后继续战斗曲)。
## 返回停掉时还在响的通道 (正在淡出暂停的不算: 剧本本来就要它停), 交给 resume_held 在视频放完后接着放
func stop_all() -> Array:
	var held := []
	for ch in _players:
		var p: AudioStreamPlayer = _players[ch]
		if p.playing or (p.stream_paused and p.stream != null):   # 暂停着的通道 playing 为假, 也要记位置, 剧本之后「继续」才接得上
			p.set_meta("resume_pos", p.get_playback_position())
			var tw: Variant = p.get_meta("fade_tween") if p.has_meta("fade_tween") else null
			var fading_out: bool = tw is Tween and (tw as Tween).is_running() and bool(p.get_meta("fade_pause", false))
			if not p.stream_paused and not fading_out:
				held.append(ch)
		p.stop()
	return held


## 过场视频放完: stop_all 停掉的通道从停下的位置接着放。原版视频指令 (0x29 → → Bink) 不碰音乐通道,
## 视频之后战斗曲照常在放 (第 30 幕蚩尤视频后剧本没有「继续」指令); 剧本要静音会自己在视频前关 / 淡出 (第 19 / 31 幕)
func resume_held(chs: Array) -> void:
	for ch in chs:
		var p: AudioStreamPlayer = _players.get(ch)
		if p != null and p.stream != null and not p.playing and p.has_meta("resume_pos"):
			p.play(float(p.get_meta("resume_pos")))
			p.remove_meta("resume_pos")


## 场景离开 / 退出时停掉并摘掉流, 否则退出时 MP3 播放对象被音频线程占着, 报 ObjectDB 泄漏
func release() -> void:
	for p in _players.values():
		if is_instance_valid(p):
			p.stop()
			p.stream = null
