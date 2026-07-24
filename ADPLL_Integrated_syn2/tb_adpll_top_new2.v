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

    // ─── 3. CLOCK GENERATION (S = 50) ────────────────────────────────
    // board_clk: the actual physical oscillator on the board (100 MHz,
    // matches the XDC "board_clk: 100 MHz physical oscillator" constraint).
    // THIS WAS MISSING ENTIRELY in the previous testbench -- board_clk was
    // declared as a reg but never driven, so clk_fast inside dco_nco never
    // toggled, dco_clk_probe never produced a second edge, and
    // measured_freq_mhz stayed 0.000 for the whole simulation. That is the
    // root cause of "measured frequency always comes out 0".
    // Free-running, independent of rst -- a real oscillator doesn't stop.
    initial begin
        board_clk = 1'b0;
        forever #5.0 board_clk = ~board_clk;  // 10ns period = 100 MHz
    end

    // ref_clk: f_ref' = f_ref_orig/S = 100MHz/50 = 2 MHz (500 ns period).
    // Every Kp/Ki value in gain_scheduler, and the DTC/TDC bin scaling,
    // were derived from the verified Python model assuming this exact
    // reference/sample rate. This matches the XDC's
    // "create_clock -period 500.000 -name ref_clk" constraint.
    //
    // NOTE: previously this file had TWO separate initial blocks both
    // driving ref_clk (a leftover 2MHz block and a stale 1.5625MHz/S=64
    // block) -- two procedural drivers racing on the same reg is illegal
    // simulation behavior. There must be exactly one driver; keeping only
    // the S=50-correct one below.
    initial begin
        ref_clk = 1'b0;
        forever #250.0 ref_clk = ~ref_clk;   // 500ns period = 2 MHz
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
    // ~60.2 MHz (the S=50 scaled target: target_freq_orig/S = 3010MHz/50),
    // NOT 3010 MHz -- that's expected and correct; see the earlier
    // discussion on why the absolute GHz target can't be built directly
    // in fabric logic.
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
        $display(" FULL SYSTEM INTEGRATION TEST (S=50 scaled model) ");
        $display("==================================================");

        rst = 1'b1;

        // ⬇️==================================================⬇️
        //      USER CONTROL PANEL
        // ⬆️==================================================⬆️

        // Target: N = 30.1 (matches target_freq'/f_ref' = 60.2MHz / 2MHz
        // in the S=50 scaled model; the ratio N is S-independent since
        // both numerator and denominator scale by S together).
        // Fraction(0.1).limit_denominator(100) = 1/10 -> F_mod=10, K_mod=1.
        // (Previous values N_int=23/F_mod=100/K_mod=67 encoded N=23.67,
        // which did not match this comment, the gain_scheduler tuning,
        // or the XDC's "-divide_by 30" fb_clk generated-clock constraint.)
        N_int = 6'd30;
        F_mod = 7'd10;
        K_mod = 7'd1;

        // =======================================================

        #25;
        rst = 1'b0;

        // Python model locked at ref cycle 291 out of 600. At 640 ns/
        // cycle that's ~186 us to lock. Run well past that to observe
        // steady-state tracking: 1000 ref cycles = 640,000 ns = 640 us.
        #6400000;

        print_ndiv_average;

        $display("==================================================");
        $display("► Full Simulation Complete.");
        $display("  Final measured freq = %0.3f MHz (target = 60.200 MHz)", measured_freq_mhz);
        $finish;
    end

endmodule
