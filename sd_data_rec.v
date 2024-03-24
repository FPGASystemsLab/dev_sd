//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module sd_data_rec
#(
parameter  [31:0] AVAIL_DATA_BITS      =  32'd4      // 1 - only one data lane available; 4 - four data lanes
)
(                                  
input  wire        CLK,            
input  wire        RST,            

// SD input
input  wire [(AVAIL_DATA_BITS-'d1):0]I_BITS,

// address input
input  wire [ 38:0]I_ADDR,
input  wire        I_ADDR_EN, 

input  wire        I_RD_EN,  
input  wire        I_RD_INT,
input  wire        I_RD_INT_MODE,
output wire        I_RD_END,
output wire        I_RD_ACK,
output wire        I_RD_ERR,
input  wire        I_RD_RST,

output wire        O_RD_FF_AF,
                             
// data output - already formated into ringbus packets
output wire [ 71:0]O_DAT, 
output wire        O_STB,
output wire        O_SOF, 
input  wire        O_ACK, 
                             
output wire        O_INT_ENA, 
output wire [  2:0]O_INT_PTR,
output wire [ 71:0]O_INT_DAT,
output wire        O_INT_MODE//,

//output wire        O_TIMEOUT     
);                  
//================================================================================================= 
// min 100ms should be waited before timeout. For max clk = 104MHz it is 10400000 periods of clock 
parameter     DAT_TIMEOUT  =                  26'd10400000; 
//=================================================================================================
// Input                                                                                           
//================================================================================================= 
reg  [  3:0]  ixl_bits;                                                                       
reg  [  3:0]  ixh_bits;                                                                       
reg           ix_bits_z;

reg  [ 63:0]  i0_dat_in;
reg           ix_stb;   
wire          ix_start; 
reg           ix_d_pend;  
reg  [  6:0]  ix_dwcnt;
reg  [  6:0]  ix_ncnt;
reg  [  4:0]  ix_ccnt;  
reg           ix_c_pend;
                          
wire          ix_crc_f;          
wire          ix_crc_en; 
wire  [  3:0] ix_crc_in;
wire          ix_crc_rst;   

//wire          i0_timeout_f;
//reg   [ 25:0] i0_timeout_cnt;

//------------------------------------------------------------------------------------------------- 
reg           i0_ff_en;      
reg           i0_ff_dw8_last; 
reg           i0_ff_pkt_last; 
wire  [ 71:0] i0_ff_d_in; 
reg   [  8:0] i0_ff_addr;    
reg   [  3:0] i0_ff_buf_cnt;

wire          ix_byte_nibble_low;
wire          ix_last_ddw_nibble;
wire          ix_last_d_dword   ;  
wire          ix_last_d_nibble  ; 

wire          ix_last_c_nibble  ;   
wire  [ 15:0] i0_crc_rec01;
wire  [ 15:0] i0_crc_rec04;
wire  [ 15:0] i0_crc_rec0;
wire  [ 15:0] i0_crc_rec1;
wire  [ 15:0] i0_crc_rec2;
wire  [ 15:0] i0_crc_rec3; 

wire          ix_last_pkt_nibble;
//-------------------------------------------------------------------------------------------------                                                                          
reg           i1_en;    
wire  [ 15:0] i0_crc_cal3;
wire  [ 15:0] i0_crc_cal2;
wire  [ 15:0] i0_crc_cal1;
wire  [ 15:0] i0_crc_cal0;
reg           i0_last_pkt_nibble; 
                                 
reg   [(AVAIL_DATA_BITS-'d1):0] i1_crc_valid;  
                         
reg           i2_en;  
reg           i2_trg;
reg           i2_crc_valid;
reg           i2_pkt_ok; 
reg           i2_pkt_err; 
                             
wire          i2_id_ack_trg; 
wire          i2_id_rej_trg;

//-------------------------------------------------------------------------------------------------                          
wire          o0_pkt_en;
wire          o0_pkt_rej;    

wire          o0_pkt_int;
wire          o0_pkt_int_mode;
                             
//-------------------------------------------------------------------------------------------------   

wire          o1_pkt_ack_rej_stb; 
wire          o1_pkt_ack_rej;  

wire          o1_pkt_int;
wire          o1_pkt_int_mode;
                 
wire          o1_pkt_ok; 
wire          o1_pkt_rej; 
                     
wire          o1_rdy_f;  
                                       
//------------------------------------------------------------------------------------------------- 
wire          o2_ff_en;   
wire          o2_ff_ack;   
wire  [ 71:0] o2_ff_d;   
reg   [  8:0] o2_ff_addr;   

wire          o2_pkt_end; 

wire          o2_ff_d_dw8_last;
wire          o2_ff_d_pkt_last; 
                         
reg           o2_pkt_ok; 
reg           o2_pkt_rej;    

reg           o2_pkt_int; 
reg           o2_pkt_int_mode;   

reg           o2_pkt_hdr_f; 
wire          o2_pkt_addr_inc;
reg   [ 38:0] o2_pkt_addr;   
wire  [  3:0] o2_pkt_rid;    
wire  [  3:0] o2_pkt_sid;   
wire  [ 71:0] o2_pkt_hdr;
reg           o2_pkt_pend;
reg           o2_dw8_pend;
                         
//-------------------------------------------------------------------------------------------------                                                                             
reg           o3_pkt_end;
reg           o3_pkt_ok;
reg           o3_pkt_err;                                                                            

reg   [ 71:0] o3_pkt_mux;  
reg           o3_ff_sof;  
wire          o3_ff_af10; 
wire          o3_ff_af2;
reg           o3_ff_en;
reg           o3_dw8_last;
wire          o3_ff_err;

reg           o3_int_enx;
wire          o3_int_en;
reg   [  2:0] o3_int_ptr; 
reg           o3_int_mode;                                                                          

//------------------------------------------------------------------------------------------------- 
wire          o4_o_sof;
wire          o4_o_stb;
wire  [ 71:0] o4_o_dat; 
wire          o4_o_ack;   
                                                                                                    
//=================================================================================================    
// i0 
//=================================================================================================  
always@(posedge CLK or posedge RST)
if(RST)                                      ix_stb    <=                                     1'b0; 
else                                         ix_stb    <=                                  I_RD_EN; 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK )                        ixl_bits  <= (AVAIL_DATA_BITS=='d4)? I_BITS        : {ixl_bits[2:0],   I_BITS[0]};  
always@(posedge CLK )                        ixh_bits  <= (AVAIL_DATA_BITS=='d4)? ixl_bits[3:0] : {ixh_bits[2:0], ixl_bits[3]};
//-------------------------------------------------------------------------------------------------  
always@(posedge CLK or posedge RST)
if(RST)                                      ix_bits_z <=                                     1'b0; 
else                                         ix_bits_z <= (AVAIL_DATA_BITS=='d4)? (I_RD_EN & (I_BITS == 4'd0)) : 
                                                                                  (I_RD_EN & (I_BITS == 1'd0));  
//------------------------------------------------------------------------------------------------- 
assign ix_start  =                                             !ix_d_pend & !ix_c_pend & ix_bits_z; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                      ix_d_pend <=                                     1'b0; 
else if(!ix_stb                            ) ix_d_pend <=                                     1'b0; 
else if( ix_start                          ) ix_d_pend <=                                     1'b1; 
else if( ix_last_d_nibble                  ) ix_d_pend <=                                     1'b0; 
else                                         ix_d_pend <=                                ix_d_pend;  
//-------------------------------------------------------------------------------------------------
// total counter - count down dwords of 512-byte packet
always@(posedge CLK or posedge RST)
if(RST)                                      ix_dwcnt <=                                     7'h7F; 
else if(ix_start & I_RD_INT                ) ix_dwcnt <=                                      7'd6; 
else if(ix_start                           ) ix_dwcnt <=                                     7'd62; 
else if(ix_last_d_dword                    ) ix_dwcnt <=                           ix_dwcnt       ;
else if(ix_last_ddw_nibble                 ) ix_dwcnt <=                           ix_dwcnt - 7'd1; 
else                                         ix_dwcnt <=                           ix_dwcnt       ;
                                                                                                   
//-------------------------------------------------------------------------------------------------
// crc counter - count down bits from start of crc
always@(posedge CLK or posedge RST)
 if(RST)                                     ix_ncnt <=                                      7'h7F; 
 else if(ix_start                          ) ix_ncnt <= (AVAIL_DATA_BITS=='d4)?      7'd14 : 7'd62;  
 else if(ix_last_ddw_nibble                ) ix_ncnt <= (AVAIL_DATA_BITS=='d4)?      7'd14 : 7'd62;
 else if(ix_d_pend || ix_c_pend            ) ix_ncnt <=                             ix_ncnt - 7'd1;
 else                                        ix_ncnt <=                             ix_ncnt       ;
   
//-------------------------------------------------------------------------------------------------  
assign ix_byte_nibble_low=  (AVAIL_DATA_BITS=='d4)?                     ix_ncnt[0] : &ix_ncnt[2:0];
assign ix_last_ddw_nibble=                                                              ix_ncnt[6];
assign ix_last_d_dword   =                                                             ix_dwcnt[6];
assign ix_last_d_nibble  =                                    ix_last_d_dword & ix_last_ddw_nibble; 
//=================================================================================================    
// i0 
//=================================================================================================  
//always@(posedge CLK or posedge RST)
// if(RST)                                     i0_timeout_cnt <=                         DAT_TIMEOUT;
// else if(!ix_stb                           ) i0_timeout_cnt <=                         DAT_TIMEOUT;
// else                                        i0_timeout_cnt <=              i0_timeout_cnt - 26'd1; 
////-------------------------------------------------------------------------------------------------
//assign i0_timeout_f  =                                                          i0_timeout_cnt[25]; 
////------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if(i1_en                              ) i0_dat_in <=                                i0_dat_in; 
else if(ix_stb & ix_byte_nibble_low        ) i0_dat_in <={ixh_bits[3:0], ixl_bits[3:0], i0_dat_in[63:8]};   
                                                                                                    
                                                                                                   
//=================================================================================================
// output buffer
//=================================================================================================           
always@(posedge CLK or posedge RST)
     if(RST                                ) i0_ff_addr <=                                    9'd0; 
else if(i0_ff_en                           ) i0_ff_addr <=                  i0_ff_addr[8:0] + 9'd1;     
else                                         i0_ff_addr <=                              i0_ff_addr; 
  
//-------------------------------------------------------------------------------------------------        
always@(posedge CLK or posedge RST)
if(RST)                                      i0_ff_buf_cnt<=                                  4'd7; 
else if( ix_start & !o2_pkt_end            ) i0_ff_buf_cnt<=                  i0_ff_buf_cnt - 4'd1; 
else if(!ix_start &  o2_pkt_end            ) i0_ff_buf_cnt<=                  i0_ff_buf_cnt + 4'd1;
else                                         i0_ff_buf_cnt<=                  i0_ff_buf_cnt       ;
                                                                                                   
//-------------------------------------------------------------------------------------------------     
always@(posedge CLK or posedge RST)
if(RST)                                      i0_ff_en   <=                                    1'b0;  
else if(ix_d_pend && ix_last_ddw_nibble    ) i0_ff_en   <=                                    1'b1;     
else                                         i0_ff_en   <=                                    1'b0;  
                                                                                                      
//-------------------------------------------------------------------------------------------------        
always@(posedge CLK or posedge RST)
if(RST)                                      i0_ff_dw8_last <=                                1'b0;     
else                                         i0_ff_dw8_last <=               ix_dwcnt[2:0] == 3'h7;
                                                                                                 
//-------------------------------------------------------------------------------------------------        
always@(posedge CLK or posedge RST)
if(RST)                                      i0_ff_pkt_last <=                                1'b0;       
else                                         i0_ff_pkt_last <=                     ix_last_d_dword;
                                                                                                    
//------------------------------------------------------------------------------------------------- 
assign i0_ff_d_in        =                 {6'd0, i0_ff_dw8_last, i0_ff_pkt_last, i0_dat_in[63:0]}; 
                                                                                                     
//------------------------------------------------------------------------------------------------- 
// assign info that currently the last buffer for 512B packet is in use so read should be stopped
assign O_RD_FF_AF =                                                               i0_ff_buf_cnt[3];
//------------------------------------------------------------------------------------------------- 
// 8 x 512-bajt packets BRAM
BRAM_SDP_MACRO 
#( 
.BRAM_SIZE              ("36Kb"),  
.DEVICE                 ("7SERIES"), 
.DO_REG                 (0),  
.SIM_COLLISION_CHECK    ("ALL"),  
.WRITE_MODE             ("WRITE_FIRST"), 
.READ_WIDTH             (72),
.WRITE_WIDTH            (72)
)
ff_interd_to_sd (
.RST        (RST),
.WRCLK      (CLK),
.RDCLK      (CLK),

.WREN       (i0_ff_en),
.WE         (8'hFF),    // Byte-Wide Write enable  - just for 8 bytes [63:0], and not for [71:64] byte
.WRADDR     (i0_ff_addr),
.DI         (i0_ff_d_in),

.RDEN       (o2_ff_en),
.RDADDR     (o2_ff_addr),
.REGCE      (),
.DO         (o2_ff_d)
);                                                                                                 

//=================================================================================================
// CRC
//=================================================================================================
always@(posedge CLK or posedge RST)
if(RST)                                      ix_c_pend  <=                                    1'b0; 
else if(!ix_stb                            ) ix_c_pend  <=                                    1'b0; 
else if( ix_last_d_nibble & ix_d_pend      ) ix_c_pend  <=                                    1'b1; 
else if( ix_last_c_nibble                  ) ix_c_pend  <=                                    1'b0; 
else                                         ix_c_pend  <=                               ix_c_pend; 
  
//-------------------------------------------------------------------------------------------------  
// 
always@(posedge CLK or posedge RST)
 if(RST)                                     ix_ccnt  <=                                     5'h1F;
 else if(ix_last_d_nibble & ix_d_pend      ) ix_ccnt  <=                                     5'd14;  
 else if(ix_last_c_nibble                  ) ix_ccnt  <=                            ix_ccnt       ;
 else                                        ix_ccnt  <=                            ix_ccnt - 5'd1; 
   
//------------------------------------------------------------------------------------------------- 
assign ix_last_c_nibble  =                                                              ix_ccnt[4]; 
assign ix_last_pkt_nibble=                                            ix_c_pend & ix_last_c_nibble; 

//------------------------------------------------------------------------------------------------- 
assign ix_crc_f     =                                                                    ix_c_pend;
assign ix_crc_en    =                                                                    ix_d_pend;  
assign ix_crc_in    = (AVAIL_DATA_BITS=='d4)?                       ixl_bits : {3'd0, ixl_bits[0]};  
assign ix_crc_rst   =                                                                      !ix_stb;                                                                                                                                                                    
assign i0_crc_rec3  = {i0_dat_in[ 7], i0_dat_in[3], i0_dat_in[15], i0_dat_in[11], i0_dat_in[23], i0_dat_in[19], i0_dat_in[31], i0_dat_in[27], i0_dat_in[39], i0_dat_in[35], i0_dat_in[47], i0_dat_in[43], i0_dat_in[55], i0_dat_in[51], i0_dat_in[63], i0_dat_in[59]};
assign i0_crc_rec2  = {i0_dat_in[ 6], i0_dat_in[2], i0_dat_in[14], i0_dat_in[10], i0_dat_in[22], i0_dat_in[18], i0_dat_in[30], i0_dat_in[26], i0_dat_in[38], i0_dat_in[34], i0_dat_in[46], i0_dat_in[42], i0_dat_in[54], i0_dat_in[50], i0_dat_in[62], i0_dat_in[58]};
assign i0_crc_rec1  = {i0_dat_in[ 5], i0_dat_in[1], i0_dat_in[13], i0_dat_in[ 9], i0_dat_in[21], i0_dat_in[17], i0_dat_in[29], i0_dat_in[25], i0_dat_in[37], i0_dat_in[33], i0_dat_in[45], i0_dat_in[41], i0_dat_in[53], i0_dat_in[49], i0_dat_in[61], i0_dat_in[57]};
assign i0_crc_rec04 = {i0_dat_in[ 4], i0_dat_in[0], i0_dat_in[12], i0_dat_in[ 8], i0_dat_in[20], i0_dat_in[16], i0_dat_in[28], i0_dat_in[24], i0_dat_in[36], i0_dat_in[32], i0_dat_in[44], i0_dat_in[40], i0_dat_in[52], i0_dat_in[48], i0_dat_in[60], i0_dat_in[56]};
assign i0_crc_rec01 = {i0_dat_in[55:48], i0_dat_in[63:56]};
assign i0_crc_rec0  = (AVAIL_DATA_BITS=='d4)?                          i0_crc_rec04 : i0_crc_rec01;                                                                                                  
//-------------------------------------------------------------------------------------------------
sd_crc16 cmd_crc_in3(
  .CLK  (CLK),    
  .RST  ((AVAIL_DATA_BITS=='d4)? ix_crc_rst: 1'b0),   
  
  .IN   (ix_crc_in[3]), 
  .SH   (1'b0),  
  .EN   ((AVAIL_DATA_BITS=='d4)? ix_crc_en: 1'b0),
  .CRC  (i0_crc_cal3)
);                                                                                             
//-------------------------------------------------------------------------------------------------
sd_crc16 cmd_crc_in2(
  .CLK  (CLK),    
  .RST  ((AVAIL_DATA_BITS=='d4)? ix_crc_rst: 1'b0),   
  
  .IN   (ix_crc_in[2]), 
  .SH   (1'b0),  
  .EN   ((AVAIL_DATA_BITS=='d4)? ix_crc_en: 1'b0),
  .CRC  (i0_crc_cal2)
);                                                                                             
//-------------------------------------------------------------------------------------------------
sd_crc16 cmd_crc_in1(
  .CLK  (CLK),    
  .RST  ((AVAIL_DATA_BITS=='d4)? ix_crc_rst: 1'b0),   
  
  .IN   (ix_crc_in[1]), 
  .SH   (1'b0),  
  .EN   ((AVAIL_DATA_BITS=='d4)? ix_crc_en: 1'b0),
  .CRC  (i0_crc_cal1)
);                                                                                             
//-------------------------------------------------------------------------------------------------
sd_crc16 cmd_crc_in0(
  .CLK  (CLK),    
  .RST  (ix_crc_rst),   
  
  .IN   (ix_crc_in[0]), 
  .SH   (1'b0),  
  .EN   (ix_crc_en),
  .CRC  (i0_crc_cal0)
);                                                                                                                                                      
//=================================================================================================
always@(posedge CLK or posedge RST)
     if(RST                                ) i0_last_pkt_nibble <=                            1'd0;     
else                                         i0_last_pkt_nibble <=              ix_last_pkt_nibble;                                                                                   
//=================================================================================================
// i1
//=================================================================================================  
always@(posedge CLK or posedge RST)
 if(RST)                                      i1_en        <=                                 1'b0;
 else if(!ix_stb                            ) i1_en        <=                                 1'b0;
 else if(i0_last_pkt_nibble                 ) i1_en        <=                                 1'b1; 
 else                                         i1_en        <=                                 1'b0; 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                                      i1_crc_valid <=                                  'b0;
 else if(i0_last_pkt_nibble                 ) i1_crc_valid <= (AVAIL_DATA_BITS=='d4)?      
                                                                    {(i0_crc_rec3 == i0_crc_cal3), 
                                                                     (i0_crc_rec2 == i0_crc_cal2), 
                                                                     (i0_crc_rec1 == i0_crc_cal1), 
                                                                     (i0_crc_rec0 == i0_crc_cal0)}:
                                                                     (i0_crc_rec0 == i0_crc_cal0);
 else                                         i1_crc_valid <=                         i1_crc_valid; 
//=================================================================================================
// i2
//================================================================================================= 
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_en        <=                                 1'b0;
 else if(I_RD_RST                           ) i2_en        <=                                 1'b0;
 else if(i1_en                              ) i2_en        <=                                 1'b1; 
 else                                         i2_en        <=                                i2_en;  
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_trg       <=                                 1'b0;
 else                                         i2_trg       <=                       !i2_en & i1_en; 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_pkt_ok    <=                                 1'b0;
 else if(I_RD_RST                           ) i2_pkt_ok    <=                                 1'b0;
 else if(i1_en                              ) i2_pkt_ok    <=                        &i1_crc_valid;
 else                                         i2_pkt_ok    <=                            i2_pkt_ok; 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_pkt_err   <=                                 1'b0;
 else if(I_RD_RST                           ) i2_pkt_err   <=                                 1'b0;
 else if(i1_en                              ) i2_pkt_err   <=                     !(&i1_crc_valid);
 else                                         i2_pkt_err   <=                           i2_pkt_err; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_crc_valid <=                                 1'b0;
 else if(i1_en                              ) i2_crc_valid <=                        &i1_crc_valid;
 else                                         i2_crc_valid <=                         i2_crc_valid; 
//------------------------------------------------------------------------------------------------- 
assign i2_id_ack_trg =                                                     i2_trg &&  i2_crc_valid; 
assign i2_id_rej_trg =                                                     i2_trg && !i2_crc_valid;

//=================================================================================================
// read request port
//================================================================================================= 
assign I_RD_END         =                                                                    i2_en;
assign I_RD_ACK         =                                                                i2_pkt_ok;
assign I_RD_ERR         =                                                               i2_pkt_err;                                                                                               
//assign O_TIMEOUT        =                                                             i0_timeout_f;

//=================================================================================================
// interdomain synchronization of packet akceptance and packet rejection signals
//================================================================================================= 
assign o0_pkt_en       =                                                             i2_id_ack_trg;
assign o0_pkt_rej      =                                                             i2_id_rej_trg;
assign o0_pkt_int      =                                                                  I_RD_INT;
assign o0_pkt_int_mode =                                                             I_RD_INT_MODE; 
                                   
//=================================================================================================
// o0
//=================================================================================================  
ff_srl_af_ack_d16
#(
.WIDTH(3)
)   
ff_ack_rej
(             
.clk    (CLK),
.rst    (RST),
                 
.i_stb  (o0_pkt_en || o0_pkt_rej),  
.i_data ({o0_pkt_int, o0_pkt_int_mode, o0_pkt_en}),
.i_af   (),
.i_full (),
.i_err  (),

.o_stb  (o1_pkt_ack_rej_stb),
.o_ack  (o2_pkt_end),
.o_data ({o1_pkt_int, o1_pkt_int_mode, o1_pkt_ack_rej}),
.o_ae   (),
.o_err  ()
);             

//------------------------------------------------------------------------------------------------- 
assign o1_pkt_ok        =                                    o1_pkt_ack_rej_stb &&  o1_pkt_ack_rej;
assign o1_pkt_rej       =                                    o1_pkt_ack_rej_stb && !o1_pkt_ack_rej; 

assign o1_rdy_f         =                ((!o3_ff_af10 && o1_pkt_ok) || o1_pkt_rej) && !o2_pkt_end; 

//=================================================================================================
// Output data fifo
//================================================================================================= 
// ack for data fifo when packet should be rejected or packet formater is cappable to get data
assign o2_ff_ack        = o1_pkt_ack_rej_stb && (o2_pkt_hdr_f || (o2_dw8_pend & !o2_ff_d_dw8_last));
assign o2_ff_en         =                                                       o1_pkt_ack_rej_stb;                                                                 
assign o2_ff_d_dw8_last =                                                              o2_ff_d[65];
assign o2_ff_d_pkt_last =                                                              o2_ff_d[64];
// ack for fifo of akceptance/rejection of a packet 
assign o2_pkt_end       =                                   o1_pkt_ack_rej_stb && o2_ff_d_pkt_last; 
                                                                                                                                                          
//-------------------------------------------------------------------------------------------------        
always@(posedge CLK or posedge RST)
if(RST)                                      o2_ff_addr <=                                   9'h00; 
else if(o2_ff_ack                          ) o2_ff_addr <=                       o2_ff_addr + 9'd1;     
else                                         o2_ff_addr <=                              o2_ff_addr;
                                                                                                     
//-------------------------------------------------------------------------------------------------  
always@(posedge CLK or posedge RST) 
 if(RST)                    o2_pkt_ok      <=                                                 1'b0; 
 else                       o2_pkt_ok      <=                                            o1_pkt_ok;

//-------------------------------------------------------------------------------------------------  
always@(posedge CLK or posedge RST) 
 if(RST)                    o2_pkt_rej     <=                                                 1'b0; 
 else                       o2_pkt_rej     <=                                           o1_pkt_rej;
//-------------------------------------------------------------------------------------------------  
always@(posedge CLK or posedge RST) 
 if(RST)                    o2_pkt_int     <=                                                 1'b0; 
 else                       o2_pkt_int     <=                                           o1_pkt_int;

//-------------------------------------------------------------------------------------------------  
always@(posedge CLK or posedge RST) 
 if(RST)                    o2_pkt_int_mode<=                                                 1'b0; 
 else                       o2_pkt_int_mode<=                                      o1_pkt_int_mode;                           
   
//-------------------------------------------------------------------------------------------------  
always@(posedge CLK or posedge RST) 
 if(RST)                    o2_pkt_hdr_f   <=                                                 1'b0; 
 else if( o2_dw8_pend      )o2_pkt_hdr_f   <=                                                 1'b0; 
 else                       o2_pkt_hdr_f   <=                             !o2_pkt_hdr_f & o1_rdy_f; 
                                                                                                   
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST) 
 if(RST)                    o2_dw8_pend    <=                                                 1'b0; 
 else if( o2_ff_d_dw8_last )o2_dw8_pend    <=                                                 1'b0; 
 else if( o2_pkt_hdr_f     )o2_dw8_pend    <=                                                 1'b1;  
 else                       o2_dw8_pend    <=                                          o2_dw8_pend; 
   
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST) 
 if(RST)                    o2_pkt_pend    <=                                                 1'b0; 
 else if( o2_ff_d_pkt_last )o2_pkt_pend    <=                                                 1'b0; 
 else if( o2_pkt_hdr_f     )o2_pkt_pend    <=                                                 1'b1;  
 else                       o2_pkt_pend    <=                                          o2_pkt_pend; 
                                   
//------------------------------------------------------------------------------------------------- 
assign o2_pkt_addr_inc =                                    o2_pkt_hdr_f & o2_pkt_ok & !o2_pkt_int;      
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK) 
      if(I_ADDR_EN         )o2_pkt_addr    <=                                               I_ADDR;
 else if( o2_pkt_addr_inc  )o2_pkt_addr    <=                                 o2_pkt_addr + 39'd64;  
 else                       o2_pkt_addr    <=                                 o2_pkt_addr         ;
                                                                                                  
//------------------------------------------------------------------------------------------------- 
assign o2_pkt_rid =                                                                           4'hF;
assign o2_pkt_sid =                                                                           4'h1;
assign o2_pkt_hdr =              {2'b10, 2'd0, 20'd0/*net addr*/, o2_pkt_sid[3:0], o2_pkt_rid[3:0], 
                                    1'b1/*long*/, o2_pkt_addr[38:3], 1'b0/*V*/, 2'b10/*MOP = WR*/};                                                                               
                                                                                                    
//=================================================================================================
// packet error or akceptance indication at the end of receiving
always@(posedge CLK or posedge RST) 
 if(RST)                    o3_pkt_end     <=                                                 1'b0;  
 else                       o3_pkt_end     <=                                           o2_pkt_end; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST) 
 if(RST)                    o3_pkt_ok      <=                                                 1'b0;  
 else if(o2_pkt_end       ) o3_pkt_ok      <=                                            o2_pkt_ok;  
 else                       o3_pkt_ok      <=                                            o3_pkt_ok;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST) 
 if(RST)                    o3_pkt_err     <=                                                 1'b0;  
 else if(o2_pkt_end       ) o3_pkt_err     <=                                           o2_pkt_rej;  
 else                       o3_pkt_err     <=                                           o3_pkt_err;   
                                                                                                    
//================================================================================================= 
always@(posedge CLK) 
      if( o2_pkt_hdr_f     )o3_pkt_mux     <=                                           o2_pkt_hdr; 
 else                       o3_pkt_mux     <=                               {8'hFF, o2_ff_d[63:0]}; 
                      
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST) 
 if(RST)                    o3_ff_sof      <=                                                 1'b0; 
 else if( o2_pkt_hdr_f     )o3_ff_sof      <=                                                 1'b1; 
 else                       o3_ff_sof      <=                                                 1'b0; 
                      
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST) 
 if(RST)                    o3_dw8_last    <=                                                 1'd0;  
 else                       o3_dw8_last    <=                                     o2_ff_d_dw8_last; 
                                                                                                    
//-------------------------------------------------------------------------------------------------
// enable for output fifo - only if in normal data transfer mode and packet is akcepted, 
// when in "internal data" mode than do not write data to fifo, instead write it throught Internal 
// data port O_INT_DATA  
always@(posedge CLK or posedge RST) 
 if(RST)                    o3_ff_en       <=                                                 1'd0; 
 else if( o2_pkt_hdr_f     )o3_ff_en       <=                              !o2_pkt_int & o2_pkt_ok; 
 else if( o3_dw8_last      )o3_ff_en       <=                                                 1'd0;
 else                       o3_ff_en       <=                                             o3_ff_en;
//-------------------------------------------------------------------------------------------------  
ff_srl_af_ack_d16
#(
.WIDTH(73),
.AF1LIMIT(10) // 10 not 9 because of 2 regs pipeline 
)   
ff_dout
(             
.clk    (CLK),
.rst    (RST),
                 
.i_stb  (o3_ff_en),  
.i_data ({o3_ff_sof, o3_pkt_mux[71:0]}),
.i_af   ({o3_ff_af10, o3_ff_af2}),
.i_full (),
.i_err  (o3_ff_err),

.o_stb  (o4_o_stb),
.o_ack  (o4_o_ack),
.o_data ({o4_o_sof, o4_o_dat}), 
.o_ae   (),
.o_err  ()
);                      

assign o4_o_ack =                                                                            O_ACK; 
//-------------------------------------------------------------------------------------------------
// enable for internal data output - if in "internal data" mode, write it throught Internal data 
// port O_INT_DATA                                                                                
always@(posedge CLK or posedge RST) 
 if(RST)                    o3_int_enx     <=                                                 1'd0; 
 else if( o2_pkt_hdr_f     )o3_int_enx     <=                               o2_pkt_int & o2_pkt_ok; 
 else if( o3_dw8_last      )o3_int_enx     <=                                                 1'd0;
 else                       o3_int_enx     <=                                           o3_int_enx; 
//------------------------------------------------------------------------------------------------- 
// disable write for headers
assign o3_int_en =                                                         !o3_ff_sof & o3_int_enx; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK ) 
      if( !o2_pkt_int      )o3_int_ptr     <=                                                 3'd7;
 else if( o3_int_en        )o3_int_ptr     <=                                    o3_int_ptr - 3'd1;
 else                       o3_int_ptr     <=                                    o3_int_ptr       ;
//-------------------------------------------------------------------------------------------------
// enable for internal data output - if in "internal data" mode, write it throught Internal data 
// port O_INT_DATA                                                                                
always@(posedge CLK or posedge RST) 
 if(RST)                    o3_int_mode    <=                                                 1'd0; 
 else if( o2_pkt_int       )o3_int_mode    <=                                      o2_pkt_int_mode;
 else                       o3_int_mode    <=                                          o3_int_mode; 
//=================================================================================================
// Data output                                                                                 
//=================================================================================================
assign O_STB        =                                                                     o4_o_stb;
assign O_DAT        =                                                               o4_o_dat[71:0]; 
assign O_SOF        =                                                                     o4_o_sof; 
//=================================================================================================
assign O_INT_ENA    =                                                                    o3_int_en; 
assign O_INT_PTR    =                                                                   o3_int_ptr;
assign O_INT_DAT    = {o3_pkt_mux[7:0], o3_pkt_mux[15:8], o3_pkt_mux[23:16], o3_pkt_mux[31:24], o3_pkt_mux[39:32], o3_pkt_mux[47:40], o3_pkt_mux[55:48], o3_pkt_mux[63:56]};
assign O_INT_MODE   =                                                                  o3_int_mode;
//=================================================================================================
endmodule

