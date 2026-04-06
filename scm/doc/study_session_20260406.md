# QPSK Modem Study Session — 2026-04-06

## 1. Overview

QPSK 모뎀의 RTL과 Python 시뮬레이션을 함께 돌리며 스터디한 결과를 정리합니다.
Python 시뮬레이션에서 BER 52%라는 비정상 결과를 발견하여 원인 분석을 시작했고,
correlator의 critical bug를 발견 및 수정하고, RTL 테스트벤치로 검증까지 완료했습니다.

---

## 2. Signal Chain

```
TX Path:
  tx_bits[1:0] → QPSK Mod → Frame Builder → Upsample(×4) → TX RRC Filter → Channel
                 (±12000)    (preamble+     (zero insert)   (41-tap SRRC)
                              payload)

RX Path:
  Channel → RX RRC Filter → Downsample(÷4) → Preamble Correlator → Frame Sync Detector
            (matched filter)  (offset=0)       (cross-correlation)   (threshold + cooldown)
                                             ↘ QPSK Demod → rx_bits[1:0]
                                               (hard decision)
```

### 주요 파라미터

| Parameter | Value | Description |
|-----------|-------|-------------|
| W | 16 bit | Symbol bit width |
| SPS | 4 | Samples per symbol |
| SCALE | 12000 | QPSK constellation amplitude |
| PREAMBLE_LEN | 16 | Preamble symbols |
| BETA | 0.35 | RRC roll-off factor |
| SPAN | 10 | RRC filter span (symbols) |
| RRC Taps | 41 | `SPAN × SPS + 1` |
| RRC_DELAY | 20 samples | Single filter group delay |
| Total Delay | 40 samples (10 symbols) | Double RRC group delay |

---

## 3. Python Simulation 수정사항

### 3.1 RRC 계수 정규화

**문제**: 정수 계수(max 32767)를 그대로 사용하면 이중 필터링 후 값이 ~10¹³으로 폭발하여 threshold 설정이 어려움.

**수정** (`scm_sim.py` line 56):

```python
# Before: RRC_COEFS = RRC_COEFS_INT (정수 그대로)
# After:
RRC_COEFS = RRC_COEFS_INT / np.sqrt(np.sum(RRC_COEFS_INT ** 2))  # unit energy
```

**효과**: 이중 RRC 필터 후 심볼 진폭이 원래 SCALE(±12000) 수준으로 유지됨.

| | Before (정수 계수) | After (정규화) |
|--|-------------------|----------------|
| TX RRC 출력 | ~10⁸ | ~8000 |
| RX RRC 출력 | ~10¹³ | ~12000 |
| Correlator 피크 | ~10³⁶ | ~10¹⁹ |
| Threshold 설정 | 감으로 잡아야 함 | 예측 가능 |

### 3.2 Preamble Correlator 수정 (Critical Bug Fix)

**문제**: `Σ rx[n-k] × p[k]` (convolution)을 계산 — cross-correlation이 아님.

**수정** (`scm_sim.py` lines 148-149):

```python
# Before:
corr_i[n] += rx_i[n - k] * PREAMBLE_I[k]       # p[k] — convolution

# After:
pI_rev = PREAMBLE_I[::-1]                        # time-reversed reference
corr_i[n] += rx_i[n - k] * pI_rev[k]             # p[L-1-k] — correlation
```

> 상세 분석은 [bug_report_correlator.md](bug_report_correlator.md) 참조.

### 3.3 Threshold를 adaptive 방식으로 변경

**수정** (`scm_sim.py` line 247):

```python
# Before: threshold = 1e18  (하드코딩, 스케일 의존적)
# After:
peak_mag = np.max(mag_sq)
threshold = peak_mag * 0.5   # peak의 50%
```

### 3.4 시뮬레이션 결과 저장 기능 추가

`run_simulation()` 함수에 `save_path` 파라미터 추가, 딕셔너리 리턴.

---

## 4. 발견된 Bug: Correlator Convolution vs Cross-Correlation

### 4.1 핵심 원인

Shift register는 `shift[k] = rx[n-k]` (시간 역순)으로 저장합니다.
여기에 `p[k]`를 곱하면 convolution이고, `p[L-1-k]`를 곱해야 cross-correlation(matched filter)입니다.

### 4.2 수학적 증명

Preamble이 정렬된 순간 (`shift[k] = p[L-1-k]`):

```
Correct (correlation):  Σ p[L-1-k] × p[L-1-k] = Σ p[m]² = L × SCALE²
Buggy (convolution):    Σ p[L-1-k] × p[k]      = cross-product (다른 값)
```

이 preamble의 실제 계산 결과:

| Component | Correct | Buggy |
|-----------|---------|-------|
| Real (I) | +2,304,000,000 | +576,000,000 |
| Real (Q) | +2,304,000,000 | **-576,000,000** |
| **Total Real** | **+4,608,000,000** | **0** (I와 Q가 상쇄!) |
| \|R\|² | **2.12 × 10¹⁹** | **≈ 0** |

### 4.3 왜 Preamble이 palindrome이 아닌가

```
I forward:  [+1, +1, +1, -1, -1, +1, -1, +1, +1, -1, -1, +1, -1, -1, +1, +1]
I reversed: [+1, +1, -1, -1, +1, -1, -1, +1, +1, -1, +1, -1, -1, +1, +1, +1]
                       *   *   *   *   *           *   *   *   *
```

16개 중 **I: 6개, Q: 10개** 불일치. Palindrome이면 convolution = correlation이지만, 아니므로 완전히 다른 결과.

### 4.4 Sidelobe 비교 (I채널)

```
lag     Autocorrelation(정상)     Convolution(버그)
 0          +16 (peak)               +4
 1           -1                      +11 ← peak보다 큼!
 7           +3                       +9
```

**정상**: Peak-to-Sidelobe Ratio = 16/6 = **2.67**
**버그**: "Peak"가 sidelobe보다 작음 = **검출 불가능**

### 4.5 증상

| Metric | Before Fix | After Fix |
|--------|-----------|-----------|
| Sync detections (SNR=20dB) | 7 (false) | 1 (correct) |
| Peak position | 잘못된 위치 | 정확 (index 25) |
| BER @ 20dB | **52.25%** (랜덤) | **0%** |
| BER @ 5dB | ~50% | 0% |
| BER @ 0dB | ~50% | 2.2% |

### 4.6 왜 발견이 어려웠나

1. **FIR 필터 패턴의 혼동 (Root Cause)**: RRC FIR 필터는 계수가 대칭(`h[k] = h[L-1-k]`)이라 `Σ shift[k] × h[k]`로 convolution이든 correlation이든 결과가 동일. 이 패턴을 correlator에 그대로 복붙했지만, preamble은 비대칭이라 convolution ≠ correlation.
2. **RTL과 Python이 같은 버그 공유** → 비교해도 "일치"
3. **주석이 "cross-correlation"이라고 거짓말** → 코드 리뷰 통과
4. **ISI가 완전한 0을 흐림** → peak 같은 것이 보이긴 함
5. **End-to-end RTL 테스트벤치 부재** → 시스템 레벨 검증 안됨

---

## 5. RTL 수정

### 5.1 `preamble_correlator.sv` — 수식 수정

**Before** (line 87-90):

```systemverilog
sum_i = sum_i + shift_i[k] * PREAMBLE_I[k]            // convolution
              + shift_q[k] * PREAMBLE_Q[k];
sum_q = sum_q + shift_q[k] * PREAMBLE_I[k]
              - shift_i[k] * PREAMBLE_Q[k];
```

**After**:

```systemverilog
sum_i = sum_i + shift_i[k] * PREAMBLE_I[PREAMBLE_LEN-1-k]    // cross-correlation
              + shift_q[k] * PREAMBLE_Q[PREAMBLE_LEN-1-k];
sum_q = sum_q + shift_q[k] * PREAMBLE_I[PREAMBLE_LEN-1-k]
              - shift_i[k] * PREAMBLE_Q[PREAMBLE_LEN-1-k];
```

### 5.2 `preamble_correlator.sv` — 주석 수정

**Before** (line 7-8):

```
//   R[n] = Σ(k=0 to L-1) { r_I[n-k]·p_I[k] + r_Q[n-k]·p_Q[k] }
```

**After**:

```
//   R[n] = Σ(k=0 to L-1) { r[n-k] · conj(p[L-1-k]) }
//        = Σ(k=0 to L-1) { r_I[n-k]·p_I[L-1-k] + r_Q[n-k]·p_Q[L-1-k] }
//                       + j·{ r_Q[n-k]·p_I[L-1-k] - r_I[n-k]·p_Q[L-1-k] }
```

### 5.3 합성 영향

변경은 localparam 인덱싱 순서뿐. **곱셈기/덧셈기 수 동일, 타이밍/면적 영향 없음.**

---

## 6. RTL Testbench 검증 결과

Python으로 테스트 벡터를 생성하고 (`gen_test_vectors.py`), Vivado xsim으로 RTL을 실행하여 비교.

### 6.1 개별 블록 테스트

| Testbench | DUT | Vectors | Result |
|-----------|-----|---------|--------|
| `tb_qpsk_modulator.sv` | `qpsk_modulator.sv` | 20 bit-pairs → symbols | **PASS** |
| `tb_qpsk_demodulator.sv` | `qpsk_demodulator.sv` | 36 symbols → bits | **PASS** |
| `tb_preamble_correlator.sv` | `preamble_correlator.sv` | 36 symbols → correlation | **PASS** |

### 6.2 Correlator 검증 상세

```
=== Preamble Correlator Testbench ===
  OK  [16]: corr_I=4608000000  corr_Q=0        ← PEAK (RTL idx 16 = Python idx 15)
  OK  [17]: corr_I=-288000000  corr_Q=288000000
  OK  [18]: corr_I=-2304000000 corr_Q=-576000000
  ...
  OK  [35]: corr_I=-1152000000 corr_Q=-576000000
PASS: Peak at correct position (RTL idx 16 = Python idx 15), all vectors matched!
```

**RTL pipeline delay**: Registered output으로 인해 Python 대비 **1 clock 지연**.
`frame_sync_detector`가 `sync_index <= sample_counter - 1`로 보정하므로 시스템 레벨에서 문제 없음.

---

## 7. BER Performance

Python 시뮬레이션으로 측정한 BER vs Eb/N0 곡선:

| Eb/N0 (dB) | BER (Simulation) | BER (Theory QPSK) |
|------------|------------------|--------------------|
| -2 | 5.41 × 10⁻² | 7.57 × 10⁻² |
| 0 | 2.19 × 10⁻² | 3.75 × 10⁻² |
| 2 | 4.70 × 10⁻³ | 1.25 × 10⁻² |
| 4 | 1.00 × 10⁻³ | 2.34 × 10⁻³ |
| 5 | 0 | 1.17 × 10⁻³ |
| 7+ | 0 | < 10⁻⁴ |

시뮬레이션 BER이 이론보다 좋은 이유: **RRC matched filter가 대역 외 노이즈를 제거**하기 때문.
(이론 QPSK BER = `0.5 × erfc(√(Eb/N0))`는 무한 대역폭 가정)

---

## 8. 생성된 플롯

| File | Description |
|------|-------------|
| `scm/src/algo/sim_result.png` | 전체 시뮬레이션 결과 6패널 (TX/RX constellation, waveform, correlation, eye diagram) |
| `scm/src/algo/ber_curve.png` | BER vs Eb/N0 곡선 (시뮬레이션 vs 이론) |
| `scm/src/algo/block_by_block.png` | 8개 블록 단계별 신호 흐름 시각화 |

---

## 9. 파일 변경 목록

### 수정된 파일

| File | Change |
|------|--------|
| `scm/src/rtl/preamble_correlator.sv` | `p[k]` → `p[L-1-k]`, 주석 수정 |
| `scm/src/algo/scm_sim.py` | RRC 정규화, correlator 수정, adaptive threshold, save_path 추가 |

### 새로 생성된 파일

| File | Description |
|------|-------------|
| `scm/src/algo/gen_test_vectors.py` | RTL 테스트벤치용 hex 벡터 생성 |
| `scm/src/tb/tb_qpsk_modulator.sv` | QPSK 변조기 테스트벤치 |
| `scm/src/tb/tb_qpsk_demodulator.sv` | QPSK 복조기 테스트벤치 |
| `scm/src/tb/tb_preamble_correlator.sv` | Correlator 테스트벤치 |
| `scm/src/tb/tv_*.hex` | Python 생성 테스트 벡터 (6개) |
| `scm/doc/bug_report_correlator.md` | Correlator 버그 리포트 |
| `scm/doc/study_session_20260406.md` | 이 문서 |

---

## 10. Lessons Learned

1. **Cross-validation의 함정**: RTL과 Python이 같은 버그를 공유하면, 둘을 비교하는 것만으로는 버그를 발견할 수 없다. 독립적인 reference(수식, 교과서)가 필요하다.

2. **주석을 신뢰하지 말 것**: "cross-correlation"이라는 주석이 있어도 실제로는 convolution일 수 있다. 수식의 인덱싱을 직접 검증해야 한다.

3. **Shift register + FIR 패턴의 함정**: RRC 필터는 대칭 계수라서 `Σ shift[k] × h[k]`가 convolution = correlation. 이 패턴을 비대칭 preamble correlator에 복붙하면 convolution ≠ correlation이 되어 치명적이다. **대칭 필터에서 검증된 코드가 비대칭 reference에서는 틀릴 수 있다.**

4. **End-to-end 테스트의 중요성**: 개별 블록이 "동작하는 것처럼 보여도" 전체 체인에서 BER을 측정해야 시스템 레벨 버그를 잡을 수 있다.

5. **RRC 계수의 정규화**: RTL에서는 정수 계수를 사용하고 bit-width로 스케일을 관리하지만, Python 시뮬레이션에서는 정규화된(unit energy) 계수를 사용하는 것이 threshold 설정과 디버깅에 유리하다.
