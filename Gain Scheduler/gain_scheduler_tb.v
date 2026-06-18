`timescale 1ns/1ps

module gain_scheduler_tb;

    reg [15:0] counter;

    wire signed [31:0] kp;
    wire signed [31:0] ki;

    // DUT
    gain_scheduler dut (
        .counter(counter),
        .kp(kp),
        .ki(ki)
    );

    initial begin

        $display("\n===== Gain Scheduler Test =====\n");

        // Fast region
        counter = 0;
        #10;
        $display("counter=%0d  kp=%0d  ki=%0d", counter, kp, ki);

        counter = 25;
        #10;
        $display("counter=%0d  kp=%0d  ki=%0d", counter, kp, ki);

        counter = 49;
        #10;
        $display("counter=%0d  kp=%0d  ki=%0d", counter, kp, ki);

        // Medium region
        counter = 50;
        #10;
        $display("counter=%0d  kp=%0d  ki=%0d", counter, kp, ki);

        counter = 75;
        #10;
        $display("counter=%0d  kp=%0d  ki=%0d", counter, kp, ki);

        counter = 99;
        #10;
        $display("counter=%0d  kp=%0d  ki=%0d", counter, kp, ki);

        // Slow region
        counter = 100;
        #10;
        $display("counter=%0d  kp=%0d  ki=%0d", counter, kp, ki);

        counter = 150;
        #10;
        $display("counter=%0d  kp=%0d  ki=%0d", counter, kp, ki);

        counter = 500;
        #10;
        $display("counter=%0d  kp=%0d  ki=%0d", counter, kp, ki);

        $finish;

    end

endmodule