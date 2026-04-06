# Bug Report: Preamble Correlator — Convolution vs Cross-Correlation

| Field | Value |
|-------|-------|
| **Severity** | Critical |
| **Component** | `preamble_correlator.sv` (RTL) |
| **Status** | Fixed (RTL + Python) |
| **Detected** | 2026-04-06 |
| **Affects** | Frame synchronization, all RX data recovery |

---

## 1. Summary

`preamble_correlator.sv`가 cross-correlation(상호상관) 대신 convolution(합성곱)을 계산합니다.
이 preamble 시퀀스는 palindrome(회문)이 아니기 때문에, **정확한 preamble 정렬 위치에서
상관 출력이 0**이 됩니다. 프레임 동기화가 근본적으로 불가능합니다.

---

## 2. Root Cause

### 2.1 문제의 수식

Shift register는 입력을 시간 역순으로 저장합니다:

```
shift_i[0] = rx[n]        (최신)
shift_i[1] = rx[n-1]
    ...
shift_i[k] = rx[n-k]
    ...
shift_i[L-1] = rx[n-L+1]  (가장 오래된)
```

**현재 구현 (convolution):**

```
C[n] = Σ(k=0..L-1) shift_i[k] × p[k]
     = Σ(k=0..L-1) rx[n-k] × p[k]          ... (1)
```

**정확한 구현 (cross-correlation / matched filter):**

```
R[n] = Σ(k=0..L-1) shift_i[k] × p[L-1-k]
     = Σ(k=0..L-1) rx[n-k] × p[L-1-k]      ... (2)
```

수식 (1)과 (2)의 차이는 reference preamble의 인덱싱 방향입니다.

### 2.2 왜 이것이 문제인가

Preamble이 시간 순서대로 송신됩니다: `p[0], p[1], ..., p[L-1]`

수신측에서 preamble이 완전히 shift register에 들어왔을 때 (n = preamble 끝):

```
shift_i[0] = p[L-1]   (마지막 송신 심볼)
shift_i[1] = p[L-2]
    ...
shift_i[k] = p[L-1-k]
    ...
shift_i[L-1] = p[0]   (처음 송신 심볼)
```

**정확한 구현 (2)의 경우:**

```
R = Σ p[L-1-k] × p[L-1-k] = Σ p[m]² = L × SCALE²
```

이것은 **autocorrelation peak** — 최대값을 줍니다.

**현재 구현 (1)의 경우:**

```
C = Σ p[L-1-k] × p[k]
```

이것은 preamble과 **뒤집힌 preamble의 내적** — preamble이 palindrome이 아니면 최대값이 아닙니다.

### 2.3 이 preamble에서 실제로 어떻게 되는가

Preamble I/Q 시퀀스 (±1 정규화):

```
Index k:    0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15
I:         +1  +1  +1  -1  -1  +1  -1  +1  +1  -1  -1  +1  -1  -1  +1  +1
I_rev:     +1  +1  -1  -1  +1  -1  -1  +1  +1  -1  +1  -1  -1  +1  +1  +1
I mismatch:             *   *   *   *   *           *   *   *   *
```

**I채널**: 16개 중 6개 불일치
**Q채널**: 16개 중 10개 불일치

정확한 정렬 위치에서 계산:

| 값 | Correct (correlation) | Buggy (convolution) |
|----|----------------------|---------------------|
| Real (I) | Σ p_I[k]² = +2,304,000,000 | Σ p_I[L-1-k]·p_I[k] = +576,000,000 |
| Real (Q) | Σ p_Q[k]² = +2,304,000,000 | Σ p_Q[L-1-k]·p_Q[k] = -576,000,000 |
| **Real Total** | **+4,608,000,000** | **0** |
| \|R\|² | **2.123 × 10¹⁹** | **≈ 0** |

**Convolution의 I 성분(+576M)과 Q 성분(-576M)이 정확히 상쇄되어 0이 됩니다.**

---

## 3. Affected Code

### 3.1 RTL — `preamble_correlator.sv` (lines 81-91)

```systemverilog
always_comb begin
    sum_i = '0;
    sum_q = '0;
    
    for (int k = 0; k < PREAMBLE_LEN; k++) begin
        // Real part: r_I[k]*p_I[k] + r_Q[k]*p_Q[k]
        sum_i = sum_i + shift_i[k] * PREAMBLE_I[k]           // ← BUG: p[k]
                      + shift_q[k] * PREAMBLE_Q[k];           // ← BUG: p[k]
        
        // Imag part: r_Q[k]*p_I[k] - r_I[k]*p_Q[k]
        sum_q = sum_q + shift_q[k] * PREAMBLE_I[k]           // ← BUG: p[k]
                      - shift_i[k] * PREAMBLE_Q[k];           // ← BUG: p[k]
    end
end
```

### 3.2 모듈 주석도 틀림 — `preamble_correlator.sv` (lines 7-8)

```systemverilog
//   Computes sliding cross-correlation:
//   R[n] = Σ(k=0 to L-1) { r_I[n-k]·p_I[k] + r_Q[n-k]·p_Q[k] }
```

이 수식은 cross-correlation이 아니라 convolution입니다.
정확한 수식: `R[n] = Σ(k=0 to L-1) { r_I[n-k]·p_I[L-1-k] + r_Q[n-k]·p_Q[L-1-k] }`

### 3.3 관련 파일들

| File | Role | Issue |
|------|------|-------|
| `preamble_correlator.sv:87-90` | Correlation 계산 | `p[k]` → `p[L-1-k]` 필요 |
| `preamble_correlator.sv:7-8` | 주석 수식 | 수식이 convolution을 기술 |
| `frame_builder.sv:157-159` | Preamble 송신 | 정상 (순방향 송신) |
| `frame_sync_detector.sv:122` | Threshold 비교 | 버그로 인해 threshold 의미 없음 |
| `qpsk_frame_sync_top.sv:262-277` | Correlator 인스턴스 | 연결은 정상 |

---

## 4. Observed Symptoms

### 4.1 Python 시뮬레이션 (수정 전)

```
SNR = 20 dB, 200 payload symbols:
  Sync detections: 7 (expected: 1)
  Peak index: 26 (expected: 25)
  BER = 52.25% (expected: 0%)
```

- **7개 false detection**: 실제 peak가 0이므로, noise/ISI에 의한 spurious peak들이 threshold를 넘김
- **Peak 위치 오류**: 실제 정렬 위치가 아닌, ISI가 우연히 만든 최대값 위치에서 detection
- **BER 52%**: 완전 랜덤 (동전 던지기) — frame sync 실패로 payload 추출 위치가 잘못됨

### 4.2 수정 후

```
SNR = 20 dB, 200 payload symbols:
  Sync detections: 1 (correct)
  Peak index: 25 (correct)
  BER = 0.000000e+00 (correct)
```

### 4.3 BER vs SNR 비교

| SNR (dB) | Before Fix | After Fix |
|----------|-----------|-----------|
| -2 | ~50% | 5.4% |
| 0 | ~50% | 2.2% |
| 5 | ~50% | 0% |
| 10 | ~50% | 0% |
| 20 | 52.25% | 0% |

수정 전에는 SNR과 무관하게 BER ≈ 50% — 프레임 동기화 완전 실패를 의미합니다.

---

## 5. Why the Bug Was Not Obvious

### 5.1 RTL 시뮬레이션 부재

프로젝트에 RTL 테스트벤치가 없었습니다 (`scm/src/tb/` 디렉토리 자체가 없었음).
Correlator 출력을 검증하는 end-to-end 시뮬레이션이 수행되지 않았습니다.

### 5.2 Python도 동일한 버그

Python simulation (`scm_sim.py`)의 원래 correlator도 동일한 수식을 사용했습니다:

```python
# 원래 (buggy):
corr_i[n] += rx_i[n - k] * PREAMBLE_I[k]    # p[k] — convolution

# 수정 후:
corr_i[n] += rx_i[n - k] * pI_rev[k]         # p[L-1-k] — correlation
```

RTL과 Python이 같은 버그를 공유했기 때문에, "Python과 RTL이 일치한다"는 검증이
버그를 발견하지 못하게 만들었습니다.

### 5.3 주석이 오해를 유발

`preamble_correlator.sv` line 7의 주석이 "cross-correlation"이라고 기술하고 있지만,
실제 수식은 convolution입니다. 코드 리뷰 시 주석을 신뢰하면 버그를 놓칩니다.

### 5.4 FIR 필터 패턴의 혼동 (Root Cause)

RRC FIR 필터의 계수는 대칭(symmetric)입니다:

```
RRC[k] = RRC[L-1-k]    (e.g., [224, -71, ..., 32767, ..., -71, 224])
```

대칭 계수에서는 `Σ shift[k] × h[k]`가 convolution이든 correlation이든 결과가 동일합니다.
이 프로젝트에서 FIR 필터(`fir_rrc`)와 correlator(`preamble_correlator`)가 같은
shift register + multiply-accumulate 패턴을 사용하므로, **FIR에서 동작하던 `coef[k]`
인덱싱을 correlator에 그대로 적용**한 것이 버그의 직접적 원인으로 추정됩니다.

```systemverilog
// FIR filter (RRC) — 대칭이라 h[k] = h[L-1-k], 문제 없음
y = Σ shift[k] * h[k]

// Correlator (preamble) — 같은 패턴이지만, p[k] ≠ p[L-1-k]이므로 결과가 다름
y = Σ shift[k] * p[k]       // ← convolution (buggy)
y = Σ shift[k] * p[L-1-k]   // ← correlation (correct)
```

### 5.5 ISI 마스킹 효과

Double-RRC 필터링 후 심볼 간 약간의 ISI가 존재합니다.
이 ISI 때문에 shift register의 값이 정확히 ±SCALE이 아니라 약간 변동이 있고,
이로 인해 I/Q 상쇄가 완벽하지 않아 correlator 출력이 완전한 0이 되지 않습니다.
결과적으로 "뭔가 peak 같은 것"이 나오지만, 위치와 크기가 모두 틀립니다.

---

## 6. Sidelobe Analysis

Preamble의 I채널 autocorrelation 특성:

```
          Autocorrelation    Convolution (buggy)
lag  0:       +16                 +4           ← peak 위치
lag  1:        -1                +11
lag  2:        -6                 -6
lag  3:        +3                 -3
lag  4:        -2                 +4
lag  5:        -5                 -5
lag  6:        +4                 -2
lag  7:        +3                 +9
lag  8:        -2                  0
lag  9:        +1                 -5
lag 10:         0                 +2
lag 11:        -3                 +1
lag 12:        -2                 -4
lag 13:        +1                 -1
lag 14:        +2                 +2
lag 15:        +1                 +1
```

**Autocorrelation**: Peak(16) vs max sidelobe(6) = **PSR 2.67:1**
**Convolution (buggy)**: "Peak"(4) vs sidelobe(11) = **PSR 0.36:1** (sidelobe가 "peak"보다 큼!)

Convolution에서는 **peak가 sidelobe보다 작으므로** 프레임 검출이 불가능합니다.

---

## 7. Proposed Fix

### 7.1 RTL Fix — `preamble_correlator.sv`

**Option A: Reference 인덱스 변경 (최소 변경)**

```systemverilog
// Lines 87-90: PREAMBLE_I[k] → PREAMBLE_I[PREAMBLE_LEN-1-k]
for (int k = 0; k < PREAMBLE_LEN; k++) begin
    sum_i = sum_i + shift_i[k] * PREAMBLE_I[PREAMBLE_LEN-1-k]
                  + shift_q[k] * PREAMBLE_Q[PREAMBLE_LEN-1-k];
    sum_q = sum_q + shift_q[k] * PREAMBLE_I[PREAMBLE_LEN-1-k]
                  - shift_i[k] * PREAMBLE_Q[PREAMBLE_LEN-1-k];
end
```

**Option B: Reversed preamble 상수 추가 (가독성 우선)**

```systemverilog
// 새로운 localparam: time-reversed reference
localparam logic signed [15:0] PREAMBLE_I_REV [0:15] = '{
    16'sd12000,  16'sd12000, -16'sd12000, -16'sd12000,
    16'sd12000, -16'sd12000, -16'sd12000,  16'sd12000,
    16'sd12000, -16'sd12000,  16'sd12000, -16'sd12000,
    -16'sd12000,  16'sd12000,  16'sd12000,  16'sd12000
};

// 계산에서 REV 사용
sum_i = sum_i + shift_i[k] * PREAMBLE_I_REV[k] + ...;
```

### 7.2 주석 수정

```systemverilog
//   Computes sliding cross-correlation (matched filter):
//   R[n] = Σ(k=0 to L-1) { r_I[n-k]·p_I[L-1-k] + r_Q[n-k]·p_Q[L-1-k] }
//        + j·{ r_Q[n-k]·p_I[L-1-k] - r_I[n-k]·p_Q[L-1-k] }
```

### 7.3 Python은 이미 수정됨

`scm_sim.py` lines 148-149:

```python
pI_rev = PREAMBLE_I[::-1]
pQ_rev = PREAMBLE_Q[::-1]
```

### 7.4 합성 영향

- 로직 변경 없음 (같은 곱셈기, 같은 덧셈기)
- 변경되는 것은 localparam 상수 값뿐
- 타이밍/면적 영향 없음

---

## 8. Verification Plan

| Test | Method | Expected |
|------|--------|----------|
| RTL unit test | `tb_preamble_correlator.sv` + Python 벡터 | Peak 위치 = preamble 끝, |R|² = 2.12×10¹⁹ |
| RTL→Python 비교 | 동일 입력에 대해 RTL/Python 출력 bit-exact 비교 | 정규화 후 일치 |
| End-to-end loopback | `qpsk_frame_sync_top` TB | BER = 0 at SNR ≥ 10dB |
| Noise robustness | SNR sweep (-2 ~ 20 dB) | BER curve가 이론값에 수렴 |

---

## 9. Lessons Learned

1. **Cross-validation의 함정**: RTL과 Python이 같은 버그를 공유하면, 둘을 비교하는 것으로는 버그를 발견할 수 없습니다. 독립적인 reference (수식, 교과서, 다른 구현)가 필요합니다.

2. **주석을 신뢰하지 마세요**: 코드가 "cross-correlation"이라고 주석에 써있어도, 실제 구현이 convolution일 수 있습니다. 수식을 직접 검증해야 합니다.

3. **Shift register 방향 주의**: FIR 필터/correlator에서 shift register를 사용할 때, `h[k]`와 `h[L-1-k]`의 차이는 convolution vs correlation의 차이입니다. 이 구분은 symmetric 필터에서는 문제가 안 되지만, asymmetric reference에서는 치명적입니다.

4. **End-to-end 테스트벤치 필수**: 개별 블록이 아닌 전체 TX→Channel→RX 체인을 테스트해야 이런 종류의 시스템 레벨 버그를 잡을 수 있습니다.
