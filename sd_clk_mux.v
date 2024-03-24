//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module sd_clk_mux
(                                    
input  wire        SYS_RST,  
    
input  wire        CLK_25M,        
input  wire        CLK_50M,        
input  wire        CLK_100M,        
input  wire        CLK_200M,    

input  wire        I_EN_400K,
input  wire        I_EN_25M,
input  wire        I_EN_50M,
input  wire        I_EN_100M,
input  wire        I_EN_200M,            
  
output wire        SD_CLK,
output wire        SD_RST
); 
//=============================================================================
(* dont_touch = "true" *)wire        clk_400k_25;
(* dont_touch = "true" *)wire        clk_100_200;
(* dont_touch = "true" *)wire        clk_400k_25_50;
wire        clk_out;
reg  [ 5:0] clk_div_cnt;
(* dont_touch = "true" *) wire        clk_400k;                                                         
//=============================================================================  
// 200 kHz clock generation                                                     
//============================================================================= 
always @(posedge CLK_25M or posedge SYS_RST)
if(SYS_RST)             clk_div_cnt <=                                    6'd0;
else                    clk_div_cnt <=                      clk_div_cnt + 6'd1;
//-----------------------------------------------------------------------------
assign clk_400k =                                               clk_div_cnt[5];
//============================================================================= 
// clock multiplexer
//============================================================================= 
/*BUFGCTRL mux_400K_25
(
.I0     (CLK_25M),
.I1     (clk_400k),
               
.CE0    (1'b1), 
.CE1    (1'b1), 
.IGNORE0(1'b0), 
.IGNORE1(1'b0), 
      
.S0     (1'b0),
.S1     (1'b1),
.O      (SD_CLK)
);*/
BUFGCTRL mux_400K_25
(
.I0     (CLK_25M),
.I1     (clk_400k),
               
.CE0    (1'b1), 
.CE1    (1'b1), 
.IGNORE0(1'b0), 
.IGNORE1(1'b0), 
      
.S0     (I_EN_25M),
.S1     (I_EN_400K),
.O      (clk_400k_25)
);
//-----------------------------------------------------------------------------
BUFGCTRL mux_100_200
(
.I0     (CLK_100M),
.I1     (CLK_200M),
                  
.CE0    (1'b1), 
.CE1    (1'b1), 
.IGNORE0(1'b0), 
.IGNORE1(1'b0), 
  
.S0     (I_EN_100M),
.S1     (I_EN_200M),
.O      (clk_100_200)
);
//-----------------------------------------------------------------------------
BUFGCTRL mux_400K_50
(
.I0     (clk_400k_25),
.I1     (CLK_50M),
                   
.CE0    (1'b1), 
.CE1    (1'b1), 
.IGNORE0(1'b0), 
.IGNORE1(1'b0), 

.S0     (I_EN_25M || I_EN_400K),
.S1     (I_EN_50M),
.O      (clk_400k_25_50)
);
//-----------------------------------------------------------------------------
BUFGCTRL mux_low_high
(
.I0     (clk_400k_25_50),
.I1     (clk_100_200),

.CE0    (1'b1), 
.CE1    (1'b1), 
.IGNORE0(1'b0), 
.IGNORE1(1'b0), 

.S0     (I_EN_50M  || I_EN_25M || I_EN_400K),
.S1     (I_EN_100M || I_EN_200M),
.O      (SD_CLK)
);                                                                                
//=============================================================================
// reset synchronization bridge
//=============================================================================
//rst_synch_bridge #(.BRIDGE_LEN(8)) rst_synch_bridge 
//(.CLK(SD_CLK), .I_RST(SYS_RST), .O_RST(SD_RST)); 
rst_bridge #(.RST_DISTR_STEPS(8)) sd_rst_synch_bridge(.CLK( SD_CLK ), .IN_RST( SYS_RST ), .OUT_RST( SD_RST  ));                              
//=============================================================================
endmodule

                  