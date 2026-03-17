`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/16/2026 10:57:57 AM
// Design Name: 
// Module Name: tb_qpsk_rrc
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_qpsk_rrc;

// Parameter

localparam int W      = 16;
localparam int W_3    = 56;
localparam int SPS    = 4;
localparam int OFFSET = 0;

// Common

logic clk, rst_n;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;  // 100MHz
end

initial begin
    rst_n = 1'b0;
    repeat (20) @(posedge clk);
    rst_n = 1'b1;
end

// DUT I/F
logic signed [W-1:0] sym_i, sym_q;
logic                sym_valid, sym_ready;

logic signed [W_3-1:0] out_i, out_q;
logic signed out_valid, out_ready;

// DUT Instance
qpsk_rrc_step1_top #(
    .W(W), .SPS(SPS), .OFFSET(OFFSET)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    
    .sym_i(sym_i),
    .sym_q(sym_q),
    .sym_valid(sym_valid),
    .sym_ready(sym_ready),
    
    .out_i(out_i),
    .out_q(out_q),
    .out_valid(out_valid),
    .out_ready(out_ready)
);

// VCD dump (Vivado/GTKWave)
//initial begin
//    $dumpfile("tb_qpsk_rrc_nonfull.vcd");
//    $dumpvars(0, tb_qpsk_rrc_nonfull);
//end

// Helper: Handshake stability check (assert)
// no changes when (valid & !ready)
//logic signed [W-1:0] sym_i_hold, sym_q_hold;
//logic        sym_hold_active;

//always_ff @(posedge clk) begin
//    if(!rst_n) begin
//        sym_hold_active <= 1'b0;
//        sym_i_hold      <= '0;
//        sym_q_hold      <= '0;
//    end else begin
//        if (sym_valid && !sym_ready) begin
//            if (!sym_hold_active) begin
//                sym_hold_active <= 1'b1;
//                sym_i_hold      <= sym_i;
//                sym_q_hold      <= sym_q;
//            end else begin
//                assert(sym_i == sym_i_hold && sym_q == sym_q_hold)
//                else $fatal(1, "INPUT violated: sym changed whild sym_valid=1 and sym_ready=0");
//            end        
//        end else begin
//            sym_hold_active <= 1'b0;
//        end
//    end
//end

//logic signed [W-1:0] out_i_hold, out_q_hold;
//logic out_hold_active;

//always_ff @(posedge clk) begin
//    if (!rst_n) begin
//        out_hold_active <= 1'b0;
//        out_i_hold      <= '0;
//        out_q_hold      <= '0;
//    end else begin
//        if(out_valid && !out_ready) begin
//            if(!out_hold_active) begin
//                out_hold_active <= 1'b1;
//                out_i_hold      <= out_i;
//                out_q_hold      <= out_q;
//            end else begin
//                assert(out_i == out_i_hold && out_q == out_q_hold)
//                    else $fatal(1, "OUTPUT violated: out changed while out_valid=1 and out_ready=0");
//            end            
//        end else begin    
//            out_hold_active <= 1'b0;
//        end
//    end
//end

// out_ready generation: "stall" in order to check back-pressure
//initial begin
//    out_ready = 1'b0;
//    wait(rst_n);
    
//    repeat (50) @(posedge clk) out_ready <= 1'b1;
    
//    forever begin
//        @(posedge clk);
//        // 80% ready, 20% stall
//        out_ready <= ($urandom_range(0,99) < 80);
//    end
//end

initial begin
    out_ready = 1'b1;
end

// TASK: 1 symbol transfer (maintain valid until ready)
task automatic send_symbol(input logic signed [W-1:0] I, input logic signed [W-1:0] Q);
    begin
        sym_i       <= I;
        sym_q       <= Q;
        sym_valid   <= 1'b1;
        
//        // wait until "accepted"
//        do @(posedge clk); while (!(sym_valid && sym_ready));
        
        // sym_ready
        if(^sym_ready !== 1'bx) begin
            do @(posedge clk);
            while (!(sym_valid && sym_ready));
            
            @(posedge clk);
        end else begin
            // without sym_ready, only 1 cycle
            @(posedge clk);
        
        end      
        
        sym_valid   <= 1'b0;
        sym_i       <= '0;
        sym_q       <= '0;
    end
endtask

// Stimulus
// 
int k;
int in_cnt, out_cnt;

initial begin
    sym_valid   = 1'b0;
    sym_i       = '0;
    sym_q       = '0;
    
    wait(rst_n);
    
    // (1) 50 set symbol
    for (k=0; k<50; k++) begin
        send_symbol(16'sd12000, 16'sd12000);        //signed decimal
    end
    
    // (2) random qpsk 200
    for (k=0; k<200; k++) begin
        logic b0, b1;
        b0 = $urandom_range(0,1);
        b1 = $urandom_range(0,1);
        
        send_symbol(b0 ? -16'sd12000 : 16'sd12000,
                    b1 ? -16'sd12000 : 16'sd12000);
    end
    
    // need to wait more because of pipeline and filter delay
    repeat (3000) @(posedge clk);
    
    $display("=== DONE ===");
    $display("in: %0d", in_cnt);
    $display("out: %0d", out_cnt);
    $finish;
end



// Monitor
always_ff @(posedge clk) begin
    if (!rst_n) begin
        in_cnt  <= 0;
        out_cnt <= 0;
    end else begin
        if (sym_valid && sym_ready) begin
            in_cnt <= in_cnt + 1;
            $display("[%0t]  IN #%0d I=%0d Q=%0d", $time, in_cnt+1, sym_i, sym_q);

        end
        
        if (out_valid) begin    //out_ready
            out_cnt <= out_cnt + 1;
            $display("[%0t] OUT #%0d I=%0d Q=%0d", $time, out_cnt+1, out_i, out_q);
        end
    end    
end

//// compare between input and output (sign)
//localparam int SKIP_OUT = 30;           //In order to skip the transient state of FIR filter
//int out_seen = 0;
//int bit_err = 0, bit_tot = 0;

//logic in_signI_q[$], in_signQ_q[$];     //[$]: Queue data structure which is the dynamic array.

//always_ff @(posedge clk) begin
//    if(!rst_n) begin
//        in_signI_q.delete();
//        in_signQ_q.delete();
//        out_seen <= 0;          
//        bit_err  <= 0;
//        bit_tot  <= 0;
//    end else begin
//        // 1) Input: The sign of accepted symbol is stored to FIFO
//        if(sym_valid && sym_ready) begin
//            in_signI_q.push_back(sym_i < 0);
//            in_signQ_q.push_back(sym_q < 0);
            
//            // $display(" ", );
//        end

//        // 2) Output: Increasing the count of effective output and comparison of sign
//        if(out_valid && out_ready) begin
        
//            if(out_seen > SKIP_OUT && in_signI_q.size() > 0) begin
//                logic refI, refQ;
//                refI = in_signI_q.pop_front();
//                refQ = in_signQ_q.pop_front();
                
////                bit_err += ((out_i < 0) != refI);
////                bit_err += ((out_q < 0) != refQ);
                
//                bit_err <= bit_err
//                        + (((out_i < 0) != refI) ? 1 : 0)
//                        + (((out_q < 0) != refQ) ? 1 : 0); 
                
//                bit_tot <= bit_tot + 2;
//            end
            
//            out_seen <= out_seen + 1;
            
//        end
//    end
//end

//final begin
//    $display("Sign-BER-ish = %0f (%0d/%0d)", (bit_tot? (bit_err*1.0/bit_tot) : 0.0), bit_err, bit_tot);
//end


// ============================================================
//  Sign-based BER with automatic delay (D) search
//  - IN/OUT 부호를 각각 저장해두고
//  - D 후보를 스윕해서 mismatch 최소 D를 찾는다
//  - 그 D에서의 BER을 출력한다
// ============================================================

// 비교할 최대 샘플 개수(너는 총 250개 OUT이 나오니까 300 정도로 여유)
localparam int MAX_SYM = 400;

// D(심볼 정렬 오프셋) 탐색 범위
localparam int D_MAX = 120;

// 과도응답 제외(OUT 기준으로 SKIP_OUT개는 비교에서 제외)
localparam int SKIP_OUT = 30;

// IN/OUT 부호 저장용 배열 (0/1로 저장)
logic inI_s [0:MAX_SYM-1];
logic inQ_s [0:MAX_SYM-1];
logic outI_s[0:MAX_SYM-1];
logic outQ_s[0:MAX_SYM-1];

int inN, outN;   // 저장된 IN/OUT 심볼 개수

// IN/OUT 부호를 배열에 저장
always_ff @(posedge clk) begin
  if (!rst_n) begin
    inN  <= 0;
    outN <= 0;
  end else begin
    // 입력 심볼이 "채택"된 순간만 저장
    if (sym_valid && sym_ready) begin
      if (inN < MAX_SYM) begin
        inI_s[inN] <= (sym_i < 0);   // I 부호
        inQ_s[inN] <= (sym_q < 0);   // Q 부호
        inN <= inN + 1;
      end
    end

    // 출력 심볼이 "유효"한 순간만 저장
    if (out_valid && out_ready) begin
      if (outN < MAX_SYM) begin
        outI_s[outN] <= (out_i < 0); // I 부호
        outQ_s[outN] <= (out_q < 0); // Q 부호
        outN <= outN + 1;
      end
    end
  end
end

// ============================================================
// 시뮬 종료 시점에 D 탐색 + BER 계산
// ============================================================
final begin
  int bestD;
  int bestErr;
  int bestTot;

  bestD   = 0;
  bestErr = 32'h7fffffff; // 큰 값으로 초기화
  bestTot = 0;

  // OUT/IN 둘 다 얼마나 모였는지 확인
  $display("Captured: inN=%0d, outN=%0d", inN, outN);

  // D 후보 스윕
  for (int D = 0; D <= D_MAX; D++) begin            //D_MAX: 120
    int err = 0;
    int tot = 0;

    // out[k]를 in[k-D]와 비교
    // k는 SKIP_OUT 이후부터 시작(초반 과도응답 버림)      //SKIP_OUT: 30
    for (int k = SKIP_OUT; k < outN; k++) begin
      int idx = k - D;  // IN 쪽 인덱스

      // idx가 유효 범위 안일 때만 비교
      if (idx >= 0 && idx < inN) begin
        err += (outI_s[k] != inI_s[idx]) ? 1 : 0;
        err += (outQ_s[k] != inQ_s[idx]) ? 1 : 0;
        tot += 2;
      end
    end

    // tot가 0이면 비교할 게 없는 D니까 스킵
    if (tot > 0) begin
      // mismatch가 최소인 D를 고른다
      if (err < bestErr) begin
        bestErr = err;
        bestTot = tot;
        bestD   = D;
      end
    end
  end

  // 결과 출력
  if (bestTot > 0) begin
    real ber;
    ber = bestErr * 1.0 / bestTot;
    $display("Best alignment D=%0d", bestD);
    $display("Sign-BER (aligned) = %0f (%0d/%0d)", ber, bestErr, bestTot);
  end else begin
    $display("No comparison possible. Increase MAX_SYM or simulation length.");
  end
end


endmodule
