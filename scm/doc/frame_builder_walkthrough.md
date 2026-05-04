# `frame_builder` 동작 완전 분석

[frame_builder.sv](../src/rtl/frame_builder.sv) 를 AXI-Stream 핸드쉐이크 + FSM 관점에서 단계별로 분석한 walkthrough.
Pattern B (FSM + 조합 출력) 의 가장 복잡한 예시. 본 프로젝트 RTL 학습의 분기점.

> 작성일: 2026-05-03
> 관련 문서: [axis_design_patterns.md](axis_design_patterns.md), [axis_upsample_zeros_walkthrough.md](axis_upsample_zeros_walkthrough.md)

---

## 1. 모듈 목적

**Payload 앞에 Preamble 16 심볼을 자동 삽입.** 한 프레임 단위로 동작.

```
입력:  ────[d0][d1][d2]─────────────       payload (외부 qpsk_modulator 출력)
                                                           ┌─ 자체 ROM 에서 생성
                                                           │
출력:  [P0][P1][P2]…[P15][d0][d1][d2]─────                
       └─── preamble 16 ───┘└── payload ──┘
       (16 cycle 자동 송출)  (pass-through)
```

`tx_frame_start` 펄스 1번 + `tx_payload_len` 입력 → 한 프레임 자동 송출 후 IDLE 복귀.

---

## 2. 내부 상태 변수

```verilog
typedef enum logic [1:0] { IDLE, PREAMBLE, PAYLOAD } state_t;
state_t state, state_next;

logic [15:0] preamble_cnt, preamble_cnt_next;   // 0..PREAMBLE_LEN-1
logic [15:0] payload_cnt,  payload_cnt_next;    // 0..payload_len-1
logic [15:0] payload_len_hold;                  // frame_start 시점 캡처
```

**Preamble ROM** (16-entry localparam):
```verilog
localparam logic signed [15:0] PREAMBLE_I [0:15] = '{ ... };
localparam logic signed [15:0] PREAMBLE_Q [0:15] = '{ ... };
```

→ 합성 시 LUT 또는 BRAM 으로 매핑. 외부 메모리 불필요.

---

## 3. FSM 상태 전이

```
                    in_frame_start=1
              ┌──────────────────────┐
              │                      ▼
      ┌────────────┐         ┌──────────────┐
      │            │         │   PREAMBLE   │
      │    IDLE    │         │  (ROM 출력)   │
      │            │         │              │
      └────────────┘         └──────────────┘
              ▲                      │
              │                      │ preamble_cnt == PREAMBLE_LEN-1
              │                      │ AND out_valid && out_ready
              │                      ▼
              │              ┌──────────────┐
              │              │   PAYLOAD    │
              └──────────────│ (pass-thru)  │
   payload_cnt == payload_len-1 └──────────────┘
   AND in_valid && in_ready
```

### 트리거 조건 — **상태별로 다름!**

| 상태 | 카운터 트리거 | 다음 상태 조건 |
|---|---|---|
| IDLE | (없음) | `in_frame_start=1` → PREAMBLE |
| PREAMBLE | `out_valid && out_ready` (= **OUTPUT** 핸드쉐이크) | `preamble_cnt==PREAMBLE_LEN-1` + 위 |
| PAYLOAD | `in_valid && in_ready` (= **INPUT** 핸드쉐이크) | `payload_cnt==payload_len_hold-1` + 위 |

### 왜 트리거가 다른가?

| 상태 | 데이터 소스 | 핸드쉐이크 의미 |
|---|---|---|
| **PREAMBLE** | 자체 ROM → output 생성 | upstream 무관, output fire 만 진행 |
| **PAYLOAD** | upstream pass-through | 양쪽 fire 가 동시 → 어느 쪽으로 카운트해도 같음, 코드는 input 쪽 선택 |

→ 본질은 둘 다 "**1 심볼이 downstream 으로 전달될 때 cnt++**" 이지만, PREAMBLE 은 input 측이 항상 stall 이라 output 측만 봄.

---

## 4. 출력 로직 (always_comb) — 상태별 행동

```verilog
case (state)
    IDLE:     begin out_valid = 0;        in_ready = 0;        end
    PREAMBLE: begin
        out_i     = PREAMBLE_I[preamble_cnt];   // ROM 출력
        out_q     = PREAMBLE_Q[preamble_cnt];
        out_valid = 1'b1;
        in_ready  = 1'b0;                       // upstream 거부
    end
    PAYLOAD:  begin
        out_i     = in_i;                       // pass-through
        out_q     = in_q;
        out_valid = in_valid;                   // valid 직결
        in_ready  = out_ready;                  // ready 직결
    end
endcase
```

### 상태별 신호 진리표

| 상태 | `in_ready` | `out_valid` | `out_i/q` |
|---|---|---|---|
| IDLE | 0 | 0 | 0 |
| PREAMBLE | **0** | **1** | `PREAMBLE_I/Q[preamble_cnt]` |
| PAYLOAD | `out_ready` | `in_valid` | `in_i/q` |

---

## 5. PAYLOAD = 진정한 Pass-through

```
                    PAYLOAD 상태
       ┌──────────────────────────────────────┐
       │                                      │
in ────┼──── data ───────────────────► out────┼──►
       │      ║                          ║    │
       │   in_valid ───────────► out_valid    │
       │      ║                          ║    │
       │   in_ready ◄─────────── out_ready    │
       │                                      │
       └──────────────────────────────────────┘
              ↑ frame_builder 가 그 순간엔 투명
```

**3 신호 (data/valid/ready) 모두 직결** → 마치 frame_builder 가 존재하지 않는 것처럼 통과.

> ⚠️ `in_ready = out_ready` 자체는 표준 위반 아님. 단, **외부에서 `in_valid` 가 `out_ready` (또는 그것에 의존하는 신호) 에 결합** 되면 combinational loop / deadlock 가능. 결합 시점에 AXI4-Stream 표준 (TVALID 가 TREADY 에 의존하지 않을 것) 준수 여부 확인 필요.

### 핸드쉐이크 fire 의 동시성

```verilog
// PAYLOAD 에서:
in_handshake  = in_valid && in_ready  = in_valid && out_ready
out_handshake = out_valid && out_ready = in_valid && out_ready
```
**같은 식!** in_handshake 와 out_handshake 가 항상 동시에 fire 또는 동시에 stall.

→ 카운터를 어느 쪽으로 트리거해도 결과 동일. 코드는 input 쪽 선택 (`in_valid && in_ready`).

---

## 6. `payload_len_hold` Latch 메커니즘

### 코드 (라인 99-102)

```verilog
if (in_frame_start) begin
    payload_len_hold <= in_payload_len;
end
```

### 왜 latch 가 필요한가

`in_payload_len` 은 **외부 입력**이라 언제든 바뀔 수 있음. 프레임 진행 중에 외부가 다음 frame 용으로 값을 바꾸면, 종료 조건 비교 (`payload_cnt == payload_len_hold - 1`) 가 맞지 않게 됨.

### Latch 없을 때 발생할 버그

```
cycle:           0   1   2   3   ...  20  21  22  ...
in_frame_start:  1
in_payload_len:  20  20  20  20  ...  10  10  10      ← 외부에서 변경

payload_cnt:     -   -   -   -   ...  0   1   2  ...
                                      ▲ 비교가 갑자기 10 으로 바뀌면 →
                                      이미 지난 값일 수 있음 → 종료 못함
```

### Latch 있을 때 — 보호됨

```
in_frame_start:    1                                     (1 cycle 펄스)
                   ↓ 이 순간만 캡처
payload_len_hold:  ?  20  20  20  ...  20  20  20  ...   ← 프레임 내내 20 유지
in_payload_len:    20  20  20  20  ...  10  10  10        ← 무시
```

### 일반 패턴 — "Latch on trigger, hold for duration"

> **출발 신호 (`frame_start`) 가 울리는 순간 결승선 거리 (`in_payload_len`) 를 기록판에 적어두고,
> 달리는 동안 결승선이 옮겨가도 처음 적힌 거리만 보고 달린다.**

비슷한 패턴이 다른 곳에도:

| 위치 | 신호 | 트리거 |
|---|---|---|
| `frame_builder` | `payload_len_hold` | `in_frame_start` |
| `frame_sync_detector` | `sync_index`, `sync_mag` | mag_sq > THRESHOLD |
| `axis_upsample_zeros` | `hold_i`, `hold_q` | `in_valid && in_ready` |

---

## 7. 시간축 시뮬 — 정상 동작 (downstream 매 사이클 받음)

`PREAMBLE_LEN=4`, `payload_len=3` 가정 (단순화):

```
cycle:           0  1  2  3  4  5  6  7  8  9
state:           I  P  P  P  P  Y  Y  Y  I  I
preamble_cnt:    -  0  1  2  3  -  -  -  -  -
payload_cnt:     -  -  -  -  -  0  1  2  -  -

in_frame_start:  1                              ← 1-cycle pulse
in_payload_len:  3                              ← cycle 0 에 캡처

in_valid:        0  1  1  1  1  1  1  1  1  0  (upstream 보내는 중)
in_ready:        0  0  0  0  0  1  1  1  0  0
in_fire:         .  .  .  .  .  ✓  ✓  ✓  .  .  ← PAYLOAD 에서만 fire

out_ready:       1  1  1  1  1  1  1  1  1  1
out_valid:       0  1  1  1  1  1  1  1  0  0
out_fire:        .  ✓  ✓  ✓  ✓  ✓  ✓  ✓  .  .

out_i:           ?  P0 P1 P2 P3 d0 d1 d2 ?  ?
```

**관찰:**
- cycle 0: `in_frame_start` 펄스 → `payload_len_hold=3`, state_next=PREAMBLE
- cycle 1~4: PREAMBLE 4개 ROM 출력. in_ready=0 으로 upstream 차단
- cycle 5: PAYLOAD 진입 → in_ready=1 (out_ready 와 직결) → upstream 데이터 받음
- cycle 5~7: pass-through. in_fire 와 out_fire 동시
- cycle 8: payload_cnt==2 (=len-1) 에서 fire → IDLE 복귀

---

## 8. 시간축 시뮬 — Corner Case (downstream stall)

### 시나리오 A — PREAMBLE 중 downstream 이 stall

```
cycle:           0  1  2  3  4  5  6  7  8
state:           I  P  P  P  P  P  P  P  Y
preamble_cnt:    -  0  1  1  1  2  3  3  -    ← stall 중 멈춤

in_ready:        0  0  0  0  0  0  0  0  *    PREAMBLE 동안 0
out_valid:       0  1  1  1  1  1  1  1  *
out_ready:       1  1  0  0  1  1  0  1  ?    ★ cycle 2,3,6 stall
out_fire:        .  ✓  .  .  ✓  ✓  .  ✓  .

out_i:           ?  P0 P1 P1 P1 P2 P3 P3 *    ← stall 동안 같은 값 유지
```

**핵심:**
- `out_ready=0` → fire 안 됨 → preamble_cnt 멈춤 → out_i 도 그대로 유지
- 결국 4 개 모두 정확히 보내짐 (시간만 늘어남)

### 시나리오 B — PAYLOAD 중 stall (양쪽 모두 가능)

```
cycle:           8  9  10 11 12 13
state:           Y  Y  Y  Y  Y  I
payload_cnt:     0  1  1  1  2  -

in_valid:        1  1  0  0  1  1     ← cycle 10,11 upstream 잠깐 멈춤
in_ready:        1  1  1  1  1  *     in_ready=out_ready=1
out_valid:       1  1  0  0  1  *     out_valid=in_valid → 함께 0
out_fire:        ✓  ✓  .  .  ✓  .
```

**Pass-through 의 결과:** in_valid=0 또는 out_ready=0 둘 중 하나만 막혀도 둘 다 멈춤. backpressure 양방향 전파.

---

## 9. 데이터 무결성 보장 메커니즘

stall 이 어떻게 발생하든 보장되는 3가지:

1. **데이터 손실 없음** — fire 시점에만 카운터 진행. fire 안 했으면 진행 안 함
2. **데이터 중복 없음** — 한 카운터 값에 한 번만 출력
3. **순서 보존** — 카운터가 단조 증가 → ROM/payload 순서대로 나감

→ AXIS 핸드쉐이크의 **자동 backpressure** 가 모든 corner case 를 자연스럽게 처리.

---

## 10. 다른 모듈과의 패턴 비교

| 측면 | `qpsk_modulator` (Pattern A) | `axis_upsample_zeros` (Pattern B) | `frame_builder` (Pattern B+) |
|---|---|---|---|
| 데이터 비율 | 1:1 | 1:N | 한 프레임 단위 (16 + N) |
| 상태 변수 | `out_valid` | `active`, `phase`, `hold` | FSM (3-state) + 카운터 2개 + latch |
| 출력 소스 | `mapped_i/q` (조합) | `hold` 또는 0 | ROM 또는 입력 pass-through |
| `in_ready` | `out_ready ∨ !out_valid` | `!active && out_ready` | 상태 의존 (0 또는 `out_ready`) |
| `out_valid` | 레지스터 | `active` | 상태 의존 (0, 1, 또는 `in_valid`) |
| 트리거 | output handshake | output handshake | **상태별로 다름** (PREAMBLE: out, PAYLOAD: in) |

→ frame_builder 는 **두 개의 서로 다른 동작 모드 (ROM 생성 / pass-through) 를 한 모듈에 결합** 한 형태.
upsample/downsample 패턴 + 사용자가 처음 보는 새 패턴 (PREAMBLE 자가-생성).

---

## 11. 검증 시 봐야 할 파형

`./run_all.sh gui tb_frame_builder` 로 띄운 후 확인할 것:

- `state` (IDLE → PREAMBLE → PAYLOAD → IDLE) 전이가 맞는가
- `preamble_cnt` 가 0..PREAMBLE_LEN-1 까지 카운트하고 PAYLOAD 진입 시 0 으로 리셋되는가
- `payload_cnt` 가 0..payload_len_hold-1 까지 카운트하고 IDLE 복귀 시 0 으로 리셋되는가
- `out_i` 가 PREAMBLE 동안 ROM 값 (12000 / -12000 패턴), PAYLOAD 동안 입력값 직결인가
- `in_ready` 가 PREAMBLE 동안 0, PAYLOAD 동안 `out_ready` 따라가는가
- `payload_len_hold` 가 `in_frame_start` 펄스 시점에만 변하는가

---

## 12. 한 줄 요약

> **frame_builder 는 한 발의 펄스 (`in_frame_start`) 로 동작을 시작해서, 16 사이클 자체 ROM 출력 후 N 사이클 pass-through, 총 16+N 심볼을 한 프레임으로 송출하는 FSM.**
> stall 은 모든 코너에서 자연스럽게 흡수되며, 외부 입력 (`in_payload_len`) 변경은 frame 시작 시점에만 latch.

이 모듈을 마스터하면:
- Pattern B 의 모든 변형 (upsample/downsample/builder) 이 같은 렌즈로 보임
- `frame_sync_detector` 의 mag_sq latch 패턴도 즉시 이해
- 다음 단계로 `preamble_correlator` (DSP + shift register) 진입할 준비 완료
