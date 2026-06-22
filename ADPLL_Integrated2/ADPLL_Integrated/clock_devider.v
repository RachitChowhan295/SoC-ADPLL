module clock_devider(
    input [4:0]N_div,
    input dco_clk,
    input rst,

    output reg fb_clk
);

reg [5:0]counter; 

always@ (posedge dco_clk or posedge rst) begin
    if(rst) begin
        counter <= 6'b0;
        fb_clk  <= 1'b1;
    end
    else begin
        if(counter == N_div-1) begin
            counter <= 6'b0;
            fb_clk <= 1'b1;
        end 
        else begin
            fb_clk <= 1'b0;
            counter <= counter + 6'd1;
        end
    end
end
endmodule