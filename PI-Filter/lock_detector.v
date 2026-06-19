module lock_detector(
    input  wire        clk,
    input  wire        rst_n,
    input  wire signed [11:0] error,

    output reg         lock
);

parameter THRESHOLD  = 12'd8;
parameter LOCK_COUNT = 6'd32;

reg [5:0] counter;

wire signed [11:0] abs_error =
        error[11] ? -error : error;

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