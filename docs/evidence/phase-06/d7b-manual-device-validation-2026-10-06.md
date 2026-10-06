# Phase 6 D7b — Manual iPhone 12 Validation (Owner-reported)

**Status:** Owner-reported manual observations.

이 문서는 자동화 Test, File / Store 검사, 측정 결과가 아니며 Phase 6 Gate 완료 증거가 아니다.

Phase 6은 In Progress이며 전체 상태는 Needs Device Test로 유지된다.

## 1. Context

| Field | Value |
| --- | --- |
| Installed Commit | `a38817dcb7ecb795ae1a504fec302c34ad6a1ed1` (`phase/06-media-import-normalization`) |
| Build / Install | Debug Device Build, 기존 설치 위 일반 In-place Update(삭제 · 재설정 · Seeding 없음) |
| Launch Arguments | 없음(UI-test Seeding · Failure Injection · Reset 인자 없음) |
| Device | LunaTestphone, iPhone 12 (`iPhone13,2`) |
| Date | 2026-10-06 (Asia/Seoul) |
| Observer | 소유자(수동 조작과 화면 관찰) |
| Media | 소유자가 준비한 Test Clip; 준비가 필요한 4초 Clip의 Codec · Frame Rate · HDR 속성은 독립적으로 검사하지 않았다 |

## 2. Manual PASS Observations

| # | Flow | Observation |
| --- | --- | --- |
| 1 | In-place Update | 기존 Project가 업데이트 뒤 열렸고 Thumbnail 3개와 Duration을 표시했다. |
| 2 | Editor Add (Ready) | Preparation Sheet 없이 Add가 성공했다. |
| 3 | Editor Undo / Redo | Undo가 추가된 Clip을 제거했고 Redo가 되돌렸다. |
| 4 | Editor Persistence | 나갔다가 다시 열어도 추가된 Clip과 순서가 유지되었다. |
| 5 | Editor Add (Preparation) | 소유자의 4초 Test Clip 추가 시 `영상을 준비하고 있어요`가 표시되고 완료 뒤 Sheet가 닫혔으며 다시 열어도 유지되었다. |
| 6 | Editor Add Cancel | 준비 중 취소는 조용히 닫혔고 Clip 수가 바뀌지 않았으며 Add Button이 다시 사용 가능해졌고 다시 열어도 Project가 유지되었다. |
| 7 | Editor Add (Too Short) | 1초 미만 Clip 하나는 승인된 짧은 영상 안내를 보였고 기존 Clip은 바뀌지 않았다. |
| 8 | Editor Add (Mixed) | 짧은 Clip과 유효 Clip을 함께 고르면 유효 Clip만 추가되고 제외 안내가 한 번 표시되었으며 기존 Clip이 유지되었고 Undo는 그 추가만 제거했다. |
| 9 | Select Clips Replacement | 소유자가 명시적으로 허용한 기존 Test Project에서 유효 Clip · 준비가 필요한 4초 Clip · 짧은 Clip을 고르면 제외 안내가 한 번 표시되고 받아들인 두 Clip이 선택 순서대로 든 새 Project가 만들어졌으며 다시 열어도 유지되었다. |
| 10 | Select Clips Replacement Cancel | 이어진 저장 Project 대체 중 준비 취소는 조용히 닫혔고 그 두 Clip Project가 유지되었다. |

## 3. Limits

- Playback · Audio는 검증하지 않았다: 현재 Editor UI에는 재생 Control이 없다.
- 준비가 필요한 Clip의 Codec · Frame Rate · HDR 속성은 독립적으로 검사하지 않았다.
- File-system 정리, Metadata Transaction, 용량, 성능 측정은 하지 않았다.
- Replace는 실행하지 않았다: Unavailable Clip / Replace 진입점이 없었고 진입점을 만들기 위해 Media를 손상시키지 않는다.
- Onboarding 동작, Back / Edge-swipe 차단, VoiceOver, 정확한 진행률 동작은 이 관찰에서 추론하지 않는다.

## 4. Untested (Still Outstanding)

- Editor Replace
- 준비 실패 뒤 `다시 시도`
- Storage 거부와 Runtime Disk-full
- 불확실한 Save UI(U1 / U2)
- 강제 Route 제거
- 진행률 반응성
- HDR / Dolby Vision과 그 밖의 필수 실제 Source 범위(일반 Dolby Vision 지원은 주장하지 않는다)
- Editor Reorder Snap-back과 Back 잠금 확인
