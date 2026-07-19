# Bulk Index Build 캠페인 현황 보고 (2026-07-11 12:00 KST)

## 1. 자원 안전 상태 (실측, .30/.34는 같은 물리 디스크 공유)
| 자원 | 상태 |
|---|---|
| /home (sda1 3.5T) | 46% 사용, **여유 1.9T** — 복구 완료 |
| /data (sdc1 11T) | 11% 사용, **여유 9.8T** |
| 메모리 | 188G 중 **가용 131G** |
| 캠페인 점유 | DB 1.3G + debug 설치 1.5G + 증거 1.1M ≈ **2.8G** |

## 2. 왜 2TB를 썼나
R1 채증 단계에서 하네스가 `cubrid diagdb -d 8`(트랜잭션 로그 덤프)을 호출. 이건 **대화형 메뉴 도구**인데 stdin 없이(EOF) 실행되자 프롬프트를 무한 반복 출력했고, 받는 로그 파일에 **크기 상한이 없어** 8시간 만에 단일 파일 2.0TB. 실패 3중 결합: 대화형 도구 + stdin 미공급 + 무상한 redirect.

## 3. 재발 방지 (전부 반영 완료)
- **SSOT 규칙 11·12 명문화**: 대화형 유틸은 응답 명시 파이프 필수 / 모든 자동화 출력에 크기 상한(ulimit -f, head -c) / 장기 명령에 디스크 preflight+watchdog(여유<100G 즉시 중단) / 전량 덤프 금지, 유계 증거(statdump delta·파일크기 delta) 우선 / 공유 디스크 경고.
- **하네스에 safety.sh 계층** (require_free_gb/bounded_run/with_answers) + 전 스크립트 정적 감사: 대화형 직접호출 0, 무상한 redirect 0 확인. amendment 002로 봉인.
- **oracle 자체를 유계 방식으로 교체**: diagdb 전량 덤프 → statdump 카운터 + 로그파일 바이트 delta + 바이너리 심볼 검사.
- **DB 축소**: 2.6G → 1.3G (재생성, log_max_archives=0). release 단계 대형 DB/backup은 /data(여유 9.8T)로 배치 예정.

## 4. 성능 개선치 — 아직 없음 (정직 보고)
성능을 내는 제품 코드는 아직 미커밋. 계획 자체가 "증명·하네스·기준선 먼저, 구현 나중"(R0→R1→R2~R4→V2 성능측정 마지막). 현재 확보: develop이 인덱스 크기만큼 로그를 쓴다는 **개선 대상 실증**(1M행 기준 oracle FAIL 채증 완료). 기대 효과는 인덱스 빌드 시 redo 로깅 제거 + 병렬 페이지 구축.

## 5. 어디까지 했나
- ✅ **R0**: 병렬화 안전 증명 14파일(page-provenance, 콜그래프, closure, 복구), critic 2회 심사 통과, 원격 불변 봉인
- ✅ **R1**: debug 빌드 green(SHA 일치 실증), 픽스처 1M행+골든 PASS, FAIL oracle 3행(로그볼륨/마커부재/restore 컨트롤), 캠페인 상태기계+SHA 체인(001→002→003)
- ✅ **게이트**: critic 최종 **APPROVE** → 승인 receipt 003 봉인 → r2 게이트 개통(validate exit 0). 승인 없으면 게이트가 안 열리는 것도 실증(exit 2)
- 🔄 **W1 착수**: R2-01(vacuum notification main-이관, 첫 제품 커밋) 실행 중 — 세션 재시작으로 agent 재기동, 커밋은 아직 없음

## 6. 뭐가 남았나
| 단계 | 내용 |
|---|---|
| W1 (지금) | R2-01 → R2-02 (inert 기반 이관, 커밋마다 게이트+push) |
| W2 승인조건 | closure 단일-FORCE 통합 설계 확정 + R3 새 SHA 정적 재증명 |
| R3 | 직렬 no-redo (플래그 전파→로깅 억제→FORCE 통합→활성화) |
| R4 | 병렬 페이지 구축 (워커 콜그래프 0 증명 후) |
| V1/V3 | 복구 27-matrix, TDE/이중모드 빌드 |
| V2 (마지막) | 성능 측정 — 여기서 개선치 최초 보고 |
