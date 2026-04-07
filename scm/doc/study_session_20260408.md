# QPSK Modem Study Session — 2026-04-08

## 1. Overview

이전 세션(2026-04-06)에서 discovered한 correlator 버그를 RTL에 반영하고, 추가로 8개의 RTL 테스트벤치를 작성하여 검증했습니다.
이번 세션에서는 **실제 `qpsk_frame_sync_top` 모듈을 DUT로 하는 9번째 TB**를 만드는 과정에서 **추가 RTL 버그 2개**를 발견 및 수정했습니다.

최종 결과: **9개 TB 모두 PASS, end-to-end BER = 0/100 (with FIR IP).**

---

## 2. 발견된 새 RTL 버그

### Bug #2: `qpsk_frame_sync_top.sv` — Multiple Driver on `rx_dn_ready` (Critical)

**위치**: `scm/src/rtl/qpsk_frame_sync_top.sv` lines 234, 249, 253, 272 (수정 전)

**증상**:

```
ERROR: [VRFC 10-3823] variable 'rx_dn_ready' might have multiple concurrent drivers
[/home/hong/workspace_claude/modem/scm/src/rtl/qpsk_frame_sync_top.sv:272]
```

**원인**: 단일 wire `rx_dn_ready`가 두 모듈의 출력 포트(`in_ready`)에 동시 연결됨.

```systemverilog
// BEFORE (BUG):
logic rx_dn_ready;  // 단일 wire

axis_downsample_pick u_rx_downsample (
    .in_ready(rx_dn_ready),     // OUTPUT — 구동 #1
    .out_ready(rx_dn_ready)     // INPUT  — 같은 wire
);

preamble_correlator u_correlator (
    .in_ready(rx_dn_ready)      // OUTPUT — 구동 #2 (충돌!)
);
```

`axis_downsample_pick.in_ready`와 `preamble_correlator.in_ready`는 둘 다 출력 포트(backpressure 신호)인데, 같은 wire에 묶여 있어 multi-driver 충돌 발생.

**수정**: 두 개의 별도 wire로 분리.

```systemverilog
// AFTER (FIXED):
logic rx_dn_in_ready;   // downsample → upstream(FIR) backpressure
logic rx_dn_out_ready;  // correlator → downsample backpressure

assign rx_fir_ready = rx_dn_in_ready;

axis_downsample_pick u_rx_downsample (
    .in_ready(rx_dn_in_ready),
    .out_ready(rx_dn_out_ready)
);

preamble_correlator u_correlator (
    .in_ready(rx_dn_out_ready)
);
```

**왜 발견이 늦었는가**:
- 이전에는 RTL 시뮬레이션 환경에서 top 모듈을 elaborate한 적이 없었음
- Vivado 합성은 multi-driver를 silently 한쪽만 선택해서 통과시키는 경우가 있음
- `tb_loopback_no_fir.sv`는 top 모듈 대신 내부 블록을 개별 인스턴스화했기 때문에 이 버그를 못 잡음

---

### Bug #3: `frame_sync_detector.sv` — THRESHOLD Parameter Width Mismatch (Medium)

**위치**: `scm/src/rtl/frame_sync_detector.sv` line 25, `qpsk_frame_sync_top.sv` line 35

**증상**:

```
=== qpsk_frame_sync_top Testbench ===
  >> SYNC at index 1
  >> SYNC at index 2
  >> SYNC at index 3
  ...
  >> SYNC at index 64       (한 프레임에 64회 false detection!)
```

**원인**: 파라미터 width 불일치로 silent truncation.

```systemverilog
// frame_sync_detector.sv (BEFORE):
module frame_sync_detector #(
    parameter int W_CORR    = 72,
    parameter int THRESHOLD = 32'd1000000000  // ← 32-bit int
)(...);

// qpsk_frame_sync_top.sv (BEFORE):
parameter longint SYNC_THRESHOLD = 64'd500000000  // ← 64-bit 선언
...
frame_sync_detector #(
    .THRESHOLD(SYNC_THRESHOLD)  // ← 64-bit → 32-bit 잘림
) u_detector (...);
```

`int`는 SystemVerilog에서 32-bit. 64-bit `longint`를 전달하면 lower 32-bit만 남음. 그런데 detector 내부 비교는:

```systemverilog
if (mag_sq_d1[127:64] > THRESHOLD)
```

`mag_sq_d1[127:64]`은 64-bit인데 `THRESHOLD`는 32-bit이라 zero-extended 비교됨. 32-bit 최댓값 약 2.1×10⁹인데, FIR 후 `mag_sq[127:64]`는 보통 10¹⁸~10¹⁹ 수준 → **모든 샘플에서 false trigger**.

**수정**: 파라미터 타입을 `longint`로 변경.

```systemverilog
// frame_sync_detector.sv (AFTER):
module frame_sync_detector #(
    parameter int      W_CORR    = 72,
    parameter longint  THRESHOLD = 64'd1000000000  // ← 64-bit
)(...);
```

**검증 결과**: `SYNC_THRESHOLD = 64'd10_000_000_000_000_000_000` (1e19) 적용 후

```
Sync detections: 2  (한 프레임당 1회 — 정확)
Best alignment: offset=26, errors=0 / 100
PASS: BER = 0/100
```

---

## 3. 새 Testbench: `tb_qpsk_frame_sync_top.sv`

### 3.1 특징

| 항목 | 값 |
|------|-----|
| DUT | `qpsk_frame_sync_top.sv` (실제 top 모듈) |
| 포함 | 최신 QPSK mod/demod, 수정된 correlator, 실제 Xilinx FIR IP |
| 데이터 | LFSR 100 symbols (200 bits) + dummy flush frame |
| 검증 | BER 측정, sync detection 카운트, alignment search |

### 3.2 FIR IP 컴파일 방법 발견

Vivado 2024.2의 precompiled FIR Compiler 라이브러리:

```
/tools/Xilinx/Vivado/2024.2/data/xsim/ip/fir_compiler_v7_2_23
```

컴파일 절차:

```bash
# 1. FIR IP VHDL을 xil_defaultlib에 컴파일
xvhdl -work xil_defaultlib \
  ../../Vivado_Project/single_carrier_modem.gen/sources_1/ip/fir_rrc/sim/fir_rrc.vhd \
  ../../Vivado_Project/single_carrier_modem.gen/sources_1/ip/fir_rrc_rx/sim/fir_rrc_rx.vhd

# 2. MIF 계수 파일을 작업 디렉토리에 복사
cp .../fir_rrc/fir_rrc.mif .
cp .../fir_rrc_rx/fir_rrc_rx.mif .

# 3. RTL + TB 컴파일
xvlog -sv ../rtl/*.sv tb_qpsk_frame_sync_top.sv

# 4. Elaborate (xil_defaultlib + fir_compiler_v7_2_23 라이브러리 링크)
xelab -L xil_defaultlib -L fir_compiler_v7_2_23 tb_qpsk_frame_sync_top -s sim_top

# 5. 실행
xsim sim_top -runall
```

### 3.3 디버깅 과정

처음에는 BER이 매우 높게 나왔는데, 단계별로 원인 파악:

| 시도 | Threshold | 결과 | 원인 |
|------|-----------|------|------|
| 1 | `64'd1` | 64 sync detections (false) | THRESHOLD 32-bit truncation (Bug #3) |
| 2 | `64'h7FFFFFFF` | 동일 | (Bug #3 미수정) |
| 3 | `64'd10_000_000_000_000_000_000` (1e19) (Bug #3 수정 후) | 1 sync, 34 errors | Alignment search 범위 좁음 |
| 4 | + alignment 범위 확대 + payload 100 + flush frame | **0 errors** | PASS! |

### 3.4 핵심 깨달음

- FIR group delay (~10 symbols) 때문에 demod stream에서 payload offset이 ~26 위치에 있음
- 단일 frame만 보내면 마지막 ~10 symbols가 FIR 안에 갇혀서 빠져나오지 못함 → **두 번째 dummy frame을 보내서 FIR pipeline을 flush**
- Sync index와 demod stream offset 매칭이 까다로움 → **wide alignment search**로 해결

---

## 4. Test Vector 생성 스크립트 보정

새 TB에서는 RTL과 Python 사이의 직접 비교가 아니라 sync 위치 + BER만 검증하므로 별도 hex 벡터 생성 불필요. 기존 8개 TB는 그대로 유지.

---

## 5. 최종 검증 결과

### 5.1 9개 TB 전부 PASS

```
========================================
 Running all 9 testbenches
========================================

--- [1/9] tb_qpsk_modulator ---       PASS
--- [2/9] tb_qpsk_demodulator ---     PASS
--- [3/9] tb_frame_builder ---        PASS
--- [4/9] tb_axis_upsample_zeros ---  PASS
--- [5/9] tb_axis_downsample_pick --- PASS
--- [6/9] tb_preamble_correlator ---  PASS
--- [7/9] tb_frame_sync_detector ---  PASS
--- [8/9] tb_loopback_no_fir ---      PASS
--- [9/9] tb_qpsk_frame_sync_top ---  PASS  ← NEW with FIR IP

========================================
 Results: 9 PASS / 0 FAIL / 9 total
========================================
```

### 5.2 End-to-End 결과

```
=== qpsk_frame_sync_top Testbench (with FIR IP) ===
  >> SYNC: index=26, mag=14794049535802713184   ← 첫 frame
TX: 100 payload bit-pairs sent
  >> SYNC: index=142, mag=14768134461927102823  ← 두 번째 frame
RX symbols collected: 232
Sync detections:      2
Best alignment: offset=26, errors=0 / 100
PASS: End-to-end (with FIR) BER = 0/100!
```

---

## 6. 누적 발견 RTL 버그 (3개)

| # | 파일 | 버그 | 발견 세션 | 상태 |
|---|------|------|----------|------|
| 1 | `preamble_correlator.sv` | Convolution 대신 cross-correlation 계산 (`p[k]` → `p[L-1-k]`) | 2026-04-06 | FIXED |
| 2 | `qpsk_frame_sync_top.sv` | Multi-driver on `rx_dn_ready` (downsample와 correlator의 `in_ready` 충돌) | 2026-04-08 | FIXED |
| 3 | `frame_sync_detector.sv` | THRESHOLD 파라미터 32-bit (`int`) — 64-bit 비교 시 silent truncation | 2026-04-08 | FIXED |

세 버그 모두 **end-to-end RTL 테스트벤치 부재**가 공통 원인. 이번 세션에서 만든 9번째 TB가 모든 버그를 한꺼번에 노출시켜 발견 가능하게 함.

---

## 7. 파일 변경 목록

### 수정된 파일

| File | Change |
|------|--------|
| `scm/src/rtl/qpsk_frame_sync_top.sv` | `rx_dn_ready` → `rx_dn_in_ready` + `rx_dn_out_ready` 분리 |
| `scm/src/rtl/frame_sync_detector.sv` | `parameter int THRESHOLD` → `parameter longint THRESHOLD` |
| `scm/src/tb/run_all.sh` | 9번째 TB 추가, FIR IP 자동 컴파일 로직 |
| `scm/doc/testbench_guide.md` | TB #9 섹션 추가 |
| `.gitignore` | `*.mif`, `Vivado_Project/` 추가 |

### 새로 생성된 파일

| File | Description |
|------|-------------|
| `scm/src/tb/tb_qpsk_frame_sync_top.sv` | 실제 top + FIR IP 통합 TB |
| `scm/src/tb/wave_tb_qpsk_frame_sync_top.tcl` | 파형 설정 Tcl |
| `scm/doc/bug_report_top_module.md` | Bug #2 + #3 상세 리포트 |
| `scm/doc/study_session_20260408.md` | 이 문서 |

---

## 8. Lessons Learned

1. **End-to-end RTL TB의 중요성**:
   - 블록 단위 TB는 multi-driver 같은 시스템 레벨 버그를 못 잡음
   - 실제 top 모듈을 elaborate해야 신호 충돌을 발견 가능
   - `tb_loopback_no_fir.sv`처럼 "내부 블록을 재조립한" TB는 한계가 있음

2. **xsim이 합성보다 엄격함**:
   - Vivado 합성은 multi-driver를 silently 우회할 수 있음
   - xelab의 elaboration check가 즉시 잡아냄
   - **합성 전에 RTL 시뮬레이션을 반드시 돌려야 함**

3. **SystemVerilog 파라미터 타입 주의**:
   - `int` vs `longint` 차이는 silent truncation으로 이어짐
   - 파라미터는 데이터 width와 일치시켜야 함
   - Linter나 width-check 도구로 잡을 수 있는 종류의 버그

4. **Xilinx IP 시뮬레이션은 가능함**:
   - VHDL은 `xvhdl -work xil_defaultlib`로 컴파일
   - Precompiled FIR Compiler 라이브러리는 Vivado에 함께 제공됨
   - MIF 계수 파일은 작업 디렉토리에 복사 필요

5. **버그는 클러스터로 발견됨**:
   - 한 버그(correlator)를 잡으니 추가 버그(multi-driver)가 드러남
   - 한 버그(multi-driver)를 잡으니 또 다른 버그(THRESHOLD width)가 드러남
   - 첫 번째 RTL 테스트벤치가 만들어진 시점부터 누적된 버그가 한꺼번에 노출됨

---

## 9. 다음 단계 제안

1. **Cooldown logic 검증**: `frame_sync_detector.sv`의 cooldown counter가 의도한 대로 동작하는지 단독 검증 필요
2. **Multi-frame test**: 연속 프레임에서도 sync가 정확히 잡히는지 stress test
3. **Noise injection**: 진짜 채널 모델 (AWGN, multipath) 추가하여 BER vs SNR 특성 측정
4. **Linter 도입**: Spyglass/Verilator-lint로 향후 multi-driver, width-mismatch 자동 검출
