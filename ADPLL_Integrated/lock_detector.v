module lock_detector(
    input  wire        clk,
    input  wire        rst_n,
    input  wire signed [31:0] error,   // FIXED: Changed from [11:0] to [31:0]
    output reg         lock
);

parameter signed [31:0] THRESHOLD  = 32'd150; // Aligned parameter width
parameter LOCK_COUNT = 6'd32;

reg [5:0] counter;

// FIXED: Adjusted the sign bit check for 32-bit two's complement
wire signed [31:0] abs_error = error[31] ? -error : error; 

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        counter <= 0;
        lock    <= 0;
    end
    else begin
        if(abs_error <= THRESHOLD) begin
            if(counter < LOCK_COUNT)
                counter <= counter + 1;
        end
        else begin
            counter <= 0;
            lock    <= 0;
        end

        if(counter >= LOCK_COUNT-1)
            lock <= 1;
    end
end

endmodule
