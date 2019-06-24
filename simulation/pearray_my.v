`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/05/2017 10:50:32 PM
// Design Name: 
// Module Name: pearray_my
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


module pearray_my#(
        parameter H_SIZE = 6, // vector[2**(H_SIZE-2)] * mat[2**H_SIZE][2**(H_SIZE-2)]
        parameter PE_DELAY = 16
    )
    (
        //from axi
        input start,
        output done,
        input S_AXI_ACLK,
        input S_AXI_ARESETN,
        
        //to BRAM
        output [31:0] BRAM_ADDR,
        output [31:0] BRAM_WRDATA,
        output [3:0] BRAM_WE,
        output BRAM_CLK, // 180 degree shifted version of S_AXI_ACLK
        input [31:0] BRAM_RDDATA
    );
    
    localparam VECTOR_SIZE = 2 ** (H_SIZE-2);
    localparam G_RAM_SIZE = H_SIZE-2; // global ram, upper(log(input vector size))
    localparam L_RAM_SIZE = H_SIZE-2; // local ram, upper(log(input matrix's row size))
    localparam NUM_PE = 2 ** H_SIZE;
    localparam LOG_NUM_PE = H_SIZE;
    
    // iteration variable
    genvar i;
    integer j;
    integer k;
    
    // clock, reset
    wire aclk = S_AXI_ACLK;
    wire aclk_180;
    wire aresetn = S_AXI_ARESETN;
    assign aclk_180 = ~aclk;
    assign BRAM_CLK = aclk_180;
    
    // PE #1
    wire [31:0] ain;
    wire [31:0] din;
    wire [L_RAM_SIZE-1:0] addr;
    wire [NUM_PE-1:0] we;
    wire valid;
    wire [NUM_PE-1:0] dvalid;
    wire [31:0] dout[NUM_PE-1:0];
    reg [31:0] dout_last[NUM_PE-1:0];
    
    // transition triggering flags
    //wire start;
    wire init_done;
    wire load_done;
    wire calc_done;
    wire harv_done;
    wire done_done;
        
    // main FSM
    reg [3:0] state, state_d;
    localparam S_IDLE = 4'd0;
    localparam S_INIT = 4'd1;
    localparam S_LOAD = 4'd2;
    localparam S_CALC = 4'd3;
    localparam S_HARV = 4'd4;
    localparam S_DONE = 4'd5;
    
    always @(posedge aclk)
        if (!aresetn)
            state <= S_IDLE;
        else
            case (state)
                S_IDLE:
                    state <= (start)? S_INIT : S_IDLE;
                S_INIT: // LOAD PEARRAYRAM
                    state <= (init_done)? S_LOAD : S_INIT;
                S_LOAD: // LOAD PERAM
                    state <= (load_done)? S_CALC : S_LOAD;
                S_CALC:
                    state <= (calc_done)? S_HARV : S_CALC;
                S_HARV:
                    state <= (harv_done)? S_DONE : S_HARV;
                S_DONE:
                    state <= (done_done)? S_IDLE : S_DONE;
                default:
                    state <= S_IDLE;
            endcase
    
    always @(posedge aclk)
        if (!aresetn)
            state_d <= S_IDLE;
        else
            state_d <= state;
    
    reg [G_RAM_SIZE-1:0] pos;
    
    wire pos_reset = !aresetn || done_done;
    
    always @(posedge aclk)
        if(pos_reset)
            pos <= 'd0;

    // pearrayram: global block ram
    wire [G_RAM_SIZE-1:0] gaddr;
    wire [31:0] gdin;
    reg [31:0] gdout;
    wire gwe;
    (* ram_style = "block" *) reg [31:0] pearrayram [0:2**G_RAM_SIZE - 1];
    (* ram_style = "block" *) reg [G_RAM_SIZE-1:0] zbit [0:2**G_RAM_SIZE - 1];
    
    always @(posedge aclk)
        if (gwe) begin
            pearrayram[gaddr] <= gdin;
            
            if(gdin == 0 && gaddr != (2**G_RAM_SIZE-1)) begin
                if(pos == 'd0) begin
                    pos <= gaddr;
                    zbit[gaddr] <= 'd1;
                end
                else begin
                    zbit[pos] <= zbit[pos] + 1;
                    zbit[gaddr] <= 'd0;
                end
            end
            else begin
                pos <= 'd0;
                zbit[gaddr] <= 'd0;
            end
            
        end
        else
            gdout <= pearrayram[gaddr];
    
    
    // SR_FF: S_INIT
    reg init_flag;
    wire init_flag_reset = !aresetn || init_done;
    wire init_flag_en = (state_d == S_IDLE) && (state == S_INIT);
    localparam CNTINIT = (VECTOR_SIZE << 1) - 1; // 2-cycle BRAM READ, bias(-1)
    always @(posedge aclk)
        if (init_flag_reset)
            init_flag <= 'd0;
        else
            if (init_flag_en)
                init_flag <= 'd1;
            else
                init_flag <= init_flag;
    
    // SR_FF: S_LOAD
    reg load_flag;
    wire load_flag_reset = !aresetn || load_done;
    wire load_flag_en = (state_d == S_INIT) && (state == S_LOAD);
    localparam CNTLOAD1 = NUM_PE;
    localparam CNTLOAD2 = (VECTOR_SIZE << 1) - 1;
    always @(posedge aclk)
        if (load_flag_reset)
            load_flag <= 'd0;
        else
            if (load_flag_en)
                load_flag <= 'd1;
            else
                load_flag <= load_flag;
    wire load2_done;
    
    // SR_FF: S_CALC
    reg calc_flag;
    wire calc_flag_reset = !aresetn || calc_done;
    wire calc_flag_en = (state_d == S_LOAD) && (state == S_CALC);
    localparam CNTCALC1 = (VECTOR_SIZE) - 1;
    always @(posedge aclk)
        if (calc_flag_reset)
            calc_flag <= 'd0;
        else
            if (calc_flag_en)
                calc_flag <= 'd1;
            else
                calc_flag <= calc_flag;
    
    // SR_FF: S_HARV
    reg harv_flag;
    wire harv_flag_reset = !aresetn || harv_done;
    wire harv_flag_en = (state_d == S_CALC) && (state == S_HARV);
    localparam CNTHARV = NUM_PE - 1;
    always @(posedge aclk)
        if (harv_flag_reset)
            harv_flag <= 'd0;
        else
            if (harv_flag_en)
                harv_flag <= 'd1;
            else
                harv_flag <= harv_flag;
    
    // SR_FF: S_DONE
    reg done_flag;
    wire done_flag_reset = !aresetn || done_done;
    wire done_flag_en = (state_d == S_HARV) && (state == S_DONE);
    localparam CNTDONE = 5;
    always @(posedge aclk)
        if (done_flag_reset)
            done_flag <= 'd0;
        else
            if (done_flag_en)
                done_flag <= 'd1;
            else
                done_flag <= done_flag;
    
    // down counter
    reg [31:0] counter;
    wire [31:0] ld_val = (init_flag_en)? CNTINIT  : 
                         (load_flag_en)? CNTLOAD1 :
                         (calc_flag_en)? CNTCALC1 : 
                         (harv_flag_en)? CNTHARV  : 
                         (done_flag_en)? CNTDONE  : 'd0;
    wire counter_ld = init_flag_en || load_flag_en || calc_flag_en || harv_flag_en || done_flag_en;
    wire counter_en = init_flag || load2_done || dvalid[0] || harv_flag || done_flag;
    wire counter_reset = !aresetn || init_done || load_done || calc_done || harv_done || done_done;

    always @(posedge aclk) begin
        if (counter_reset)
            counter <= 'd0;
            
        else if (counter_ld)
            counter <= ld_val;
            
        else if (counter_en) begin
            if(calc_flag && zbit[counter-1] && counter != 1) begin
                if(counter >= zbit[counter-1] + 1)
                    counter <= counter - zbit[counter-1] - 1;
                else
                    counter <= 0;
            end
            else
                counter <= counter - 1;
        end
    end
    
    // down counter2
    reg [31:0] counter2;
    wire [31:0] ld_val2 = (load_flag_en || load2_done)? CNTLOAD2 : 'd0;
    wire counter_ld2 = load_flag_en || load2_done;
    wire counter_en2 = load_flag;
    wire counter_reset2 = !aresetn || load_done;
    
    always @(posedge aclk)
        if (counter_reset2)
            counter2 <= 'd0;
       else
            if (counter_ld2)
                counter2 <= ld_val2;
            else if (counter_en2) begin
                if(zbit[counter2[G_RAM_SIZE:1]-1] && counter2[G_RAM_SIZE:1] != 1) begin
                    if(counter2[0])
                        counter2 <= counter2 - 1;
                    else if(counter2[G_RAM_SIZE:1] >= zbit[counter2[G_RAM_SIZE:1]-1] + 1)
                        counter2 <= counter2 - 2*zbit[counter2[G_RAM_SIZE:1]-1] - 1;
                    else
                        counter2 <= 0;
                end
                else
                    counter2 <= counter2 - 1;            
            end
    assign load2_done = (load_flag) && (counter2 == 'd0);
    
    // calculator control signals : S_CALC
    reg valid_pre, valid_reg;
    always @(posedge aclk)
        if (!aresetn)
            valid_pre <= 'd0;
        else
            if (counter_ld || counter_en)
                valid_pre <= 'd1;
            else
                valid_pre <= 'd0;
    
    always @(posedge aclk)
        if (!aresetn)
            valid_reg <= 'd0;
        else
            valid_reg <= valid_pre;
     
    assign valid = (calc_flag) && valid_reg;
    assign ain = (calc_flag)? gdout : 'd0;
    
    
    always @(posedge aclk)
        if (!aresetn)
            for (j = 0; j < NUM_PE; j = j + 1)
                dout_last[j] <= 'd0;
        else
            if (calc_done)
                for (j = 0; j < NUM_PE; j = j + 1)
                    dout_last[j] <= dout[j];
            else
                for (j = 0; j < NUM_PE; j = j + 1)
                    dout_last[j] <= dout_last[j];
    
    // done signals
    assign init_done = (init_flag) && (counter == 'd0);
    assign load_done = (load_flag) && (counter == 'd0);
    assign calc_done = (calc_flag) && (counter == 'd0) && dvalid[0];
    assign harv_done = (harv_flag) && (counter == 'd0);
    assign done_done = (done_flag) && (counter == 'd0);
    
    assign done = (state == S_DONE) && done_done;
    
    // data_mover : S_INIT, S_LOAD, S_HARV
    assign BRAM_ADDR = (init_flag)? counter[G_RAM_SIZE:1] << 2: 
                       (load_flag)? {counter[LOG_NUM_PE+1:0], counter2[G_RAM_SIZE:1]} << 2: 
                       (harv_flag)? counter[LOG_NUM_PE+1:0] << 2: 'd0;
    assign BRAM_WE = (harv_flag)? 4'b1111 : 4'b0000;
    
    assign BRAM_WRDATA = (harv_flag)? dout_last[counter] : 'd0;
    
    // global_data_mover : S_INIT
    assign gaddr = (init_flag)? counter[G_RAM_SIZE:1]: 
                   (calc_flag)? counter[G_RAM_SIZE-1:0]: 'd0;
    assign gdin = (init_flag)? BRAM_RDDATA : 'd0;
    assign gwe = (init_flag)? (counter[0] == 0) : 'd0;
    
    // local_data_mover : S_LOAD
    assign addr = (load_flag)? counter2[G_RAM_SIZE:1]:
                  (calc_flag)? counter[G_RAM_SIZE-1:0]: 'd0;
    assign din = (load_flag)? BRAM_RDDATA : 'd0;
    
    generate
        for (i = 0; i < NUM_PE; i = i + 1) begin: INST_WE
            assign we[i] = (load_flag && (counter == i+1))? (counter2[0] == 0) : 'd0;
        end
    endgenerate    
    
    // MMCM
//    clk_wiz_0 u_clk (.clk_out1(aclk_180), .clk_in1(aclk));
    
    
    generate
        for (i = 0; i < NUM_PE; i = i + 1)
        begin: INST_PE
            pe_my #(.L_RAM_SIZE(L_RAM_SIZE)
            ) u_pe (
                .aclk(aclk),
                .aresetn(aresetn && (state != S_DONE)),
                .ain(ain),
                .din(din),
                .addr(addr),
                .we(we[i]),
                .valid(valid),
                .dvalid(dvalid[i]),
                .dout(dout[i])
            );
        end
    endgenerate
    
endmodule