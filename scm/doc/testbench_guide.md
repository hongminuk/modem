# Testbench Guide

## 1. 디렉토리 구조

```
scm/src/tb/
├── run_all.sh                          # 실행 스크립트
│
├── tb_qpsk_modulator.sv                # 1. QPSK 변조기 TB
├── tb_qpsk_demodulator.sv              # 2. QPSK 복조기 TB
├── tb_frame_builder.sv                 # 3. 프레임 빌더 TB
├── tb_axis_upsample_zeros.sv           # 4. 업샘플러 TB
├── tb_axis_downsample_pick.sv          # 5. 다운샘플러 TB
├── tb_preamble_correlator.sv           # 6. 프리앰블 상관기 TB
├── tb_frame_sync_detector.sv           # 7. 프레임 동기 검출기 TB
├── tb_loopback_no_fir.sv              # 8. End-to-End 루프백 TB
│
├── wave_tb_*.tcl                       # 각 TB의 파형 설정 (8개)
│
├── tv_*.hex                            # Python 생성 테스트 벡터
│
└── ../algo/gen_test_vectors.py         # 테스트 벡터 생성 스크립트
```

---

## 2. 요구사항

- Vivado 2024.2+ (xvlog, xelab, xsim)
- Python 3 + NumPy (테스트 벡터 생성용)

---

## 3. 빠른 시작

### 전체 TB 실행 (텍스트 모드)

```bash
cd scm/src/tb
./run_all.sh
```

출력 예시:

```
========================================
 Running all 8 testbenches
========================================

--- [1/8] tb_qpsk_modulator ---
  PASS
--- [2/8] tb_qpsk_demodulator ---
  PASS
...
--- [8/8] tb_loopback_no_fir ---
  PASS

========================================
 Results: 8 PASS / 0 FAIL / 8 total
========================================
```

### 특정 TB를 GUI 파형으로 열기

```bash
./run_all.sh gui tb_qpsk_modulator
./run_all.sh gui tb_loopback_no_fir
```

Vivado Simulator GUI가 열리고, 파형이 자동으로 추가됩니다.

---

## 4. 수동 실행 (3단계)

```bash
cd scm/src/tb

# Step 1: 컴파일
xvlog -sv ../rtl/qpsk_modulator.sv tb_qpsk_modulator.sv

# Step 2: 엘라보레이트
xelab -debug typical tb_qpsk_modulator -s sim_mod

# Step 3a: 텍스트 실행
xsim sim_mod -runall

# Step 3b: GUI 파형 실행 (3a 대신)
xsim sim_mod -gui -tclbatch wave_tb_qpsk_modulator.tcl
```

### End-to-End TB (여러 RTL 파일)

```bash
xvlog -sv \
  ../rtl/qpsk_modulator.sv \
  ../rtl/qpsk_demodulator.sv \
  ../rtl/frame_builder.sv \
  ../rtl/axis_upsample_zeros.sv \
  ../rtl/axis_downsample_pick.sv \
  ../rtl/preamble_correlator.sv \
  ../rtl/frame_sync_detector.sv \
  tb_loopback_no_fir.sv

xelab -debug typical tb_loopback_no_fir -s sim_loop
xsim sim_loop -gui -tclbatch wave_tb_loopback_no_fir.tcl
```

### 임시파일 정리

```bash
rm -rf xsim.dir .Xil *.jou *.log *.pb *.wdb webtalk*
```

---

## 5. 테스트 벡터 재생성

RTL 코드를 수정한 후 테스트 벡터를 갱신해야 합니다:

```bash
cd scm/src/algo
python3 gen_test_vectors.py
```

생성되는 파일:

| 파일 | 내용 | 사용하는 TB |
|------|------|-------------|
| `tv_tx_bits.hex` | TX 입력 비트 (2-bit) | modulator |
| `tv_mod_i.hex`, `tv_mod_q.hex` | 변조기 출력 I/Q | modulator |
| `tv_frame_i.hex`, `tv_frame_q.hex` | 프레임 출력 I/Q | demodulator, frame_builder |
| `tv_demod_bits.hex` | 복조 예상 출력 | demodulator |
| `tv_fb_payload_i/q.hex` | 프레임빌더 payload 입력 | frame_builder |
| `tv_fb_out_i/q.hex` | 프레임빌더 출력 | frame_builder, upsample |
| `tv_up_out_i/q.hex` | 업샘플 출력 | upsample, downsample |
| `tv_ds_out_i/q.hex` | 다운샘플 출력 | downsample |
| `tv_corr_in_i/q.hex` | 상관기 입력 | correlator |
| `tv_corr_out_i/q.hex` | 상관기 출력 | correlator |

---

## 6. 테스트벤치 상세

### TB 1: `tb_qpsk_modulator`

| 항목 | 값 |
|------|-----|
| DUT | `qpsk_modulator.sv` |
| 벡터 수 | 20 bit-pairs |
| 검증 | Python 출력과 bit-exact 비교 |
| 핵심 확인 | bit 0 → +12000, bit 1 → -12000 매핑 |

### TB 2: `tb_qpsk_demodulator`

| 항목 | 값 |
|------|-----|
| DUT | `qpsk_demodulator.sv` |
| 벡터 수 | 36 symbols (preamble + payload) |
| 검증 | I/Q sign bit → 2-bit 복원 |
| 핵심 확인 | positive → 0, negative → 1 |

### TB 3: `tb_frame_builder`

| 항목 | 값 |
|------|-----|
| DUT | `frame_builder.sv` |
| 벡터 수 | 16 preamble + 20 payload = 36 |
| 검증 | Preamble 패턴 + payload 순서 |
| 핵심 확인 | IDLE → PREAMBLE → PAYLOAD state machine |

### TB 4: `tb_axis_upsample_zeros`

| 항목 | 값 |
|------|-----|
| DUT | `axis_upsample_zeros.sv` |
| 벡터 수 | 36 symbols → 144 samples |
| 검증 | Phase 0 = symbol, Phase 1-3 = zero |
| 핵심 확인 | SPS=4 zero-insertion |

### TB 5: `tb_axis_downsample_pick`

| 항목 | 값 |
|------|-----|
| DUT | `axis_downsample_pick.sv` |
| 벡터 수 | 144 samples → 36 symbols |
| 검증 | Upsample의 역연산 |
| 핵심 확인 | OFFSET=0에서 원래 심볼 복원 |

### TB 6: `tb_preamble_correlator`

| 항목 | 값 |
|------|-----|
| DUT | `preamble_correlator.sv` |
| 벡터 수 | 36 symbols |
| 검증 | Python 상관 출력과 비교 (1-cycle offset) |
| 핵심 확인 | Peak 위치 = index 16 (RTL), corr_I = 4,608,000,000 |

> **참고**: RTL은 registered output으로 Python 대비 1-clock 지연.
> RTL index 16 = Python index 15. TB는 이를 보정하여 비교합니다.

### TB 7: `tb_frame_sync_detector`

| 항목 | 값 |
|------|-----|
| DUT | `frame_sync_detector.sv` |
| 벡터 수 | 36 (합성 테스트 입력) |
| 검증 | 1회 sync detection, cooldown 동작 |
| 핵심 확인 | Peak index 정확, false detection 없음 |

### TB 8: `tb_loopback_no_fir`

| 항목 | 값 |
|------|-----|
| DUT | 전체 체인 (FIR 제외) |
| 데이터 | LFSR 50 symbols (100 bits) |
| 검증 | TX bits == RX demod bits |
| 핵심 확인 | BER = 0, sync detection 1회 |

> **참고**: Xilinx FIR Compiler IP 없이 동작. Upsample → Downsample 직결 루프백.
> Payload offset = PREAMBLE_LEN + 1 = 17 (modulator pipeline delay).
> 49/50 payload symbols 검증 (마지막 1개는 pipeline 밖으로 밀림).

---

## 7. 파형 Tcl 파일

각 `wave_tb_*.tcl` 파일은 다음을 수행합니다:

1. `log_wave -recursive *` — 전체 신호 기록
2. `add_wave` — 주요 신호를 그룹별로 파형 뷰어에 추가
3. `run -all` — 시뮬레이션 실행

**파형 그룹 구성:**

| 그룹 | 포함 신호 |
|------|-----------|
| Clock/Reset | clk, rst_n |
| TX Input | tx_bits, valid, ready |
| Symbol I/Q | 각 블록의 I/Q 출력 (decimal 표시) |
| Handshake | valid, ready 쌍 |
| Internal | state machine, counter, phase 등 |
| Sync | sync_found, sync_index, sync_mag |

---

## 8. 새 TB 추가 방법

1. `tb_<module_name>.sv` 작성
2. `wave_tb_<module_name>.tcl` 작성
3. `run_all.sh`의 `TBS` 배열에 추가:
   ```bash
   "tb_<module_name>:<rtl_file1>.sv <rtl_file2>.sv"
   ```
4. 필요시 `gen_test_vectors.py`에 테스트 벡터 추가
