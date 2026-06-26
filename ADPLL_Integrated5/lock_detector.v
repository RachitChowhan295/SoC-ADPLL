`timescale 1ns/1ps

module lock_detector(
    input  wire        clk,
    input  wire        rst,      
    input  wire signed [31:0] error,   
    output reg         lock
);

// Tighter threshold for a true lock
parameter signed [31:0] THRESHOLD  = 32'd400; 
parameter LOCK_COUNT = 6'd64;

reg [5:0] counter;
// ? THE FIX: A timer to ignore the fake "0 error" at simulation startup
reg [9:0] startup_blanking; 

wire signed [31:0] abs_error = error[31] ? -error : error; 

always @(posedge clk or posedge rst) begin  
    if(rst) begin                               
        counter <= 0;
        lock    <= 0;
        startup_blanking <= 0;
    end
    else begin
        // Wait for 500 clock cycles before trusting the error signal
        if (startup_blanking < 100) begin
            startup_blanking <= startup_blanking + 1;
            counter <= 0;
            lock    <= 0;
        end
        else begin
            // Normal Lock Detection Logic
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
end

endmodule
