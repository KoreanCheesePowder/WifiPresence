Synology Wi-Fi Presence Edge Driver v1.0.8
===========================================

Synology RT2600ac / SRM 1.2.x의 장치 목록을 조회해 최대 4대 휴대폰의 Wi-Fi 재실 상태를 SmartThings에 제공하는 LAN Edge 드라이버입니다. BLE 신호만으로 외출을 판단하지 않도록 보조 재실 센서로 사용할 수 있습니다.

주요 기능
---------
- phone1~phone4에 등록한 MAC 주소별 presenceSensor 상태 표시
- 등록한 휴대폰 중 한 대라도 재실이면 main을 present로 표시
- HTTP 또는 HTTPS로 SRM 로그인 및 장치 목록 조회
- SRM 환경에 맞는 SYNO.Core.Network.NSM.Device 메서드와 버전을 자동 탐색해 재사용
- 조회 주기와 연속 미접속 확인 횟수 설정
- 수동 refresh 지원
- 제작자와 드라이버 버전 표시

안전 우선 동작
--------------
1. SRM 로그인, API 호출 또는 네트워크 자체가 실패하면 기존 재실 상태를 유지합니다.
2. 한 번의 미접속 결과만으로 외출 처리하지 않고 설정한 횟수만큼 연속 확인합니다.
3. 재실 확인은 즉시 반영하며, 외출 판단은 보수적으로 처리합니다.
4. 장치 목록에 MAC이 있어도 연결 상태나 유효한 IP가 없으면 미접속 후보로 처리합니다.
5. 첫 조회 전에는 설정된 휴대폰을 present로 두어 API 장애가 잘못된 외출 이벤트를 만들지 않게 합니다.

설치
----
1. SmartThings CLI가 설치되고 로그인된 Windows PC에서 SETUP-AND-INSTALL.cmd를 실행합니다.
2. SmartThings 앱에서 기기 추가 -> 주변 검색을 실행합니다.
3. C.P Synology Wi-Fi Presence 기기를 생성합니다.
4. 기기 설정에서 공유기 주소, 포트, SRM 전용 계정, 휴대폰 1~4의 Wi-Fi MAC 주소, 조회 주기와 미접속 확인 횟수를 입력합니다.

MAC 주소 주의
-------------
iPhone과 Android는 Wi-Fi 네트워크마다 Private/Randomized MAC을 사용할 수 있습니다. 하드웨어 MAC을 추측하지 말고 SRM 네트워크 센터의 장치 목록에 현재 표시되는 MAC 주소를 입력하세요.

SRM API 점검
------------
연결에 실패하면 SRM-API-PROBE.ps1을 실행해 SYNO.API.Info, 로그인, SYNO.Core.Network.NSM.Device 후보 메서드와 원본 JSON을 확인하세요. 이 API는 공개 명세가 없어 SRM 버전에 따라 메서드나 응답 필드가 다를 수 있습니다.

자동문 연동 권장 방식
--------------------
Wi-Fi Presence에서 해당 휴대폰이 not present로 외출 확정된 뒤 BLE 드라이버의 같은 슬롯에서 귀가·근접 이벤트가 발생할 때 문을 여는 방식으로 구성하세요. Wi-Fi not present만으로 문을 열지 마세요.

드라이버 정보
-------------
- 제작자: 치즈가루
- 버전: v1.0.8
- packageKey: synology-wifi-presence-srm12
