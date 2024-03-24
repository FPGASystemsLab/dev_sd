//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module sd_cmd_136b_parser
(                                  
input  wire        CLK,            
input  wire        RST,            
                                     
input  wire        I_BIT,            
input  wire        I_EN,            
input  wire        I_48,            
input  wire        I_136,         

output wire [125:0]O_CMD,
output wire        O_CMD_EN,
output wire        O_CMD_EN_TIC,
output wire [  6:0]O_CRC,
output wire        O_CRC_VALID, 
output wire        O_TIMEOUT     
);                  
//=================================================================================================
parameter     CMD_TIMEOUT  =                                                               15'd150; // count in tic of SD clock 
//=================================================================================================
// Input                                                                                           
//================================================================================================= 
reg  [135:0]  i0_cmd_in;
reg           i0_cmd_stb;
wire          i0_cmd_bit;
reg           i0_wait_cmd; 
wire          i0_start; 
reg           i0_wait_48;
reg           i0_wait_136;
reg           i0_cmd_pend;
wire          i0_cmd_endbit;
reg  [  8:0]  i0_cmd_tcnt;
reg  [  8:0]  i0_cmd_ccnt;
reg  [  3:0]  i0_cmd_scnt;      
 
wire          i0_cmd_body_f;
wire          i0_cmd_crc_f;  
wire          i0_cmd_skip_head136_f;
wire          i0_crc_en; 
wire          i0_crc_in;
wire          i0_crc_rst; 
wire  [  6:0] i0_crc_rec;   

wire          i0_timeout_f;
reg  [  9:0]  i0_timeout_cnt;
//------------------------------------------------------------------------------------------------- 
wire  [  6:0] i1_crc_cal;
reg   [  6:0] i1_crc_rec;  
reg           i1_crc_valid;
reg           i1_cmd_en;  
reg           i1_cmd_en_tic;    
//=================================================================================================    
// i0 
//=================================================================================================                                                                           
assign i0_cmd_bit =                                                                          I_BIT; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                     i0_cmd_stb<=                                                      1'b0; 
else                        i0_cmd_stb<=                                                      I_EN;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if(i0_cmd_endbit      )i0_cmd_in <=                                                 i0_cmd_in; 
else if(i1_cmd_en          )i0_cmd_in <=                                                 i0_cmd_in; 
else if(i0_cmd_stb         )i0_cmd_in <=                                   {i0_cmd_in, i0_cmd_bit};
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if( i0_cmd_endbit     )i0_wait_cmd  <=                                                   1'b0; 
else if( i0_start          )i0_wait_cmd  <=                                                   1'b0; 
else                        i0_wait_cmd  <=                           I_EN && !i0_cmd_pend        ;  
//------------------------------------------------------------------------------------------------- 
assign                      i0_start  =                                  i0_wait_cmd & !i0_cmd_bit; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if( i0_cmd_endbit     )i0_wait_48   <=                                                   1'b0; 
else if( i0_start          )i0_wait_48   <=                                                   1'b0; 
else                        i0_wait_48   <=                           I_EN && !i0_cmd_pend && I_48; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if( i0_cmd_endbit     )i0_wait_136  <=                                                   1'b0; 
else if( i0_start          )i0_wait_136  <=                                                   1'b0; 
else                        i0_wait_136  <=                          I_EN && !i0_cmd_pend && I_136; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                     i0_cmd_pend  <=                                                   1'b0; 
else if(!i0_cmd_stb        )i0_cmd_pend  <=                                                   1'b0; 
else if( i0_start          )i0_cmd_pend  <=                                                   1'b1; 
else if( i0_cmd_endbit     )i0_cmd_pend  <=                                                   1'b0; 
else                        i0_cmd_pend  <=                                            i0_cmd_pend; 
//-------------------------------------------------------------------------------------------------    
assign i0_cmd_endbit   =                                              i0_cmd_pend & i0_cmd_tcnt[8];  

//-------------------------------------------------------------------------------------------------
// total counter - count down bits of packet
always@(posedge CLK or posedge RST)
 if(RST)                                      i0_cmd_tcnt <=                           {1'b1,8'hx};
 else if(i0_wait_48  && !i0_cmd_bit         ) i0_cmd_tcnt <=                                 9'd46;
 else if(i0_wait_136 && !i0_cmd_bit         ) i0_cmd_tcnt <=                                9'd134; 
 else if(i0_cmd_tcnt[8]                     ) i0_cmd_tcnt <=                    i0_cmd_tcnt       ;
 else                                         i0_cmd_tcnt <=                    i0_cmd_tcnt - 9'd1;
                                                                                                   
//-------------------------------------------------------------------------------------------------
// crc counter - count down bits from start of packet
always@(posedge CLK or posedge RST)
 if(RST)                                      i0_cmd_ccnt <=                           {1'b1,8'hx}; 
 else if(i0_wait_48  && !i0_cmd_bit         ) i0_cmd_ccnt <=                                 9'd38; 
 else if(i0_wait_136 && !i0_cmd_bit         ) i0_cmd_ccnt <=                                9'd126;  
 else if(i0_cmd_ccnt[8]                     ) i0_cmd_ccnt <=                    i0_cmd_ccnt       ;
 else                                         i0_cmd_ccnt <=                    i0_cmd_ccnt - 9'd1; 
//-------------------------------------------------------------------------------------------------  
// skip counter - count down bits from long packet. For first 8 bits of long packet no crc should be counted
always@(posedge CLK or posedge RST)
 if(RST)                                      i0_cmd_scnt <=                           {1'b1,3'hx};
 else if(i0_wait_136 && !i0_cmd_bit         ) i0_cmd_scnt <=                                  4'h6;  
 else if(i0_cmd_scnt[3]                     ) i0_cmd_scnt <=                    i0_cmd_scnt       ;
 else                                         i0_cmd_scnt <=                    i0_cmd_scnt - 4'd1; 
//-------------------------------------------------------------------------------------------------  
assign i0_cmd_body_f=                                   i0_cmd_stb & (i0_start || !i0_cmd_ccnt[8]);
assign i0_cmd_crc_f =                                            i0_cmd_ccnt[8] && !i0_cmd_tcnt[8];
assign i0_cmd_skip_head136_f =                                                     !i0_cmd_scnt[3];
assign i0_crc_en    =                                                                i0_cmd_body_f;  
assign i0_crc_in    =                                                                   i0_cmd_bit;  
assign i0_crc_rst   =                                         !i0_cmd_stb || i0_cmd_skip_head136_f; 
assign i0_crc_rec   =                                                             i0_cmd_in[ 7: 1];
                                                                                                  
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                                      i0_timeout_cnt <=                        CMD_TIMEOUT;
 else if(!i0_cmd_stb                        ) i0_timeout_cnt <=                        CMD_TIMEOUT;
 else                                         i0_timeout_cnt <=             i0_timeout_cnt - 10'd1; 
//-------------------------------------------------------------------------------------------------
assign i0_timeout_f  =                                                           i0_timeout_cnt[9];
//-------------------------------------------------------------------------------------------------
 sd_crc7 cmd_crc_in(
  .CLK  (CLK),    
  .RST  (i0_crc_rst),   
  
  .IN   (i0_crc_in), 
  .SH   (1'b0),  
  .EN   (i0_crc_en),
  .CRC  (i1_crc_cal)
);                                                                                                  
//=================================================================================================
// i1
//=================================================================================================  
always@(posedge CLK or posedge RST)
 if(RST)                                      i1_cmd_en    <=                                 1'b0;
 else if(!i0_cmd_stb                        ) i1_cmd_en    <=                                 1'b0;
 else if(i0_cmd_endbit                      ) i1_cmd_en    <=                                 1'b1; 
 else                                         i1_cmd_en    <=                            i1_cmd_en; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
 if(RST)                                      i1_cmd_en_tic<=                                 1'b0;
 else if(!i0_cmd_stb                        ) i1_cmd_en_tic<=                                 1'b0;
 else if(i0_cmd_endbit                      ) i1_cmd_en_tic<=                                 1'b1; 
 else                                         i1_cmd_en_tic<=                                 1'b0; 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                                      i1_crc_rec   <=                                 1'b0;
 else if(i0_cmd_endbit                      ) i1_crc_rec   <=                           i0_crc_rec; 
 else                                         i1_crc_rec   <=                           i1_crc_rec; 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                                      i1_crc_valid <=                                 1'b0;
 else if(i0_cmd_endbit                      ) i1_crc_valid <=           (i0_crc_rec == i1_crc_cal); 
 else                                         i1_crc_valid <=                         i1_crc_valid;
//=================================================================================================
// Tristate output
//=================================================================================================
assign O_CMD_EN     =                                                                    i1_cmd_en;
assign O_CMD_EN_TIC =                                                                i1_cmd_en_tic;
assign O_CMD        =                                                             i0_cmd_in[133:8];
assign O_CRC        =                                                                   i1_crc_rec;
assign O_CRC_VALID  =                                                                 i1_crc_valid;
assign O_TIMEOUT    =                                                                 i0_timeout_f;
//-------------------------------------------------------------------------------------------------          
endmodule

