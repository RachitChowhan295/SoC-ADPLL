`timescale 1ns/1ps

module tb_adpll_loop_filter;

    //--------------------------------------------------
    // Clock
    //--------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk;      // 100 MHz

    //--------------------------------------------------
    // Reset
    //--------------------------------------------------
    reg rst_n;

    //--------------------------------------------------
    // TDC error
    //--------------------------------------------------
    reg signed [11:0] error;

    //--------------------------------------------------
    // Scheduler outputs
    //--------------------------------------------------
    reg [15:0] counter;
    wire signed [31:0] kp;
    wire signed [31:0] ki;

    //--------------------------------------------------
    // PI output
    //--------------------------------------------------
    wire signed [15:0] ctrl_word;

    //--------------------------------------------------
    // DUT 1 : Gain Scheduler
    //--------------------------------------------------
    gain_scheduler scheduler (
    .counter(counter),
    .kp(kp),
    .ki(ki)
);

    //--------------------------------------------------
    // DUT 2 : PI Filter
    //--------------------------------------------------
    pi_loop_filter filter (
        .clk       (clk),
        .rst_n     (rst_n),
        .error     (error),
        .kp        (kp),
        .ki        (ki),
        .ctrl_word (ctrl_word)
    );
     wire lock;

    lock_detector u_lock (
    .clk   (clk),
    .rst_n (rst_n),
    .error (error),      // TDC output
    .lock  (lock)
     );
    //--------------------------------------------------
    // Monitor
    //--------------------------------------------------
    initial begin
        $display("time\t err\t kp\t ki\t ctrl\t lock");

        $monitor("%0t\t%d\t%d\t%d\t%d\t%b",
                 $time,
                 error,
                 kp,
                 ki,
                 ctrl_word,
                 lock );
    end

    //--------------------------------------------------
    // Stimulus
    //--------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        counter <= 0;
    else
        counter <= counter + 1;
end

    initial begin

        rst_n = 0;
        error = 0;

        repeat(5) @(posedge clk);

        rst_n = 1;

        //----------------------------------------------
        // Acquisition
        //----------------------------------------------
        for(i=0;i<50;i=i+1) begin
            @(posedge clk);
            error <= 20;
        end

        //----------------------------------------------
        // Convergence
        //----------------------------------------------
        for(i=0;i<50;i=i+1) begin
            @(posedge clk);
            error <= 5;
        end

        //----------------------------------------------
        // Near lock
        //----------------------------------------------
        for(i=0;i<50;i=i+1) begin
            @(posedge clk);
            error <= 1;
        end

        //----------------------------------------------
        // Locked
        //----------------------------------------------
        for(i=0;i<100;i=i+1) begin
            @(posedge clk);

            case(i % 3)
                0: error <= 0;
                1: error <= 1;
                2: error <= -1;
            endcase
        end

        //----------------------------------------------
        // Disturbance
        //----------------------------------------------
        for(i=0;i<30;i=i+1) begin
            @(posedge clk);
            error <= 12;
        end

        //----------------------------------------------
        // Re-lock
        //----------------------------------------------
        for(i=0;i<80;i=i+1) begin
            @(posedge clk);
            error <= 0;
        end

        $finish;
    end
always @(posedge clk) begin
    $display("counter=%0d kp=%0d ki=%0d",
             counter, kp, ki);
end
    //--------------------------------------------------
    // Wave dump
    //--------------------------------------------------
    initial begin
        $dumpfile("adpll_loop_filter.vcd");
        $dumpvars(0,tb_adpll_loop_filter);
    end

endmodule