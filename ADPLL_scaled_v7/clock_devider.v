`timescale 1ns/1ps

module clock_devider(
    input [5:0]N_div,
    input dco_clk,
    input rst,

    output reg fb_clk
);

reg [6:0]counter; 

(* ASYNC_REG = "TRUE" *) reg [5:0] N_div_sync1, N_div_sync2;

always @(posedge dco_clk or posedge rst) begin
    if (rst) begin
        N_div_sync1 <= 6'd0;
        N_div_sync2 <= 6'd0;
    end else begin
        N_div_sync1 <= N_div;
        N_div_sync2 <= N_div_sync1;
    end
end

always@ (posedge dco_clk or posedge rst) begin
    if(rst) begin
        counter <= 7'b0;
        fb_clk  <= 1'b1;
    end
    else begin
        if(counter >= N_div_sync2-1) begin
            counter <= 7'b0;
            fb_clk <= 1'b1;
        end 
        else begin
            fb_clk <= 1'b0;
            counter <= counter + 7'd1;
        end
    end
end
endmodule