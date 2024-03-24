//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module sd_cmd_48b_formater
(                                  
input  wire        CLK,            
input  wire        RST,      
                          
input  wire        I_STB,
input  wire [37:0] I_CMD, 
output wire        I_ACK,
                                      
output wire        O_BIT,              
output wire        O_BIT_EN,           
output wire        O_BIT_LST,
output wire        O_BODY_F,
output wire        O_CRC_F      
);                                                                                                  
//=================================================================================================   
// Variables
//================================================================================================= 
wire        o0_cmd_start;  

//-------------------------------------------------------------------------------------------------
reg         o1_cmd_start;
reg  [39:0] o1_cmd;          
reg  [ 6:0] o1_cmd_tcnt;
reg         o1_no_cmd;
reg  [ 6:0] o1_cmd_ccnt; 
reg         o1_cmd_pending;
wire        o1_cmd_body_f;
wire        o1_cmd_crc_f;  
wire        o1_crc_in;   
wire        o1_crc_en;   
wire        o1_crc_rst; 
reg         o1_crc_sh;

wire        o1_end_bit_end_f;
wire        o1_end_bit_f;  

//-------------------------------------------------------------------------------------------------  
reg         o2_cmd_pending;
reg         o2_cmd_last; 
reg         o2_cmd;    
reg         o2_crc_send;
wire [ 6:0] o2_crc;
                    
//------------------------------------------------------------------------------------------------- 
reg         o3_cmd_pending;
reg         o3_cmd_crc_f;
reg         o3_cmd_body_f;
reg         o3_cmd_last;
reg         o3_cmd;
                                                                                                    
//=================================================================================================   
assign                      o0_cmd_start   =                            (I_STB && !o1_cmd_pending);
assign                      I_ACK          =                                          o1_cmd_start;
//================================================================================================= 
always@(negedge CLK)
                                                                      // START  MOSI      CMD
      if(o0_cmd_start      )o1_cmd    <=                                 {1'b0, 1'b1, I_CMD[37:0]};  
 else                       o1_cmd    <=                                            {o1_cmd, 1'b1}; // shift out 
                                                                                                   
//------------------------------------------------------------------------------------------------- 
always@(negedge CLK or posedge RST)
 if(RST)                    o1_crc_sh <=                                                      1'b0;   
 else                       o1_crc_sh <=                                               o2_crc_send;  

//-------------------------------------------------------------------------------------------------   
assign o1_crc_en      =                                              o0_cmd_start || o1_cmd_body_f;   
assign o1_crc_rst     =                                                                 o1_no_cmd; 
assign o1_crc_in      =                                                                 o1_cmd[39];
//-------------------------------------------------------------------------------------------------
 sd_crc7 cmd_crc(
  .CLK  (CLK),    
  .RST  (o1_crc_rst),   
  
  .IN   (o1_cmd[39]), 
  .SH   (o1_crc_sh),  
  .EN   (o1_crc_en),
  .CRC  (o2_crc)                             
);                                                                                                  
//-------------------------------------------------------------------------------------------------
always@(negedge CLK or posedge RST)
 if(RST)                                      o1_cmd_start<=                                  1'b0;
 else                                         o1_cmd_start<=                          o0_cmd_start;
                                                                                                   
//-------------------------------------------------------------------------------------------------
always@(negedge CLK or posedge RST)
 if(RST)                                      o1_cmd_tcnt <=                                  7'd0;
 else if(o0_cmd_start                       ) o1_cmd_tcnt <=                                 7'd46; 
 else if(o1_cmd_tcnt[6]                     ) o1_cmd_tcnt <=                    o1_cmd_tcnt       ;
 else                                         o1_cmd_tcnt <=                    o1_cmd_tcnt - 7'd1;
                                                                                                    
//------------------------------------------------------------------------------------------------- 
always@(negedge CLK or posedge RST)
 if(RST)                                      o1_no_cmd      <=                               1'd0;  
 else                                         o1_no_cmd      <=                     o1_cmd_tcnt[6];  
   
//-------------------------------------------------------------------------------------------------
always@(negedge CLK or posedge RST)
 if(RST)                                      o1_cmd_ccnt <=                                  7'd0;
 else if(o0_cmd_start                       ) o1_cmd_ccnt <=                                 7'd39; 
 else if(o1_cmd_ccnt[6]                     ) o1_cmd_ccnt <=                    o1_cmd_ccnt       ;
 else                                         o1_cmd_ccnt <=                    o1_cmd_ccnt - 7'd1;
                                                                                                    
//------------------------------------------------------------------------------------------------- 
always@(negedge CLK or posedge RST)
 if(RST)                                      o1_cmd_pending  <=                              1'd0; 
 else if(o0_cmd_start                       ) o1_cmd_pending  <=                              1'd1; 
 else if(o1_cmd_tcnt[6] /*o1 (!sic)*/       ) o1_cmd_pending  <=                              1'd0; 
 else                                         o1_cmd_pending  <=                    o1_cmd_pending;

//------------------------------------------------------------------------------------------------- 
assign o1_cmd_body_f    = o1_cmd_pending & !o1_cmd_ccnt[6];
assign o1_cmd_crc_f     = o1_cmd_pending &  o1_cmd_ccnt[6];                   
assign o1_end_bit_f     = o1_cmd_pending &  o1_cmd_tcnt[6];              
assign o1_end_bit_end_f = o1_cmd_pending &  o1_cmd_tcnt[6];  
//=================================================================================================
// s2
//=================================================================================================  
always@(negedge CLK or posedge RST)
 if(RST)                                      o2_cmd_pending  <=                              1'd0;  
 else                                         o2_cmd_pending  <=                    o1_cmd_pending;
                                                                                                     
                                                                                                   
//------------------------------------------------------------------------------------------------- 
always@(negedge CLK or posedge RST)
 if(RST)                                      o2_cmd_last     <=                              1'd0;  
 else                                         o2_cmd_last     <=                      o1_end_bit_f;
                                                                                                   
//------------------------------------------------------------------------------------------------- 
always@(negedge CLK or posedge RST)
 if(RST)                                      o2_cmd          <=                              1'b1;
 else                                         o2_cmd          <=                        o1_cmd[39];
                                                                 
//-------------------------------------------------------------------------------------------------
always@(negedge CLK or posedge RST)                              
 if(RST)                                      o2_crc_send     <=                              1'b0;
 else                                         o2_crc_send     <=    o1_cmd_crc_f & !o1_cmd_tcnt[6];

//=================================================================================================
// s3
//=================================================================================================  
always@(negedge CLK or posedge RST)
 if(RST)                                      o3_cmd_pending <=                               1'd0;  
 else                                         o3_cmd_pending <=                     o2_cmd_pending;
                                                                                                    
//-------------------------------------------------------------------------------------------------  
always@(negedge CLK or posedge RST)                             
 if(RST)                                      o3_cmd_crc_f   <=                               1'd0;  
 else                                         o3_cmd_crc_f   <=                        o2_crc_send;
                                                                                                   
//-------------------------------------------------------------------------------------------------  
always@(negedge CLK or posedge RST)                             
 if(RST)                                      o3_cmd_body_f  <=                               1'd0;  
 else                                         o3_cmd_body_f  <=     o2_cmd_pending && !o2_crc_send;
                                                                                                   
//-------------------------------------------------------------------------------------------------  
always@(negedge CLK or posedge RST)                             
 if(RST)                                      o3_cmd_last    <=                               1'd0;  
 else                                         o3_cmd_last    <=                        o2_cmd_last;
                                                                                                       
//------------------------------------------------------------------------------------------------- 
always@(negedge CLK or posedge RST)
 if(RST)                                      o3_cmd         <=                               1'b1;
 else                                         o3_cmd         <=  (o2_crc_send)? o2_crc[6] : o2_cmd;  
                                                                                                   
//================================================================================================= 
assign O_BIT      =                                                                         o3_cmd; 
assign O_BIT_EN   =                                                                 o3_cmd_pending; 
assign O_BIT_LST  =                                                                    o3_cmd_last; 
assign O_CRC_F    =                                                                   o3_cmd_crc_f; 
assign O_BODY_F   =                                                                  o3_cmd_body_f;
//-------------------------------------------------------------------------------------------------          
endmodule

