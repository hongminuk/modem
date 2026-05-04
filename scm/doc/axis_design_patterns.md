# AXIS RTL 디자인 패턴 — `qpsk_modulator` vs `axis_upsample_zeros`

본 프로젝트의 RTL 모듈들이 사용하는 두 가지 핵심 AXI-Stream 디자인 패턴을 비교 정리한 문서.
모듈마다 데이터 비율(1:1 / 1:N / N:1) 에 따라 자연스럽게 다른 패턴이 적용된다.

> 작성일: 2026-05-01

---

## 1. 두 패턴의 핵심 차이

### Pattern A — **1-stage skid buffer** (`qpsk_modulator` 식)

```verilog
// 출력은 always_ff 안에서 결정 (레지스터)
always_ff @(posedge clk) begin
    // (B) output handshake — 먼저
    if (out_valid && out_ready) begin
        out_valid <= 1'b0;
    end
    // (A) input handshake — 나중 (NBA 마지막 어사인이 이김)
    if (in_valid && in_ready) begin
        out_i     <= mapped_i;     // 출력 레지스터에 저장
        out_valid <= 1'b1;          // ← 동시 fire 시에도 1 유지 → 데이터 보존
    end
end
assign in_ready = out_ready || !out_valid;
```

### ⚠️ 코드 순서가 매우 중요

`out_valid && out_ready && in_valid && in_ready` 가 동시에 만족 가능 (back-to-back) 한 cycle 에서:
- **(B) 먼저, (A) 나중** 순서 → (A) 가 NBA 마지막 어사인 → `out_valid <= 1'b1` → ✅ 데이터 보존
- (A) 먼저, (B) 나중 순서 → (B) 가 마지막 → `out_valid <= 1'b0` → ✗ **데이터 손실 버그**

→ Pattern A 채택 시 **반드시 invalidate-then-load 순서로 작성**.

특징:
- 출력 레지스터 1단(`out_i`, `out_valid`) 으로 **1개 데이터 임시 보관 가능**
- 상류 / 하류 둘 중 하나가 stall 해도 한 사이클 쿠션 있음
- 표준 AXI-Stream 1-stage register slice 와 동일
- Throughput **1.0 sample/clk** (back-to-back 동작 가능)

### Pattern B — **FSM + 조합 출력** (`axis_upsample_zeros` 식)

```verilog
// 출력은 always_comb (조합), 상태만 always_ff
always_comb begin
    if (!active)        out_i = '0;
    else if (phase==0)  out_i = hold_i;
    else                out_i = '0;
end

always_ff @(posedge clk) begin
    if (in_valid && in_ready) begin
        hold_i <= in_i;            // ← 입력만 레지스터에 저장
        active <= 1'b1;
        phase  <= '0;
    end
    if (out_valid && out_ready) begin
        if (phase == SPS-1) active <= 0;
        else                phase  <= phase + 1;
    end
end

assign out_valid = active;
assign in_ready  = !active && out_ready;
```

- **상태 머신** 으로 멀티사이클 출력 시퀀스 관리 (`active`, `phase`)
- 출력은 조합으로, 매 클럭 phase 에 따라 다른 값 생성
- `in_ready` 정책이 모듈 specific (busy gating)

---

## 2. 왜 다른가? — **데이터 비율이 결정한다**

| 측면 | Pattern A (skid) | Pattern B (FSM) |
|---|---|---|
| **데이터 비율** | 1 in : 1 out | 1 in : N out (멀티사이클) |
| **상태가 필요한가?** | ❌ 출력 레지스터 1개로 충분 | ✅ "몇 번째 샘플 내는 중?" 추적 필요 |
| **출력 구현** | `always_ff` (레지스터) | `always_comb` (조합) |
| **`in_ready` 정책** | 표준 skid: `out_ready \|\| !out_valid` | 맞춤: `!active && out_ready` |
| **Throughput** | 1 데이터 / clk (양쪽 동일) | 1 데이터 / (N+1) clk (입력측), N/(N+1) sample/clk (출력측) — bubble 강제 |
| **Stall 동작** | 출력 레지스터에 임시 보관 → bubble 적게 | 입력 거부 (`in_ready=0`) → upstream backpressure |

### 핵심 인사이트

> 데이터가 **즉시 빠져나갈 수 있으면** (1:1) → **skid buffer** 로 충분.
> 데이터가 **여러 사이클에 걸쳐 나가야 하면** (1:N 또는 N:1) → **FSM + 조합 출력 + busy gating**.

---

## 3. 패턴별 적용 룰

### Pattern A: **1-stage skid** 가 적합한 경우
- ✅ 1 in : 1 out (변환, 매핑, 단일 연산)
- ✅ throughput 100% 필요
- ✅ 상류·하류 stall 시 1개 임시 보관 여유 필요
- 예시: `qpsk_modulator`, `qpsk_demodulator`, 단순 연산 파이프라인 단

### Pattern B: **FSM + 조합 출력** 이 적합한 경우
- ✅ 1 in : N out (rate-up, replication, sequence 생성)
- ✅ N in : 1 out (rate-down, accumulation) — 변형
- ✅ 시간에 따라 출력이 다른 값 (sequence generator)
- 예시: `axis_upsample_zeros`, `frame_builder` (preamble 16 사이클 자동 출력), `axis_downsample_pick`

### Pattern C: **순수 조합 (skid 없음)** — 참고
```verilog
assign out_i     = combinational_func(in_i);
assign out_valid = in_valid;
assign in_ready  = out_ready;
```
- ✅ 0 사이클 latency 가 필요할 때
- ❌ Critical path 길어짐 (조합 깊이 누적)
- 잘 안 씀, 쓰면 의도적 설계 결정

---

## 4. 본 프로젝트 모듈별 분류

| 모듈 | 패턴 | 이유 |
|---|---|---|
| [qpsk_modulator.sv](../src/rtl/qpsk_modulator.sv) | A (skid) | 1:1 매핑 (bit pair → I/Q) |
| [qpsk_demodulator.sv](../src/rtl/qpsk_demodulator.sv) | A (skid) | 1:1 sign decision |
| [axis_upsample_zeros.sv](../src/rtl/axis_upsample_zeros.sv) | B (FSM) | 1 : SPS (zero insertion) |
| [axis_downsample_pick.sv](../src/rtl/axis_downsample_pick.sv) | B (FSM) | SPS : 1 (phase 선택) |
| [frame_builder.sv](../src/rtl/frame_builder.sv) | B (FSM) | IDLE/PREAMBLE/PAYLOAD 3-state, preamble 16 사이클 자동 출력 |
| [preamble_correlator.sv](../src/rtl/preamble_correlator.sv) | A 변형 (shift reg + 조합 sum) | 1:1 이지만 내부에 16-tap shift register |
| [frame_sync_detector.sv](../src/rtl/frame_sync_detector.sv) | A (멀티 stage pipeline) | 1:1 이지만 mag_sq 계산 + delay line + cooldown |

---

## 5. `in_ready` 정책 비교 (진리표)

### Pattern A — `in_ready = out_ready || !out_valid`

| `out_valid` | `out_ready` | `in_ready` | 의미 |
|:-:|:-:|:-:|---|
| 0 | 0 | **1** | 버퍼 비어있음 → 받아도 OK |
| 0 | 1 | **1** | 버퍼 비었고 downstream 도 받음 → OK |
| 1 | 0 | **0** | 버퍼 차있는데 downstream 안 받음 → **stall** |
| 1 | 1 | **1** | 데이터 빠져나가며 동시에 새 입력 받음 (back-to-back) |

**stall 조건은 단 하나**: `out_valid && !out_ready` (버퍼 가득 + downstream 막힘).

### Pattern B — `in_ready = !active && out_ready`

| `active` | `out_ready` | `in_ready` | 의미 |
|:-:|:-:|:-:|---|
| 0 | 0 | **0** | idle 인데 downstream 도 idle → 받지 말자 |
| 0 | 1 | **1** | idle + downstream 받을 준비 → ✅ **들어와!** |
| 1 | 0 | 0 | busy + downstream 막힘 (이중 stall) |
| 1 | 1 | 0 | busy 중 → 받으면 hold 덮어씀 |

**`in_ready=1` 조건은 단 하나**: `!active && out_ready`.

---

## 6. 설계 컨벤션 정리

### 인터페이스는 표준화, 내부는 패턴 자유
- 모든 모듈이 동일한 AXIS 신호 (`in_valid/ready`, `out_valid/ready`) 사용
- 내부 구현은 데이터 비율과 동작 특성에 맞춰 자유롭게 선택
- → 모듈 간 연결은 통일된 인터페이스로 단순, 내부는 최적화 자유

### 패턴 통일에 집착하지 말 것
- 1:1 모듈에 FSM 강요 → 불필요한 상태 변수 + 코드 복잡도 ↑
- 1:N 모듈에 skid 강요 → 멀티사이클 출력 표현 어려움
- 모듈마다 가장 자연스러운 패턴 선택

---

## 7. 참고 — 다음 분석 후보

[frame_builder.sv](../src/rtl/frame_builder.sv) 가 Pattern B 의 가장 복잡한 예시:
- 3-state FSM (IDLE / PREAMBLE / PAYLOAD)
- Preamble ROM (16 entry localparam)
- 입력 재 routing (PREAMBLE 중엔 입력 거부, PAYLOAD 시 pass-through)
- Counter 2개 (preamble_cnt, payload_cnt)
