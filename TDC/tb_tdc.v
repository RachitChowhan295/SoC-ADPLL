`timescale 1ns/1ps

module tb_sim_vernier_tdc;

    // --- Inputs to UUT ---
    reg clk_ref;
    reg clk_dco;
    reg rst;

    // --- Outputs from UUT ---
    wire signed [5:0] tdc_fine_out; // 6-bit output (0 to 31)

    // --- Instantiate the Unit Under Test (UUT) ---
    sim_vernier_tdc #(
        .STAGES(32)
    ) uut (
        .clk_ref(clk_ref),
        .clk_dco(clk_dco),
        .rst(rst),
        .tdc_fine_out(tdc_fine_out)
    );

    // --- Clock Generation ---
    // Reference Clock: Exact 10.000 ns period -> 5.000 ns half-period
    always #5.000 clk_ref = ~clk_ref;

    // DCO Clock: Exact 10.010 ns period -> 5.005 ns half-period
    // Shifts 1 TDC bin (10ps) per cycle.
    always #5.005 clk_dco = ~clk_dco;

    // --- Test Sequence ---
    initial begin
        // 1. Setup Waveform Dumping
        $dumpfile("tb_sim_vernier_tdc.vcd");
        $dumpvars(0, tb_sim_vernier_tdc);

        // 2. Initialize Inputs
        clk_ref = 0;
        clk_dco = 0;
        rst = 1;

        // 3. Hold Reset to let signals stabilize
        // Releasing at 27ns avoids exact clock edges (which happen at 25ns and 30ns)
        #27;
        rst = 0;

        // 4. Let it run for 400ns (approx 40 cycles)
        #400;

        // 5. End Simulation
        $display("Dynamic phase sweep complete. Check waveform for staircase pattern.");
        $finish; // $finish closes the simulation cleanly compared to $stop
    end

endmodule
