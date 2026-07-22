`timescale 1ns/1fs

module tb_async_fifo;

    // Parameters
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 4; // Depth = 16

    // Signals
    reg                   wr_clk = 0;
    reg                   wr_rst = 1;
    reg                   wr_en  = 0;
    reg  [DATA_WIDTH-1:0] data_in = 0;
    wire                  full;

    reg                   rd_clk = 0;
    reg                   rd_rst = 1;
    reg                   rd_en  = 0;
    wire [DATA_WIDTH-1:0] data_out;
    wire                  empty;

    // Asynchronous Clocks
    always #250 wr_clk = ~wr_clk; // Slow Reference (~2 MHz)
    always #2  rd_clk = ~rd_clk; // Fast DCO (~250 MHz)

    // DUT Instantiation
    fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk(wr_clk),
        .wr_rst(wr_rst),
        .wr_en(wr_en),
        .data_in(data_in),
        .full(full),
        .rd_clk(rd_clk),
        .rd_rst(rd_rst),
        .rd_en(rd_en),
        .data_out(data_out),
        .empty(empty)
    );

    // ------------------------------------------------------------------------
    // Read Checker (Evaluated on negedge to avoid simulation race conditions)
    // ------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] expected_data = 0;
    reg                  rd_en_d1 = 0;
    integer              errors = 0;
    integer              reads_completed = 0;

    // Track rd_en with 1 cycle latency (since BRAM has 1 cycle read latency)
    always @(posedge rd_clk) begin
        if (rd_rst) rd_en_d1 <= 0;
        else        rd_en_d1 <= rd_en;
    end

    // Check data safely in the middle of the clock cycle
    always @(negedge rd_clk) begin
        if (rd_en_d1) begin
            reads_completed = reads_completed + 1;
            if (data_out !== expected_data) begin
                $display("[FAIL] Time: %0t | Expected: %0d, Got: %0d", $time, expected_data, data_out);
                errors = errors + 1;
            end else begin
                $display("[PASS] Time: %0t | Read Data: %0d", $time, data_out);
            end
            expected_data = expected_data + 1;
        end
    end

    // ------------------------------------------------------------------------
    // Stimulus Generation (Outputs driven #1 after posedge)
    // ------------------------------------------------------------------------
    integer i;
    initial begin
        // Optional: Generate Waveforms for GTKWave
        $dumpfile("fifo_waves.vcd");
        $dumpvars(0, tb_async_fifo);

        $display("Starting Asynchronous FIFO Test...");
        
        // Phase 0: Reset
        #250;
        wr_rst = 0;
        rd_rst = 0;
        #250;

        // Phase 1: Burst Write until FULL
        $display("\n--- Phase 1: Burst Write ---");
        @(posedge wr_clk);
        #1; // Step slightly past the clock edge
        
        begin : BURST_WRITE_LOOP
            for (i = 0; i < 20; i = i + 1) begin
                if (!full) begin
                    wr_en   = 1;
                    data_in = i;
                    $display("[WRITE] Time: %0t | Writing Data: %0d", $time, data_in);
                end else begin
                    wr_en   = 0;
                    $display("[WRITE] FIFO Full detected. Pausing writes.");
                    disable BURST_WRITE_LOOP;
                end
                @(posedge wr_clk);
                #1; // Delay update to mimic real-world hold time
            end
        end
        wr_en = 0;

        // Allow synchronizers time to pass flags across domains
        #500;

        // Phase 2: Burst Read until EMPTY
        $display("\n--- Phase 2: Burst Read ---");
        @(posedge rd_clk);
        #1;
        while (!empty) begin
            rd_en = 1;
            @(posedge rd_clk);
            #1;
        end
        rd_en = 0;
        $display("[READ] FIFO Empty detected.");

        // Phase 3: Concurrent Read and Write
        $display("\n--- Phase 3: Concurrent Operations ---");
        fork
            // Writer Thread
            begin
                for (i = 16; i < 50; i = i + 1) begin
                    @(posedge wr_clk);
                    #1;
                    while (full) begin
                        wr_en = 0;
                        @(posedge wr_clk);
                        #1;
                    end
                    wr_en = 1;
                    data_in = i;
                end
                @(posedge wr_clk);
                #1;
                wr_en = 0;
            end
            
            // Reader Thread
            begin
                while (reads_completed < 50) begin
                    @(posedge rd_clk);
                    #1;
                    if (!empty) rd_en = 1;
                    else        rd_en = 0;
                end
                @(posedge rd_clk);
                #1;
                rd_en = 0;
            end
        join

        // Test Summary
        #100;
        $display("\n--- TEST SUMMARY ---");
        $display("Total Words Read: %0d", reads_completed);
        if (errors == 0 && reads_completed == 50)
            $display("RESULT: [SUCCESS] No dropped, duplicated, or metastable bits!");
        else
            $display("RESULT: [FAILED] %0d errors detected.", errors);
            
        $finish;
    end

endmodule