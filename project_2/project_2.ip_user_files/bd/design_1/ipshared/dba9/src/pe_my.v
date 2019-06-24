`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/05/2017 09:43:59 PM
// Design Name: 
// Module Name: pe_my
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


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