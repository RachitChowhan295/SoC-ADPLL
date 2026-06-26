`timescale 1ns/1fs

module ring_dco_model(
    input  wire rst,
    input  wire signed [15:0] ctrl_word,
    output wire [15:0] phases,  // The 16 tapped wires for the Snapshot TDC
    output wire fb_clk          // The main clock for the Coarse PFD
);

    parameter integer F_FREE_MHZ = 2500;
    parameter integer KDCO_MHZ   = 5;

    real freq_mhz;
    real stage_delay_ns;
    
    // The physical 16-stage ring
    reg [15:0] ring_state;

    // ??? 1. FREQUENCY CALCULATION ?????????????????????????????
    always @(*) begin
        freq_mhz = F_FREE_MHZ + (ctrl_word * KDCO_MHZ);
        if(freq_mhz < 100) freq_mhz = 100;

        // Total period in nanoseconds = 1000.0 / freq_mhz
        // Since a 16-stage ring has 32 edge transitions per full cycle:
        stage_delay_ns = (1000.0 / freq_mhz) / 32.0;
    end

    // ??? 2. THE RING OSCILLATOR ENGINE ????????????????????????
    initial begin
        ring_state = 16'h0000;
    end

    always begin
        if (rst) begin
            ring_state = 16'h0000;
            #1; // Hold in reset
        end else begin
            #(stage_delay_ns);
            // Mobius shift: Shift bits left and invert the MSB into the LSB
            ring_state = {ring_state[14:0], ~ring_state[15]};
        end
    end

    // ??? 3. OUTPUT ROUTING ????????????????????????????????????
    // Feed the entire 16-wire bus to the Snapshot TDC
    assign phases = ring_state;
    
    // Feed just one wire (the MSB) to the Coarse PFD
    assign fb_clk = ring_state[15];

endmodule
