`timescale 1ns/1ps

module direct_fll (
    input  wire ref_clk,
    input  wire dco_clk,
    input  wire rst,
    input  wire [5:0] N_int,
    input  wire [6:0] K_mod,
    input  wire [6:0] F_mod,
    
    output reg signed [15:0] fll_ctrl,
    output reg fll_locked
);
    // 1. 13-bit DCO Edge Counter (Runs at High Speed)
    reg [12:0] dco_count;
    always @(posedge dco_clk or posedge rst) begin
        if (rst) dco_count <= 0;
        else dco_count <= dco_count + 1;
    end

    // 2. Safely cross the fast counter into the Ref Clock domain
    wire [12:0] dco_count_gray = dco_count ^ (dco_count >> 1);
    (* ASYNC_REG = "TRUE" *) reg [12:0] gray_sync1, gray_sync2;
    always @(posedge ref_clk or posedge rst) begin
        if (rst) begin
            gray_sync1 <= 0;
            gray_sync2 <= 0;
        end else begin
            gray_sync1 <= dco_count_gray;
            gray_sync2 <= gray_sync1;
        end
    end

    // 3. Gray to Binary Decoder
    reg [12:0] bin_sync;
    integer i;
    always @(*) begin
        bin_sync[12] = gray_sync2[12];
        for (i = 11; i >= 0; i = i - 1) begin
            bin_sync[i] = bin_sync[i+1] ^ gray_sync2[i];
        end
    end

    // 4. Time Window Generator (Count over 16 Ref Cycles)
   // 4. Time Window Generator (Count over 16 Ref Cycles)
    reg [3:0] ref_cnt;
    reg [12:0] bin_sync_prev;
    reg signed [16:0] freq_err; 
    reg update_fll;

    // Calculate exact target edges across 16 cycles: (N_int * 16) + (K_mod * 16 / F_mod)
    wire [12:0] target_16 = {N_int, 4'b0000} + ((K_mod << 4) / F_mod);
    
    // MOVED OUTSIDE: 13-bit unsigned subtraction safely handles wrap-around
    wire [12:0] actual_cycles = bin_sync - bin_sync_prev;

    always @(posedge ref_clk or posedge rst) begin
        if (rst) begin
            ref_cnt <= 0;
            bin_sync_prev <= 0;
            update_fll <= 0;
            freq_err <= 0;
        end else begin
            ref_cnt <= ref_cnt + 1;
            update_fll <= (ref_cnt == 4'd15);
            
            if (ref_cnt == 4'd15) begin
                // Zero-pad to 17-bit signed for math
                freq_err <= $signed({4'b0, target_16}) - $signed({4'b0, actual_cycles});
                bin_sync_prev <= bin_sync;
            end
        end
    end
    // 5. FLL Integrator & Handoff
    reg [3:0] lock_timer;
    always @(posedge ref_clk or posedge rst) begin
        if (rst) begin
            fll_ctrl   <= 0;
            fll_locked <= 0;
            lock_timer <= 0;
        end else if (update_fll) begin
            if (!fll_locked) begin
                // Gain of 16. A 1-edge error over 16 cycles (125kHz) moves ctrl by 16
                fll_ctrl <= fll_ctrl - (freq_err * 17'sd16); 
            end

            // Handoff to PLL only when DCO is within +/- 2 edges (250kHz) over 16 cycles
            if (freq_err >= -2 && freq_err <= 2) begin
                if (lock_timer < 3) lock_timer <= lock_timer + 1;
                else fll_locked <= 1'b1;
            end else begin
                lock_timer <= 0;
            end
        end
    end
endmodule