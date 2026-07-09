// Purpose:   Synthesizable CARRY4 TDC for Fractional-N ADPLL
// Mechanism: Tapped Delay Line with Clock Domain Crossing
// Target:    Xilinx 7-Series / Artix7 / Kintex7 / Virtex7
// Note:      Simulation model runs automatically unless SYNTHESIS macro is defined.

`timescale 1ps/1ps

module adpll_tdc #(
    parameter NUM_TAPS = 64  // 64 taps covers ~384ps (assuming ~6ps/tap)
) (
    input  wire                 dtc_out,    // Delayed reference clock (propagates down the line)
    input  wire                 fb_clk,     // Feedback clock from DCO divider (samples the line)
    input  wire                 ref_clk,    // System reference clock (CIC Decimator domain)
    input  wire                 rst_n,      // Active low async reset
    
    output reg signed [7:0]     tdc_error,  // Signed fractional phase error (in raw bins)
    output reg                  valid,      // 1-cycle valid pulse in the ref_clk domain
    output wire [NUM_TAPS-1:0]  therm_out   // Thermometer code (debug)
);

`ifndef SYNTHESIS
    //=========================================
    // SIMULATION MODEL (Vernier Delay Model)
    //=========================================
    wire [NUM_TAPS:0] dtc_delayed;
    wire [NUM_TAPS:0] fb_delayed;
    reg  [NUM_TAPS-1:0] sim_therm_code;

    assign dtc_delayed[0] = dtc_out;
    assign fb_delayed[0]  = fb_clk;

    genvar i;
    generate
        for (i = 0; i < NUM_TAPS; i = i + 1) begin : sim_delay_chain
            // Emulate delay propagation asymmetry
            assign #0.020 dtc_delayed[i+1] = dtc_delayed[i];
            assign #0.010 fb_delayed[i+1]  = fb_delayed[i];

            // Feedback clock edge samples the moving DTC wave front
            always @(posedge fb_delayed[i+1] or negedge rst_n) begin
                if (!rst_n) sim_therm_code[i] <= 1'b0;
                else        sim_therm_code[i] <= dtc_delayed[i+1];
            end
        end
    endgenerate

    assign therm_out = sim_therm_code;

    integer j;
    reg [7:0] sim_tap_count;

    // Population count decoding logic
    always @(*) begin
        sim_tap_count = 8'd0;
        for (j = 0; j < NUM_TAPS; j = j + 1) begin
            if (sim_therm_code[j]) begin
                sim_tap_count = sim_tap_count + 1'b1;
            end
        end
    end

    // Direct synchronous output for clean simulation viewing
    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            tdc_error <= 8'sd0;
            valid     <= 1'b0;
        end else begin
            tdc_error <= $signed({1'b0, sim_tap_count}) - $signed(NUM_TAPS/2);
            valid     <= 1'b1;
        end
    end

`else
    //=========================================
    // SYNTHESIS HARDWARE SPECIFIC PATH
    //=========================================
    (* KEEP = "TRUE", S = "TRUE" *)
    wire [NUM_TAPS-1:0] delay_line;
    
    // Metastability Resolving Registers
    reg [NUM_TAPS-1:0]  therm_q1;
    reg [NUM_TAPS-1:0]  therm_q2;
    
    reg [7:0]           tap_count;
    reg signed [7:0]    error_fb_domain;
    reg                 data_ready_toggle;

    // 3-Stage CDC Toggle Synchronizer
    (* ASYNC_REG = "TRUE" *) reg sync1_toggle, sync2_toggle, sync3_toggle;

    integer i;

    // Hardware Implementation: CARRY4 Macro Primitive Chain
    genvar g;
    generate
        for (g = 0; g < NUM_TAPS/4; g = g + 1) begin : carry_chain
            (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) 
            CARRY4 carry4_inst (
                .CO     (delay_line[g*4+3 : g*4]), 
                .O      (), 
                .CI     (g == 0 ? 1'b0    : delay_line[g*4-1]),
                .CYINIT (g == 0 ? dtc_out : 1'b0),
                .DI     (4'b0000),
                .S      (4'b1111)
            );
        end
    endgenerate

    // Capture & Double-Flop Synchronize (fb_clk domain)
    always @(posedge fb_clk or negedge rst_n) begin
        if (!rst_n) begin
            therm_q1 <= {NUM_TAPS{1'b0}};
            therm_q2 <= {NUM_TAPS{1'b0}};
        end else begin
            therm_q1 <= delay_line; 
            therm_q2 <= therm_q1;   
        end
    end

    assign therm_out = therm_q2;

    // Parallel-Safe Combinational Population Counter
    always @(*) begin
        tap_count = 8'd0;
        for (i = 0; i < NUM_TAPS; i = i + 1) begin
            if (therm_q2[i]) begin
                tap_count = tap_count + 1'b1;
            end
        end
    end

    // Compute Error Centering & Strobe Generation
    always @(posedge fb_clk or negedge rst_n) begin
        if (!rst_n) begin
            error_fb_domain   <= 8'sd0;
            data_ready_toggle <= 1'b0;
        end else begin
            error_fb_domain   <= $signed({1'b0, tap_count}) - $signed(NUM_TAPS/2);
            data_ready_toggle <= ~data_ready_toggle; 
        end
    end

    // Asynchronous Clock Domain Crossing (ref_clk domain)
    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1_toggle <= 1'b0;
            sync2_toggle <= 1'b0;
            sync3_toggle <= 1'b0;
            tdc_error    <= 8'sd0;
            valid        <= 1'b0;
        end else begin
            sync1_toggle <= data_ready_toggle;
            sync2_toggle <= sync1_toggle;
            sync3_toggle <= sync2_toggle;

            // Toggle edge detection validates safe multi-bit CDC crossing
            if (sync2_toggle != sync3_toggle) begin
                tdc_error <= error_fb_domain; 
                valid     <= 1'b1;            
            end else begin
                valid     <= 1'b0;            
            end
        end
    end
`endif 

endmodule
