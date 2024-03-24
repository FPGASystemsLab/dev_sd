//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
// Mux for: 
// - packets with data read request send to memory,
// - packets with data from SD card to be stored in memory
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module sd_ring_mux
(                                     
input  wire        CLK,            
input  wire        RST,            

// Input for SD register data
input  wire        I_G_STB, 
input  wire        I_G_SOF, 
input  wire [71:0] I_G_DATA,
output wire        I_G_ACK,          

// Input for SD read data
input  wire        I_D_STB, 
input  wire        I_D_SOF, 
input  wire [71:0] I_D_DATA,
output wire        I_D_ACK, 

// Input for requests
input  wire        I_R_STB, 
input  wire        I_R_SOF, 
input  wire [71:0] I_R_DATA,
output wire        I_R_ACK,
                                                                                                    
// Output to ringbus interface
output wire        O_EN, 
output wire        O_SOF, 
output wire [71:0] O_DATA,
input  wire [ 1:0] O_AF
); 
//=================================================================================================
reg  [ 4:0]   i1_g_cnt;
wire          i1_g_pend;
wire          i0_g_start;  

reg  [ 4:0]   i1_d_cnt;
wire          i1_d_pend;
wire          i0_d_start; 

reg  [ 1:0]   i1_r_cnt;
wire          i1_r_pend;
wire          i0_r_start;

//-------------------------------------------------------------------------------------------------
reg           i2_en;
reg  [71:0]   i2_data_mux;
reg           i2_sof_mux;

//=================================================================================================
// start packet sending rules:                         
// - register data input has higher priority than    data input
// -          data input has higher priority than request input
// - sending data is started only if almost full flag is low (!O_AF[1]). After checking the flag 
//   two clock periods past before packet header appear on the output - from i0 to i2 stage. 
//   At this time fifo fullness can change. To prevent that situation start is delayed to the point
//   when i1-i2 pipeline is empty (!i2_en).                                                         
assign i0_g_start =                !i2_en & !O_AF[1] & I_G_STB & I_G_SOF & !i1_r_pend & !i1_g_pend;
assign i0_d_start =                !i2_en & !O_AF[1] & I_D_STB & I_D_SOF & !i1_r_pend &   !I_G_STB;
assign i0_r_start =                !i2_en & !O_AF[0] & I_R_STB & I_R_SOF & !I_D_STB   &   !I_G_STB;
                                                                                                   
//=================================================================================================
always@(posedge CLK or posedge RST)
if(RST)                                      i1_g_cnt      <=                         {1'b0, 4'd0};   
else if(i1_g_pend                          ) i1_g_cnt      <=                      i1_g_cnt - 5'd1;
else if(i0_g_start                         ) i1_g_cnt      <=                         {1'b1, 4'd8};
else                                         i1_g_cnt      <=                             i1_g_cnt;
//-------------------------------------------------------------------------------------------------
assign i1_g_pend  =                                                                    i1_g_cnt[4];
assign I_G_ACK    =                                                                      i1_g_pend; 

//=================================================================================================
always@(posedge CLK or posedge RST)
if(RST)                                      i1_d_cnt      <=                         {1'b0, 4'd0};   
else if(i1_d_pend                          ) i1_d_cnt      <=                      i1_d_cnt - 5'd1;
else if(i0_d_start                         ) i1_d_cnt      <=                         {1'b1, 4'd8};
else                                         i1_d_cnt      <=                             i1_d_cnt;
//-------------------------------------------------------------------------------------------------
assign i1_d_pend  =                                                                    i1_d_cnt[4];
assign I_D_ACK    =                                                                      i1_d_pend; 
                                                                                                    
//=================================================================================================
always@(posedge CLK or posedge RST)                   
if(RST)                                      i1_r_cnt      <=                         {1'b0, 1'd0};   
else if(i1_r_pend                          ) i1_r_cnt      <=                      i1_r_cnt - 2'd1;
else if(i0_r_start                         ) i1_r_cnt      <=                         {1'b1, 1'd1};
else                                         i1_r_cnt      <=                             i1_r_cnt;
//-------------------------------------------------------------------------------------------------
assign i1_r_pend =                                                                     i1_r_cnt[1]; 
assign I_R_ACK    =                                                                      i1_r_pend;

//=================================================================================================
always@(posedge CLK or posedge RST)                   
if(RST)                                      i2_en         <=                                 1'b0; 
else                                         i2_en         <=  i1_r_pend || i1_d_pend || i1_g_pend;

//-------------------------------------------------------------------------------------------------
always@(posedge CLK)                                                                               
     if(i1_g_pend                          ) i2_data_mux   <=                             I_G_DATA;
else if(i1_d_pend                          ) i2_data_mux   <=                             I_D_DATA;
else/* if(i1_r_pend                      )*/ i2_data_mux   <=                             I_R_DATA;
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
if(RST)                                      i2_sof_mux    <=                                 1'd0; 
else if(i1_g_pend                          ) i2_sof_mux    <=                              I_G_SOF;
else if(i1_d_pend                          ) i2_sof_mux    <=                              I_D_SOF;
else/* if(i1_r_pend                      )*/ i2_sof_mux    <=                              I_R_SOF;

//=================================================================================================
assign O_EN     =                                                                            i2_en;
assign O_SOF    =                                                                       i2_sof_mux;
assign O_DATA   =                                                                      i2_data_mux;
//=================================================================================================
endmodule
