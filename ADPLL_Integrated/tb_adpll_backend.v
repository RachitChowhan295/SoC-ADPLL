`timescale 1ns/1ps

module tb_adpll_backend();

    // ─── 1. SYSTEM SIGNALS ──────────────────────────────────────────
    reg clk;
    reg rst;   // CHANGED to active-high

    // ─── 2. BACKEND WIRES ───────────────────────────────────────────
    wire signed [24:0] tdc_phase_residual; // Fake TDC input to your CIC
    
    wire [15:0] counter;
    wire do_update;
    wire signed [31:0] current_phi_error;
    
    wire signed [31:0] kp;
    wire signed [31:0] ki;
    
    wire signed [15:0] ctrl_word;
    wire lock;

    // ─── 3. INSTANTIATE YOUR MODULES ────────────────────────────────
    cic_decimator cic_inst(
        .clk(clk),
        .rst(rst),   // CHANGED to active-high direct mapping
        .phase_residual(tdc_phase_residual),
        .counter(counter),
        .do_update(do_update),
        .current_phi_error(current_phi_error)
    );

    gain_scheduler scheduler(
        .counter(counter),
        .kp(kp),
        .ki(ki)
    );

    pi_loop_filter filter(
        .clk(clk),
        .rst(rst),   // CHANGED to active-high direct mapping
        .enable(do_update),
        .error(current_phi_error),
        .kp(kp),
        .ki(ki),
        .ctrl_word(ctrl_word)
    );

    lock_detector detector(
        .clk(clk),
        .rst(rst),   // CHANGED to active-high direct mapping
        .error(current_phi_error),
        .lock(lock)
    );

    // ─── 4. CLOCK GENERATION (100 MHz) ──────────────────────────────
    initial begin
        clk = 0;
        forever #1.0 clk = ~clk; 
    end

    // ─── 5. BEHAVIORAL FRONT-END (Math substituting the TDC/DTC) ────
    real f_ref;
    real f_free;  
    real target_freq;  
    real N_div;
    real ko_gain;    
    real rad_res;
    
    real actual_phase_error = 0.0;
    real tdc_quant_err      = 0.0;
    real freq_dco           = 1000.0e6;
    real FERR               = 0.0;
    real tdc_input          = 0.0;
    real raw_bins           = 0.0;
    real pd_bins            = 0.0;
    real pd_out             = 0.0;
    reg fll_handoff_done    = 0;   

    integer phase_res_int = 0;
    assign tdc_phase_residual = phase_res_int;

    // Calculate all dynamic constants exactly once at startup
    initial begin
        f_ref       = 100.0e6;
        f_free      = 1000.0e6;  
        
        // 👉 CHANGE THIS TO ANYTHING (e.g., 1000.0e6, 3000.0e6)
        target_freq = 4000.0e6;  
        
        ko_gain     = 100.0e3;    
        N_div       = target_freq / f_ref;
        rad_res     = (2.0 * 3.14159265359 * f_ref) / target_freq;
    end

    always @(posedge clk) begin
        if (rst) begin   // CHANGED to check for active-high reset
            actual_phase_error = 0.0;
            tdc_quant_err      = 0.0;
            phase_res_int      = 0;
        end else begin
            freq_dco = f_free + (ko_gain * $itor(ctrl_word));
            FERR = (freq_dco / f_ref) - N_div;
            actual_phase_error = actual_phase_error + ((2.0 * 3.14159265359 / N_div) * FERR);

            // ── DYNAMIC FLL HANDOFF ────────────────────
            if (!fll_handoff_done && cycle_count > 500 && 
                freq_dco >= (target_freq - 20.0e6) && freq_dco <= (target_freq + 20.0e6)) begin
                actual_phase_error = 0.0;
                tdc_quant_err      = 0.0;
                fll_handoff_done   = 1;
                $display("► Cycle %0d: FLL Handoff triggered! Phase debt flushed.", cycle_count);
            end
            
            tdc_input = actual_phase_error + tdc_quant_err;
            raw_bins  = tdc_input / rad_res;

            if (raw_bins >= 0) raw_bins = $floor(raw_bins + 0.5);
            else               raw_bins = $ceil(raw_bins - 0.5);

            if (raw_bins > 128.0)       pd_bins = 128.0;
            else if (raw_bins < -128.0) pd_bins = -128.0;
            else                        pd_bins = raw_bins;

            pd_out = pd_bins * rad_res;

            if (pd_bins == raw_bins) tdc_quant_err = tdc_input - pd_out;
            else                     tdc_quant_err = 0.0;

            phase_res_int = $rtoi(pd_out * 4096.0);
        end
    end

    // ─── 6. TEST SEQUENCE & TELEMETRY ───────────────────────────────
    integer cycle_count = 0;
    always @(posedge clk) begin
        if (!rst) cycle_count = cycle_count + 1;  // CHANGED to count only when NOT resetting
        
        // Print Telemetry every 1000 Reference Cycles
        if (cycle_count % 1000 == 0 && cycle_count > 0) begin
            $display("Ref Cycle %0d | FB Cycle %0d | DCO Freq: %0.1f MHz | Ctrl Word: %0d | Lock: %b", 
                     cycle_count, counter, freq_dco/1e6, ctrl_word, lock);
        end
    end

    initial begin
        $display("==================================================");
        $display(" BACKEND ISOLATION TEST (NO FRONT-END MODULES)    ");
        $display("==================================================");
        
        // CHANGED stimulus to drive active-high logic
        rst = 1;
        #25;      
        rst = 0;
        
        #150000; // Run for 15,000 reference cycles
        
        $display("==================================================");
        $display("► Backend Simulation Complete.");
        $finish;
    end

    // Waveform Dumping
    initial begin
        $dumpfile("backend_isolation.vcd");
        $dumpvars(0, tb_adpll_backend);
    end

endmodule
