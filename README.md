Single Carrier QPSK Modem (rev.2)

1. Block Diagram
TX Path:

┌─────────────┐    ┌──────────┐    ┌─────────┐    ┌─────────┐
│   Payload   │ -> │  Frame   │ -> │Upsample │ -> │ TX RRC  │
│   Source    │    │ Builder  │    │  (×4)   │    │ Filter  │
└─────────────┘    └──────────┘    └─────────┘    └─────────┘
                   [Preamble+Data]

RX Path:

┌─────────┐    ┌──────────┐    ┌───────────┐    ┌──────────┐
│ RX RRC  │ -> │Downsample│ -> │ Preamble  │ -> │  Frame   │
│ Filter  │    │  (÷4)    │    │Correlator │    │  Sync    │
└─────────┘    └──────────┘    └───────────┘    │ Detector │
                                                 └──────────┘
                                                      |
                                                  sync_found
2. File List
  - (added) frame_builder.sv                 : TX Frame generator (Preamble + Payload)
  - axis_upsample_zeros.sv           : TX Symbol to Sample rate (Upsampler-sps:x4(zero added))
  - fir_tx_i & q                     : pulse shaping
    
  - fir_rx_i & q                     : matched filter
  - axis_downsample_pick.sv          : RX Sample rate to Symbol (Downsmapler-/4)
  - (added) preamble_correlator.sv : RX Cross-correlation (detection for preamble)
  - (added) frame_sync_detector.sv : RX Sync detection (Peak detection + Threshold)
    
4. coe for RRC Filter is generated from python code ( https://colab.research.google.com/drive/1_Zry-mf2LVL4mHI1rFktUdSwNIZy-wqP#scrollTo=-t1DMAErsUGN )
