// Purpose: Synthesizable CARRY4 TDC for Fractional-N ADPLL
// Mechanism: Tapped Delay Line with Clock Domain Crossing
// Target: Xilinx 7-Series / Artix7 / Kintex7 / Virtex7

`timescale 1ps/1ps

module adpll_tdc #(
    // 64 taps covers ~384ps (assuming ~6ps/tap), enough for a 3-4 GHz DCO cycle
    parameter NUM_TAPS = 64  
) (
    input  wire                 dtc_out,    // Delayed reference clock (propagates down the line)
    input  wire                 fb_clk,     // Feedback clock from DCO divider (samples the line)
    input  wire                 ref_clk,    // System reference clock (CIC Decimator domain)
    input  wire                 rst_n,      // Active low async reset
    
    output reg signed [7:0]     tdc_error,  // Signed fractional phase error (in raw bins)
    output reg                  valid,      // 1-cycle valid pulse in the ref_clk domain
    output wire [NUM_TAPS-1:0]  therm_out   // Thermometer code (debug)
);

    //=========================================
    // Internal Signals
    //=========================================
    (* KEEP = "TRUE", S = "TRUE" *)
    wire [NUM_TAPS-1:0]   delay_line;
    
    // Synchronizer registers (fb_clk domain)
    reg [NUM_TAPS-1:0] therm_q1;
    reg [NUM_TAPS-1:0] therm_q2;
    
    integer i;
    reg [7:0] tap_count;

    //=========================================
    // Delay Line (CARRY4 Chain)
    //=========================================
    genvar g;
    generate
        for (g = 0; g < NUM_TAPS/4; g = g + 1) begin : carry_chain
            (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) 
            CARRY4 carry4_inst (
                // All 4 taps connect sequentially in one clean block
                .CO (delay_line[g*4+3 : g*4]), 
                .O  (), 
                
                // Cascade into CI from the highest tap of the previous block
                .CI     (g == 0 ? 1'b0 : delay_line[g*4-1]),
                
                // The input signal (dtc_out) feeds into the first block
                .CYINIT (g == 0 ? dtc_out : 1'b0),
                
                .DI (4'b0000),
                .S  (4'b1111)
            );
        end
    endgenerate

    //=========================================
    // Capture & Synchronize (fb_clk domain)
    //=========================================
    always @(posedge fb_clk or negedge rst_n) begin
        if (!rst_n) begin
            therm_q1 <= {NUM_TAPS{1'b0}};
            therm_q2 <= {NUM_TAPS{1'b0}};
        end else begin
            therm_q1 <= delay_line; // Snapshot the dtc_out wave
            therm_q2 <= therm_q1;   // Mitigate metastability
        end
    end

    assign therm_out = therm_q2;

    //=========================================
    // Thermometer Decoder (Combinational)
    //=========================================
    // Count the number of 1s to get the raw bin count
    always @(*) begin
        tap_count = 8'd0;
        for (i = 0; i < NUM_TAPS; i = i + 1) begin
            if (therm_q2[i]) begin
                tap_count = tap_count + 1'b1;
            end
        end
    end

    //=========================================
    // Signed Error & Handshake Toggle (fb_clk)
    //=========================================
    reg signed [7:0] error_fb_domain;
    reg              data_ready_toggle;

    always @(posedge fb_clk or negedge rst_n) begin
        if (!rst_n) begin
            error_fb_domain   <= 8'sd0;
            data_ready_toggle <= 1'b0;
        end else begin
            // Center the error to create a signed output. 
            // If the signal travels exactly halfway (32 taps), the error is 0.
            error_fb_domain   <= $signed({1'b0, tap_count}) - $signed(NUM_TAPS/2);
            
            // Flip the toggle bit every time new data is ready
            data_ready_toggle <= ~data_ready_toggle; 
        end
    end

    //=========================================
    // Clock Domain Crossing (ref_clk domain)
    //=========================================
    // Safely transfer the signed error from fb_clk to ref_clk for the CIC Filter
    (* ASYNC_REG = "TRUE" *) reg sync1_toggle, sync2_toggle, sync3_toggle;

    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1_toggle <= 1'b0;
            sync2_toggle <= 1'b0;
            sync3_toggle <= 1'b0;
            tdc_error    <= 8'sd0;
            valid        <= 1'b0;
        end else begin
            // 3-Stage Synchronizer for the toggle flag
            sync1_toggle <= data_ready_toggle;
            sync2_toggle <= sync1_toggle;
            sync3_toggle <= sync2_toggle;

            // Edge detection: When the toggle state changes, the data is stable and safe to read
            if (sync2_toggle != sync3_toggle) begin
                tdc_error <= error_fb_domain; // Latch the multi-bit data
                valid     <= 1'b1;            // Fire valid pulse to the CIC Decimator
            end else begin
                valid     <= 1'b0;            // Clear valid pulse
            end
        end
    end

endmodule