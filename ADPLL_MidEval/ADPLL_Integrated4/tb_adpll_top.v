`timescale 1ns/1ps

module tb_adpll_top();

    // ─── 1. SYSTEM SIGNALS ──────────────────────────────────────────
    reg  ref_clk;
    reg  rst;

    reg  [4:0] N_int;
    reg  [6:0] m1_reg;
    reg  [6:0] F_mod;
    reg  [6:0] K_mod;
    reg        c2_prev;

    wire signed [24:0] phase_residual;
    wire signed [15:0] ctrl_word_out;
    wire fb_clk;  

    // ─── 2. DUT INSTANTIATION ───────────────────────────────────────
    adpll_top dut (
        .ref_clk(ref_clk),
        .fb_clk(fb_clk),
        .rst(rst),
        .N_int(N_int),
        .F_mod(F_mod),
        .K_mod(K_mod),
        .phase_residual(phase_residual),
        .ctrl_word_out(ctrl_word_out)
    );

    // ─── 3. CLOCK GENERATION (100 MHz) ──────────────────────────────
    initial begin
        ref_clk = 1'b0;
        forever #5.0 ref_clk = ~ref_clk; // 10ns period = 100 MHz
    end

    // ─── 4. PHYSICAL FREQUENCY COUNTER ──────────────────────────────
    integer dco_edges = 0;
    real measured_freq_mhz = 0.0;

    always @(posedge dut.dco_clk) begin
        if (!rst) dco_edges = dco_edges + 1;
    end

    always begin
        #1000; // Wait exactly 1 microsecond
        if (!rst) begin
            measured_freq_mhz = dco_edges / 1.0; 
            dco_edges = 0; 
        end
    end

    // ─── 5. TELEMETRY PRINTOUT ──────────────────────────────────────
    integer cycle_count = 0;
    always @(posedge ref_clk) begin
        if (!rst) cycle_count = cycle_count + 1;
        
        if (cycle_count % 1000 == 0 && cycle_count > 0) begin
            $display("Ref Cycle %0d | Measured Freq: %0.1f MHz | Phase Error: %0d | Ctrl Word: %0d", 
                     cycle_count, measured_freq_mhz, phase_residual, ctrl_word_out);
        end
    end

    // ─── 6. STIMULUS AND RUN ────────────────────────────────────────
    initial begin
        $dumpfile("adpll_top.vcd");
        $dumpvars(0, tb_adpll_top);

        $display("==================================================");
        $display(" FULL SYSTEM INTEGRATION TEST                     ");
        $display("==================================================");

        rst = 1'b1;

        // ⬇️==================================================⬇️
        //      USER CONTROL PANEL (EXERCISE YOUR FREE WILL)
        // ⬆️==================================================⬆️
        
        // 1. Integer Division (Target Freq = ref_clk * N_int)
        // For 3000 MHz, N_int = 3000 / 100 = 30.
        N_int = 5'd30; 

        // 2. Fractional Modulation (MASH Delta-Sigma)
        // Set F_mod as your denominator and K_mod as your numerator.
        // E.g., K=0, F=0 means pure integer mode (3.0 GHz)
        // E.g., K=1, F=2 means +0.5 fraction (3.5 GHz)
        F_mod = 7'd1;
        K_mod = 7'd0; 

        // =======================================================

        #25;
        rst = 1'b0;

        #20000; // Run for 20us

        $display("==================================================");
        $display("► Full Simulation Complete.");
        $finish;
    end

endmodule