extends RefCounted
## Display-time localization. Game logic, save data and campaign content keep
## their English source strings (several double as logic keys); only text that is
## drawn goes through t() / f() / notice(). First launch follows the device
## language, with English fallback; a saved explicit choice takes precedence.

const SETTINGS_PATH := "user://settings.cfg"
## Hangul subsets of Noto Sans KR (KS X 1001 syllables). DejaVu stays primary for
## Latin text; these are attached at runtime rather than as import-time fallbacks,
## because importing a font whose fallback is imported in the same pass is racy.
const KOREAN_UI: Font = preload("res://assets/ko_ui.ttf")
const KOREAN_TITLE: Font = preload("res://assets/ko_title.ttf")
const LOCALES := ["ko", "en"]

static var locale := "en"
## Test hook: when valid, main.gd reports every drawn string as (text, pos, size, bold).
static var recorder: Callable

const KO := {
	"BACK": "뒤로",
	"%d CORES": "코어 %d",
	"BUY / %d CORES": "구매 / 코어 %d",
	"CHANGE SHIP": "함선 변경",
	"CLEAR SIGNAL GRAVEYARD": "신호의 묘지 완료 시 해금",
	"CLEAR ION FOUNDRY": "이온 주조소 완료 시 해금",
	"CONTINUE": "이어하기",
	"Collect energy from farther away.": "더 먼 곳의 에너지를 수집합니다.",
	"DASH": "대시",
	"FAN": "확산포",
	"FULL EFFECTS": "효과 전체",
	"HANGAR": "격납고",
	"JOURNAL": "기록실",
	"LANCE": "관통포",
	"LAUNCH": "출격",
	"LEVEL": "레벨",
	"LICENSES": "라이선스",
	"PRIVACY POLICY": "개인정보 안내",
	"SUPPORT": "지원",
	"Could not open the browser.": "브라우저를 열지 못했습니다.",
	"Move with the left stick. Fire is automatic.": "왼쪽 스틱으로 이동합니다. 공격은 자동입니다.",
	"NEW CAMPAIGN": "새 캠페인",
	"NEXT": "다음",
	"PAUSE": "일시정지",
	"PREVIOUS": "이전",
	"Play in landscape orientation.": "기기를 가로로 돌려 플레이하세요.",
	"Practice start: earlier sectors are skipped.": "연습 출격: 앞 구역은 건너뜁니다.",
	"Progress is saved on this device.": "진행도는 이 기기에 저장됩니다.",
	"REDUCED EFFECTS": "효과 줄임",
	"Rotate your device": "기기를 돌려주세요",
	"SECTOR MAP": "구역 지도",
	"SELECT": "선택",
	"SETTINGS": "설정",
	"SOUND OFF": "소리 끔",
	"SOUND ON": "소리 켬",
	"START NEW": "새로 시작",
	"Settings could not be saved.": "설정을 저장하지 못했습니다.",
	"TRANSMISSION COMPLETE": "임무 완료",
	"TRY AGAIN": "다시 도전",
	"WEAPON": "무기",
	"Fly through the glowing beacons. Move out of marked mine fields before they detonate.": "빛나는 신호기를 통과하세요. 지뢰가 터지기 전에 표시된 구역을 벗어나세요.",
	"Stay inside the relay field to charge it. Progress is kept when you leave to evade danger.": "중계 구역 안에 머물러 충전하세요. 위험을 피해 나가도 충전량은 유지됩니다.",
	"Collect salvage cores from the wreck field. Gravity wells pull you off course; dash to escape.": "잔해에서 코어를 모으세요. 중력장에 끌려가면 대시로 탈출하세요.",
	# ----- Title, hangar, shared footer -----
	"O R B I T A L   /   A R C A D E   0 1": "궤 도   /   아 케 이 드   0 1",
	"One pilot. An endless signal.": "한 명의 파일럿. 끝나지 않는 신호.",
	"Three sectors. Build a fleet. Break the Crown.": "세 개의 구역. 함대를 키우고 왕관을 부수세요.",
	"CONTINUE EXPEDITION": "원정 이어하기",
	"CAMPAIGN / ENTER": "캠페인 / ENTER",
	"HANGAR / %d CORES   [H]": "격납고 / 코어 %d   [H]",
	"SECTOR MAP / JOURNAL   [C]": "구역 지도 / 일지   [C]",
	"PERSONAL BEST  /  %06d": "개인 최고 기록  /  %06d",
	"MK IV / ASCENDANT": "MK IV / 어센던트",
	"SECTORS": "구역",
	"SHIPS": "함선",
	"Auto-save every 5s + on pause. Same browser/device only.": "5초마다, 그리고 일시정지할 때 자동 저장됩니다. 같은 브라우저·기기에서만 이어집니다.",
	"PERMANENT HANGAR": "영구 격납고",
	"%d CORES  /  %d LIFETIME ELIMINATIONS": "코어 %d  /  누적 처치 %d",
	"Every 5 kills = 1 core. Upgrades survive defeat and apply to NEW expeditions.": "5회 처치마다 코어 1개. 강화는 패배해도 남고, 새 원정부터 적용됩니다.",
	"REINFORCED HULL": "강화 선체",
	"REACTOR": "반응로",
	"SALVAGE ARRAY": "회수 장치",
	"+1 starting and maximum hull": "시작 및 최대 선체 +1",
	"+0.2 damage per projectile": "투사체 피해 +0.2",
	"+20 energy pickup range": "에너지 획득 범위 +20",
	"RANK %d / 5": "등급 %d / 5",
	"MAXED": "최대 등급",
	"[%d] BUY / %d CORES": "[%d] 구매 / 코어 %d",
	"LOADOUT: %s   [W]": "무장: %s   [W]",
	"PULSE": "펄스",
	"FAN (+2 BOLTS)": "확산 (탄환 +2)",
	"LANCE (2x DAMAGE)": "랜스 (피해 2배)",
	"Fan unlocks at 100 kills / Lance at 300. Click loadout to cycle.": "확산은 누적 100회, 랜스는 300회 처치로 해금. 무장을 클릭하면 바뀝니다.",
	"BACK TO TITLE   /   ESC": "타이틀로   /   ESC",
	"Browser data can be cleared: this is a local save, not a cloud account.": "브라우저 데이터를 지우면 사라질 수 있습니다. 클라우드가 아닌 기기 내 저장입니다.",
	"WASD / ↑ ↓ ← →   MOVE": "WASD / ↑ ↓ ← →   이동",
	"SPACE   DASH + PHASE": "SPACE   대시 + 위상 통과",
	"AUTO-FIRE   ALWAYS ON": "자동 사격   항상 켜짐",
	"ESC PAUSE  M %s  V %s  L %s": "ESC 일시정지  M %s  V %s  L %s",
	"MUTED": "음소거",
	"SOUND": "소리",
	"CALM": "차분",
	"FX": "효과",
	# ----- In-run HUD and toasts -----
	"CAMPAIGN / SECTOR %02d": "캠페인 / 구역 %02d",
	"SECTOR %02d / %s": "구역 %02d / %s",
	"ENDLESS": "무한",
	"HULL": "선체",
	"DEFEAT THE WARDEN": "감시자를 처치하세요",
	"EXPEDITION / 10:00": "원정 / 10:00",
	"SCORE": "점수",
	"DASH READY": "대시 준비",
	"DASH  %.1fs": "대시  %.1f초",
	"LV %02d": "레벨 %02d",
	"+%d CORES / %d BOLTS / DMG %.1f": "코어 +%d / 탄환 %d / 피해 %.1f",
	"NOVA %.1fs": "노바 %.1f초",
	"SIGNAL WARDEN": "신호 감시자",
	"STAY MOVING.  COLLECT ENERGY.": "계속 움직이세요.  에너지를 모으세요.",
	"EXPEDITION RESTORED  /  YOUR BUILD IS INTACT": "원정 복구  /  빌드가 그대로 유지됩니다",
	"WAVE %02d  /  SIGNAL INTENSIFYING": "웨이브 %02d  /  신호가 강해집니다",
	"BOSS DEFEATED / COMPLETE YOUR OBJECTIVE": "보스 격파 / 남은 임무를 완료하세요",
	"WARDEN DEFEATED  /  +50 PERMANENT CORES": "감시자 격파  /  영구 코어 +50",
	"PERMANENT WEAPON UNLOCKED  /  VISIT THE HANGAR": "영구 무기 해금  /  격납고를 확인하세요",
	"LEVEL %02d  /  FIREPOWER UP + 1 HULL": "레벨 %02d  /  화력 증가 + 선체 1 회복",
	"%s / BREAK THE SIGNAL": "%s / 신호를 끊어내세요",
	"THE SIGNAL WARDEN  /  DEFEAT IT TO EXTRACT": "신호 감시자  /  처치하고 탈출하세요",
	"OVERDRIVE  /  FASTER AUTO-FIRE": "오버드라이브  /  자동 사격 가속",
	"PHASE ENGINE  /  FASTER MOVE + DASH": "페이즈 엔진  /  이동 + 대시 가속",
	"RECOVERY  /  REPAIR + WIDER ENERGY MAGNET": "회복  /  수리 + 에너지 자석 범위 확대",
	"%s / COMPLETE THE MISSION": "%s / 임무를 완수하세요",
	"WEAPON EVOLVED / %s": "무기 진화 / %s",
	"JUMP COMPLETE / %s": "도약 완료 / %s",
	"CHARGE RELAY": "릴레이 충전",
	"SALVAGE": "잔해 회수",
	"LINK BEACON": "비콘 연결",
	# ----- Pause, result and confirmation overlays -----
	"/ /  SIGNAL HELD  / /": "/ /  신호 유지 중  / /",
	"/ /  TRANSMISSION COMPLETE  / /": "/ /  송신 완료  / /",
	"/ /  SIGNAL INTERRUPTED  / /": "/ /  신호 끊김  / /",
	"DRIFT LOST": "격추되었습니다",
	"PAUSED": "일시정지",
	"CROWN SILENCED": "왕관 침묵",
	"SECTOR CLEARED": "구역 클리어",
	"YOU SURVIVED": "생존 성공",
	"Take a breath. The arena can wait.": "잠시 숨을 고르세요. 전장은 기다려 줍니다.",
	"The convoy is free. Your fleet keeps growing.": "호송대가 풀려났습니다. 함대는 계속 성장합니다.",
	"Warden defeated. Your pilot keeps growing.": "감시자를 처치했습니다. 파일럿은 계속 성장합니다.",
	"Stay moving. Dash through the danger.": "멈추지 마세요. 대시로 위험을 돌파하세요.",
	"Saved. ESC / ENTER to resume": "저장됨. ESC / ENTER로 재개",
	"ESC / ENTER to resume": "ESC / ENTER로 재개",
	"%02ds survived   •   %d eliminated   •   level %d": "%02d초 생존   •   %d회 처치   •   레벨 %d",
	"RESUME RUN": "계속하기",
	"TRY AGAIN   /   ENTER": "다시 도전   /   ENTER",
	"SAVE & TITLE": "저장 후 타이틀로",
	"TITLE / HANGAR": "타이틀 / 격납고",
	"KEEP THIS BUILD / ENDLESS [E]": "이 빌드로 무한 모드 [E]",
	"+%d cores saved. Permanent upgrades are waiting in the hangar.": "코어 +%d 저장됨. 격납고에서 영구 강화를 구매할 수 있습니다.",
	"REPLACE SAVED RUN?": "저장된 원정을 교체할까요?",
	"The current expedition build will be replaced.": "진행 중인 원정의 빌드가 교체됩니다.",
	"Your cores, unlocks and hangar upgrades stay.": "코어, 해금, 격납고 강화는 그대로 유지됩니다.",
	"START NEW / ENTER": "새로 시작 / ENTER",
	"CANCEL / ESC": "취소 / ESC",
	# ----- Level-up choice -----
	"LEVEL %02d  /  SIGNAL UPGRADE": "레벨 %02d  /  신호 강화",
	"CHOOSE YOUR EDGE": "강화를 선택하세요",
	"Time is paused. Pick one module. Every level also repairs 1 hull.": "시간이 멈췄습니다. 모듈 하나를 고르세요. 레벨이 오를 때마다 선체도 1 회복됩니다.",
	"OVERDRIVE": "오버드라이브",
	"PHASE ENGINE": "페이즈 엔진",
	"RECOVERY": "회복",
	"Faster fire + stronger bolts.": "더 빠른 사격 + 더 강한 탄환.",
	"Every 3 ranks: +1 projectile.": "3등급마다 투사체 +1.",
	"Move faster. Dash sooner.": "더 빠르게 이동하고 더 자주 대시.",
	"Escape. Then strike back.": "빠져나간 뒤 반격하세요.",
	"Repair 2 hull immediately.": "즉시 선체 2 수리.",
	"Wider magnet + stronger nova.": "자석 범위 확대 + 노바 강화.",
	"SELECT  /  %d": "선택  /  %d",
	"Click or press 1, 2, 3  /  Level 8 unlocks an automatic nova pulse": "클릭하거나 1, 2, 3을 누르세요  /  레벨 8에 자동 노바 펄스 해금",
	# ----- Sector map -----
	"E X P E D I T I O N   /   N A V I G A T I O N": "원 정   /   항 법",
	"CHART YOUR SIGNAL": "신호의 항로를 그리세요",
	"Three sectors. One evolving ship. Push through to the source.": "세 개의 구역, 진화하는 함선 하나. 신호의 근원까지 돌파하세요.",
	"%d CORES  /  %d CAMPAIGN CLEARS": "코어 %d  /  캠페인 클리어 %d회",
	"SELECTED": "선택됨",
	"AVAILABLE": "진입 가능",
	"LOCKED": "잠김",
	"SECTOR %d": "구역 %d",
	"SECTOR": "구역",
	"OBJECTIVE": "임무",
	"Clear sector %02d to unlock": "구역 %02d 클리어 시 해금",
	"GUARDIAN / %s": "수호자 / %s",
	"UNKNOWN": "알 수 없음",
	"SHIP": "함선",
	"LAUNCH SECTOR %02d / ENTER": "구역 %02d 출격 / ENTER",
	"SECTOR LOCKED": "잠긴 구역",
	"FLEET UNLOCKS / Sector 01: KESTREL  |  Sector 02: BASTION": "함선 해금 / 구역 01: 케스트럴  |  구역 02: 바스티온",
	"PILOT JOURNAL / J": "파일럿 일지 / J",
	"BACK TO TITLE / ESC": "타이틀로 / ESC",
	"PRACTICE START: earlier sectors, their build and relic rewards are skipped.": "연습 출격: 앞 구역과 그 구역에서 얻을 빌드·유물 보상을 건너뜁니다.",
	"For a full campaign clear, launch sector 01 and claim all three sectors in one run.": "정식 캠페인 클리어는 구역 01부터 출격해 한 번의 원정으로 세 구역을 모두 되찾아야 합니다.",
	"Your build travels with you. Choose a relic after each of the first two guardians.": "빌드는 다음 구역으로 이어집니다. 처음 두 수호자를 처치할 때마다 유물을 고르세요.",
	"Claim all three sectors in one expedition to complete the campaign.": "한 번의 원정으로 세 구역을 모두 되찾으면 캠페인을 완료합니다.",
	"1 / 2 / 3  SELECT SECTOR": "1 / 2 / 3  구역 선택",
	"S  CYCLE SHIP": "S  함선 변경",
	"ENTER  LAUNCH": "ENTER  출격",
	"J  JOURNAL    ESC  BACK": "J  일지    ESC  뒤로",
	# ----- Relic intermission -----
	"S E C T O R   S I G N A L   S E C U R E D": "구 역   신 호   확 보",
	"%s CLEARED": "%s 클리어",
	"CHOOSE A RELIC": "유물을 선택하세요",
	"Your build carries forward. Choosing a relic launches the next sector.": "빌드는 그대로 이어집니다. 유물을 고르면 다음 구역으로 출격합니다.",
	"HELIX REACTOR": "헬릭스 반응로",
	"PHASE CAPACITOR": "페이즈 축전기",
	"REPAIR MATRIX": "수리 매트릭스",
	"+0.5 projectile damage": "투사체 피해 +0.5",
	"+1 phase rank": "페이즈 등급 +1",
	"+1 maximum hull": "최대 선체 +1",
	"A permanent boost for this expedition.": "이번 원정이 끝날 때까지 유지되는 강화.",
	"More speed. Faster dash recovery.": "속도 증가. 대시 재충전 가속.",
	"Fully repairs your hull immediately.": "즉시 선체를 완전히 수리합니다.",
	"0%d / RELIC": "0%d / 유물",
	"SELECT / %d": "선택 / %d",
	"Click a relic or press 1, 2, 3. The arena stays paused until you choose.": "유물을 클릭하거나 1, 2, 3을 누르세요. 고를 때까지 전장은 멈춰 있습니다.",
	"SAVE & TITLE / ESC": "저장 후 타이틀로 / ESC",
	"Resume this expedition later to choose your relic and continue.": "나중에 이 원정을 이어서 유물을 고르고 계속할 수 있습니다.",
	# ----- Journal and campaign HUD -----
	"P I L O T   A R C H I V E   /   P R O G R E S S I O N": "파 일 럿   기 록   /   진 행",
	"THE SIGNAL JOURNAL": "신호 일지",
	"%d / %d ACHIEVEMENTS  /  %d CAMPAIGN CLEARS": "업적 %d / %d  /  캠페인 클리어 %d회",
	"PILOT MILESTONES": "파일럿 업적",
	"WEAPON EVOLUTION RECIPES": "무기 진화 조합",
	"MILESTONE": "업적",
	"EARNED": "달성",
	"BACK TO MAP / ESC": "지도로 / ESC",
	"ACHIEVEMENTS PERSIST": "업적은 영구 보존",
	"RECIPES APPLY PER RUN": "조합은 원정마다 적용",
	"BUILD RANKS TO EVOLVE": "등급을 올려 진화",
	"ESC  BACK TO MAP": "ESC  지도로",
	"PULSE > NOVA ARRAY": "펄스 > 노바 어레이",
	"FAN > STARWEAVE": "확산 > 스타위브",
	"LANCE > VOID LANCE": "랜스 > 보이드 랜스",
	"Overdrive rank 3 + Recovery rank 2": "오버드라이브 3등급 + 회복 2등급",
	"Overdrive rank 3 + Phase Engine rank 2": "오버드라이브 3등급 + 페이즈 엔진 2등급",
	"A wide nova pulses every 2.5 seconds.": "2.5초마다 넓은 노바가 퍼집니다.",
	"Eight radial stars join every volley.": "사격할 때마다 8방향 별탄이 추가됩니다.",
	"Heavy plasma pierces successive enemies.": "강력한 플라즈마가 일직선의 적을 연달아 관통합니다.",
	"Evolves automatically with the matching weapon equipped.": "맞는 무기를 장착하고 조건을 채우면 자동으로 진화합니다.",
	"EVOLVED / %s": "진화 완료 / %s",
	"EVO / OVERDRIVE %d/3 + PHASE %d/2": "진화 / 오버드라이브 %d/3 + 페이즈 %d/2",
	"EVO / OVERDRIVE %d/3 + RECOVERY %d/2": "진화 / 오버드라이브 %d/3 + 회복 %d/2",
	"NOVA ARRAY": "노바 어레이",
	"STARWEAVE": "스타위브",
	"VOID LANCE": "보이드 랜스",
	# ----- Campaign content (campaign.gd display fields) -----
	"SIGNAL GRAVEYARD": "신호의 묘지",
	"ION FOUNDRY": "이온 주조소",
	"THE HOLLOW CROWN": "텅 빈 왕관",
	"01 / THE LAST TRANSMISSION": "01 / 마지막 송신",
	"02 / THE MACHINES REMEMBER": "02 / 기계는 기억한다",
	"03 / BRING THEM HOME": "03 / 그들을 집으로",
	"A broken distress signal leads into the wreck field. Recover five beacon fragments and silence the Warden to open the route to the Foundry.": "끊어진 구조 신호가 잔해 지대로 이어집니다. 비콘 조각 다섯 개를 회수하고 감시자를 침묵시켜 주조소로 가는 항로를 여세요.",
	"The convoy's route is locked behind a dead relay. Hold inside its signal field to restore power while ion storms tear through the factory.": "호송대의 항로가 멈춘 릴레이에 막혀 있습니다. 이온 폭풍이 공장을 휩쓰는 동안 신호장 안에 머물러 전력을 되살리세요.",
	"The missing convoy is trapped in the Crown's gravity wake. Recover twelve salvage cores to power extraction, then destroy the intelligence holding the fleet.": "실종된 호송대가 왕관의 중력 항적에 갇혀 있습니다. 회수 코어 열두 개로 탈출 동력을 확보한 뒤, 함대를 붙잡은 지성체를 파괴하세요.",
	"RECOVER BEACONS": "비콘 회수",
	"CHARGE THE RELAY": "릴레이 충전",
	"RECOVER SALVAGE": "잔해 회수",
	"THE WARDEN": "감시자",
	"THE CRUCIBLE": "도가니",
	"THE CROWN": "왕관",
	"VECTOR": "벡터",
	"KESTREL": "케스트럴",
	"BASTION": "바스티온",
	"BALANCED EXPLORER": "균형형 탐사선",
	"FAST INTERCEPTOR": "고속 요격기",
	"ARMORED SALVAGER": "중장갑 회수선",
	"A dependable rescue craft. Balanced hull, handling, and firepower.": "믿음직한 구조선. 선체, 조종 성능, 화력이 고루 균형 잡혀 있습니다.",
	"One less hull point, faster engines, and a shorter dash cooldown. Built for pilots who never stop moving.": "선체 -1, 더 빠른 엔진, 더 짧은 대시 대기시간. 멈추지 않는 파일럿을 위한 기체입니다.",
	"Two extra hull points and heavier shots, traded for slower engines and a longer dash cooldown.": "선체 +2와 더 강한 사격. 대신 엔진이 느리고 대시 대기시간이 깁니다.",
	"FIRST SIGNAL": "첫 번째 신호",
	"FOUNDRY BREAKER": "주조소 파괴자",
	"CROWNLESS": "왕관을 꺾은 자",
	"STAR ARCHITECT": "별의 설계자",
	"PHASE MASTER": "페이즈 마스터",
	"DRIFT VETERAN": "드리프트 베테랑",
	"Complete Signal Graveyard.": "신호의 묘지를 클리어하세요.",
	"Complete Ion Foundry.": "이온 주조소를 클리어하세요.",
	"Clear all three sectors in one expedition.": "한 번의 원정으로 세 구역을 모두 클리어하세요.",
	"Evolve any weapon during a run.": "원정 중에 무기를 진화시키세요.",
	"Reach Phase Engine rank 5 during a run.": "원정 중에 페이즈 엔진 5등급에 도달하세요.",
	"Defeat 1,000 enemies across all runs.": "모든 원정을 합쳐 적 1,000기를 처치하세요.",
	# ----- Save notices (main.gd and progression.gd last_error) -----
	"SAVE FAILED: progress is only in this session": "저장 실패: 진행 상황이 이번 세션에만 남습니다",
	"Saved run cannot be read. Start a new expedition.": "저장된 원정을 읽을 수 없습니다. 새 원정을 시작하세요.",
	"The pilot save could not be read. Starting with a new pilot.": "파일럿 저장을 읽을 수 없어 새 파일럿으로 시작합니다.",
	"The suspended run was invalid. Your pilot upgrades were kept.": "중단된 원정이 손상되었습니다. 파일럿 강화는 유지됩니다.",
	"Recovered your pilot from the backup save.": "백업 저장에서 파일럿을 복구했습니다.",
	"The suspended run could not be saved because it is invalid.": "원정 상태가 올바르지 않아 저장하지 못했습니다.",
	"Could not write the pilot save (%s).": "파일럿 저장을 기록하지 못했습니다 (%s).",
	"Could not verify the pilot save. Your previous save was kept.": "파일럿 저장을 검증하지 못해 이전 저장을 유지했습니다.",
	"Could not back up the pilot save (%s).": "파일럿 저장을 백업하지 못했습니다 (%s).",
	"Could not finish the pilot save (%s).": "파일럿 저장을 마무리하지 못했습니다 (%s).",
	"Unknown pilot upgrade.": "알 수 없는 파일럿 강화입니다.",
	"This upgrade is already at maximum rank.": "이미 최대 등급인 강화입니다.",
	"Not enough credits for this upgrade.": "코어가 부족합니다.",
	"This pilot save uses an unsupported version. It has not been changed.": "지원하지 않는 버전의 파일럿 저장입니다. 변경하지 않았습니다.",
}

## Name of the language L switches to, written in that language.
const SWITCH_LABEL := {"ko": "ENGLISH", "en": "한국어"}


static func install_fonts(ui: Font, title: Font) -> void:
	for pair in [[ui, KOREAN_UI], [title, KOREAN_TITLE]]:
		var font: Font = pair[0]
		if not font.fallbacks.has(pair[1]):
			var fallbacks := font.fallbacks.duplicate()
			fallbacks.append(pair[1])
			font.fallbacks = fallbacks


static func t(text: String) -> String:
	if locale != "ko":
		return text
	return KO.get(text, text)


static func f(template: String, args: Variant) -> String:
	return t(template) % args


## Save notices may end in an engine error detail: "... (File not found)."
static func notice(text: String) -> String:
	if locale != "ko" or text.is_empty() or KO.has(text):
		return t(text)
	var open := text.rfind(" (")
	if open > 0 and text.ends_with(")."):
		var template := text.substr(0, open) + " (%s)."
		if KO.has(template):
			return KO[template] % text.substr(open + 2, text.length() - open - 4)
	return text


static func switch_label() -> String:
	return SWITCH_LABEL.get(locale, "ENGLISH")


static func locale_for_device(language: String) -> String:
	var code := language.strip_edges().to_lower().replace("-", "_").get_slice("_", 0)
	return code if code in LOCALES else "en"


static func load_settings(device_language: String = "") -> void:
	locale = locale_for_device(OS.get_locale_language() if device_language.is_empty() else device_language)
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var value: Variant = config.get_value("display", "locale", locale)
	if value is String and value in LOCALES:
		locale = value


## Switches language for this session and remembers it. Returns false if the
## preference could not be written; the switch still applies until reload.
static func toggle() -> bool:
	locale = "en" if locale == "ko" else "ko"
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("display", "locale", locale)
	return config.save(SETTINGS_PATH) == OK
