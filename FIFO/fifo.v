`timescale 1ns/1ps

module fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] data_in,
    output reg                   full,

    input  wire                  rd_clk,
    input  wire                  rd_rst,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] data_out,
    output reg                   empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;
    localparam MEM_SIZE_BITS = DEPTH * DATA_WIDTH;

    // ------------------------------------------------------------------------
    // POINTERS & GRAY CODE LOGIC (Unchanged)
    // ------------------------------------------------------------------------
    reg [ADDR_WIDTH:0] wr_ptr_bin, wr_ptr_gray;
    reg [ADDR_WIDTH:0] rd_ptr_bin, rd_ptr_gray;

    // --- WRITE DOMAIN ---
    wire [ADDR_WIDTH:0] wr_ptr_bin_next  = wr_ptr_bin + (wr_en & ~full);
    wire [ADDR_WIDTH:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    wire full_val = (wr_ptr_gray_next == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], 
                                           rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) full <= 1'b0;
        else        full <= full_val;
    end

    // --- READ DOMAIN ---
    wire [ADDR_WIDTH:0] rd_ptr_bin_next  = rd_ptr_bin + (rd_en & ~empty);
    wire [ADDR_WIDTH:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    wire empty_val = (rd_ptr_gray_next == wr_ptr_gray_sync2);
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) empty <= 1'b1;
        else        empty <= empty_val;
    end

    // ------------------------------------------------------------------------
    // CONDITIONAL MEMORY INSTANTIATION
    // ------------------------------------------------------------------------
    wire wr_en_safe = wr_en & ~full;
    wire rd_en_safe = rd_en & ~empty;

`ifdef __ICARUS__
    // ========================================================================
    // ICARUS VERILOG SIMULATION BYPASS
    // Behaves exactly like BRAM (1-cycle read latency, independent clocks)
    // ========================================================================
    reg [DATA_WIDTH-1:0] sim_mem [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] sim_dout;

    // Write Port
    always @(posedge wr_clk) begin
        if (wr_en_safe) begin
            sim_mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= data_in;
        end
    end

    // Read Port (1-Cycle Latency)
    always @(posedge rd_clk) begin
        if (rd_en_safe) begin
            sim_dout <= sim_mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
        end
    end

    assign data_out = sim_dout;

`else
    // ========================================================================
    // VIVADO SYNTHESIS (XPM)
    // ========================================================================
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(ADDR_WIDTH),       
        .ADDR_WIDTH_B(ADDR_WIDTH),       
        .AUTO_SLEEP_TIME(0),             
        .BYTE_WRITE_WIDTH_A(DATA_WIDTH), 
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("independent_clock"), 
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),       
        .MEMORY_SIZE(MEM_SIZE_BITS),      
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(DATA_WIDTH),
        .READ_LATENCY_B(1),               
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(1),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(DATA_WIDTH),
        .WRITE_MODE_B("read_first")       
    )
    xpm_memory_sdpram_inst (
        .dbiterrb(),                      
        .doutb(data_out),                 
        .sbiterrb(),                      
        .addrb(rd_ptr_bin[ADDR_WIDTH-1:0]),
        .clkb(rd_clk),                    
        .enb(rd_en_safe),                 
        .injectdbiterrb(1'b0),            
        .injectsbiterrb(1'b0),            
        .regceb(1'b1),                    
        .rstb(rd_rst),                    
        .addra(wr_ptr_bin[ADDR_WIDTH-1:0]),
        .clka(wr_clk),                    
        .dina(data_in),                   
        .ena(1'b1),                       
        .injectdbiterra(1'b0),            
        .injectsbiterra(1'b0),            
        .wea(wr_en_safe)                  
    );
`endif

endmodule   