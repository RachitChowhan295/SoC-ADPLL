`timescale 1ns/1ps

module tb_cic_decimator;

    reg clk;
    reg reset;
    reg signed [31:0] pd_out;
    reg [15:0] counter;

    wire do_update;
    wire signed [31:0] current_phi_error;

    //----------------------------------------
    // DUT (Fixed module name instantiation)
    //----------------------------------------
    cic_decimator dut (
        .clk(clk),
        .reset(reset),
        .pd_out(pd_out),
        .counter(counter),
        .do_update(do_update),
        .current_phi_error(current_phi_error)
    );

    //----------------------------------------
    // Clock generation
    //----------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    //----------------------------------------
    // Stimulus (Modified to capture 5 outputs)
    //----------------------------------------
    integer update_count = 0;

    initial begin
        $display("TESTBENCH STARTED");
        reset   = 1;
        pd_out  = 0;
        counter = 0;

        #50;
        @(posedge clk);
        reset = 0;

        // Provide a constant phase error input
        pd_out = 32'sd100; 

        // Keep running until we observe exactly 5 decimation outputs
        while (update_count < 5) begin
            @(posedge clk);
            counter <= counter + 1;
            
            if (do_update) begin
                update_count = update_count + 1;
            end
        end

        #20;
        $display("TESTBENCH FINISHED (Captured 5 outputs)");
        $finish;
    end

    //----------------------------------------
    // Monitor output
    //----------------------------------------
    always @(posedge clk) begin
        if(do_update) begin
            $display(
                "Output #%0d | Time=%0t | Counter=%0d | pd_out=%0d | phi_err=%0d",
                update_count + 1, // Lookahead index for display
                $time,
                counter,
                pd_out,
                current_phi_error
            );
        end
    end

    //----------------------------------------
    // Waveform Dump
    //----------------------------------------
    initial begin
        $dumpfile("cic.vcd");
        $dumpvars(0, tb_cic_decimator);
    end

endmodule