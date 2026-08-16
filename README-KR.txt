Synology Wi-Fi Presence Edge Driver v1.0.1
===========================================
대상: Synology RT2600ac / SRM 1.2.x

목적
----
이 드라이버는 집 공유기에서 핸드폰이 Wi-Fi에 실제 접속해 있는지를 읽어
핸드폰 1~4 각각의 presenceSensor 상태를 SmartThings에 제공합니다.
BLE 신호의 -127/LOST를 외출 판단으로 직접 사용하지 않도록 하기 위한 보조 재실 센서입니다.

안전 우선 동작
--------------
1. SRM API 자체가 실패/타임아웃이면 기존 재실 상태를 유지합니다. API 장애를 '외출'로 바꾸지 않습니다.
2. MAC이 장치 목록에서 사라져도 바로 외출 처리하지 않습니다.
   기본 120초 동안 연속 미접속일 때만 not present로 바뀝니다.
3. SRM 응답에 online/connected 필드가 없지만 MAC이 보이면 기본적으로 재실로 간주합니다.
   자동문 열림 용도이므로 false-away보다 false-present를 선택한 fail-safe 정책입니다.

설치
----
1. SmartThings CLI가 설치/로그인된 Windows PC에서 SETUP-AND-INSTALL.cmd 실행
2. SmartThings 앱 -> 기기 추가 -> 주변 검색
3. 'Synology Wi-Fi Presence' 기기 생성
4. 기기 설정에서 아래 항목 입력
   - 공유기 내부 IP: 보통 192.168.1.1 (실제 환경에 맞게)
   - 포트: HTTP 8000 권장. HTTP가 꺼져 있으면 HTTPS 8001 시도
   - SRM 전용 계정 / 비밀번호
   - 핸드폰 1~4의 Wi-Fi MAC 주소
   - 조회 주기: 기본 15초
   - 외출 확정 지연: 기본 120초

MAC 주소 주의
-------------
iPhone/Android는 Wi-Fi 네트워크마다 Private/Randomized MAC을 사용할 수 있습니다.
휴대폰 하드웨어 MAC을 추측하지 말고 SRM 네트워크 센터의 장치 목록에 현재 표시되는 MAC을 입력하세요.

SRM 계정 보안
-------------
메인 관리자 계정보다 전용 계정을 권장합니다.
이 SRM 내부 API는 공식 문서가 공개되어 있지 않아 장치 목록 조회에 관리자 권한이 요구될 수 있습니다.
처음 테스트할 때만 권한 있는 계정으로 확인한 뒤 가능한 최소 권한으로 낮추세요.

API가 안 될 때
--------------
SRM-API-PROBE.ps1 을 먼저 실행하세요.
이 스크립트는:
- SYNO.API.Info 확인
- SRM 로그인
- SYNO.Core.Network.NSM.Device에서 get/list/load/get_list/list_devices/query 후보 자동 테스트
- 성공한 원본 JSON 출력
을 수행합니다.

중요: SYNO.Core.Network.NSM.Device는 SRM에서 실제 사용하는 내부 API지만 공개 명세가 없습니다.
따라서 RT2600ac SRM 1.2.5에서 메서드/응답 필드가 다른 경우 PROBE 결과로 드라이버를 1회 맞춰야 할 수 있습니다.

SmartThings 표시
----------------
main   : 등록한 폰 중 한 대라도 재실이면 present
phone1 : 핸드폰 1 Wi-Fi 재실
phone2 : 핸드폰 2 Wi-Fi 재실
phone3 : 핸드폰 3 Wi-Fi 재실
phone4 : 핸드폰 4 Wi-Fi 재실

권장 자동문 구조
---------------
Wi-Fi Presence의 해당 폰이 not present로 외출 확정
  -> BLE 드라이버의 같은 슬롯 귀가/근접 이벤트가 발생
  -> 문 열기

Wi-Fi not present 자체만으로 문을 열지 마세요.
