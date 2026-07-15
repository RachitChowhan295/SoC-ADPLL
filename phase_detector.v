module phase_detector(
    input ref_clk,
    input fb_clk,
    input rst,
    output reg signed [24:0]phase_error
);

reg [23:0] phase_ref;

//Reference phase accumulator
always@(posedge ref_clk or posedge rst) begin
    if(rst)
        phase_ref <= 24'd0;
    else 
        phase_ref <= phase_ref + 24'd1;
end

//Feedback phase accumulator
reg[23:0] phase_fb_bin;
always@(posedge fb_clk or posedge rst) begin
    if(rst)
        phase_fb_bin <= 24'd0;
    else 
        phase_fb_bin <= phase_fb_bin + 24'd1;
end

//Binary to gray code
wire [23:0]phase_fb_gray;
assign phase_fb_gray = (phase_fb_bin) ^ (phase_fb_bin >> 1);

//2-FF synchronizer
reg [23:0]gray_sync1;
reg [23:0]gray_sync2;

always@(posedge ref_clk or posedge rst) begin
    if(rst) begin
        gray_sync1 <= 24'd0;
        gray_sync2 <= 24'd0;
    end
    else begin
        gray_sync1 <= phase_fb_gray;
        gray_sync2 <= gray_sync1;
    end
end

//Gray to Binary
wire [23:0]phase_fb_bin_sync;
genvar i;
generate 
    assign phase_fb_bin_sync[23] = gray_sync2[23];
    for(i = 22; i>=0; i=i-1)
        assign phase_fb_bin_sync[i] = phase_fb_bin_sync[i+1] ^ gray_sync2[i];
endgenerate

//Phase error calculation
always@(posedge ref_clk or posedge rst) begin
    if(rst)
        phase_error <= 25'sd0;
    else
        phase_error <= $signed({1'b0,phase_ref}) - $signed({1'b0,phase_fb_bin_sync});
end




endmodule