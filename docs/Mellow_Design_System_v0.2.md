# Mellow — 디자인 시스템 & 무드보드 v0.2

> **무드 한 줄.** 한낮의 햇살처럼 따뜻하고, 살짝 빛바랜, 아늑한 필름 다이어리.
> **이 문서는** Mellow의 시각 정체성(색·타이포·질감·UI 톤)을 정의하고, 구현용 디자인 토큰까지 연결한다. PRD와 짝을 이룬다.

---

## 1. 디자인 원칙

1. **따뜻한 페이드 우선.** 모든 색은 따뜻한 쪽으로 기운다. 차가운 톤은 액센트로만.
2. **들린 블랙.** 순수 검정(`#000`)을 쓰지 않는다. 그림자는 항상 살짝 떠 있다(`#3B362E`). 필름 감성의 핵심.
3. **덜어내기.** 기능보다 분위기. 화면에 요소가 많아지면 의심한다.
4. **통일된 세계관.** 모든 필터·화면이 하나의 팔레트를 공유해 '같은 다이어리'로 묶인다.
5. **아날로그 질감.** 그레인·라이트릭·페이퍼가 디지털의 매끈함을 부드럽게 덮는다.
6. **몰입.** 라이브 프리뷰로 '순간에 머무는' 경험. 후보정 단계를 만들지 않는다.

---

## 2. 컬러 시스템

### 2.1 코어 팔레트

**한낮 햇살 · Midday Sun** — 하이라이트·온기의 주축
| 이름 | HEX | 용도 |
| --- | --- | --- |
| 크림 | `#F6E7C9` | 밝은 면, 하이라이트 |
| 허니 | `#EFC98A` | 따뜻한 강조, 버튼 톤 |
| 골든 | `#E0A85C` | 주 강조색 후보 |
| 앰버 | `#C97F3E` | 액센트, 셔터/포인트 |

**카페 · Café** — 중간톤·그림자
| 이름 | HEX | 용도 |
| --- | --- | --- |
| 라떼 | `#DCC4A2` | 중간 면, 카드 보더 |
| 카라멜 | `#B0855C` | 중간톤 텍스트 |
| 토피 | `#936B45` | 보조 텍스트 |
| 모카 | `#7E5A3C` | 딥 톤 |

**빛바랜 필름 · Faded Film** — 무드·딥
| 이름 | HEX | 용도 |
| --- | --- | --- |
| 세이지 | `#A8B49B` | 빛바랜 그림자 톤 |
| 더스티로즈 | `#D49C86` | 부드러운 포인트 |
| 클레이 | `#B5765E` | 따뜻한 무드 |
| 들린블랙 | `#3B362E` | **그림자·딥(순수 검정 대체)** |

**베이스 · Paper** — 배경·텍스트
| 이름 | HEX | 용도 |
| --- | --- | --- |
| 아이보리 | `#FBF8F1` | 가장 밝은 배경 |
| 페이퍼 | `#F4EEE1` | 기본 배경 |
| 라이트탄 | `#EBDFCB` | 면 분리, 보더 |
| 잉크 | `#4A443A` | **본문 텍스트** |

### 2.2 분위기 빛 (차용 액센트)

| 이름 | HEX | 출처 | 사용 규칙 |
| --- | --- | --- | --- |
| 하늘 | `#B4C8CC` | PICNIC | ⚠️ **액센트 한정.** 하늘 영역·그림자 균형에만. 넓게 깔면 따뜻함이 깨진다. |
| 노을 | `#F0B894` | PICNIC | 골든아워 하이라이트, 공기감 |
| 드림워시 | `#F1E5E0` | PICNIC | 밀키 헤이즈, 전체 톤 살짝 띄우기 |
| 번짐 글로우 | `#F6CCA0` | Retrica | 라이트릭·헐레이션 빛샘색 |

### 2.3 시맨틱 역할 (어디에 무엇을)

| 역할 | 토큰 | 값 |
| --- | --- | --- |
| 배경 (기본) | `bg` | 페이퍼 `#F4EEE1` |
| 배경 (밝음) | `bgRaised` | 아이보리 `#FBF8F1` |
| 본문 텍스트 | `textPrimary` | 잉크 `#4A443A` |
| 보조 텍스트 | `textSecondary` | 카라멜 `#B0855C` |
| 그림자·딥 | `shadow` | 들린블랙 `#3B362E` |
| 주 액센트 | `accent` | 앰버 `#C97F3E` |
| 빛샘 글로우 | `glow` | 번짐 글로우 `#F6CCA0` |
| 보더·구분선 | `border` | 라이트탄 `#EBDFCB` |

---

## 3. 타이포그래피

- **포인트 (세리프):** 날짜·제목·필름명 등 '감성' 순간. 따뜻한 세리프.
  - 한글 후보: 나눔명조 / 마루 부리. 라틴 후보: Fraunces / Lora.
- **본문·UI (산세리프):** 깔끔하고 읽기 좋게.
  - 한글 후보: Pretendard. 라틴 후보: Inter.
- **스케일(가이드):** 타이틀 22 · 섹션 18 · 본문 16 · 캡션 13 · 마이크로 11.
- 항상 **문장형 대소문자(sentence case)**, ALL CAPS 지양.

---

## 4. 질감 & 효과

| 요소 | 가이드 |
| --- | --- |
| 필름 그레인 | 사진은 정적, **영상은 프레임마다 시드 흔들기**(정적이면 '먼지'처럼 보임). 강도 조절. |
| 라이트릭(빛샘) | 번짐 글로우색. 랜덤하게 들어갈수록 '진짜 필름'. |
| 들린 블랙 | 모든 그림자에 적용. 블랙 = `#3B362E`. |
| 페이퍼 질감 | 배경·카드에 은은한 종이결. 과하지 않게. |
| 하프톤 | 포인트 그래픽·스플래시에 레트로 도트. |
| 비네팅 | 가장자리 살짝 어둡게, 시선 모으기. |
| 헐레이션 | 밝은 부분의 부드러운 번짐. |
| 날짜 스탬프 | **기본 OFF + 토글.** 메타데이터 날짜는 항상 저장(다이어리). 켜면 세리프 톤. |

---

## 5. 시그니처 필름 룩 (8종, 확정 네이밍)

> 색 *방향*만 참고, 이름·LUT는 전부 Mellow 오리지널. HEX는 각 룩의 색 시그니처(그림자→하이라이트 흐름).

**히어로 — 따뜻하고 아늑 (기본값)**
- **Sunday** (선데이) `#FBF8F1 → #F6E7C9 → #EFC98A → #C97F3E` · 따뜻한 앰버 하이라이트, 나른한 오후 *(기본 선택)*
- **Honey** (허니) `#FCEFD2 → #F2D08F → #E0A85C → #936B45` · 골든 스냅샷 온기
- **Breeze** (브리즈) `#EFEDDB → #CFC79E → #A8AE8C → #8A6E4A` · 산뜻한 미드톤, 캐주얼 데일리

**차분 — 절제된 톤**
- **Hush** (허쉬) `#A8B49B → #EFE6D4 → #D49C86 → #3B362E` · 빠진 채도 + 세이지 그림자 + 들린 블랙
- **Olive** (올리브) `#B7B6A4 → #DCD6C4 → #B89A7E → #4A443A` · 절제된 올리브, 다큐멘터리
- **Linen** (리넨) `#F4EEE1 → #E6D3C0 → #CBB39C → #6E5E50` · 아주 플랫, 자연 피부톤

**레인지 — 시네마틱 (따뜻하게 튜닝)**
- **Ember** (엠버) `#2C3540 → #5E6B6E → #C97F3E → #F0C98A` · 쿨 그림자 + 따뜻한 할레이션 (밤·실내)
- **Velvet** (벨벳) `#6E6B62 → #B8B2A4 → #8A7A66 → #2E2B26` · 채도 낮고 대비 높은 차분함

*(드롭: 비비드 — 고채도·고대비가 아늑함과 상충.)*

### 네이밍 어휘 & 2단 전략
- **코어 8종 = 짧고 따뜻한 단어**(Sunday·Honey·Breeze·Hush·Olive·Linen·Ember·Velvet). 한·영 공통, 무드를 담음 — 레트리카의 간결함 + 피크닉의 감성.
- **시즌·한정 필름 = 시적 구절**(피크닉식, 예: '스쳐간 여름밤'). 특별함·현지화용.
- 어휘 결: 짧고(1~2음절), 포근하고, 두 언어에서 굴러가는 단어.

---

## 6. UI 톤 & 컴포넌트 방향

- **배경:** 따뜻한 페이퍼. 무거운 블랙 가죽 ❌.
- **필터 피커:** 부드러운 스큐어모픽 **필름통** 메타포 (다이어리 정신모델과 일치).
- **모서리:** 둥글게. 카드 12px, 컨트롤 8px.
- **아이콘:** 얇고 둥근 라인. 과한 디테일 지양.
- **모션:** 느긋하고 부드럽게(gentle). 빠르고 튀는 트랜지션 ❌.
- **햅틱:** 셔터·필름 전환 등 '필름 만지는' 촉감.
- **마이크로 인터랙션:** 필름 감김, 현상되는 듯한 로딩 등 아날로그 은유 (단, 구닥처럼 과한 대기 강요는 ❌).

---

## 7. 디자인 토큰 (구현용 · Swift)

```swift
import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8)  & 0xff) / 255,
                  blue:  Double( hex        & 0xff) / 255,
                  opacity: alpha)
    }
}

extension Color {
    // MARK: Core — 한낮 햇살
    static let mellowCream  = Color(hex: 0xF6E7C9)
    static let mellowHoney  = Color(hex: 0xEFC98A)
    static let mellowGolden = Color(hex: 0xE0A85C)
    static let mellowAmber  = Color(hex: 0xC97F3E)

    // MARK: Core — 카페 / 빛바랜 필름 / 베이스
    static let mellowLatte      = Color(hex: 0xDCC4A2)
    static let mellowSage       = Color(hex: 0xA8B49B)
    static let mellowDustyRose  = Color(hex: 0xD49C86)
    static let mellowIvory      = Color(hex: 0xFBF8F1)
    static let mellowPaper      = Color(hex: 0xF4EEE1)
    static let mellowLightTan   = Color(hex: 0xEBDFCB)

    // MARK: 분위기 빛 (액센트)
    static let mellowSky        = Color(hex: 0xB4C8CC) // 액센트 한정
    static let mellowSunset     = Color(hex: 0xF0B894)
    static let mellowDreamWash  = Color(hex: 0xF1E5E0)
    static let mellowBleedGlow  = Color(hex: 0xF6CCA0)

    // MARK: 시맨틱 역할
    static let mellowBg            = Color(hex: 0xF4EEE1) // 배경
    static let mellowBgRaised      = Color(hex: 0xFBF8F1) // 밝은 배경
    static let mellowTextPrimary   = Color(hex: 0x4A443A) // 본문 (잉크)
    static let mellowTextSecondary = Color(hex: 0xB0855C) // 보조 (카라멜)
    static let mellowShadow        = Color(hex: 0x3B362E) // 들린 블랙
    static let mellowAccent        = Color(hex: 0xC97F3E) // 주 액센트
    static let mellowBorder        = Color(hex: 0xEBDFCB) // 보더
}
```

```swift
// 사용 예
Text("일요일 오후 3시")
    .font(.system(size: 22))          // → 추후 세리프 커스텀 폰트로 교체
    .foregroundStyle(Color.mellowTextPrimary)
    .padding()
    .background(Color.mellowBgRaised)
    .overlay(RoundedRectangle(cornerRadius: 12)
        .stroke(Color.mellowBorder, lineWidth: 0.5))
```

> **다크모드:** v1은 **라이트 모드 고정**으로 출시한다(따뜻한 페이드 팔레트가 라이트 지향). 다크모드 토큰셋(딥 페이퍼 배경 + 따뜻한 텍스트)은 **v1.1**에서 정의.

---

## 8. 차용 출처 & 크레딧

| 가져온 것 | 출처 | 적용 |
| --- | --- | --- |
| 하늘·노을·드림워시 (공기감) | PICNIC | 분위기 빛 액센트 |
| 빈티지 번짐·소프트 글로우 | Retrica | 라이트릭 색 / 글로우 |
| 통일된 톤앤매너 | VSCO | 단일 팔레트 공유 원칙 |
| 절제·미니멀·다이어리 정신 | 구닥 | 덜어내기 원칙 |
| 후보정 생략·라이브 프리뷰 | Retrica·mood.camera | 몰입 원칙 |
| 시적·시즌 네이밍 | PICNIC | 시즌 한정 필름 명명 |
| 짧은 핸들 네이밍 | Retrica | 코어 필터 명명 |

---

## 9. 일관성 체크리스트 (Do / Don't)

**Do**
- ✅ 그림자엔 항상 들린 블랙(`#3B362E`).
- ✅ 모든 필터는 단일 팔레트에서 색을 뽑는다.
- ✅ 차가운 색은 액센트로만.
- ✅ 둥근 모서리, 부드러운 모션.
- ✅ 필터 이름은 짧고 따뜻한 단어로.

**Don't**
- ❌ 순수 검정(`#000`) 사용.
- ❌ 하늘색을 넓은 면에 사용.
- ❌ 고채도·쨍한 색 (아늑함과 상충).
- ❌ 무거운 블랙 가죽 UI.
- ❌ 필터 8종 큐레이션 초과 (양산 금지).

---

*버전 v0.2 · PRD v0.2와 함께 관리 · 다음 갱신: 폰트 확정, 다크모드 토큰, 컴포넌트 스펙*