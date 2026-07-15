`timescale 1ns/1ps

module tb_adpll_top();

    // ─── 1. SYSTEM SIGNALS ──────────────────────────────────────────
    reg  ref_clk;
    reg  rst;
    reg board_clk;

    reg  [5:0] N_int;
    reg  [6:0] m1_reg;
    reg  [6:0] F_mod;
    reg  [6:0] K_mod;
    reg        c2_prev;

    wire signed [24:0] phase_residual;
    wire signed [15:0] ctrl_word_out;
    wire fb_clk;  

    wire [5:0]N_div;

    // ─── 2. DUT INSTANTIATION ───────────────────────────────────────
    adpll_top dut (
        .ref_clk(ref_clk),
        .fb_clk(fb_clk),
        .rst(rst),
        .board_clk(board_clk),
        .N_int(N_int),
        .F_mod(F_mod),
        .K_mod(K_mod),
        .phase_residual(phase_residual),
        .ctrl_word_out(ctrl_word_out),
        .N_div(N_div)
    );

    // ─── 3. CLOCK GENERATION (100 MHz) ──────────────────────────────
    initial begin
        ref_clk = 1'b0;
        forever #5.0 ref_clk = ~ref_clk; // 10ns period = 100 MHz
    end

    //Board clock generation (10GHz)
    initial begin
        board_clk = 1'b0;
        forever #0.05 board_clk = ~board_clk; //0.05ns period = 10GHz
    end


    //Verification of Mash mash_modulator
    // ─── Average N_div monitor ──────────────────────────────
    real ndiv_sum = 0.0;
    integer ndiv_count = 0;
    real ndiv_average;

    always @(posedge ref_clk) begin
        if (!rst) begin
            ndiv_sum = ndiv_sum + N_div;
            ndiv_count = ndiv_count + 1;
        end
    end

    // Call this task periodically (or at end of sim) to check convergence
    task print_ndiv_average;
        begin
            ndiv_average = ndiv_sum / ndiv_count;
            $display("Time=%0t | Samples=%0d | Average N_div = %.6f (ideal = 30.1)",
                    $time, ndiv_count, ndiv_average);
        end
    endtask

    // ─── 4. PHYSICAL FREQUENCY COUNTER ──────────────────────────────
    real last_edge_time = 0.0;
    real period_sum_ns = 0.0;
    integer period_count = 0;
    real measured_freq_mhz = 0.0;

    parameter AVG_EDGES = 10000; // average over 100 edges

    always @(posedge dut.dco_clk) begin
        if (!rst) begin
            if (last_edge_time != 0.0) begin
                period_sum_ns = period_sum_ns + ($realtime - last_edge_time);
                period_count = period_count + 1;

                if (period_count == AVG_EDGES) begin
                    measured_freq_mhz = (1000.0 * AVG_EDGES) / period_sum_ns;
                    period_sum_ns = 0.0;
                    period_count = 0;
                end
            end
            last_edge_time = $realtime;
        end
        else begin
            last_edge_time = 0.0;
            period_sum_ns = 0.0;
            period_count = 0;
        end
    end

    initial begin
    // ... your reset and setup ...
    repeat (50) begin
        #(1000 * 10);  // wait some number of reference cycles, adjust as needed
        //print_ndiv_average;
    end
    $finish;
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
        N_int = 6'd30; 

        // 2. Fractional Modulation (MASH Delta-Sigma)
        // Set F_mod as your denominator and K_mod as your numerator.
        // E.g., K=0, F=0 means pure integer mode (3.0 GHz)
        // E.g., K=1, F=2 means 3050MHz
        F_mod = 7'd100;
        K_mod = 7'd57; 

        // =======================================================

        #25;
        rst = 1'b0;

        #500000; // Run for 20us

        $display("==================================================");
        $display("► Full Simulation Complete.");
        $finish;
    end

endmodule