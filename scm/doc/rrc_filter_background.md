# RRC Filter Background — DSP 이론 + IP 설정 + AXIS 인터페이스

본 프로젝트의 [fir_rrc / fir_rrc_rx](../create_project.tcl) (Xilinx FIR Compiler IP) 의
**RTL 이 아닌, 외부 시각** 에서 이해하기 위한 reference.
실제 RTL 은 IP 가 자동 생성한 VHDL 이라 분석 가치가 낮으므로, 본 문서는 **DSP 역할 + 파라미터 의미 + 인터페이스** 에 집중.

> 작성일: 2026-05-03
> 관련 문서: [scm_sim_rtl.ipynb](../src/algo/scm_sim_rtl.ipynb), [axis_design_patterns.md](axis_design_patterns.md)

---

## 1. 왜 RRC 필터가 필요한가?

### 문제 — 사각파 심볼은 무한대 대역폭

QPSK 변조기 출력은 ±SCALE 의 **사각파(계단 함수)**:

```
심볼:    ±SCALE     ±SCALE
시간:    ─────┐     ┌─────
              │_____│
        T_sym
```

사각파의 푸리에 변환 = sinc 함수 = **무한대 sidelobe**.
그대로 전송하면:

1. **대역폭 낭비** — 할당 대역 외부로 에너지 새어나감 (인접 채널 간섭)
2. **법규 위반** — 통신 규제 (FCC, ETSI 등) 의 spectral mask 위반
3. **수신측 SNR ↓** — 대역제한 채널 통과 시 왜곡 → BER ↑

### 해결책 — Pulse Shaping

심볼을 **부드러운 모양** 으로 바꿔 대역제한.
사각파 → 사인 형태 펄스.

---

## 2. ISI 와 Nyquist 기준

### ISI (Inter-Symbol Interference)

부드러운 펄스로 바꾸면 **펄스 꼬리가 다음 심볼 시점에 침범** 가능:

```
   심볼 0       심볼 1       심볼 2
   T=0          T=Tsym       T=2Tsym
     ▲            ▲            ▲
     │            │            │
     ┌─┐  꼬리   ┌─┐  꼬리   ┌─┐
     │ │ ──────►│ │ ──────►│ │
     ┘ └────────┘ └────────┘ └
            ↑ 다른 심볼 시점에 영향 = ISI
```

심볼 0 의 펄스 꼬리가 심볼 1 시점 (T=Tsym) 에서 0 이 아니면 → 심볼 1 의 값을 왜곡.

### Nyquist ISI-Free 조건

> **수신측 심볼 시점 (T_sym 간격) 에 샘플링했을 때, 자기 시점 외엔 모두 0 이어야 한다.**

수식:
```
p(0) = 1, p(T_sym) = 0, p(2·T_sym) = 0, p(-T_sym) = 0, ...
```

이 조건 만족하면 ISI = 0.

### Sinc — 이상적이지만 비현실적

```
sinc(t/T) = sin(π·t/T) / (π·t/T)
```
- ✅ Nyquist 조건 정확히 만족
- ❌ **무한대 길이** (시간상 영원히 지속)
- ❌ Brick-wall 주파수 응답 → **하드웨어 구현 불가능**

---

## 3. Raised Cosine (RC) → Root Raised Cosine (RRC)

### Raised Cosine — 실용적 절충

sinc 의 유한 길이 근사. 주파수 응답이 cosine 모양:

```
주파수 응답:
      │
   1 ─┤────╮
      │     ╲     β = roll-off factor (0~1)
   ½ ─┤      ╲    β=0 → brick wall (= sinc, 비현실적)
      │       ╲   β=1 → 가장 부드러움 (대역폭 2배)
   0 ─┴───────╲────── freq
            (1+β)/(2T)
```

**β (roll-off factor)** 의 trade-off:
- 작을수록 → 대역폭 좁음 (효율 ↑), 펄스 꼬리 길어짐 (구현 어려움)
- 클수록 → 대역폭 넓음 (효율 ↓), 부드럽고 짧음 (구현 쉬움)
- **본 프로젝트: β = 0.35** (전형적 modem 값, 효율 vs 구현 균형)

### 왜 "Root" Raised Cosine 인가?

핵심 트릭: RC 를 **TX 와 RX 로 나눠서 각각 RRC** 통과시키면 합성이 RC 가 됨:

```
TX: 심볼 → RRC → 채널 → RRC → RX → 샘플링
                        ↓
                    TX·RX 합성 = RC (제곱근의 곱)
```

수학적으로:
```
RRC(f) × RRC(f) = RC(f)
```

→ **전체 시스템 = RC** → ISI 0.

### 왜 굳이 나누는가?

1. **Matched filter** — 같은 모양 필터로 RX 측 통과 시 **SNR 최대화** (잡음에 대한 최적해)
2. **AWGN 채널에서 BER 최소화** 의 수학적 최적해
3. RX 측이 결국 matched filter 가 되어야 하므로, TX 도 RRC 로 맞추는게 자연스러움

→ **TX RRC = pulse shaping**, **RX RRC = matched filter + ISI 제거**.

본 프로젝트의 [fir_rrc](../src/rtl/qpsk_frame_sync_top.sv) (TX) 와 [fir_rrc_rx](../src/rtl/qpsk_frame_sync_top.sv) (RX) 의 정체.

---

## 4. 본 프로젝트의 RRC 파라미터

[create_project.tcl](../create_project.tcl) 의 IP 설정 + COE 파일에서:

| 파라미터 | 값 | 의미 |
|---|---|---|
| **β (roll-off)** | 0.35 | 대역폭 = `(1+0.35)/Tsym` = 1.35×Nyquist |
| **span** | 10 | 펄스 길이 = 10 심볼 (양쪽 ±5 sym) |
| **SPS** | 4 | 심볼당 샘플 수 (oversampling) |
| **Number of taps** | `span × SPS + 1 = 41` | 41 탭 FIR |
| **Coefficient quantization** | Q1.15 (16-bit signed) | -32768 ~ +32767 |

### COE 파일

[src/coe/rrc_sps4_beta0p35_span10_q16p.coe](../src/coe/rrc_sps4_beta0p35_span10_q16p.coe) 에 41 개 계수.
Python [scm_sim_rtl.ipynb](../src/algo/scm_sim_rtl.ipynb) 의 `RRC_COEFS_INT` 와 동일.

```python
RRC_COEFS_INT = [224, -71, ..., 32767, ..., -71, 224]   # 41 entries, 좌우 대칭
```

대칭성: RRC 계수는 **center-symmetric** (`h[k] = h[N-1-k]`, linear-phase Type I FIR)
→ FIR Compiler 가 reduced multiplier 구조로 자동 최적화 (탭 수 절반).

### Group Delay

```
group_delay = (taps - 1) / 2 = (41 - 1) / 2 = 20 samples
```

샘플 레이트에서 20 샘플 = **5 심볼** (SPS=4) 지연.
TX RRC + RX RRC 합쳐서 **40 샘플 = 10 심볼** 지연 → 수신측 심볼 추출 시 이 지연 보정 필요.

### Output Width (bit growth)

`Output_Rounding_Mode = Full_Precision` 모드. IP 가 자체적으로 effective bit-width 를 결정하고, AXI-Stream tdata 는 byte-aligned (8 의 배수) 로 노출:

| Stage | Input (Data_Width) | Coef | Taps | IP Output_Width | AXI tdata (top RTL) |
|---|---|---|---|---|---|
| TX `fir_rrc` | 16 | 16 | 41 | **34-bit** | 40-bit (`W_2`) |
| RX `fir_rrc_rx` | 34 | 16 | 41 | **52-bit** | 56-bit (`W_3`) |

→ IP 의 실제 출력은 34/52-bit 이지만 AXI tdata 는 byte-align 으로 40/56-bit. [qpsk_frame_sync_top.sv](../src/rtl/qpsk_frame_sync_top.sv) 의 `W_2=40, W_3=56` 은 tdata 폭. RX 입력 (`Data_Width=34`) 은 TX 출력의 IP 실제 폭과 일치 (LSB-aligned).

> 이론상 full-precision 비트폭 = `input_width + coef_width + ceil(log2(taps))` = 16+16+6 = 38 (TX) 인데 IP 는 34 로 나옴. 이는 FIR Compiler 의 **center-symmetric 계수 인식 + reduced precision allocation** 결과로 추정. 정확한 산출 알고리즘은 IP 내부 구현 세부.

---

## 5. AXI-Stream 인터페이스

### 신호 매핑

| Xilinx AXIS (FIR IP) | 우리 코드 컨벤션 |
|---|---|
| `s_axis_data_tvalid` | `in_valid` |
| `s_axis_data_tready` | `in_ready` |
| `s_axis_data_tdata` | `in_i` (또는 `in_q`) |
| `m_axis_data_tvalid` | `out_valid` |
| `m_axis_data_tready` | `out_ready` |
| `m_axis_data_tdata` | `out_i` |

→ **우리 프로젝트 AXIS 컨벤션 그대로**. backpressure / handshake 동일하게 동작.

### 인스턴스화 코드 (TX 측 예시)

```verilog
fir_rrc u_fir_tx_i (
    .aclk              (clk),
    .aresetn           (rst_n),

    // Input (slave AXIS)
    .s_axis_data_tvalid(tx_fir_valid),
    .s_axis_data_tready(tx_ready_i),
    .s_axis_data_tdata (tx_up_i),

    // Output (master AXIS)
    .m_axis_data_tvalid(tx_valid_i),
    .m_axis_data_tready(tx_fir_ready),
    .m_axis_data_tdata (tx_out_i)
);
```

### I/Q 분리 — FIR 인스턴스 2개

복소 신호이므로 I 와 Q 각각 별도 FIR 통과:

```verilog
fir_rrc u_fir_tx_i ( ... );    // I 채널
fir_rrc u_fir_tx_q ( ... );    // Q 채널
```

두 인스턴스는 **같은 valid/ready 사용** (병렬 동작). 본 프로젝트의 [qpsk_frame_sync_top.sv](../src/rtl/qpsk_frame_sync_top.sv) 코드:

```verilog
// 입력측: 둘 다 ready 일 때만 valid 띄움
assign tx_fir_valid = tx_up_valid & (tx_ready_i & tx_ready_q);    // ⚠️ 표준 위반
assign tx_up_ready  = tx_ready_i & tx_ready_q;

// 출력측: 둘 다 valid 일 때만 valid 띄움
assign tx_out_valid = tx_valid_i & tx_valid_q;
```

→ I/Q 가 **같은 클럭 엣지에 함께 진행** 되어 위상 정합 보장.

### ⚠️ AXI4-Stream 표준 위반 — `valid` 가 `ready` 에 의존

위 코드의 `tx_fir_valid = tx_up_valid & (tx_ready_i & tx_ready_q)` 는 ARM AMBA AXI4-Stream 사양 §2.2.1 위반:

> **TVALID must not depend on TREADY.**

이유:
- Combinational loop 가능성
- Vivado AXI4 Protocol Checker IP 가 violation 으로 잡음
- 다른 IP 와 통합 시 호환성 문제

표준 준수 패턴:
```verilog
// valid 는 ready 에 무관
assign tx_fir_valid = tx_up_valid;
// ready 만 결합
assign tx_up_ready  = tx_ready_i & tx_ready_q;
```

I/Q 두 FIR 이 동일 latency·동일 동작이라 **본 프로젝트에선 동작상 문제 없음**. 외부 IP 통합 또는 protocol checker 사용 시 수정 필요.

### top-level 연결 구조 — TX 측

```
qpsk_modulator → frame_builder → axis_upsample_zeros
                                         │
                                         ▼ (16-bit symbol-rate × 2 (I/Q))
                                  ┌──────┴───────┐
                                  ▼              ▼
                              fir_rrc(I)     fir_rrc(Q)
                              (16→40b)       (16→40b)
                                  │              │
                                  ▼              ▼
                                  tx_out_i     tx_out_q
                                       (40-bit sample-rate)
```

### top-level 연결 구조 — RX 측

```
rx_in_i, rx_in_q  (40-bit)
        │
        ├──► fir_rrc_rx(I)  ─┐
        │    (40→56b)        │
        │                    ├──► axis_downsample_pick → ...
        └──► fir_rrc_rx(Q)  ─┘
             (40→56b)
                    (56-bit symbol-rate)
```

---

## 6. 핵심 한 그림

```
       Tx 측                         Rx 측
   ┌─────────────┐               ┌──────────────┐
   │  심볼 ±SCALE │               │ 받은 신호    │
   └──────┬──────┘               │ (잡음 포함)  │
          │ zero-insert ×SPS     └──────┬───────┘
          ▼                              │ matched filter
   ┌─────────────┐                ┌──────┴─────────┐
   │  fir_rrc    │  → 채널 →      │   fir_rrc_rx   │
   │ (16→40 b)   │                │   (40→56 b)    │
   │ pulse shape │                │ ISI 제거 + SNR↑│
   └──────┬──────┘                └──────┬─────────┘
          │                                │
          ▼ (TX 출력)             심볼 시점 샘플링 ▼
                                          ↓
                                    심볼 추출
                                  (band-limited,
                                   ISI=0,
                                   matched filter)
```

---

## 7. 핵심 키워드 정리

| 용어 | 의미 |
|---|---|
| **Pulse shaping** | 사각파 → 부드러운 펄스, 대역제한 |
| **ISI** | 다른 심볼의 꼬리가 자기 심볼 시점을 침범하는 간섭 |
| **Nyquist 조건** | 심볼 시점 외 펄스 = 0 → ISI 0 |
| **Sinc** | Nyquist 조건의 이상적 해, 무한대 길이 |
| **Raised Cosine (RC)** | sinc 의 유한 길이 근사, β 로 부드러움 조정 |
| **Root Raised Cosine (RRC)** | RC 의 제곱근. TX·RX 둘 다 통과하면 RC |
| **Matched filter** | RX 측 RRC 의 두 번째 역할 (SNR 최대화) |
| **β (roll-off)** | RC 의 대역폭/부드러움 조정 (0~1) |
| **span** | 펄스 길이 (심볼 단위) |
| **SPS** | 심볼당 샘플 수 (oversampling rate) |
| **Group delay** | FIR 의 위상 지연 = (탭수-1)/2 |
| **Bit growth** | FIR 의 출력 비트폭 증가 (Full Precision 모드) |

---

## 8. 본 프로젝트 RRC 사양 요약

| 항목 | 값 |
|---|---|
| β | 0.35 |
| span | 10 symbols |
| SPS | 4 |
| Taps | 41 |
| Coef width | 16-bit (Q1.15) |
| TX I/O | 16 → 40 bit |
| RX I/O | 40 → 56 bit |
| Group delay (single) | 20 samples = 5 symbols |
| Group delay (TX+RX) | 40 samples = 10 symbols |

---

## 9. 추가 학습 — 이미 본 프로젝트에 있는 자료

1. **[scm_sim_rtl.ipynb](../src/algo/scm_sim_rtl.ipynb)** Section 1 — RRC 계수 시각화, eye diagram
2. **[src/algo/rrc_filter.py](../src/algo/rrc_filter.py)** — RRC 계수 생성 + 양자화 코드
3. **[src/coe/rrc_sps4_beta0p35_span10_q16p.coe](../src/coe/rrc_sps4_beta0p35_span10_q16p.coe)** — 실제 IP 가 사용하는 계수 파일

`rrc_filter.py` 를 보면 RRC 수식이 직접 코드로 표현되어 있어 이론 → 실제 매핑 확인 가능.

---

## 10. 한 줄 요약

> **RRC 는 사각파 심볼을 대역제한된 부드러운 펄스로 정형하면서 ISI 0 을 보장하는 펄스 정형 필터.**
> TX·RX 둘 다 RRC 통과 = 합성 RC = ISI 0. RX 측은 matched filter 역할 동시 수행.
> 본 프로젝트는 β=0.35, span=10, SPS=4 의 41 탭 FIR. Xilinx FIR Compiler IP 로 인스턴스화.

이 배경 이해 위에서:
- TX 통합 (Step 4) 에서 fir_rrc 의 valid/ready 사슬 분석 가능
- RX 통합 (Step 5) 에서 matched filter + downsample 의 group delay 보정 분석 가능
- 추후 채널 효과 (Step 6) 에서 RRC 의 SNR 영향 정량화 가능
