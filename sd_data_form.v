//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module sd_data_form
#(
parameter  [31:0] AVAIL_DATA_BITS      =  32'd4      // 1 - only one data lane available; 4 - four data lanes
)
(                  
input  wire        SD_CLK,             
input  wire        RST,            
                             
input  wire        SD_I_TRG,  
output wire        SD_I_DONE,

// SD_CLK domain input
input  wire        SD_I_PKT_RDY, 
input  wire [ 63:0]SD_I_DAT,   
output wire        SD_I_ACK,
input  wire        SD_I_FIRST,  
input  wire        SD_I_LAST, 

// SD_CLK domain output
output wire [(AVAIL_DATA_BITS-'d1):0]SD_O_DAT,
output wire        SD_OE
);                                                                                                  
//=================================================================================================   
// Variables
//================================================================================================= 
localparam IDLE                     =  32'h00000000;
localparam WAIT_PKT                 =  32'h00000001;
localparam SEND_START               =  32'h00000002;
localparam SEND_DATA                =  32'h00000004;
localparam SEND_CRC                 =  32'h00000008;
localparam SEND_END                 =  32'h00000010;

//------------------------------------------------------------------------------------------------- 
integer     state;
wire        state_idle_f;      
wire        state_wait_pkt_f;    
wire        state_send_start_f;   
wire        state_send_data_f;   
wire        state_send_crc_f;   
wire        state_send_end_f;    

//-------------------------------------------------------------------------------------------------
reg         o0_data_load; 
reg  [  6:0]o0_64nib_ptr;
wire        o0_64nib_last; 
wire        o0_64nib_1blast;
wire        o0_512nib_last;
wire        o0_crc_last;

//------------------------------------------------------------------------------------------------- 
reg         o1_en;      
reg  [ 63:0]o1_data; 
reg         o1_last_dw;
reg  [  1:0]o1_mux_ctrl;
                         
wire        o1_crc_rst;                                                                             
reg         o1_crc_en; 
wire [  3:0]o1_crc_data;                                     
//------------------------------------------------------------------------------------------------- 
reg         o2_en;
reg  [(AVAIL_DATA_BITS-'d1):0]o2_data;
reg  [  1:0]o2_mux_ctrl;

//-------------------------------------------------------------------------------------------------                                                          
reg         o2_crc_sh; 
wire [ 15:0]o2_crc_out[0:3];                        
wire [  3:0]o2_crc_out_4msb;                        
wire        o2_crc_out_1msb;      
wire [(AVAIL_DATA_BITS-'d1):0]o2_crc_out_mux;  
reg         o2_endbit_f;
                         
//-------------------------------------------------------------------------------------------------
reg         o3_en;
reg  [(AVAIL_DATA_BITS-'d1):0]o3_data_mux; 
reg         o3_endbit_f;

//------------------------------------------------------------------------------------------------- 
assign state_idle_f         =                                             (state == IDLE         );
assign state_wait_pkt_f     =                                             (state == WAIT_PKT     );
assign state_send_start_f   =                                             (state == SEND_START   );
assign state_send_data_f    =                                             (state == SEND_DATA    );
assign state_send_crc_f     =                                             (state == SEND_CRC     );
assign state_send_end_f     =                                             (state == SEND_END     );

//=================================================================================================
// STATE MACHINE
//=================================================================================================

always@(posedge SD_CLK or posedge RST)
 if(RST)                                                state   <=                          IDLE;
 else case(state)                                                  
 IDLE:          if(SD_I_TRG                           ) state   <=                      WAIT_PKT; 
           else                                         state   <=                          IDLE;
 WAIT_PKT:      if(SD_I_PKT_RDY                       ) state   <=                    SEND_START; 
           else                                         state   <=                      WAIT_PKT;                                                                 
 SEND_START:                                            state   <=                     SEND_DATA;                                                                 
 SEND_DATA:     if(o0_512nib_last                     ) state   <=                      SEND_CRC;                                                                 
           else                                         state   <=                     SEND_DATA;                                                                 
 SEND_CRC:      if(o0_crc_last                        ) state   <=                      SEND_END;                                                                
           else                                         state   <=                      SEND_CRC;   
 SEND_END:                                              state   <=                          IDLE;                                                                 
 endcase   
                                                                                                    
//-------------------------------------------------------------------------------------------------
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o0_data_load  <=                                 1'b0;        
else if(state_send_start_f                 ) o0_data_load  <=                                 1'b1;      
else if(state_send_data_f & o0_64nib_1blast) o0_data_load  <=                          !o1_last_dw; 
else                                         o0_data_load  <=                                 1'b0; 

//-------------------------------------------------------------------------------------------------
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o0_64nib_ptr  <=                          {1'b0,6'hx};      
else if(state_send_start_f                 ) o0_64nib_ptr  <= (AVAIL_DATA_BITS=='d4)?7'd15 : 7'd63;      
else if(      o1_last_dw && o0_64nib_last  ) o0_64nib_ptr  <=                        7'd14        ; // 16 bits of CRC     
else if(                    o0_64nib_last  ) o0_64nib_ptr  <= (AVAIL_DATA_BITS=='d4)?7'd14 : 7'd62; // 16 / 64 data bits
else                                         o0_64nib_ptr  <=                  o0_64nib_ptr - 7'd1; 

//------------------------------------------------------------------------------------------------- 
assign o0_64nib_last   =                                                           o0_64nib_ptr[6]; 
assign o0_64nib_1blast =                                                 o0_64nib_ptr[5:0] == 6'd0; 
assign o0_512nib_last  =                                               o1_last_dw && o0_64nib_last;
assign o0_crc_last     =                                         state_send_crc_f && o0_64nib_last;

//------------------------------------------------------------------------------------------------- 
assign SD_I_ACK       =                                                               o0_data_load;
//================================================================================================= 
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o1_en         <=                                 1'd0;        
else if(state_send_start_f                 ) o1_en         <=                                 1'b1;        
else if(state_send_data_f                  ) o1_en         <=                                 1'b1;        
else if(state_send_crc_f                   ) o1_en         <=                                 1'b1; 
else                                         o1_en         <=                                 1'b0; 
                                                                                                   
//-------------------------------------------------------------------------------------------------
// in on byte sending order is: from MSb to LSb
// in a whole packet it is:     from LSB to MSB
always@(posedge SD_CLK)
     if(o0_data_load                    ) o1_data <= {SD_I_DAT[7:0], SD_I_DAT[15:8], SD_I_DAT[23:16], SD_I_DAT[31:24], SD_I_DAT[39:32], SD_I_DAT[47:40], SD_I_DAT[55:48], SD_I_DAT[63:56]};      
else if(state_send_data_f               ) o1_data <= (AVAIL_DATA_BITS=='d4)? {o1_data[59:0], 4'hF}: 
                                                                             {o1_data[62:0], 1'h1}; 
else                                      o1_data <=                                       o1_data;
  
//-------------------------------------------------------------------------------------------------
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o1_last_dw    <=                                 1'd0;        
else if(o0_data_load                       ) o1_last_dw    <=                            SD_I_LAST;        
else if(state_send_end_f                   ) o1_last_dw    <=                                 1'b0; 
else                                         o1_last_dw    <=                           o1_last_dw; 
                                                                                                 
//-------------------------------------------------------------------------------------------------
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o1_mux_ctrl   <=                                 2'd3;      
else if(state_send_start_f                 ) o1_mux_ctrl   <=                                 2'd0;      
else if(state_send_data_f                  ) o1_mux_ctrl   <= (o0_512nib_last)?        2'd2 : 2'd1;      
else if(state_send_crc_f                   ) o1_mux_ctrl   <= (o0_64nib_last )?        2'd3 : 2'd2; 
else                                         o1_mux_ctrl   <=                                 2'd3; 
                                                                                              
//------------------------------------------------------------------------------------------------- 
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o1_crc_en     <=                                 1'd0;    
else if(state_send_data_f                  ) o1_crc_en     <= (o0_512nib_last)?        1'b0 : 1'b1; 
else                                         o1_crc_en     <=                                 1'b0; 
                                                                                                    
//-------------------------------------------------------------------------------------------------       
assign o1_crc_rst =                                                             state_send_start_f;
assign o1_crc_data= (AVAIL_DATA_BITS=='d4)?                    o1_data[63:60]: {3'd0, o1_data[63]}; 
//=================================================================================================
sd_crc16 dat_crc3(
  .CLK  (SD_CLK),    
  .RST  ((AVAIL_DATA_BITS=='d4)? o1_crc_rst     : 1'b0),   
  
  .IN   ((AVAIL_DATA_BITS=='d4)? o1_crc_data[3] : 1'b0), 
  .SH   ((AVAIL_DATA_BITS=='d4)? o2_crc_sh      : 1'b0),  
  .EN   ((AVAIL_DATA_BITS=='d4)? o1_crc_en      : 1'b0),
  .CRC  (o2_crc_out[3])
);                                                                                             
//-------------------------------------------------------------------------------------------------
sd_crc16 dat_crc2(
  .CLK  (SD_CLK),    
  .RST  ((AVAIL_DATA_BITS=='d4)? o1_crc_rst     : 1'b0),   
  
  .IN   ((AVAIL_DATA_BITS=='d4)? o1_crc_data[2] : 1'b0), 
  .SH   ((AVAIL_DATA_BITS=='d4)? o2_crc_sh      : 1'b0),  
  .EN   ((AVAIL_DATA_BITS=='d4)? o1_crc_en      : 1'b0),
  .CRC  (o2_crc_out[2])
);                                                                                             
//-------------------------------------------------------------------------------------------------
sd_crc16 dat_crc1(
  .CLK  (SD_CLK),    
  .RST  ((AVAIL_DATA_BITS=='d4)? o1_crc_rst     : 1'b0),   
  
  .IN   ((AVAIL_DATA_BITS=='d4)? o1_crc_data[1] : 1'b0), 
  .SH   ((AVAIL_DATA_BITS=='d4)? o2_crc_sh      : 1'b0),  
  .EN   ((AVAIL_DATA_BITS=='d4)? o1_crc_en      : 1'b0),
  .CRC  (o2_crc_out[1])
);                                                                                             
//-------------------------------------------------------------------------------------------------
sd_crc16 dat_crc0(
  .CLK  (SD_CLK),    
  .RST  (o1_crc_rst),   
  
  .IN   (o1_crc_data[0]), 
  .SH   (o2_crc_sh),  
  .EN   (o1_crc_en),
  .CRC  (o2_crc_out[0])
);                                                                                             

//================================================================================================= 
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o2_crc_sh     <=                                 1'd0;    
else if(o1_mux_ctrl == 2'd2                ) o2_crc_sh     <=                                 1'b1; 
else                                         o2_crc_sh     <=                                 1'b0; 
//-------------------------------------------------------------------------------------------------     
assign o2_crc_out_4msb = {o2_crc_out[3][15], o2_crc_out[2][15], o2_crc_out[1][15], o2_crc_out[0][15]};
assign o2_crc_out_1msb =                                                           o2_crc_out[0][15];
assign o2_crc_out_mux  = (AVAIL_DATA_BITS=='d4)?                 o2_crc_out_4msb : o2_crc_out_1msb;

//------------------------------------------------------------------------------------------------- 
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o2_mux_ctrl    <=                                1'd0; 
else                                         o2_mux_ctrl    <=                         o1_mux_ctrl; 
//------------------------------------------------------------------------------------------------- 
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o2_data     <=                                     -1;        
else                                         o2_data     <= (AVAIL_DATA_BITS=='d4)? o1_data[63:60]:
                                                                                    o1_data[63   ];

//-------------------------------------------------------------------------------------------------
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o2_en         <=                                 1'b0;
else                                         o2_en         <=                                o1_en;
  
//-------------------------------------------------------------------------------------------------
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o2_endbit_f   <=                                 1'b0;
else                                         o2_endbit_f   <=                     state_send_end_f;  
                                                                                                       
//================================================================================================= 
always@(posedge SD_CLK)
     if(o2_mux_ctrl == 2'd0    ) o3_data_mux <=                                                'd0; // start bit 0     
else if(o2_mux_ctrl == 2'd1    ) o3_data_mux <=                                            o2_data; // data      
else if(o2_mux_ctrl == 2'd2    ) o3_data_mux <=                                     o2_crc_out_mux; // crc
else /*if(o2_mux_ctrl == 2'd3)*/ o3_data_mux <=                                                 -1; // end bit 1
                                                                                                    
//-------------------------------------------------------------------------------------------------
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o3_en         <=                                 1'b0;
else                                         o3_en         <=                                o2_en; 
  
//-------------------------------------------------------------------------------------------------
always@(posedge SD_CLK or posedge RST)
if(RST)                                      o3_endbit_f   <=                                 1'b0;
else                                         o3_endbit_f   <=                          o2_endbit_f; 
 
//================================================================================================= 
// OUTPUT
//================================================================================================= 
assign SD_O_DAT   =                                                                    o3_data_mux;
assign SD_OE      =                                                                          o3_en;

assign SD_I_DONE  =                                                                    o3_endbit_f;
//-------------------------------------------------------------------------------------------------          
endmodule

