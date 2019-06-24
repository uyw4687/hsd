module tb_con ();
parameter CLK_PERIOD = 10;

reg aclk;
reg aresetn;
reg start;
//reg [31:0] din;
wire done;


integer i;
initial begin
    aclk <= 0;
    start <= 0;
    aresetn<=0;
    
    #(CLK_PERIOD*5);
    aresetn<=1;
    
    #(CLK_PERIOD*5);
    start = 1;
    #(CLK_PERIOD);
    start = 0;
    
end

always #(CLK_PERIOD/2) aclk = ~aclk;

wire [31:0] bram_addr;
wire [31:0] bram_wrdata;
wire [31:0] bram_rddata;
wire [3:0] bram_we;
wire bram_clk;

pearray_my #(6, 16) pearraymy(
    .start(start),
    .done(done),
    .S_AXI_ACLK(aclk),
    .S_AXI_ARESETN(aresetn),
    
    .BRAM_ADDR(bram_addr),
    .BRAM_WRDATA(bram_wrdata),
    .BRAM_WE(bram_we),
    .BRAM_CLK(bram_clk), // 180 degree shifted version of S_AXI_ACLK
    .BRAM_RDDATA(bram_rddata)
    );

my_bram #(13) BRAM(
    .BRAM_ADDR(bram_addr),
    .BRAM_CLK(bram_clk),
    .BRAM_WRDATA(bram_wrdata),
    .BRAM_RDDATA(bram_rddata),
    .BRAM_EN(1),
    .BRAM_RST(0),
    .BRAM_WE(bram_we),
    .done(done)
);

endmodule
    