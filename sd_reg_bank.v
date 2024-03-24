//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module sd_reg_bank
#(
parameter HW_VER = 16'd1
)
(                                  
input  wire        CLK,            
input  wire        RST,            
                      
// read request
input  wire        I_REQ_RD,
input  wire [ 38:0]I_REQ_ADR,
output wire        I_REQ_ACK,     
                  
// registers input      
input  wire        I_CMD_EN, 
input  wire [125:0]I_CMD, 
input  wire        I_CMD_STA, 
input  wire        I_CMD_OCR, 
input  wire        I_CMD_CID, 
input  wire        I_CMD_CSD, 
                             
input  wire        I_DAT_EN, 
input  wire [ 63:0]I_DAT, 
input  wire [  2:0]I_DAT_PTR,

input  wire        I_HOST_STATE_EN, 
input  wire [ 15:0]I_HOST_STATE,  
                                                                                                         
// data output - already formated into ringbus packets
output wire [ 71:0]O_DAT, 
output wire        O_STB,
output wire        O_SOF, 
input  wire        O_ACK    
);                  
//================================================================================================= 

reg  [63:0] regBank [0:15];//31]; 

// 0x00 - st512 [ 63:  0]                
// 0x01 - st512 [127: 64]               
// 0x02 - st512 [191:128]               
// 0x03 - st512 [255:192]               
// 0x04 - st512 [319:256]               
// 0x05 - st512 [383:320]               
// 0x06 - st512 [447:384]               
// 0x07 - st512 [511:448]   
// 0x08 - {1'valid, 1'b0, CID[127:72]}             
// 0x09 - {CID [ 71: 8]}              
// 0x0A - {1'valid, 1'b0, CSD[127:72]} 
// 0x0B - {CSD [ 71: 8]}                    
// 0x0C - {32'h0, status32 [ 31: 0]} 
// 0x0D - {32'h0, OCR [ 31: 0]} 
// 0x0E - 64'h0;
// 0x0F - {32'd0, HW_VER [ 15: 0], HOST_STATE [ 15: 0]} 

reg   [4:0] i1_addr;
reg  [63:0] i1_dat;
reg         i1_en; 

reg         I_CMD_EN2;  
reg         I_CMD_CID2;
reg         I_CMD_CSD2;

integer     fsm_st; 
                         
reg         o0_en;
reg         o0_sof;  
reg   [4:0] o0_addr;
                      
reg         o1_en; 
reg         o1_sof;  
reg  [63:0] o1_dat; 
reg  [38:0] o1_adr;
    
reg         o2_en;
reg         o2_sof;   
reg  [71:0] o2_mux;
wire [ 1:0] o2_ff_af;    
reg  [ 2:0] o2_last_cnt;
wire        o2_last_f;
reg         o2_end_f;
//================================================================================================= 
localparam IDLE = 32'h00000001; 
localparam BR   = 32'h00000002;
localparam H    = 32'h00000004; 
localparam D0   = 32'h00000010;
localparam D1   = 32'h00000020;
localparam D2   = 32'h00000040;
localparam D3   = 32'h00000080;
localparam D4   = 32'h00000100;
localparam D5   = 32'h00000200;
localparam D6   = 32'h00000400;
localparam D7   = 32'h00000800; 
localparam STOP = 32'h00001000;  
//================================================================================================= 
always @(posedge CLK or posedge RST)                                                                
  if(RST)                       fsm_st         <=                                             IDLE;
 else begin case(fsm_st)                                                                           
IDLE:     if(I_REQ_RD         ) fsm_st         <=                                               BR; 
     else                       fsm_st         <=                                           fsm_st;
BR:       if( o2_last_f       ) fsm_st         <=                                             IDLE;
     else if( !o2_ff_af[1]    ) fsm_st         <=                                                H;
     else                       fsm_st         <=                                           fsm_st;     
H:                              fsm_st         <=                                               D0;  
D0:                             fsm_st         <=                                               D1; 
D1:                             fsm_st         <=                                               D2; 
D2:                             fsm_st         <=                                               D3; 
D3:                             fsm_st         <=                                               D4; 
D4:                             fsm_st         <=                                               D5; 
D5:                             fsm_st         <=                                               D6; 
D6:                             fsm_st         <=                                               D7; 
D7:                             fsm_st         <=                                             STOP; 
STOP:                           fsm_st         <=                                               BR;    
  endcase
end                                                                                                
//=================================================================================================  
always@(posedge CLK or posedge RST)                                           
 if(RST)                        I_CMD_EN2      <=                                             1'b0;
else                            I_CMD_EN2      <=                                         I_CMD_EN;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)            I_CMD_CID2     <=                                        I_CMD_CID;
always@(posedge CLK)            I_CMD_CSD2     <=                                        I_CMD_CSD;
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)                                           
 if(RST)                        i1_en          <=                                             1'b0;                                              
else if(        I_DAT_EN)       i1_en          <=                                             1'b1;
else if(        I_CMD_EN)       i1_en          <= I_CMD_STA || I_CMD_OCR || I_CMD_CID || I_CMD_CSD;
else if(       I_CMD_EN2)       i1_en          <=                           I_CMD_CID || I_CMD_CSD;
else if( I_HOST_STATE_EN)       i1_en          <=                                             1'b1;
else                            i1_en          <=                                             1'b0;
//-------------------------------------------------------------------------------------------------                      
                                                     
always@(posedge CLK)
     if(        I_DAT_EN)       i1_dat         <=                                   I_DAT[ 63: 0] ; 
else if(        I_CMD_EN)       i1_dat         <=                                   I_CMD[ 63: 0] ; 
else if(       I_CMD_EN2)       i1_dat         <=                   {1'b1, 7'd0,    I_CMD[119:64]}; 
else /*( I_HOST_STATE_EN)*/     i1_dat         <=        {32'd0, HW_VER[15:0], I_HOST_STATE[15:0]}; 
//------------------------------------------------------------------------------------------------- 
                                               
always@(posedge CLK)
     if(           I_DAT_EN )   i1_addr        <=                   { 2'd0 ,      ~I_DAT_PTR[2:0]};            
else if(I_CMD_EN2& I_CMD_CID2)  i1_addr        <=                   { 4'd4 ,                 1'b0};         
else if(I_CMD_EN & I_CMD_CID)   i1_addr        <=                   { 4'd4 ,                 1'b1};           
else if(I_CMD_EN2& I_CMD_CSD2)  i1_addr        <=                   { 4'd5 ,                 1'b0};        
else if(I_CMD_EN & I_CMD_CSD)   i1_addr        <=                   { 4'd5 ,                 1'b1}; 
else if(I_CMD_EN & I_CMD_STA)   i1_addr        <=                   { 4'd6 ,                 1'b0};          
else if(I_CMD_EN & I_CMD_OCR)   i1_addr        <=                   { 4'd6 ,                 1'b1};          
else /*(     I_HOST_STATE_EN)*/ i1_addr        <=                   { 4'd7 ,                 1'b1};                      
                                                                                                     
//------------------------------------------------------------------------------------------------- 
initial begin                            
  regBank[ 5'd0] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[ 5'd1] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[ 5'd2] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[ 5'd3] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[ 5'd4] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[ 5'd5] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[ 5'd6] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[ 5'd7] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[ 5'd8] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[ 5'd9] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[5'd10] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[5'd11] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[5'd12] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[5'd13] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[5'd14] <= 64'hFFFFFFFF_FFFFFFFF;
  regBank[5'd15] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd16] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd17] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd18] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd19] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd20] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd21] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd22] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd23] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd24] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd25] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd26] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd27] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd28] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd29] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd30] <= 64'hFFFFFFFF_FFFFFFFF;
//  regBank[5'd31] <= 64'hFFFFFFFF_FFFFFFFF;
  end        
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK) if(i1_en)  regBank[i1_addr]  <=                                i1_dat[ 63: 0]; 
always@(posedge CLK)            o1_dat            <=                              regBank[o0_addr];
//=================================================================================================
always@(posedge CLK or posedge RST)                                                                               
     if( RST                   ) o0_en         <=                                             1'b0;              
else if( fsm_st == IDLE        ) o0_en         <=                                             1'b0; 
else if( fsm_st == BR          ) o0_en         <=                                             1'b0;
else if( fsm_st == STOP        ) o0_en         <=                                             1'b0; 
else                             o0_en         <=                                             1'b1; 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK)                                                                                               
     if( fsm_st == H           ) o0_sof        <=                                             1'b1;
else                             o0_sof        <=                                             1'b0;
//-------------------------------------------------------------------------------------------------  
always@(posedge CLK)                                                                                  
     if( fsm_st == IDLE        ) o0_addr       <=                                            5'h1F;  
else if( fsm_st == BR          ) o0_addr       <=                                   o0_addr       ;  
else if( fsm_st == H           ) o0_addr       <=                                   o0_addr       ;  
else if( fsm_st == STOP        ) o0_addr       <=                                   o0_addr       ;     
else                             o0_addr       <=                                   o0_addr + 5'd1; 
//=================================================================================================   
always@(posedge CLK or posedge RST)                                                                                                                                                   
     if( RST                   ) o1_en         <=                                             1'b0;
else                             o1_en         <=                                            o0_en;
//-------------------------------------------------------------------------------------------------
always@(posedge CLK)             o1_sof        <=                                           o0_sof; 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK)             
     if( fsm_st == IDLE        ) o1_adr        <=                                        I_REQ_ADR;
else if( fsm_st == STOP        ) o1_adr        <=                                  o1_adr + 39'd64;
else                             o1_adr        <=                                  o1_adr         ;
//=================================================================================================   
always@(posedge CLK or posedge RST)                                                                                                                                                
     if( RST                   ) o2_en         <=                                             1'b0;
else                             o2_en         <=                                            o1_en;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)             o2_sof        <=                                           o1_sof;
//-------------------------------------------------------------------------------------------------
always@(posedge CLK)             
     if(o1_sof              )    o2_mux        <=        {4'h8, 28'd0, 1'b1, o1_adr[38:3], 3'b010};
else                             o2_mux        <=                                  {8'hFF, o1_dat};
//-------------------------------------------------------------------------------------------------
always@(posedge CLK)             
     if( fsm_st == IDLE        ) o2_last_cnt   <=                                             3'd1;//3;
else if( fsm_st == H           ) o2_last_cnt   <=                               o2_last_cnt - 3'd1;
else                             o2_last_cnt   <=                                      o2_last_cnt;
//-------------------------------------------------------------------------------------------------
assign o2_last_f =                                                                  o2_last_cnt[2];
//-------------------------------------------------------------------------------------------------
always@(posedge CLK)             
     if( fsm_st == STOP        ) o2_end_f      <=                                        o2_last_f;
else                             o2_end_f      <=                                             1'b0;
//=================================================================================================  
ff_srl_af_ack_d16
#(
.WIDTH(73),
.AF1LIMIT(11) // 11 not 9 because of 2 regs pipeline 
)   
ff_dout
(             
.clk    (CLK),
.rst    (RST),
                 
.i_stb  (o2_en),  
.i_data ({o2_sof, o2_mux}),
.i_af   (o2_ff_af),
.i_full (),
.i_err  (),

.o_stb  (O_STB),
.o_ack  (O_ACK),
.o_data ({O_SOF, O_DAT}),
.o_ae   (),
.o_err  ()
);                                                                                                
//================================================================================================= 
assign I_REQ_ACK =                                                                        o2_end_f;
//=================================================================================================                                   
endmodule

