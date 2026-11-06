--!strict
-- All player-facing Vietnamese text, flat, so another language can be added as a
-- sibling table later. Labels carry no numbers; the UI appends them
-- (for example `Strings.level .. " " .. level` gives "Cấp 5").
local Strings: { [string]: string } = {
	-- HUD
	hp = "Máu",
	energy = "Năng lượng",
	level = "Cấp",
	xp = "Kinh nghiệm",
	points = "Điểm",
	pointsLeft = "Điểm còn lại",
	locked = "Đã khoá",
	unlockAt = "Mở ở cấp",
	levelUp = "Lên cấp!",
	blocked = "Chặn",

	-- screens
	passives = "Thiên Phú",
	gems = "Ngọc Hỗ Trợ",
	reset = "Đặt lại",
	close = "Đóng",
	inventory = "Túi ngọc",
	emptySocket = "Ô trống",
	unsocketHint = "Chuột phải hoặc giữ để tháo ngọc",
	selectGemHint = "Chọn một viên ngọc, rồi chọn ô khảm",
	allocateHint = "Bấm để học thiên phú",
	treeHint = "Kéo để di chuyển, cuộn hoặc chụm hai ngón để thu phóng",
	tapAgain = "Chạm lần nữa để học",
	learned = "Đã học",
	noGems = "Chưa có ngọc. Hạ quái để nhận thêm",

	-- boss
	summonBoss = "Triệu hồi Boss",
	bossName = "Hộ Vệ Nhật Thực",
	bossNeedLevel = "Cần đạt cấp 8 để triệu hồi",
	bossCooldown = "Tế đàn đang hồi lại",
	bossTooFar = "Hãy đến gần tế đàn để triệu hồi",
	bossDefeated = "Đã hạ gục Hộ Vệ Nhật Thực!",
	enemy_hollow_knight = "Hiệp Sĩ Rỗng",

	-- gem socket reasons (GemRules.canSocket)
	reason_no_sockets = "Kỹ năng này không có ô khảm",
	reason_bad_slot = "Ô khảm không hợp lệ",
	reason_tag = "Ngọc không hợp với kỹ năng này",
	reason_element = "Mỗi kỹ năng chỉ mang một nguyên tố",
	reason_duplicate = "Kỹ năng đã có viên ngọc này",

	-- passive reasons (PassiveTree.canAllocate)
	reason_unknown = "Thiên phú không tồn tại",
	reason_allocated = "Đã học thiên phú này",
	reason_no_points = "Không còn điểm thiên phú",
	reason_not_linked = "Phải nối với một thiên phú đã học",

	-- skills (match Config/Skills displayName)
	skill_basic = "Chém",
	skill_blade_rain = "Mưa Kiếm Tinh Tú",
	skill_dawnbreaker = "Cột Sáng Bình Minh",
	skill_crimson_lance = "Giáo Huyết",
	skill_hex_aegis = "Khiên Lục Giác",
	skill_ascension = "Thăng Hoa",

	-- gems (match Config/Gems displayName)
	gem_multishot = "Đa Phát",
	gem_frost = "Băng",
	gem_flame = "Hoả",
	gem_storm = "Lôi",
	gem_wide_burst = "Nổ Lan",
	gem_swift_cast = "Tốc Thi",

	gemDesc_multishot = "Mưa Kiếm thêm 4 kiếm, Giáo Huyết thêm 2 giáo toả 20°. Sát thương ×0,85",
	gemDesc_frost = "Đòn đánh mang băng, làm chậm 30% trong 2 giây",
	gemDesc_flame = "Đòn đánh mang lửa, thiêu 20% sát thương trong 3 giây",
	gemDesc_storm = "Đòn đánh mang sét, lan sang 2 kẻ địch gần với 50% sát thương",
	gemDesc_wide_burst = "Bán kính ×1,4, mỗi điểm trúng nổ thêm bán kính 6 gây 30% sát thương",
	gemDesc_swift_cast = "Thời gian hồi ×0,75",

	-- passive tree
	region_might = "Uy Lực",
	region_swift = "Tốc Biến",
	region_insight = "Thấu Suốt",
	kind_start = "Khởi đầu",
	kind_small = "Thiên phú",
	kind_notable = "Thiên phú lớn",
	kind_keystone = "Thiên phú tối thượng",

	stat_damage = "Sát thương",
	stat_maxHp = "Máu tối đa",
	stat_maxEnergy = "Năng lượng tối đa",
	stat_energyRegen = "Hồi năng lượng mỗi giây",
	stat_cooldown = "Thời gian hồi",
	stat_moveSpeed = "Tốc độ chạy",
	stat_critChance = "Tỉ lệ chí mạng",
	stat_critMul = "Hệ số chí mạng",
	stat_aoe = "Diện tích tác dụng",
	stat_shield = "Sức chứa khiên",

	keystoneDesc_blood_oath = "Kỹ năng tiêu hao Máu thay cho Năng lượng. Sát thương +40%",
	keystoneDesc_endless_arsenal = "Mưa Kiếm thêm 6 kiếm, mỗi kiếm ×0,75 sát thương",
	keystoneDesc_radiant_mind = "Thăng Hoa kéo dài đến khi cạn Năng lượng, rút 6 Năng lượng mỗi giây",
}

return table.freeze(Strings)
