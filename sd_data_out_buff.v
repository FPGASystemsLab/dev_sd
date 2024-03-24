//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
// Module that:
// - reads data from main memory using ringbus protocol
// - forms 512B packets for SD interface protocol
// - buffers up to 8 512B-packets
// - keeps packets until acceptance. When CRC error is reported than packet 
//   can be retransmitted using buffered data 
// Request to memory are send with RID and SID indicating ID of buffer where
// data from memory should be stored - when packets, with data from memory, 
// return in order, different than requests were send, than them can still be
// assembled in right order:
// SID = {1'b1,                           3 bits <0-7> for buffer ID         }
// RID = {one bit tag for debug purposes, 3 bits <0-7> for 64B data packet ID}
//
// For packets send from this module, the MSB of SID (SID[3]) is set high, so 
// packets with data from memory can be recognized - they will also have this 
// bit set high. 
//   
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module sd_data_out_buff
(                                  
input  wire        CLK,                
input  wire        RST,            
 

// address input
input  wire        SYS_I_REQ_STB,
input  wire [ 38:0]SYS_I_REQ_MEM_ADDR, 
input  wire [ 15:0]SYS_I_REQ_MUL_M2, // up to 32GB of data to be write in a single operation 
output wire        SYS_I_REQ_ACK,  
                    
// output
output wire        SD_O_PKT_RDY, 
output wire [ 63:0]SD_O_DAT,   
input  wire        SD_O_ACK,
output wire        SD_O_FIRST,  
output wire        SD_O_LAST, 
output wire [ 15:0]SD_O_512B_DONE, // how many 512-Byte packets has been successfully send to the card  
input  wire        SD_I_PKT_ACK,   
input  wire        SD_I_PKT_RET,  
        
// ringbus interface
input  wire        I_EN, 
input  wire        I_SOF,
input  wire [ 71:0]I_DAT, 
output wire        I_AF9,      
 
output wire        O_STB,
output wire        O_SOF,
output wire [ 71:0]O_DAT, 
input  wire        O_ACK     
); 
//-------------------------------------------------------------------------------------------------
localparam IDLE                     =  32'h00000000;
localparam CHECK_512_FREE           =  32'h00000001;
localparam INIT_512_BUF             =  32'h00000002;
localparam INIT_64_RD               =  32'h00000004;
localparam REQ_H_OUT                =  32'h00000008;
localparam REQ_S_OUT                =  32'h00000010;
localparam REQ_PEND                 =  32'h00000020;
localparam CH_512                   =  32'h00000040;  
localparam WR_PEND                  =  32'h00000080; 
        
//------------------------------------------------------------------------------------------------- 
integer     i_state;      
wire        state_idle_f; 
wire        state_check_512_free_f;      
wire        state_init_512_buf_f;  
wire        state_init_64_rd_f;   
wire        state_req_h_f;     
wire        state_req_s_f;     
wire        state_req_pend_f;        
wire        state_ch_512_f;        
wire        state_wr_pend_f;    

//------------------------------------------------------------------------------------------------- 
assign state_idle_f            =                                       (i_state == IDLE          );
assign state_check_512_free_f  =                                       (i_state == CHECK_512_FREE);
assign state_init_512_buf_f    =                                       (i_state == INIT_512_BUF  );
assign state_init_64_rd_f      =                                       (i_state == INIT_64_RD    );
assign state_req_h_f           =                                       (i_state == REQ_H_OUT     ); 
assign state_req_s_f           =                                       (i_state == REQ_S_OUT     );
assign state_req_pend_f        =                                       (i_state == REQ_PEND      );
assign state_ch_512_f          =                                       (i_state == CH_512        ); 
assign state_wr_pend_f         =                                       (i_state == WR_PEND       );  

//=================================================================================================
// STATE MACHINE
//=================================================================================================

always@(posedge CLK or posedge RST)
 if(RST)                                                i_state   <=                          IDLE;
 else case(i_state)                                                  
 IDLE:          if(SYS_I_REQ_STB                      ) i_state   <=                CHECK_512_FREE; 
           else                                         i_state   <=                          IDLE;
 CHECK_512_FREE:if(has_free_512_f                     ) i_state   <=                  INIT_512_BUF;
           else                                         i_state   <=                CHECK_512_FREE;
 INIT_512_BUF:                                          i_state   <=                    INIT_64_RD;
 INIT_64_RD:                                            i_state   <=                     REQ_H_OUT;                                                                 
 REQ_H_OUT:     if( O_ACK                             ) i_state   <=                     REQ_S_OUT; 
           else                                         i_state   <=                     REQ_H_OUT;
 REQ_S_OUT:     if( O_ACK & req_64id_last             ) i_state   <=                      REQ_PEND;  
           else if( O_ACK                             ) i_state   <=                    INIT_64_RD;  
           else                                         i_state   <=                     REQ_S_OUT;
 REQ_PEND:      if(i0_curr512_pend                    ) i_state   <=                      REQ_PEND;
           else                                         i_state   <=                        CH_512;
 CH_512:        if(req_512pkt_last                    ) i_state   <=                       WR_PEND;
           else                                         i_state   <=                CHECK_512_FREE;
 WR_PEND:       if(buff_empty_f                       ) i_state   <=                          IDLE;  
           else                                         i_state   <=                       WR_PEND;
 endcase          
//=================================================================================================
//                                                                                             
//================================================================================================= 
reg   [ 16:0] req_512_cnt;
wire          req_512pkt_last;
wire          req_64pkt_last_tic;
reg   [  3:0] free_512_cnt;
reg   [  2:0] free_512_ptr;
wire          has_free_512_f;
reg           buff_empty_f;
reg   [ 38:0] req_addr;
reg           req_tag;
reg   [  2:0] req_id;
wire          req_64id_last;
wire  [  3:0] req_rid;
reg   [  2:0] req_buf_id;
wire  [  3:0] req_sid;
wire  [ 71:0] req_hdr;
reg           req_ack;
wire          one_pkt512_done; // from SD clock domain to SYS clock domain signal about packet acceptance

//=================================================================================================
// 512B packet acceptance
//=================================================================================================                              
assign one_pkt512_done =                                                              SD_I_PKT_ACK;

//=================================================================================================
// requests sending and buffer fullness managing 
//================================================================================================= 
always@(posedge CLK)
     if( state_idle_f                        ) req_512_cnt  <=                    SYS_I_REQ_MUL_M2;
else if( state_ch_512_f                      ) req_512_cnt  <=                 req_512_cnt - 17'd1;
else                                           req_512_cnt  <=                 req_512_cnt        ;
//------------------------------------------------------------------------------------------------- 
assign req_512pkt_last =                                                           req_512_cnt[16];
assign req_64pkt_last_tic  =                                         state_req_s_f & req_64id_last;  
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        free_512_cnt <=                                4'd7; 
else if( state_init_512_buf_f&!one_pkt512_done)free_512_cnt <=                 free_512_cnt - 4'd1;
else if(!state_init_512_buf_f& one_pkt512_done)free_512_cnt <=                 free_512_cnt + 4'd1;
else                                           free_512_cnt <=                 free_512_cnt       ; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        buff_empty_f <=                                1'd1;
else                                           buff_empty_f <=                free_512_cnt == 4'd7;
//------------------------------------------------------------------------------------------------- 
assign has_free_512_f =                                                           !free_512_cnt[3];

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        free_512_ptr <=                                3'd0; 
else if( state_init_512_buf_f                ) free_512_ptr <=                 free_512_ptr + 3'd1;
else                                           free_512_ptr <=                 free_512_ptr       ;

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if( state_idle_f                        ) req_addr <=                      SYS_I_REQ_MEM_ADDR;
else if( state_req_s_f & O_ACK               ) req_addr <=                       req_addr + 39'd64;
else                                           req_addr <=                       req_addr         ;

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if( state_idle_f                        ) req_id   <=                                    3'd0;
else if( state_req_s_f & O_ACK               ) req_id   <=                           req_id + 3'd1;
else                                           req_id   <=                           req_id       ;
//-------------------------------------------------------------------------------------------------
assign req_64id_last =                                                              req_id == 3'd7;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        req_tag  <=                                    1'd0; 
else if( state_idle_f                        ) req_tag  <=                                    1'd0;
else if( state_req_s_f & O_ACK               ) req_tag  <=                                ~req_tag;
else                                           req_tag  <=                                 req_tag;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if( state_init_512_buf_f                ) req_buf_id   <=                        free_512_ptr;
else                                           req_buf_id   <=                          req_buf_id;
//------------------------------------------------------------------------------------------------- 

assign req_rid          =                                                    {req_tag,     req_id};
assign req_sid          =                                                    {   1'b1, req_buf_id};
assign req_hdr          = {2'b10, 2'b00, 20'h0, req_sid, req_rid, 1'b0, req_addr[38:3], 1'b0 /*V*/, 2'b01 /*MOP = RD8*/};
 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        req_ack  <=                                    1'b0; 
else if( state_idle_f & SYS_I_REQ_STB        ) req_ack  <=                          has_free_512_f;
else                                           req_ack  <=                                    1'b0;

//=================================================================================================
// REQUEST OUTPUT
//=================================================================================================
assign O_DAT            =                                                            req_hdr[71:0]; // data in read-req-packet is invalid so it can be the same as header data
assign O_STB            =                                           state_req_h_f || state_req_s_f;
assign O_SOF            =                                           state_req_h_f                 ;

//=================================================================================================
// REQUEST ACCEPTANCE 
//=================================================================================================
assign SYS_I_REQ_ACK    =                                                                  req_ack;

//=================================================================================================
// RECEIVED DATA
//=================================================================================================
wire  [ 71:0] i0_dat_in;
wire  [  3:0] i0_sid;
wire  [  3:0] i0_rid;
wire  [  2:0] i0_buf_id;
wire  [  2:0] i0_id;
wire          i0_hdr_f;
reg   [  3:0] i0_dat_en_cnt;

wire          i0_ff_en; 
wire  [  8:0] i0_ff_addr;
wire          i0_ff_af;
wire  [ 71:0] i0_ff_d_in;
//------------------------------------------------------------------------------------------------- 
reg   [  8:0] i0_addr; 
wire  [  2:0] i0_addr_3lsb_p1;
reg           i0_512dw_first;
reg           i0_512dw_last;
reg           i0_64dw_last;

reg   [  3:0] i0_64pkt_cnt;
wire          i0_64pkt_last;

reg           i0_curr512_pend;
reg           i0_new512_trg;
                                                                                                      
//=================================================================================================
// output buffer
//=================================================================================================
reg  [  8:0] o0_ff_addr;
wire [  5:0] o0_ff_addr_lb;
wire [ 63:0] o0_ff_data;

wire         o0_512dw_first;
wire         o0_512dw_last;
wire         o0_64dw_last;
wire [  4:0] o0_unused;

reg          o0_new512_trg;
reg  [  3:0] o0_buf_used;
reg  [  2:0] o0_buf_ptr;
wire         o0_512pkt_rdy;
wire         o0_ack512;
wire         o0_rej512;
reg  [ 15:0] o0_512pkt_cnt;
 
//=================================================================================================
// PARSE DATA FROM MEMORY                                                                                            
//=================================================================================================
assign i0_hdr_f         =                                                            I_SOF && I_EN; 
assign i0_dat_in        =                                                              I_DAT[71:0];         
assign i0_sid           =                                                         i0_dat_in[47:44];        
assign i0_rid           =                                                         i0_dat_in[43:40];        
assign i0_buf_id        =                                                            i0_sid[ 2: 0];        
assign i0_id            =                                                            i0_rid[ 2: 0];  
assign i0_64pkt_last    =                                                          i0_64pkt_cnt[3];          

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                      i0_dat_en_cnt <=                                 4'd0;        
else if(i0_hdr_f                           ) i0_dat_en_cnt <=                         {1'b1, 3'd7}; 
else if(i0_ff_en                           ) i0_dat_en_cnt <=                 i0_dat_en_cnt - 4'd1;
else                                         i0_dat_en_cnt <=                 i0_dat_en_cnt       ; 
                                                                                                    
//------------------------------------------------------------------------------------------------- 
assign i0_addr_3lsb_p1 =                                                       i0_addr[2:0] + 3'd1;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if(i0_hdr_f                           ) i0_addr     <=    {i0_buf_id, i0_id,            3'd0}; 
else if(i0_ff_en                           ) i0_addr     <=    {    i0_addr[8:3], i0_addr_3lsb_p1};
else                                         i0_addr     <=                                i0_addr; 

//-------------------------------------------------------------------------------------------------
// To SD data are send in "Least significant DW first" order - i0_512dw_first indicates "oldest" DW
always@(posedge CLK or posedge RST)
if(RST)                                     i0_512dw_first <=                                 1'b0;        
else if(i0_hdr_f && (i0_id == 3'd0)       ) i0_512dw_first <=                                 1'b1;        
else                                        i0_512dw_first <=                                 1'b0; 

//------------------------------------------------------------------------------------------------- 
// To SD data are send in "Least significant DW first" order - i0_512dw_last indicates "youngest" DW
always@(posedge CLK or posedge RST)
if(RST)                                     i0_512dw_last  <=                                 1'b0; 
else if(i0_hdr_f                           )i0_512dw_last  <=                                 1'b0;
else                                        i0_512dw_last  <= {i0_addr[5:3],i0_addr_3lsb_p1}=={3'h7,3'h7}; 

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                     i0_64dw_last   <=                                 1'b0;  
else                                        i0_64dw_last   <= {      i0_dat_en_cnt} == {     4'h9}; 

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if(state_init_512_buf_f               ) i0_64pkt_cnt  <=                         {1'b0, 3'd7}; 
else if(i0_hdr_f                           ) i0_64pkt_cnt  <=                  i0_64pkt_cnt - 4'd1;
else                                         i0_64pkt_cnt  <=                  i0_64pkt_cnt       ; 

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                      i0_curr512_pend<=                                1'b0;        
else if(state_init_512_buf_f               ) i0_curr512_pend<=                                1'b1; 
else if(i0_64pkt_last & i0_64dw_last       ) i0_curr512_pend<=                                1'b0;
else                                         i0_curr512_pend<=                     i0_curr512_pend; 

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                      i0_new512_trg  <=                                1'b0; 
else if(i0_64pkt_last & i0_64dw_last       ) i0_new512_trg  <=                                1'b1;
else                                         i0_new512_trg  <=                                1'b0; 

//=================================================================================================
// interdomain synchronization of a new 512B packet availability
//=================================================================================================                              
//intdom_trg_synch #(.MAX_LOG2_IFREQ_DIV_OFREQ(7), .MAX_LOG2_OFREQ_DIV_IFREQ(1))
//i_id_ack_synch (.i_clk(CLK), .i_rst(RST), .i_trg(i0_new512_trg), .i_bsy(), .o_clk(CLK), .o_rst(RST), .o_trg(o0_new512_trg));
//                                                                                                  
always@(posedge CLK or posedge RST)
if(RST)                                      o0_new512_trg  <=                                1'b0; 
else                                         o0_new512_trg  <=                       i0_new512_trg; 
//assign o0_new512_trg =                                                               i0_new512_trg;
//=================================================================================================
// output buffer
//================================================================================================= 
assign i0_ff_en          =                                                        i0_dat_en_cnt[3];
assign i0_ff_addr        =                                                                 i0_addr;
assign I_AF9             =                                                                i0_ff_af;
assign i0_ff_d_in        ={i0_dat_en_cnt, 1'd0, i0_512dw_first, i0_64dw_last, i0_512dw_last, i0_dat_in[63:0]}; 
assign i0_ff_af          =                                                                    1'b0;
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

.RDEN       (o0_512pkt_rdy),
.RDADDR     (o0_ff_addr),
.REGCE      (),
.DO         ({o0_unused, o0_512dw_first, o0_64dw_last, o0_512dw_last, o0_ff_data})
);                              
//-------------------------------------------------------------------------------------------------
assign o0_ack512    =                                                                 SD_I_PKT_ACK;
assign o0_rej512    =                                                                 SD_I_PKT_RET;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                      o0_buf_used   <=                                   -1;        
else if( o0_new512_trg & !o0_ack512        ) o0_buf_used   <=                o0_buf_used    + 4'd1;        
else if(!o0_new512_trg &  o0_ack512        ) o0_buf_used   <=                o0_buf_used    - 4'd1; 
else                                         o0_buf_used   <=                o0_buf_used          ; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                      o0_buf_ptr    <=                                 3'd0;        
else if(                  o0_rej512        ) o0_buf_ptr    <=                 o0_buf_ptr          ;        
else if(                  o0_ack512        ) o0_buf_ptr    <=                 o0_buf_ptr    + 3'd1; 
else                                         o0_buf_ptr    <=                 o0_buf_ptr          ; 
//-------------------------------------------------------------------------------------------------
assign o0_512pkt_rdy =                                                          !o0_buf_used   [3];

assign o0_ff_addr_lb =                                                      o0_ff_addr[5:0] + 6'd1; // Least sig. DW first 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if( o_state_wait_pkt_f                ) o0_ff_addr    <= {o0_buf_ptr[2:0],              6'h0}; // Least sig. DW first       
else if( SD_O_ACK                          ) o0_ff_addr    <= {o0_buf_ptr[2:0],     o0_ff_addr_lb}; 
else                                         o0_ff_addr    <=                       o0_ff_addr    ; 

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                      o0_512pkt_cnt <=                                15'd0;        
else if( o0_ack512                         ) o0_512pkt_cnt <=                o0_512pkt_cnt + 15'd1;        
else if( o0_rej512                         ) o0_512pkt_cnt <=                                15'd0;
else                                         o0_512pkt_cnt <=                        o0_512pkt_cnt; 

//-------------------------------------------------------------------------------------------------
//localparam IDLE                     =  32'h00000000;
localparam WAIT_PKT                 =  32'h00000001;
localparam SEND_DATA                =  32'h00000002;
localparam WAIT_CNF                 =  32'h00000004;
localparam PREP_RET                 =  32'h00000008;  
        
//------------------------------------------------------------------------------------------------- 
integer     o_state;  
//wire        o_state_idle_f;      
wire        o_state_wait_pkt_f;    
wire        o_state_send_data_f;        
wire        o_state_wait_cnf_f;    
wire        o_state_prep_ret_f;     

//------------------------------------------------------------------------------------------------- 
//assign o_state_idle_f         =                                         (o_state == IDLE         );
assign o_state_wait_pkt_f     =                                         (o_state == WAIT_PKT     );
assign o_state_send_data_f    =                                         (o_state == SEND_DATA    );
assign o_state_wait_cnf_f     =                                         (o_state == WAIT_CNF     ); 
assign o_state_prep_ret_f     =                                         (o_state == PREP_RET     ); 

//=================================================================================================
// STATE MACHINE
//=================================================================================================

always@(posedge CLK or posedge RST)
 if(RST)                                                o_state   <=                      WAIT_PKT;//  IDLE;
 else case(o_state)                                                  
// IDLE:          if(O_STB                               ) o_state   <=                      WAIT_PKT; 
//           else                                         o_state   <=                          IDLE;
 WAIT_PKT:      if(o0_512pkt_rdy                      ) o_state   <=                     SEND_DATA; 
           else                                         o_state   <=                      WAIT_PKT;                                                                 
 SEND_DATA:     if(o0_512dw_last & SD_O_ACK           ) o_state   <=                      WAIT_CNF; 
 WAIT_CNF:      if(o0_ack512                          ) o_state   <=                      WAIT_PKT;//    IDLE;  
           else if(o0_rej512                          ) o_state   <=                      PREP_RET;  
           else                                         o_state   <=                      WAIT_CNF;
 PREP_RET:                                              o_state   <=                      WAIT_PKT;//    IDLE;
 endcase          
//=================================================================================================
// 
//=================================================================================================
assign SD_O_PKT_RDY   =                                                              o0_512pkt_rdy;
assign SD_O_DAT       =                                                                 o0_ff_data;
assign SD_O_FIRST     =                                                             o0_512dw_first;
assign SD_O_LAST      =                                                              o0_512dw_last;
assign SD_O_512B_DONE =                                                        o0_512pkt_cnt[15:0]; 
//=================================================================================================
endmodule        
