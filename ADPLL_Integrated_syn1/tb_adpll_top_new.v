`timescale 1ns/1ps

module tb_adpll_top();

    // ─── 1. SYSTEM SIGNALS ──────────────────────────────────────────
    reg  ref_clk;
    reg  board_clk;     // NEW: physical board oscillator, feeds the MMCM inside
                         //      adpll_top which derives clk_fast for dco_nco
    reg  rst;

    reg  [5:0] N_int;
    reg  [6:0] F_mod;
    reg  [6:0] K_mod;

    wire signed [24:0] phase_residual;
    wire signed [15:0] ctrl_word_out;
    wire fb_clk;  

    wire [5:0]N_div;
    wire dco_clk_probe;   // NEW: connects to top-level debug port, replaces
                          // the fragile hierarchical dut.dco_clk reference

    // ─── 2. DUT INSTANTIATION ───────────────────────────────────────
    adpll_top dut (
        .ref_clk(ref_clk),
        .board_clk(board_clk),
        .fb_clk(fb_clk),
        .rst(rst),
        .N_int(N_int),
        .F_mod(F_mod),
        .K_mod(K_mod),
        .phase_residual(phase_residual),
        .ctrl_word_out(ctrl_word_out),
        .N_div(N_div),
        .dco_clk_probe(dco_clk_probe)
    );

    // ─── 3. CLOCK GENERATION ─────────────────────────────────────────
    // board_clk: the actual physical oscillator on your board (100 MHz).
    // Free-running, independent of rst -- a real oscillator doesn't stop.
    initial begin
        board_clk = 1'b0;
        forever #5.0 board_clk = ~board_clk;   // 10 ns period = 100 MHz
    end

    // ref_clk: CHANGED from 100 MHz to 1.5625 MHz (640 ns period).
    // This is not an arbitrary choice -- every Kp/Ki value in
    // gain_scheduler, and rad_res inside dtc_model/TDC scaling, were
    // derived from the verified Python model assuming the loop's
    // reference/sample rate is f_ref' = f_ref_orig/S = 100MHz/64 =
    // 1.5625 MHz. Driving ref_clk at 100 MHz here would silently
    // reintroduce the same sample-rate-vs-bandwidth instability that
    // caused the divergence you saw earlier, even though every other
    // module would still "look" correctly configured.
    //
    // In this design, ref_clk is treated as an independent reference
    // input (as it already is at the top-level port) rather than being
    // derived on-chip from board_clk. If you'd rather generate it from
    // board_clk with an on-chip /64 divider for a single-oscillator
    // board demo, that's a small additional module -- ask if you want
    // it and I'll add it.
    initial begin
        ref_clk = 1'b0;
        forever #320.0 ref_clk = ~ref_clk;   // 640 ns period = 1.5625 MHz
    end

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

    task print_ndiv_average;
        begin
            ndiv_average = ndiv_sum / ndiv_count;
            $display("Time=%0t | Samples=%0d | Average N_div = %.6f (ideal = 30.1)",
                    $time, ndiv_count, ndiv_average);
        end
    endtask

    // ─── 4. PHYSICAL FREQUENCY COUNTER ──────────────────────────────
    // Now measures dco_clk from dco_nco. Expected lock frequency is
    // ~47.03 MHz (the S=64 scaled target), NOT 3010 MHz -- that's
    // expected and correct; see the earlier discussion on why the
    // absolute GHz target can't be built directly in fabric logic.
    real last_edge_time = 0.0;
    real period_sum_ns = 0.0;
    integer period_count = 0;
    real measured_freq_mhz = 0.0;

    parameter AVG_EDGES = 100;

    always @(posedge dco_clk_probe) begin
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

    // ─── 5. TELEMETRY PRINTOUT ──────────────────────────────────────
    integer cycle_count = 0;
    always @(posedge ref_clk) begin
        if (!rst) cycle_count = cycle_count + 1;

        if (cycle_count % 100 == 0 && cycle_count > 0) begin
            $display("Ref Cycle %0d | Measured Freq: %0.3f MHz | Phase Residual: %0d | Ctrl Word: %0d",
                     cycle_count, measured_freq_mhz, phase_residual, ctrl_word_out);
        end
    end

    // ─── 6. STIMULUS AND RUN ────────────────────────────────────────
    initial begin
        $dumpfile("adpll_top.vcd");
        $dumpvars(0, tb_adpll_top);

        $display("==================================================");
        $display(" FULL SYSTEM INTEGRATION TEST (S=64 scaled model) ");
        $display("==================================================");

        rst = 1'b1;

        // ⬇️==================================================⬇️
        //      USER CONTROL PANEL
        // ⬆️==================================================⬆️

        // Target: N = 30.1 (matches target_freq'/f_ref' = 47.03125MHz /
        // 1.5625MHz in the verified S=64 Python model).
        // CHANGED from the old F_mod=100/K_mod=57 (which encoded a
        // different, arbitrary fraction) to match the model exactly:
        // Fraction(0.1).limit_denominator(100) = 1/10.
        N_int = 6'd30;
        F_mod = 7'd10;
        K_mod = 7'd1;

        // =======================================================

        #25;
        rst = 1'b0;

        // Python model locked at ref cycle 291 out of 600. At 640 ns/
        // cycle that's ~186 us to lock. Run well past that to observe
        // steady-state tracking: 1000 ref cycles = 640,000 ns = 640 us.
        #640000;

        print_ndiv_average;

        $display("==================================================");
        $display("► Full Simulation Complete.");
        $display("  Final measured freq = %0.3f MHz (target = 47.031 MHz)", measured_freq_mhz);
        $finish;
    end

endmodule