`timescale 1ns/1ps

module lock_detector(
    input  wire        clk,
    input  wire        rst,      
    input  wire signed [31:0] error,   
    output reg         lock
);

parameter signed [31:0] THRESHOLD  = 32'd150; 
parameter LOCK_COUNT = 6'd32;

reg [5:0] counter;

wire signed [31:0] abs_error = error[31] ? -error : error; 

always @(posedge clk or posedge rst) begin  
    if(rst) begin                           
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
