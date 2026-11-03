# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 近景战斗里被打一方的受击摆动与命中震屏 (原版 Win10 原生逐帧实测)。动画用合成数据, 不依赖原版资源。


func _fake_ok() -> bool:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Assets") != null


## 合成被打方 misc: 14 帧 (同 236misc 的布局: 帧 0 格挡, 1~5 受击, 6 空, 7~13 待机), 每帧 time=2 (3 tick = 0.12 秒), 动作表 [站立 0, 待机 7]
func _fake_misc(key: String) -> void:
	var A = (Engine.get_main_loop() as SceneTree).root.get_node("Assets")
	var frames := []
	for i in 14:
		frames.append({"sound": -1, "time": 2, "hit": 0, "color": 0, "shake": 0, "unk4": 0, "parts": []})
	A._anims[key.to_lower()] = {"frames": frames, "action_counts": [0, 7, 0, 0, 0], "textures": [], "sounds": [], "dir": key}
	A._index[(key + "/anim.json").to_lower()] = true


func _unfake(key: String) -> void:
	var A = (Engine.get_main_loop() as SceneTree).root.get_node("Assets")
	A._anims.erase(key.to_lower())
	A._index.erase((key + "/anim.json").to_lower())


func _range(m) -> Array:
	return [m.start_frame, m.end_frame, m.loop]


func test_hit_sway_is_1_2_1_2_then_idle():
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	var key := "Sprite/test_hit/misc"
	_fake_misc(key)
	var cu := BattleCloseup.new(null)
	var m := AnimPlayer.new()
	cu._hit_sway(m, key)
	eq(_range(m), [1, 3, false], "命中: 帧 1~2 播一遍 (不循环, 不播帧 3 的翻滚姿势)")
	m._process(0.24)   # 2 帧 x 0.12 秒
	eq(_range(m), [1, 3, false], "再摆一遍: 帧 1~2")
	m._process(0.24)
	eq(_range(m), [7, 14, true], "然后回待机循环 (帧 7~13)")
	m.free()
	cu.free()
	_unfake(key)


func test_new_hit_restarts_and_stale_sway_does_not_play_twice():
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	var key := "Sprite/test_hit2/misc"
	_fake_misc(key)
	var cu := BattleCloseup.new(null)
	var m := AnimPlayer.new()
	cu._hit_sway(m, key)
	m._process(0.2)                 # 摆到一半又被命中
	cu._hit_sway(m, key)
	eq(_range(m), [1, 3, false], "第二次命中重新从帧 1 开始")
	m._process(0.24)
	eq(_range(m), [1, 3, false], "旧的摆动作废, 只有新的往下走 (第二遍)")
	m._process(0.24)
	eq(_range(m), [7, 14, true], "之后回待机")
	m.free()
	cu.free()
	_unfake(key)


func test_finishing_the_attack_cancels_a_sway_in_progress():
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	var key := "Sprite/test_hit3/misc"
	_fake_misc(key)
	var cu := BattleCloseup.new(null)
	var m := AnimPlayer.new()
	cu._hit_sway(m, key)
	m._process(0.1)
	cu._hit_id += 1                 # 攻击放完 (_play_attack 里做的)
	m.play(key, 7, 14)              # 之后调用方自己播待机
	m._process(0.5)
	eq(_range(m), [7, 14, true], "被作废的摆动不再改动画")
	m.free()
	cu.free()
	_unfake(key)


## 被打方没有 misc 动画 (个别单位缺文件): 摆动流程不报错、不动待机
func test_hit_sway_without_misc_data_is_harmless():
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	var cu := BattleCloseup.new(null)
	var m := AnimPlayer.new()
	cu._hit_sway(m, "Sprite/not_there/misc")   # Assets.exists 为假: AnimPlayer 走「缺动画」分支
	check(m.data.is_empty(), "没有动画数据")
	cu._hit_id += 1
	m.free()
	cu.free()
	check(true, "没有抛错")


## 震屏偏移 (原版像素): (7, 3) = 左上 3 像素, 每级缩小 1; 幅度 = shake/2, unk4 为轴位掩码
func test_shake_offsets():
	# 读原版内存表 (静态观察 3.2): 方向 (shake-1)/3 取整, 幅度序列 (shake-1)%3
	var seq := [[3, 2, 1], [6, 4, 2, 1], [12, 6, 4, 1]]
	var dirs := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, 1)]
	for shake in range(1, 13):
		var want := []
		for n in seq[(shake - 1) % 3]:
			want.append(dirs[(shake - 1) / 3] * float(n))
		eq(BattleCloseup.shake_offsets(shake), want, "shake=%d" % shake)
	eq(BattleCloseup.shake_offsets(7), [Vector2(-3, -3), Vector2(-2, -2), Vector2(-1, -1)], "原版实测 shake=7: 3,2,1 左上")
	eq(BattleCloseup.shake_offsets(0), [], "shake=0 不震")
	eq(BattleCloseup.shake_offsets(13), [], "shake>12 不震")


## 帧头 color -> 色闪 (级, 色号): 十位定级 (1~10 背景 / 11~20 不可见 / 21~30 人物之下 / >30 盖住一切), 个位 1..7 = 白红绿蓝黄品红青 (读码 + Windows 直读状态)
func test_color_code():
	eq(BattleCloseup.color_code(0), [], "0 无色闪")
	eq(BattleCloseup.color_code(14), [], "11~20 级 2: 原版没有绘制代码读, 不可见")
	eq(BattleCloseup.color_code(3), [1, 3], "级 1 绿")
	eq(BattleCloseup.color_code(21), [3, 1], "级 3 白")
	eq(BattleCloseup.color_code(25), [3, 5], "级 3 黄")
	eq(BattleCloseup.color_code(31), [4, 1], "级 4 白 (会心)")
	eq(BattleCloseup.color_code(32), [4, 2], "级 4 红 (格挡)")
	eq(BattleCloseup.color_code(10), [], "个位 10 无效")
	eq(BattleCloseup.color_code(28), [], "个位 8 无效")


func test_push_steps_return_to_origin():
	for ab in [false, true]:
		var sum := Vector2.ZERO
		for st in BattleCloseup.PUSH_STEPS[ab]:
			sum += st
		eq(sum, Vector2.ZERO, "位移三步累计回原位 ab=%s" % ab)


## hit=2 / hit=3 被打方位移 (Windows 直读实测 U3): hit=2 瞬移 (6,4) 左负右正且累加, hit=3 ±(3,2) 交替, hit=4 不动
func test_hit2_hit3_displacement():
	var cu := BattleCloseup.new(null)
	var m := Node2D.new()
	cu._hit_disp(m, 2, true, false)
	eq(m.position, Vector2(-6, -4), "hit=2 左侧 (-6,-4)")
	cu._hit_disp(m, 2, true, false)
	eq(m.position, Vector2(-12, -8), "连续 hit=2 累加")
	var m2 := Node2D.new()
	cu._hit_disp(m2, 2, false, false)
	eq(m2.position, Vector2(6, 4), "hit=2 右侧取反")
	var m3 := Node2D.new()
	cu._hit_disp(m3, 3, true, false)
	eq(m3.position, Vector2(-3, -2), "hit=3 左先负")
	cu._hit_disp(m3, 3, true, false)
	eq(m3.position, Vector2(3, 2), "hit=3 交替")
	var m4 := Node2D.new()
	cu._hit_disp(m4, 4, true, false)
	eq(m4.position, Vector2.ZERO, "hit=4 无位移")
	for n in [m, m2, m3, m4]:
		n.free()
	cu.free()
