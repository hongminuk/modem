# `axis_downsample_pick` 동작 완전 분석

[axis_downsample_pick.sv](../src/rtl/axis_downsample_pick.sv) 를 backpressure / NBA 렌즈로 분석한 walkthrough.
표면적으로 `axis_upsample_zeros` 의 거울이지만, **실제로는 더 정교한 Hybrid 패턴** 을 사용한다.

> 작성일: 2026-05-07
> 관련 문서: [axis_design_patterns.md](axis_design_patterns.md), [axis_upsample_zeros_walkthrough.md](axis_upsample_zeros_walkthrough.md)

---

## 1. 모듈 목적

**SPS 샘플 입력 → 1 심볼 출력** (phase==OFFSET 인 샘플만 캡처). RX 측의 sample-rate → symbol-rate 변환.

```
입력 (samp rate):  ─[s0][s1][s2][s3][s4][s5][s6][s7]─    s_n = sample n
                   phase: 0  1  2  3  0  1  2  3
                          
                          (OFFSET=2 가정)
                                ↓                ↓
출력 (sym rate):  ────────[s2]─────────────[s6]──────
                  
                  ★ phase==OFFSET 샘플만 살리고 나머지는 버림
```

본 프로젝트는 [qpsk_frame_sync_top.sv](../src/rtl/qpsk_frame_sync_top.sv) 에서 `OFFSET=0` 으로 인스턴스화 → 첫 샘플 (s0, s4, s8, ...) 만 살림.

---

## 2. 내부 상태 변수

```verilog
logic [$clog2(SPS)-1:0] phase;          // 0..SPS-1
logic signed [W_3-1:0] out_i_r, out_q_r; // 출력 레지스터 (1-stage skid)
logic out_valid_r;                       // 출력 valid 레지스터
```

→ 단순. 출력 레지스터 + phase 카운터.

---

## 3. ⭐ 핵심 — **Hybrid Backpressure Pattern**

이 모듈의 가장 중요한 설계 결정. `in_ready` 가 phase 에 따라 두 가지 패턴을 섞어 씀.

### 코드 (라인 63~69)

```verilog
always_comb begin
    if(phase == OFFSET) begin
        in_ready = (!out_valid_r) || out_ready;   // Pattern A (skid)
    end else begin
        in_ready = 1'b1;                           // Pattern C (조합 직결)
    end
end
```

### 패턴 분류표

| phase | `in_ready` 식 | 패턴 | 의미 |
|---|---|:-:|---|
| `phase != OFFSET` | `1'b1` (always) | **C** (조합 직결) | "어차피 버릴 샘플 → backpressure 만들 필요 없음" |
| `phase == OFFSET` | `(!out_valid_r) \|\| out_ready` | **A** (1-stage skid) | "이건 캡처할 샘플 → skid buffer 가득 차면 stall" |

### Pattern A 진리표 (phase==OFFSET 일 때)

| `out_valid_r` | `out_ready` | `in_ready` | 의미 |
|:-:|:-:|:-:|---|
| 0 | × | **1** | skid buffer 비어있음 → 받을 수 있음 |
| 1 | 1 | **1** | 빠져나가며 동시에 새 샘플 받음 (back-to-back) |
| 1 | 0 | **0** | skid 가득 + downstream 막힘 → **STALL** |

### 왜 Hybrid 인가 — upsample 과의 본질적 차이

**upsample (1:SPS)** — Pattern B 단일 (busy gating):
```
입력 1개 잡고 SPS cycle 동안 출력 → 그 동안 입력 거부 (active=1)
→ 입력은 SPS cycle 마다 한 번만 받으면 됨 → 단일 정책으로 충분
```

**downsample (SPS:1)** — Hybrid (C + A):
```
SPS cycle 동안 입력 받고 그중 1개만 살림
→ 살리지 않는 SPS-1 cycle 은 backpressure 가 무의미 (어차피 안 잡음)
→ 그 cycle 들엔 그냥 통과 (Pattern C), 캡처 cycle 만 skid 적용
```

→ **방향에 맞춘 최적화**. 단순 거울이 아니다.

---

## 4. NBA 분석 — invalidate-then-load 안전한가?

```verilog
always_ff @(posedge clk) begin
    // (B) output handshake fire → invalidate
    if (xfer_out) out_valid_r <= 1'b0;

    // (A) input handshake fire → (OFFSET 일 때만) load
    if (xfer_in) begin
        if (phase == OFFSET) begin
            out_i_r     <= in_i;
            out_q_r     <= in_q;
            out_valid_r <= 1'b1;
        end
        ...
    end
end
```

→ **(B) 먼저, (A) 나중**. ✅ Pattern A 의 invalidate-then-load 안전 패턴 준수.

### 동시 fire 가능 시나리오 (back-to-back at OFFSET cycle)

```
phase == OFFSET, out_valid_r=1, out_ready=1, in_valid=1 일 때:
  → in_ready = !out_valid_r || out_ready = 0 || 1 = 1
  → xfer_in 과 xfer_out 동시 fire

NBA 처리:
  (B): out_valid_r <= 0    (예약)
  (A): out_valid_r <= 1    (덮어쓰기 — 마지막 어사인 이김)
  
결과: out_valid_r = 1, 새 데이터 캡처 ✅
```

→ qpsk_modulator 와 동일한 안전 패턴.

### 비-OFFSET cycle 에서의 동시 fire 분석

```
phase != OFFSET 일 때:
  in_ready = 1 (항상)
  xfer_in 자주 fire (in_valid=1 인 한)
  xfer_out 도 fire 가능 (out_valid_r=1, out_ready=1)
  
하지만:
  (A) 의 capture branch (phase==OFFSET) 는 실행 안 됨
  → out_valid_r 는 (B) 만 작용 → 빠져나가면 0 으로 변함
  → 새 데이터 capture 안 함 (의도된 동작)
```

→ 비-OFFSET cycle 의 동시 fire 는 **단순 출력 소비** + **입력 무시** 의 조합. 안전.

---

## 5. ⭐ phase 카운팅 위치 — `xfer_in` 트리거

```verilog
if (xfer_in) begin
    ...
    if (phase == SPS-1) phase <= '0;            // wrap-around
    else                phase <= phase + 1'b1;   // 정상 증가
end
```

→ **phase 는 입력 핸드쉐이크 fire 시에만 증가**.

### upsample 과의 본질적 차이 — phase 트리거 비교

| 모듈 | phase 트리거 | 이유 |
|---|---|---|
| `axis_upsample_zeros` | **`xfer_out`** (출력 fire) | 1 입력 받고 → SPS 사이클 동안 출력 → 출력 진행에 따라 phase++ |
| `axis_downsample_pick` | **`xfer_in`** (입력 fire) | SPS 입력 받고 → 1 출력 → 입력 진행에 따라 phase++ |

### 의미

> 각 모듈에서 **"1 주기(period) 의 흐름을 결정하는 측"** 의 핸드쉐이크가 phase 카운팅 트리거.

- upsample 의 한 주기 = 1 입력 후 SPS 출력 → 출력이 loop 의 주체
- downsample 의 한 주기 = SPS 입력 후 1 출력 → 입력이 loop 의 주체

이 구조 차이가 **모듈을 단순한 거울이 아닌 방향-적응형 디자인**으로 만듦.

---

## 6. 시간축 시뮬 — 정상 동작 (SPS=4, OFFSET=2)

downstream 항상 받음 가정:

```
cycle:           0  1  2  3  4  5  6  7  8  9
phase:           0  1  2  3  0  1  2  3  0  1
in_valid:        1  1  1  1  1  1  1  1  1  1
in_data:         s0 s1 s2 s3 s4 s5 s6 s7 s8 s9

in_ready 정책:
  phase != OFFSET (0,1,3): 1 (Pattern C)
  phase == OFFSET (2):     (!out_valid_r) || out_ready
  
in_ready:        1  1  1  1  1  1  1  1  1  1   ← 평소엔 다 1 (downstream 받음)
xfer_in:         ✓  ✓  ✓  ✓  ✓  ✓  ✓  ✓  ✓  ✓

OFFSET 도달:           ▲           ▲           ▲       (cycle 2, 6, ...)

out_valid_r:     0  0  0  1  1  1  0  1  1  1  ← phase=2 다음 cycle 부터 1
out_ready:       1  1  1  1  1  1  1  1  1  1
out_i_r:         ?  ?  ?  s2 s2 s2 s2 s6 s6 s6
xfer_out:        .  .  .  ✓  .  .  ✓  ✓  .  .
                          ↑           ↑     
                       cycle 3에서 s2 받아감, cycle 6 에서도 fire
```

**관찰:**
- cycle 2: `phase=OFFSET`, `xfer_in` fire → s2 캡처 (다음 cycle out_valid_r=1)
- cycle 3~5: 출력 valid 유지, downstream 이 cycle 3 에 받음 → 다음 cycle out_valid_r=0
- cycle 6: 다음 OFFSET 도달, 새 샘플 (s6) 캡처
- 출력 throughput: 1 sample / SPS=4 cycle

---

## 7. 시간축 시뮬 — Stall 시나리오

### Downstream stall 발생 → OFFSET cycle 에서만 backpressure

```
cycle:           0  1  2  3  4  5  6  7
phase:           0  1  2  3  0  1  2  2  ★ phase=2 에서 멈춤
in_valid:        1  1  1  1  1  1  1  1
out_valid_r:     0  0  0  1  1  1  1  1
out_ready:       1  1  1  0  0  0  0  0    ← cycle 3 부터 stall

phase != OFFSET (0,1,3,4,5): in_ready = 1
phase == OFFSET (2,6,7):
   cycle 2: out_valid_r=0 → in_ready = 1 → xfer_in fire, s2 캡처
   cycle 6: out_valid_r=1, out_ready=0 → in_ready = 0 → ✗ STALL
   cycle 7: 동일 → 계속 STALL

in_ready:        1  1  1  1  1  1  0  0
xfer_in:         ✓  ✓  ✓  ✓  ✓  ✓  .  .
phase 진행:                              ▲ 멈춤 (xfer_in=0 이라 phase 도 멈춤)
```

**관찰:**
- cycle 6: phase=2 (OFFSET) 도달했으나 skid buffer 가 가득 + downstream 막힘 → upstream stall
- cycle 7~: phase=2 에서 멈춰있음 → 다음 cycle 에도 같은 상태 유지
- → downstream 이 풀리면 자동 복귀

### Pattern C cycle 에선 stall 영향 X

phase=0,1,3 cycle 들에선 `in_ready=1` 그대로 → stall 무관. **출력이 막힌 동안에도 비-OFFSET cycle 입력은 받기는 하지만, 모두 버려짐**. 데이터 손실 X (어차피 사용 안 할 데이터).

---

## 8. 데이터 무결성 verification

### 보장 매커니즘 3가지

1. **OFFSET cycle 캡처 시점**: skid buffer 가득 차있으면 in_ready=0 → upstream 강제 stall → 다음 OFFSET 까지 대기
2. **invalidate-then-load NBA**: back-to-back 동시 fire 시 새 데이터 보존
3. **비-OFFSET cycle 의 입력**: 어차피 버릴 데이터라 stall 무관

### 손실 가능성 분석

- 비-OFFSET 입력은 의도적으로 버림 → 손실 아님 (downsample 의 정의)
- OFFSET 입력은 skid buffer 로 보호 → 안전
- back-to-back 시 NBA 순서 (B→A) 로 보호 → 안전

→ ✅ **데이터 무결성 완전 보장**.

---

## 9. upsample vs downsample — 진정한 차이

| 측면 | `axis_upsample_zeros` | `axis_downsample_pick` |
|---|---|---|
| 데이터 비율 | 1 in : SPS out | SPS in : 1 out |
| 주된 패턴 | **B (단일)** — busy gating | **Hybrid (C + A)** — 상황별 |
| 출력 형식 | 조합 (always_comb) | 레지스터 (always_ff capture) |
| 상태 변수 | `active`, `phase`, `hold` | `phase`, `out_*_r` |
| `in_ready` | `!active && out_ready` | phase 따라 `1` 또는 skid |
| `out_valid` | `active` (조합) | `out_valid_r` (레지스터) |
| **phase 트리거** | `xfer_out` (출력 fire) | **`xfer_in` (입력 fire)** |
| Throughput in | 1 / (SPS+1) clk (보수적, bubble) | **1 / clk (full rate)** |
| Throughput out | SPS / (SPS+1) clk (bubble) | **1 / SPS clk (정확)** |
| 백프레셔 처리 | busy gating | hybrid (대부분 통과, OFFSET 만 skid) |

### 핵심 인사이트

> **upsample 은 모든 입력을 잡아야** 해서 보수적 정책 (한 cycle bubble 강제).
> **downsample 은 일부 입력만 잡으면** 되니까 효율적 정책 (필요한 cycle 에만 stall).
>
> 같은 SPS 변환이지만 **방향에 따라 최적 디자인이 다르다**.

---

## 10. 본 프로젝트의 OFFSET=0 특성

[qpsk_frame_sync_top.sv](../src/rtl/qpsk_frame_sync_top.sv):
```verilog
parameter int OFFSET = 0;
```

→ phase 0, SPS, 2·SPS, ... 마다 캡처. 즉 **첫 샘플** 만 캡처.

### 왜 0?

TX upsample 도 phase 0 에 심볼을 두니까, **체인 끝까지 phase 0 정합 유지**:
```
TX upsample:    심볼이 phase 0 에 위치
TX RRC:         FIR delay 만큼 shift (40 sample 그룹 딜레이 = 10 sym = phase 보존)
RX RRC:         FIR delay (또 phase 보존)
RX downsample:  phase 0 에서 캡처 → TX 의 phase 0 와 동일 위상
```

만약 timing recovery (Gardner / M&M) 가 들어가면 OFFSET 이 동적으로 바뀔 수 있음 — 현재는 단순화를 위해 고정.

### Reset 시 동작

```verilog
if(!rst_n) begin
    phase <= '0;
    ...
end
```
→ rst 풀린 직후 phase=0 = OFFSET 매칭 → **첫 입력부터 즉시 캡처**.

---

## 11. 검증 시 봐야 할 파형 — `tb_axis_downsample_pick`

`./run_all.sh gui tb_axis_downsample_pick` 로 띄운 후:

- `phase` 가 매 입력 cycle 마다 0→1→2→3→0 으로 wrap 되는가
- `phase == OFFSET` cycle 에서만 `out_i_r` 가 갱신되는가
- 비-OFFSET cycle 에선 `in_ready = 1`, OFFSET cycle 에선 skid 정책 따라가는가
- `out_valid_r` 가 OFFSET 직후 cycle 부터 1 이 되고, downstream 이 받으면 다음 cycle 에 0 되는가
- downstream stall 시 OFFSET cycle 에서만 in_ready=0 으로 stall 되는가 (비-OFFSET 은 영향 없음)

---

## 12. 한 줄 요약

> **`axis_downsample_pick` 은 매 입력에 phase++, phase==OFFSET 인 입력만 1-stage skid buffer 로 캡처.**
> 비-OFFSET cycle 은 Pattern C (직결, 무조건 받고 버림), OFFSET cycle 은 Pattern A (skid).
> upsample 의 단순 거울이 아닌, **방향-적응형 Hybrid 디자인**.
> back-to-back back-pressure 시에도 invalidate-then-load NBA 순서로 데이터 보존.

이 모듈을 마스터하면:
- Pattern C / A 를 한 모듈에서 섞어 쓸 수 있음을 학습
- 데이터 비율과 backpressure 정책의 관계가 명확해짐
- 다음 단계: [preamble_correlator.sv](../src/rtl/preamble_correlator.sv) — DSP 본격 시작 (matched filter)
