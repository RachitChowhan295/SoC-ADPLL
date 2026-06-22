module mash_modulator(
    input [6:0]F_mod,
    input [6:0]K_mod,
    input [4:0]N_int,
    input clk,
    input rst,
    output reg [4:0]N_div,
    output reg [6:0]m1_reg
);

reg [6:0]m2_reg;
reg c1, c2, c2_prev;
reg signed [2:0]sdm_out;

reg [7:0]m1_sum;
reg [7:0]m2_sum;
reg [4:0]ndiv_next;

always@ (*) begin
    c1 = 1'b0;
    c2 = 1'b0;
    sdm_out = 3'sd0;
    m1_sum = {1'b0, m1_reg} + {1'b0, K_mod};
    m2_sum = {1'b0, m2_reg};
    ndiv_next = N_int;

    if(F_mod != {7{1'b0}}) begin
        if(m1_sum >= {1'b0,F_mod})
            c1 = 1'b1;

        m2_sum = {1'b0,m2_reg} + c1;
        if(m2_sum >= {1'b0,F_mod})
            c2 = 1'b1;

        sdm_out = (c1? 3'sd1:3'sd0) + (c2? 3'sd1:3'sd0) - (c2_prev? 3'sd1:3'sd0);

        if(sdm_out == -3'sd1)
            ndiv_next = ((N_int == 0) ? {5{1'b0}} : (N_int - 1'b1));
        else if(sdm_out == 3'sd1)
            ndiv_next = N_int + 1'b1;
        else if(sdm_out == 3'sd2)
            ndiv_next = N_int + 2'b10;
        else 
            ndiv_next = (N_int == 0) ? {5{1'b0}}:N_int;

    end
end


always@ (posedge clk or posedge rst) begin
    if(rst) begin
        m1_reg <= {7{1'b0}};
        m2_reg <= {7{1'b0}};
        c2_prev <= 1'b0;
        N_div <= {5{1'b0}};
    end
    else begin
        if(F_mod != {7{1'b0}}) begin
            if(m1_sum >= {1'b0,F_mod})
                m1_reg <= m1_sum - {1'b0,F_mod};
            else
                m1_reg <= m1_sum[6:0];

            if(m2_sum >= {1'b0,F_mod})
                m2_reg <= m2_sum - {1'b0,F_mod};
            else
                m2_reg <= m2_sum[6:0];

            c2_prev <= c2;
            N_div <= ndiv_next;
        end
        else begin
            m1_reg <= {7{1'b0}};
            m2_reg <= {7{1'b0}};
            c2_prev <= 1'b0;
            N_div <= N_int;
        end
    end
end

endmodule