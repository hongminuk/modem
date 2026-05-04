# `axis_upsample_zeros` 동작 완전 분석

[axis_upsample_zeros.sv](../src/rtl/axis_upsample_zeros.sv) 를 AXI-Stream 핸드쉐이크 관점에서 단계별로 분석한 walkthrough.
qpsk_modulator 와 다른 디자인 패턴 (FSM + 멀티사이클 출력) 의 대표적 예시.

> 작성일: 2026-05-01
> 관련 문서: [axis_design_patterns.md](axis_design_patterns.md)

---

## 1. 모듈 목적

**1 심볼 입력 → SPS 샘플 출력**. symbol rate × SPS = sample rate 변환.

```
입력 (sym rate):  ──[X]────────[Y]─────────       X, Y는 심볼
                    │           │
                    ▼           ▼
출력 (samp rate): ─[X][0][0][0][Y][0][0][0]─      SPS=4 가정
                  phase: 0  1  2  3  0  1  2  3
```

phase 0 에 심볼 값, 1..SPS−1 에 0 을 삽입.
zero-stuffing → RRC FIR 필터를 통과하면 pulse shaping 이 됨.

---

## 2. 내부 상태 변수 (3 개)

```verilog
logic active;                          // 1 = "현재 SPS 샘플 출력 중", 0 = idle
logic [$clog2(SPS)-1:0] phase;          // 0..SPS-1 (어느 샘플 출력 중인가)
logic signed [W-1:0] hold_i, hold_q;    // 캡처한 심볼 보관
```

핵심: **입력 1개를 받으면 SPS 사이클 동안 그 값을 들고 있어야** 함.
`qpsk_modulator` 가 "1 in → 1 out" 인 것과 결정적 차이.

---

## 3. 출력 로직 — 조합 (always_comb)

```verilog
always_comb begin
    if(!active) begin
        out_i = '0;          // idle 시 0
        out_q = '0;
    end else begin
        if (phase == 0) begin
            out_i = hold_i;  // 첫 샘플 = 심볼 값
            out_q = hold_q;
        end else begin
            out_i = '0;      // 나머지 = 0 (zero stuffing)
            out_q = '0;
        end
    end
end

assign out_valid = active;   // 출력 중이면 valid 유지
```

출력은 레지스터가 아닌 **와이어**. `active`, `phase`, `hold_i` 가 다 레지스터라
클럭 엣지마다 결정되고, 그 값들로 조합 회로가 즉시 출력을 결정.

---

## 4. `in_ready` 가 '1' 이 되는 조건 — 가장 중요한 부분

```verilog
assign in_ready = (!active) && out_ready;
```

**AND 두 개 모두 만족** 해야 1.

### 조건 1: `!active` (= 한가함)

| `active` | 모듈 상태 | 새 심볼 받을 수 있나? |
|:-:|---|:-:|
| 0 | **idle** — `hold_i/q` 비어있음 | ✅ 받을 수 있음 |
| 1 | **busy** — phase 0..SPS−1 진행 중 | ❌ 받으면 hold 덮어씀 |

→ active=1 동안 입력 받으면 **데이터 손실**. 절대 조건.

### 조건 2: `out_ready` (= 다음 모듈도 준비됨)

> "입력 ready 인데 왜 출력 쪽 신호를 보지?"

이유: **입력 캡처 = 다음 사이클부터 첫 샘플(phase=0, hold_i) 출력 시작**.
downstream 이 안 받을 거면 (out_ready=0) → 캡처해도 첫 샘플 못 빠져나감 → 굳이 캡처할 의미 없음.

→ **"받아도 흐름이 막힐 거면 받지 말자"** 는 보수적 정책.

### 진리표

| `active` | `out_ready` | `in_ready` | 의미 |
|:-:|:-:|:-:|---|
| 0 | 0 | **0** | idle 인데 downstream 도 idle → 받지 말자 |
| 0 | 1 | **1** | idle + downstream 받을 준비 → ✅ **들어와!** |
| 1 | 0 | 0 | busy + downstream 막힘 (이중 stall) |
| 1 | 1 | 0 | busy 중 → 받으면 hold 덮어씀 |

**`in_ready=1` 조건은 단 하나**: `!active && out_ready`.

---

## 5. 핸드쉐이크 단계별 흐름

### 입력 핸드쉐이크 (받기)

```
1단계: !active && out_ready=1  →  in_ready=1     ("받을 준비 됨")
                                       │
                                       ▼
2단계: in_valid=1 + in_ready=1 →  in_fire        ("받음")
                                       │
                                       ▼
3단계: 클럭 엣지에:
         hold_i  <= in_i
         hold_q  <= in_q
         active  <= 1                            ("보내기 시작")
         phase   <= 0
                                       │
                                       ▼
4단계: 다음 사이클부터 active=1, out_valid=1     ("보내는 중")
```

### 핵심 분리:
- **`in_ready=1`** = "받을 준비" (input 측)
- **`out_valid=1`** (= `active=1`) = "보내는 중" (output 측)
- 받음 → 캡처 → 보냄 의 순서가 **클럭 1 단위씩 분리**

### 출력 핸드쉐이크 (보내기)

```verilog
if (out_valid && out_ready) begin
    if (phase == SPS-1) active <= 0;
    else                phase  <= phase + 1;
end
```

**phase 는 출력 핸드쉐이크 fire 할 때마다 한 칸씩 증가**. downstream 이 stall 하면 phase 도 멈춤.

| 상황 | `out_valid` | `out_ready` | phase 동작 |
|---|:-:|:-:|---|
| idle | 0 | × | 변화 없음 (애초에 active=0) |
| 출력 중, downstream 받음 | 1 | 1 | **phase++** (SPS-1 이면 active=0 으로 전이) |
| 출력 중, downstream stall | 1 | 0 | 멈춤. 같은 phase 의 출력값 유지 |

---

## 6. 시간축 시뮬레이션 (SPS=4)

### 시나리오 A — 백투백 입력 (downstream 매 cycle 받음)
```
cycle:           1     2    3    4    5    6    7    8    9
                 ─    ──   ──   ──   ──   ─    ──   ──   ──
active:          0    1    1    1    1    0    1    1    1
phase:           0    0    1    2    3    0    0    1    2
hold_i:          ?    X    X    X    X    X    Y    Y    Y

in_valid:        1    1    1    1    1    1    1    1    1
in_ready:        1    0    0    0    0    1    0    0    0
in_fire:         ✓★                       ✓★

out_valid:       0    1    1    1    1    0    1    1    1
out_ready:       1    1    1    1    1    1    1    1    1
out_i:           0    X    0    0    0    0    Y    0    0
out_handshake:   .    ✓    ✓    ✓    ✓★   .    ✓    ✓    ✓
```

**관찰:**
- cycle 1: in_fire (X 캡처) → cycle 2 부터 active=1
- cycle 2~5: phase 0,1,2,3 진행, X / 0 / 0 / 0 출력
- cycle 5: phase=SPS-1 + out_handshake fire → cycle 6 에 active=0 복귀
- cycle 6: idle 상태, in_fire (Y 캡처). 그러나 **out_valid=0 라 출력 핸드쉐이크 없음**
- cycle 7: active=1, 새 심볼 Y 출력 시작

### ⚠️ Throughput — bubble 발생함 (보수적 정책의 결과)

표를 자세히 보면 cycle 6 에 `out_handshake = .` (no fire). 즉 **5 cycle 마다 1 cycle 의 bubble** 발생.

```
입력측 throughput: 1 심볼 / (SPS+1) cycle = 1/5 = 0.2 sym/clk
출력측 throughput: SPS / (SPS+1) sample/cycle = 4/5 = 0.8 sample/clk
```

→ **출력측이 100% throughput 이 아님!** SPS=4 기준 80%.

### 왜 bubble 이 강제되나 — `active` 의 mutual exclusion

```verilog
assign in_ready  = (!active) && out_ready;    → in_fire 조건: active=0
assign out_valid = active;                     → out_fire 조건: active=1
```

**`active` 한 비트로 input fire 와 output fire 가 mutually exclusive** → 같은 cycle 에 둘 다 발생 불가능. 따라서:
- 마지막 출력 (`phase=SPS-1` + out_fire) → 다음 cycle 에 `active=0`
- 그 cycle 에 in_fire 가능, 하지만 같은 cycle 에 출력은 불가능 (active=0 → out_valid=0)
- 그 다음 cycle 에 비로소 새 심볼 출력 시작

→ **input fire 와 다음 output 시작 사이에 1 cycle bubble 강제 삽입**.

### Lookahead 정책으로 throughput 개선 가능

현재의 `in_ready = !active && out_ready` 는 **보수적 정책**. lookahead 로 수정하면 bubble 제거 가능:

```verilog
// 개선안 (lookahead)
assign in_ready = (!active || (phase == SPS-1 && out_ready)) && out_ready;
```

마지막 phase 의 출력 fire 와 동시에 새 input fire 를 허용 → **1.0 sample/clk** 달성. RTL 복잡도 ↑ trade-off.

본 프로젝트는 **단순함을 위한 보수적 정책 채택**. 실제 응용에서 throughput 이 critical 하면 lookahead 로 교체.

### 시나리오 B — downstream stall
```
cycle:        N    N+1  N+2  N+3
active:       1    1    1    1
phase:        2    2    2    3      ← out_ready=0 동안 phase 멈춤
out_valid:    1    1    1    1
out_ready:    1    0    0    1      ← cycle N+1, N+2 stall
out_i:        0    0    0    hold_i / 0  (phase에 따라)
                   └──┴── stall, 같은 값 유지
```

cycle N+1, N+2 동안엔 같은 출력이 계속 띄워져있고, downstream 이 다시 받을 준비 되면 cycle N+3 에 핸드쉐이크 fire → phase++.

→ **자동 backpressure 흡수**. 데이터 손실 없음.

---

## 7. 두 영역의 always_ff 분리

```verilog
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        active <= 0; phase <= 0; hold_i <= 0; hold_q <= 0;
    end else begin
        // (A) 입력 핸드쉐이크 → 캡처 + active 진입
        if (in_valid && in_ready) begin
            hold_i <= in_i; hold_q <= in_q;
            active <= 1'b1;
            phase  <= '0;
        end

        // (B) 출력 핸드쉐이크 → phase 진행 또는 idle 복귀
        if(out_valid && out_ready) begin
            if(phase == SPS-1) begin
                active <= 1'b0;            // 4번째 샘플 빠져나감 → idle
                phase  <= '0;
            end else begin
                phase  <= phase + 1;       // 다음 샘플
            end
        end
    end
end
```

### (A) 와 (B) 의 동시 fire 는 **불가능**

```
in_fire  조건: in_valid && in_ready  = in_valid && (!active && out_ready)   → active=0 필요
out_fire 조건: out_valid && out_ready = active && out_ready                 → active=1 필요
```

`active` 한 비트로 두 fire 가 **mutually exclusive**. 따라서 (A) 와 (B) 가 같은 클럭에 동시 fire 하는 시나리오는 존재하지 않음. NBA 우선순위 분석 자체가 무의미.

대신 시퀀스는:
```
cycle N:    active=1, phase=SPS-1, (B) fire   → 다음 cycle 에 active <= 0
cycle N+1:  active=0, idle. (A) fire 가능       → 다음 cycle 에 active <= 1
cycle N+2:  active=1, 새 심볼 출력 시작
```
→ 사이에 1-cycle bubble (cycle N+1) 이 강제 삽입 (§6 참고).

---

## 8. 핵심 메커니즘 한 줄 요약

> **upsample 은 입력 1 심볼 받을 때마다 SPS 사이클 동안 자기 안에 가둬놓고, 출력 핸드쉐이크가 fire 할 때마다 한 샘플씩 흘려보낸다.**
> phase 0 에 심볼, 나머지엔 0. 다 보내면 (`phase==SPS-1` + fire) 다시 idle 로 돌아가서 다음 심볼 받을 준비.

---

## 9. 같은 패턴이 적용되는 다른 모듈

| 모듈 | 역할 | 비슷한 부분 |
|---|---|---|
| [axis_downsample_pick.sv](../src/rtl/axis_downsample_pick.sv) | SPS:1 (rate-down) | phase 카운터로 phase==OFFSET 일 때만 캡처 |
| [frame_builder.sv](../src/rtl/frame_builder.sv) | preamble 16 사이클 자동 출력 | FSM 3-state (IDLE/PREAMBLE/PAYLOAD) + counter |
| [preamble_correlator.sv](../src/rtl/preamble_correlator.sv) | shift register + 조합 sum | 1:1 이지만 내부에 16-tap 메모리 |

**공통 컨셉:** "받음 → 내부 상태 진행 → 보냄" 의 사이클 분리.

---

## 10. 검증 시 봐야 할 파형

`./run_all.sh gui tb_axis_upsample_zeros` 로 띄운 후:

- `active`, `phase`, `hold_i/q`, `out_i`, `in_ready` 가 위 시간축 표대로 움직이는지 확인
- 특히:
  - `phase=SPS-1` → 다음 cycle 에 `active=0` 으로 떨어지는가
  - 그 다음 cycle 에 `in_ready=1` 다시 올라오는가
  - back-to-back 입력 시 출력 사이에 **1 cycle bubble** 이 발생하는가 (보수적 정책 검증)
  - 입력측 throughput = 1/(SPS+1), 출력측 throughput = SPS/(SPS+1) 로 측정되는가
