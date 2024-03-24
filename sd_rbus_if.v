//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
// Input for new events with data read/write from/to SD card.
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns              
//=============================================================================
module sd_rbus_if
(                                     
input  wire        clk_net,            
input  wire        rst_net,         

// network interface
input  wire         net_i_stb,                                 
input  wire         net_i_sof,
input  wire [71:0]  net_i_data,
output wire  [1:0]  net_i_rdy,

output wire         net_o_stb,  
output wire         net_o_sof,  
output wire [71:0]  net_o_data,
input wire   [1:0]  net_o_rdy, 
input wire   [1:0]  net_o_rdyE,  

// network interface
input  wire         dev_i_stb,                                 
input  wire         dev_i_sof,
input  wire [71:0]  dev_i_data,
output wire  [1:0]  dev_i_rdy,

output wire         dev_o_stb,  
output wire         dev_o_sof,  
output wire [71:0]  dev_o_data,
input wire   [1:0]  dev_o_rdy,   
           
input  wire        clk_sd,            
input  wire        rst_sd,

input  wire        sd_initialized,

// Output requests
output wire        sd_soft_rst,
output reg         sd_req_rd_stb, 
output reg         sd_req_wr_stb,
output reg         sd_req_reg_stb,
output reg  [38:0] sd_req_mem_addr,
output reg  [38:0] sd_req_sd_addr,
output reg  [15:0] sd_req_mul_m1,
input  wire        sd_req_ack,

output wire        ff_err
 
); 
//=================================================================================================
wire         sd_bsy;   

//------------------------------------------------------------------------------------------------- 
wire         sd0_d2r_eve_stb; 
wire   [7:0] sd0_d2r_eve_dev;
wire   [7:0] sd0_d2r_eve_cmd;
wire  [39:0] sd0_d2r_eve_ptr;
wire         sd0_d2r_eve_ack;

wire         sd0_r2d_eve_stb;
wire   [7:0] sd0_r2d_eve_cmd;
wire  [39:0] sd0_r2d_eve_ptr;
wire         sd0_r2d_eve_ack;
wire         sd0_r2d_eve_ena;

//-------------------------------------------------------------------------------------------------   
wire         sd1_r2d_stb;  
wire         sd1_r2d_hdr;  
wire  [71:0] sd1_r2d_data; 
wire   [1:0] sd1_r2d_rdy;   
                        
wire         sd1_d2r_stb;  
wire         sd1_d2r_hdr;
wire  [71:0] sd1_d2r_data; 
wire   [1:0] sd1_d2r_rdy; 

//=================================================================================================
// interdomain fifo
rbus_bridge iff_mem_2_sd 
(
.i_clk    (clk_net),
.i_rst    (rst_net),
.i_stb    (net_i_stb), 
.i_sof    (net_i_sof), 
.i_data   (net_i_data),
.i_rdy    (net_i_rdy),  

.o_clk    (clk_sd),
.o_rst    (rst_sd),
.o_stb    (sd1_r2d_stb), 
.o_sof    (sd1_r2d_hdr), 
.o_data   (sd1_r2d_data),
.o_rdy    (sd1_r2d_rdy)  
);                  
//------------------------------------------------------------------------------------------------- 
rbus_bridge iff_sd_2_mem 
(
.i_clk    (clk_sd),
.i_rst    (rst_sd),
.i_stb    (sd1_d2r_stb), 
.i_sof    (sd1_d2r_hdr), 
.i_data   (sd1_d2r_data),
.i_rdy    (sd1_d2r_rdy),  

.o_clk    (clk_net),
.o_rst    (rst_net),
.o_stb    (net_o_stb), 
.o_sof    (net_o_sof), 
.o_data   (net_o_data),
.o_rdy    (net_o_rdy)  
);             
//============================================================================================== 
// device if with event catch
rbus_devif  
#(
  .DEVICE_CLASS   (8'h4), 
  .DEVICE_VER     (8'h10),  
  .DEVICE_FEATURES(48'd0)
)
sd_rbus_if
(
  .clk            (clk_sd),     
  .rst            (rst_sd),   
                            
  .net_i_stb      (sd1_r2d_stb),  
  .net_i_sof      (sd1_r2d_hdr),  
  .net_i_data     (sd1_r2d_data), 
  .net_i_rdy      (sd1_r2d_rdy),   
                           
  .net_o_stb      (sd1_d2r_stb),  
  .net_o_sof      (sd1_d2r_hdr),  
  .net_o_data     (sd1_d2r_data), 
  .net_o_rdy      (sd1_d2r_rdy),                                                          
  .net_o_rdyE     (sd1_d2r_rdy), // connected through a bridge that do not support rdyE signals 

  .dev_o_rst      (sd_soft_rst), 

  .dev_i_stb      (dev_i_stb),  
  .dev_i_sof      (dev_i_sof),  
  .dev_i_data     (dev_i_data),
  .dev_i_rdy      (dev_i_rdy),    

  .dev_i_eve_stb  (sd0_d2r_eve_stb), 
  .dev_i_eve_dev  (sd0_d2r_eve_dev),
  .dev_i_eve_cmd  (sd0_d2r_eve_cmd),
  .dev_i_eve_ptr  (sd0_d2r_eve_ptr),
  .dev_i_eve_ack  (sd0_d2r_eve_ack),
                                   
  .dev_o_stb      (dev_o_stb), 
  .dev_o_sof      (dev_o_sof), 
  .dev_o_data     (dev_o_data),
  .dev_o_rdy      (dev_o_rdy),   
                                         
  .dev_o_eve_stb  (sd0_r2d_eve_stb),
  .dev_o_eve_cmd  (sd0_r2d_eve_cmd),
  .dev_o_eve_ptr  (sd0_r2d_eve_ptr),
  .dev_o_eve_ack  (sd0_r2d_eve_ack),
  
  .ff_err         (ff_err)
);     
                                                                                                    
//-------------------------------------------------------------------------------------------------
always@(posedge clk_sd or posedge rst_sd)
  if(rst_sd)                          sd_req_rd_stb   <=                                      1'd0;
  else if(!sd_initialized       )     sd_req_rd_stb   <=                                      1'd0;      
  else if(sd0_r2d_eve_ena       )     sd_req_rd_stb   <=             sd0_r2d_eve_cmd[7:0] == 8'h40;
  else if(sd_req_ack            )     sd_req_rd_stb   <=                                      1'b0; 
//------------------------------------------------------------------------------------------------- 
always@(posedge clk_sd or posedge rst_sd)
  if(rst_sd)                          sd_req_wr_stb   <=                                      1'd0; 
  else if(!sd_initialized       )     sd_req_wr_stb   <=                                      1'd0;  
  else if(sd0_r2d_eve_ena       )     sd_req_wr_stb   <=             sd0_r2d_eve_cmd[7:0] == 8'h41; 
  else if(sd_req_ack            )     sd_req_wr_stb   <=                                      1'b0; 
//-------------------------------------------------------------------------------------------------
always@(posedge clk_sd or posedge rst_sd)
  if(rst_sd)                          sd_req_reg_stb  <=                                      1'd0; 
//else if(!sd_initialized       )     sd_req_reg_stb  <=                                      1'd0;  
  else if(sd0_r2d_eve_ena       )     sd_req_reg_stb  <=             sd0_r2d_eve_cmd[7:0] == 8'h45; 
  else if(sd_req_ack            )     sd_req_reg_stb  <=                                      1'b0; 
//-------------------------------------------------------------------------------------------------
always@(posedge clk_sd or posedge rst_sd)
  if(rst_sd)                          sd_req_mem_addr <=                                                           39'h7FFFFFFFFF;  
  else if(sd0_r2d_eve_ena       )     sd_req_mem_addr <= (sd0_r2d_eve_cmd[7:0] == 8'h42)? sd0_r2d_eve_ptr[38:0] : sd_req_mem_addr;
  else                                sd_req_mem_addr <=                                                          sd_req_mem_addr; 
//-------------------------------------------------------------------------------------------------
always@(posedge clk_sd or posedge rst_sd)
  if(rst_sd)                          sd_req_sd_addr  <=                                                           39'h7FFFFFFFFF;    
  else if(sd0_r2d_eve_ena       )     sd_req_sd_addr  <= (sd0_r2d_eve_cmd[7:0] == 8'h43)? sd0_r2d_eve_ptr[38:0] :  sd_req_sd_addr;
  else                                sd_req_sd_addr  <=                                                           sd_req_sd_addr; 
//-------------------------------------------------------------------------------------------------
always@(posedge clk_sd or posedge rst_sd)
  if(rst_sd)                          sd_req_mul_m1   <=                                                                 16'd0;    
  else if(sd0_r2d_eve_ena       )     sd_req_mul_m1   <= (sd0_r2d_eve_cmd[7:0] == 8'h44)? sd0_r2d_eve_ptr[15:0] : sd_req_mul_m1;
  else                                sd_req_mul_m1   <=                                                          sd_req_mul_m1; 
//-------------------------------------------------------------------------------------------------  
assign sd_bsy          =                        (sd_req_wr_stb || sd_req_rd_stb || sd_req_reg_stb); 
assign sd0_r2d_eve_ena =                                                 sd0_r2d_eve_stb & !sd_bsy;
assign sd0_r2d_eve_ack =                                                           sd0_r2d_eve_ena;

assign sd0_d2r_eve_stb =  1'b0;
assign sd0_d2r_eve_dev =  8'b0;
assign sd0_d2r_eve_cmd =  8'b0;
assign sd0_d2r_eve_ptr = 40'b0;
// sd0_d2r_eve_ack
//=================================================================================================
endmodule
