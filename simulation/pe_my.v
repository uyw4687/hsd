/*module pe_my #(
        parameter L_RAM_SIZE = 6,
        parameter NUM_IP = 4
    )
    (
        // clk/reset
        input aclk,
        input aresetn,        
        // port A
        input [31:0] ain,        
        // peram -> port B 
        input [7:0] din,
        input [L_RAM_SIZE-1:0]  addr, //addr previous posedge given
        input we,        
        // integrated valid signal
        input valid,        
        // computation result
        output reg dvalid,
        output [15:0] dout
    );
    
//    wire avalid = valid;
//    wire bvalid = valid;
//    wire cvalid = valid;
    
    // peram: PE's local RAM -> Port B
    reg [31:0] bin;
    (* ram_style = "block" *) reg [31:0] peram [0:2**L_RAM_SIZE/NUM_IP - 1];
    
    genvar i;
    generate for(i=0;i<NUM_IP;i=i+1) begin:getinput
        always @(posedge aclk) begin
            if (we && addr%4 == i) begin
                peram[addr/4][i*8+7:i*8] <= din;
            end
        end
    end endgenerate
    
    always @(posedge aclk) begin
        if(!we)
            bin <= peram[addr];
    end
    
    reg [15:0] dout_fb;
    
    always @(posedge aclk) begin
        if (!aresetn)
            dout_fb <= 'd0;
        else
            if (dvalid)
                dout_fb <= dout;
            else
                dout_fb <= dout_fb;
    end
    
    always @(posedge aclk) begin
        if (!aresetn)
            dvalid <= 'd0;
        else
            dvalid <= valid;
            
    end
    
    wire [15:0] result[0:3];
    
    generate for (i=0;i<NUM_IP;i=i+1) begin:mac
        multadd u_int (
            .A(ain[i*8+7:i*8]),
            .B(bin[i*8+7:i*8]),
            .C(dout_fb & {16{i==0}}),
            .P(result[i])
        );
    end endgenerate
    
    assign dout = result[0] + result[1] + result[2] + result[3];
    
endmodule
 */
 
`timescale 1ns / 1ps

module pe_my #(
        parameter L_RAM_SIZE = 4
    )
    (
        // clk/reset
        input aclk,
        input aresetn,
        
        // port A
        input [31:0] ain,
        
        // peram -> port B 
        input [31:0] din,
        input [L_RAM_SIZE-1:0]  addr,
        input we,
        
        // integrated valid signal
        input valid,
        
        // computation result
        output dvalid,
        output [31:0] dout
    );

//    wire avalid = valid;
//    wire bvalid = valid;
//    wire cvalid = valid;
    
    reg dvalid_reg;
    
    // peram: PE's local RAM -> Port B
    reg [31:0] bin;
    (* ram_style = "block" *) reg [31:0] peram [0:2**L_RAM_SIZE - 1];
    always @(posedge aclk)
        if (we)
            peram[addr] <= din;
        else
            bin <= peram[addr];
    
    reg [15:0] dout_fb;
    always @(posedge aclk)
        if (!aresetn)
            dout_fb <= 'd0;
        else
            if (dvalid)
                dout_fb <= dout;
            else
                dout_fb <= dout_fb;
    
    always @(posedge aclk)
        if (!aresetn)
            dvalid_reg <= 'd0;
        else
            if(valid)
                dvalid_reg <= 'd1;
            else
                dvalid_reg <= 'd0;
    
    assign dvalid = dvalid_reg;
    
    wire signed [7:0] A_cut1 = ain[31:24];
    wire signed [7:0] A_cut2 = ain[23:16];
    wire signed [7:0] A_cut3 = ain[15:8];
    wire signed [7:0] A_cut4 = ain[7:0];

    wire signed [7:0] B_cut1 = bin[31:24];
    wire signed [7:0] B_cut2 = bin[23:16];
    wire signed [7:0] B_cut3 = bin[15:8];
    wire signed [7:0] B_cut4 = bin[7:0];

    wire signed [15:0] C_cut = dout_fb[15:0];
    wire signed [15:0] dout_cut;
    
    assign dout_cut = A_cut1 * B_cut1 + A_cut2 * B_cut2 + A_cut3 * B_cut3 + A_cut4 * B_cut4 + C_cut;
    assign dout = dout_cut;
   
endmodule