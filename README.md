# Remote Mode

게이밍 데스크탑을 켜두고 맥북에서 Tailscale + Sunshine으로 원격 플레이할 때 쓰는 ON/OFF 도구입니다.

Windows 업데이트 재부팅이나 장시간 무입력 절전 때문에 원격이 먹통이 되던 문제를 막습니다. **Tailscale은 상시 실행**이 전제이며, 이 도구는 Tailscale을 켜거나 끄지 않습니다.

관리자 권한이 필요합니다.

## 이 PC 전제

| 항목 | 값 |
| --- | --- |
| 물리 모니터 | 삼성 LC32G7xT (`DISPLAY\SAM7058`) |
| Virtual Display | MikeTheTech VDD (`ROOT\DISPLAY\0000`, 모니터 `MTT1337`) |
| Sunshine | `SunshineService` (`C:\Program Files\Sunshine`) |
| 유선 NIC | Realtek PCIe 2.5GbE |
| Tailscale | Windows 서비스 Automatic (토글 대상 아님) |

설정은 [`config.json`](config.json)에 있습니다.

## 사용 흐름

```
책상에서 Remote ON
  → 삼성(메인) + VDD(보조) + Sunshine + 절전/재부팅 방지

물리 모니터만 끄고 나감
  → Remote 상태는 그대로. VDD·Sunshine 유지

원격으로 사용

집에 와서 물리 모니터를 켬
  → 메인만 삼성으로 바꿈. VDD·Sunshine은 끄지 않음

로컬만 쓰려면 Remote OFF
  → Sunshine 중지, VDD 제거, 자동 로그인/절전/업데이트 원상 복구
```

모니터 전원은 **디스플레이 메인만** 바꿉니다. Remote의 생사는 **ON / OFF 명령**만 결정합니다.

## 설치

저장소 폴더에서 관리자 PowerShell:

```powershell
cd C:\Users\sinbu\Documents\GitHub\my-remote-setting
powershell -ExecutionPolicy Bypass -File .\remote-mode.ps1 install
```

하는 일:

- 파일을 `C:\ProgramData\RemoteMode\`로 복사
- 부팅/로그온/2분 주기 스케줄 작업 등록
- 바탕화면 바로가기: **Remote Mode**(GUI), **Remote ON**, **Remote OFF**
- Sunshine `global_prep_cmd`의 `displayswitch.exe` 제거 (백업: `sunshine.conf.remotemode.bak`). 데스크탑+VDD에서 메인을 엉뚱한 화면으로 고정하던 설정이라 OFF 때도 되돌리지 않습니다
- 자동 로그인용 Windows 비밀번호 1회 입력 (DPAPI로 `C:\ProgramData\RemoteMode\autologon.bin`에 저장)

저장소 스크립트를 고친 뒤에는 `install`을 다시 실행해 ProgramData 복사본을 갱신하세요.

## GUI

관리자 UAC가 뜹니다. 창을 닫았다 열면 마지막 버튼이 아니라 **지금 장치/서비스 실상태**를 다시 읽습니다.

```powershell
powershell -STA -ExecutionPolicy Bypass -File .\remote-mode-gui.ps1
# 또는
.\remote-mode.ps1 gui
```

| 표시 | 의미 |
| --- | --- |
| **ON** | 기록 `desired=on` 이고 VDD 켜짐 + Sunshine 실행 |
| **OFF** | 기록 `desired=off` 이고 VDD 꺼짐 + Sunshine 중지 |
| **불일치** | 기록과 실상태가 다름. 표와 로그를 보면 됨 |

- **Remote ON / OFF** — 적용. 진행 로그가 아래 로그창과 `C:\ProgramData\RemoteMode\remote-mode.log`에 동시에 남습니다
- **다시 확인** — 실상태만 재조회
- **설치** — 위 `install`과 동일. 비밀번호가 없으면 GUI에서 물어봅니다

## 명령줄

```powershell
.\remote-mode.ps1 on          # Remote 켜기
.\remote-mode.ps1 off         # Remote 끄기 (명시적일 때만)
.\remote-mode.ps1 status      # 실상태 요약
.\remote-mode.ps1 doctor      # 디스플레이/전원/NIC까지 점검
.\remote-mode.ps1 install
.\remote-mode.ps1 uninstall   # 켜져 있으면 먼저 off, 스케줄·바로가기 제거
.\remote-mode.ps1 gui
```

내부용: `watch` (로그온/주기 watchdog), `apply-boot` (부팅 시 SYSTEM 재적용).

## ON일 때 / OFF일 때

**ON**

1. `desired=on` 기록
2. 슬립·최대 절전·하이브리드·무인 슬립 금지, Realtek NIC 장치 절전 해제
3. Windows Update 일시 중지 + 로그인 중 자동 재시작 금지
4. 자동 로그인 무장 (재부팅돼도 세션이 다시 뜨게). 책상에서 ON 누를 때는 화면을 잠그지 않음. **재부팅 후 로그온** 때만 잠금
5. VDD 켜기, 메인은 삼성 유지
6. Sunshine 시작, StartType Automatic
7. 사용자 세션 watchdog (절전 방지, Sunshine/VDD 복구, 삼성 모니터가 켜지면 메인만 물리로)

**OFF** (직접 명령할 때만)

1. watchdog 중지
2. Sunshine 중지, StartType Manual (로컬 부팅 때 다시 안 뜨게)
3. VDD 끄기
4. 자동 로그인 해제
5. 절전/업데이트 정책 복원
6. `desired=off`

## 로그와 상태 파일

| 경로 | 내용 |
| --- | --- |
| `C:\ProgramData\RemoteMode\remote-mode.log` | 조작 로그 |
| `C:\ProgramData\RemoteMode\state.json` | desired on/off, 전원·업데이트 백업 |
| `C:\ProgramData\RemoteMode\autologon.bin` | 자동 로그인 비밀번호 (LocalMachine DPAPI) |
| `C:\ProgramData\RemoteMode\config.json` | 이 PC 장치 ID |

## 제거

```powershell
.\remote-mode.ps1 uninstall
```

스케줄과 바탕화면 바로가기만 지웁니다. ProgramData 상태/로그/비밀번호 파일은 남깁니다. 그것까지 지우려면 `C:\ProgramData\RemoteMode`를 직접 삭제하세요.

## 주의

- 자동 로그인은 **Remote ON일 때만** Winlogon에 비밀번호가 들어갑니다. OFF면 키를 지웁니다. 집 PC + Tailscale 뒤라는 전제입니다
- Session 0(부팅 SYSTEM 작업)은 화면 배치를 못 바꿉니다. 메인 전환은 로그온된 watchdog가 합니다
- `watch` / `apply-boot`는 스케줄이 호출합니다. 평소에는 GUI 또는 `on` / `off`만 쓰면 됩니다
