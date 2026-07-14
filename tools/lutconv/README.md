# lutconv — .cube → .lutbin 오프라인 컨버터

`LUTSource/*.cube`(Adobe/Resolve 3D LUT 텍스트)를 앱이 런타임에 그대로 읽는
바이너리 블롭 `Mellow/LUTs/*.lutbin`으로 변환한다. 런타임 텍스트 파싱(64³ 한 장에
~1–3s)을 없애기 위한 것으로, 변환에는 앱과 **동일한 `CubeParser`를 컴파일해** 쓰고,
쓴 파일을 즉시 되읽어 페이로드가 파서 출력과 **바이트 동일**한지 검증한다.

## .lutbin v1 포맷

| offset | size | field | |
|---|---|---|---|
| 0 | 4 | magic | ASCII `MLUT` |
| 4 | 4 | version | UInt32 LE, = 1 |
| 8 | 4 | dimension | UInt32 LE, n (2…64) |
| 12 | n³×16 | payload | Float32 RGBA LE, RED fastest, A=1.0 — `LUTCube.data` 그대로 |

- 페이로드 길이 = n³ × 16 바이트 (총 파일 = 12 + n³×16).
- colorSpace는 저장하지 않음 — 항상 sRGB, 런타임에 재구성.
- 런타임 리더는 `Mellow/Camera/LUTStore.swift`의 `loadCube(forSlug:)`. **포맷을 바꾸면 양쪽을 함께 바꿀 것.**

## 실행 (repo 루트에서)

```sh
swiftc -O tools/lutconv/main.swift \
  Mellow/Camera/CubeParser.swift Mellow/Camera/LUTCube.swift \
  -o /tmp/lutconv
/tmp/lutconv LUTSource Mellow/LUTs
```

9/9 PASS가 아니면 블롭을 커밋하지 말 것(비정상 종료 코드로도 실패를 알린다).

## 워크플로

**`LUTSource/`의 .cube가 바뀌면(추가/수정) 이걸 재실행해 `Mellow/LUTs/`의 .lutbin을
재생성하고, .cube와 .lutbin을 함께 커밋한다.** `Mellow/LUTs/`는 sync group에 의해
자동 번들되므로 파일을 넣는 것만으로 배포된다. `.cube`를 `Mellow/` 안에 두지 말 것 —
같이 번들되어 앱이 ~10MB 커진다.
