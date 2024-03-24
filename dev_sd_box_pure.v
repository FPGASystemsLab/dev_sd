//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module dev_sd_box_pure
#(
parameter  [ 0:0] OP_COND_S18R         =  1'b0,      // try switch to 1.8V - request UHS1 modes 
parameter  [31:0] TIME_POWER_INI       =  32'd100000,// count in tic of SD clock. For 400KHz SD CLK period equals 2.5us, so 100000 clocks is 250ms 
parameter  [31:0] AVAIL_DATA_BITS      =  32'd4      // 1 - only one data lane available; 4 - four data lanes
)
(                                  
input  wire        CLK,              /*synthesis syn_keep=1*/
input  wire        RST,              /*synthesis syn_keep=1*/  

// ringbus events interface                              
input  wire        REQ_I_RD_STB,     /*synthesis syn_keep=1*/                        
input  wire        REQ_I_WR_STB,     /*synthesis syn_keep=1*/                        
input  wire        REQ_I_REG_STB,    /*synthesis syn_keep=1*/
input  wire [38:0] REQ_I_MEM_ADDR,   /*synthesis syn_keep=1*/
input  wire [38:0] REQ_I_SD_ADDR,    /*synthesis syn_keep=1*/
input  wire [15:0] REQ_I_512B_MUL_M1,/*synthesis syn_keep=1*/  
output wire        REQ_I_ACK,        /*synthesis syn_keep=1*/

output wire        REQ_I_DONE,       /*synthesis syn_keep=1*/
output wire        REQ_I_ERR,        /*synthesis syn_keep=1*/

// ringbus interface         
input  wire        SYS_I_STB,        /*synthesis syn_keep=1*/
input  wire        SYS_I_SOF,        /*synthesis syn_keep=1*/
input  wire [71:0] SYS_I_DAT,        /*synthesis syn_keep=1*/
output wire [ 1:0] SYS_I_AF,         /*synthesis syn_keep=1*/
 
output wire        SYS_O_STB,        /*synthesis syn_keep=1*/
output wire        SYS_O_SOF,        /*synthesis syn_keep=1*/
output wire [71:0] SYS_O_DAT,        /*synthesis syn_keep=1*/
input  wire [ 1:0] SYS_O_AF,         /*synthesis syn_keep=1*/
 
//SD card interface             
input  wire        SD_CMD_I_PIN,     /*synthesis syn_keep=1*/
input  wire [ (AVAIL_DATA_BITS-'d1):0] SD_DAT_I_PINS,    /*synthesis syn_keep=1*/
output wire        SD_CMD_O_PIN,     /*synthesis syn_keep=1*/
output wire [ (AVAIL_DATA_BITS-'d1):0] SD_DAT_O_PINS,    /*synthesis syn_keep=1*/

// CLOCK selection signals
output wire        CLK_EN_400K,      /*synthesis syn_keep=1*/
output wire        CLK_EN_25M,       /*synthesis syn_keep=1*/
output wire        CLK_EN_50M,       /*synthesis syn_keep=1*/
output wire        CLK_EN_100M,      /*synthesis syn_keep=1*/
output wire        CLK_EN_200M,      /*synthesis syn_keep=1*/

// common signals        
output wire        SD_LV_F,          /*synthesis syn_keep=1*/
output wire        SD_HV_F,          /*synthesis syn_keep=1*/
output wire        SD_DAT_4B_F,      /*synthesis syn_keep=1*/   
output wire        SD_CLK_OE,        /*synthesis syn_keep=1*/
output wire        SD_DAT_OE,        /*synthesis syn_keep=1*/
output wire        SD_CMD_OE,        /*synthesis syn_keep=1*/
output wire        SD_CMD_CMD_F,     /*synthesis syn_keep=1*/
output wire        SD_CMD_CRC_F,     /*synthesis syn_keep=1*/

input  wire        SD_CARD_PIN,      /*synthesis syn_keep=1*/

// error indicators and debug signals
output reg         initialized,      /*synthesis syn_keep=1*/
output reg         rd_led,           /*synthesis syn_keep=1*/
output reg         wr_led,           /*synthesis syn_keep=1*/

output wire        err_unsuported_card,/*synthesis syn_keep=1*/
output wire        err_crc,          /*synthesis syn_keep=1*/
output wire        err_flash,        /*synthesis syn_keep=1*/
output wire        err_timeout,      /*synthesis syn_keep=1*/
                                
output reg         dbg_state_changed,/*synthesis syn_keep=1*/     
output reg  [15:0] dbg_state,        /*synthesis syn_keep=1*/
output wire [31:0] dbg_st_reg,       /*synthesis syn_keep=1*/   
output wire [ 4:0] dbg_ocr,          /*synthesis syn_keep=1*/
output wire [15:0] dbg_rca           /*synthesis syn_keep=1*/ 
);   
//------------------------------------------------------------------------------------------------- 
initial
    begin
        if((AVAIL_DATA_BITS != 1) && (AVAIL_DATA_BITS != 4))
            begin
            $display( "!!!ERROR!!! AVAIL_DATA_BITS = %d, is out of range {1, 4}", AVAIL_DATA_BITS ); 
            $finish;
            end
        if( OP_COND_S18R && (AVAIL_DATA_BITS != 4)) 
            begin
            $display( "!!!ERROR!!! UHS requested while AVAIL_DATA_BITS = %d. 4-bits interface required for UHS.", AVAIL_DATA_BITS ); 
            $finish;
            end 
    end
//-------------------------------------------------------------------------------------------------
localparam [15:0] IDLE                 =  16'h0000;
localparam [15:0] INIT0                =  16'h0001;
localparam [15:0] CMD0_OUT             =  16'h0002; 
localparam [15:0] V_CH_CMD8_OUT        =  16'h0011;
localparam [15:0] V_CH_CMD8_IN         =  16'h0012;
localparam [15:0] V_CH_END             =  16'h0013; 
localparam [15:0] CMD55_OUT            =  16'h0020;
localparam [15:0] CMD55_IN             =  16'h0021;
localparam [15:0] ACMD41_OUT           =  16'h0022;
localparam [15:0] ACMD41_IN            =  16'h0023; 

localparam [15:0] CMD11_OUT            =  16'h0100;
localparam [15:0] CMD11_IN             =  16'h0101; 
localparam [15:0] VOLT_SW0             =  16'h0102;
localparam [15:0] VOLT_SW1             =  16'h0104;
localparam [15:0] VOLT_SW2             =  16'h0108; 

localparam [15:0] CLK_SW0              =  16'h0200;
localparam [15:0] CLK_SW1              =  16'h0201;

localparam [15:0] CMD2_OUT             =  16'h0202;
localparam [15:0] CMD2_IN              =  16'h0203; 
localparam [15:0] CMD3_OUT             =  16'h0300;
localparam [15:0] CMD3_IN              =  16'h0301;
localparam [15:0] CMD9_OUT             =  16'h0304;
localparam [15:0] CMD9_IN              =  16'h0305;
localparam [15:0] CMD7_OUT             =  16'h0400;
localparam [15:0] CMD7_IN              =  16'h0401;                 
localparam [15:0] CMD42_OUT            =  16'h0500;
localparam [15:0] CMD42_IN             =  16'h0501;
localparam [15:0] CMD55_OUT2           =  16'h0600;
localparam [15:0] CMD55_IN2            =  16'h0601;
localparam [15:0] ACMD6_OUT            =  16'h0700;
localparam [15:0] ACMD6_IN             =  16'h0701;
localparam [15:0] DATAW_SW             =  16'h0702; 
localparam [15:0] CH_CMD6_OUT          =  16'h0800;
localparam [15:0] CH_CMD6_IN           =  16'h0801;
localparam [15:0] CH_FUN               =  16'h0802; 
localparam [15:0] SW_CMD6_OUT          =  16'h0804; 
localparam [15:0] SW_CMD6_IN           =  16'h0808;  
localparam [15:0] CH_SW_FUN            =  16'h0810; 
localparam [15:0] SW_FUN               =  16'h0820;  

localparam [15:0] DATA_IDLE            =  16'h1000;

localparam [15:0] PREP_RD              =  16'h2000; 
localparam [15:0] CMD18_OUT            =  16'h2020;
localparam [15:0] CMD18_IN             =  16'h2021;
localparam [15:0] BLK_DIN              =  16'h2040;  
localparam [15:0] BLK_DIN_CH           =  16'h2041; 

localparam [15:0] PREP_WR              =  16'h4000;  
localparam [15:0] CMD32_OUT            =  16'h4010;
localparam [15:0] CMD32_IN             =  16'h4011;  
localparam [15:0] CMD33_OUT            =  16'h4012;
localparam [15:0] CMD33_IN             =  16'h4013;  
localparam [15:0] CMD38_OUT            =  16'h4014;
localparam [15:0] CMD38_IN             =  16'h4015;  
localparam [15:0] ERASE_WAIT           =  16'h4016;
localparam [15:0] CMD25_OUT            =  16'h4020;
localparam [15:0] CMD25_IN             =  16'h4021;  
localparam [15:0] PREP_BLK_DOUT        =  16'h4040;
localparam [15:0] BLK_DOUT             =  16'h4041; 
localparam [15:0] SD_ST_ON_D0          =  16'h4042;
localparam [15:0] BLK_DOUT_CH          =  16'h4044; 

localparam [15:0] CMD12_OUT            =  16'h1001;
localparam [15:0] CMD12_IN             =  16'h1002;
localparam [15:0] CMD12_BSY            =  16'h1003; 

localparam [15:0] RDY                  =  16'h8001;
localparam [15:0] UNSUPORTED           =  16'h8002;
localparam [15:0] TO_ERROR             =  16'h8004; 
localparam [15:0] CRC_ERROR            =  16'h8008;
localparam [15:0] FLASH_ERROR          =  16'h8010;
localparam [15:0] CARD_LCK             =  16'h8020;
//-------------------------------------------------------------------------------------------------                                         
localparam [31:0] TIME_VOL_SW0         =  32'd2000;  // count in tic of SD clock. For 400KHz SD CLK period equals 2.5us, so 2000 clocks is 5ms
localparam [31:0] TIME_VOL_SW2         =  32'd400;   // count in tic of SD clock. For 400KHz SD CLK period equals 2.5us, so 400 clocks is 1ms
                                                                         
//-------------------------------------------------------------------------------------------------    
localparam [0:0] OP_COND_HCS           =  1'b1; // HIGH CAPPACITY SUPPORT (SDHC or SDXC)
localparam [0:0] OP_COND_XPC           =  1'b1; // Maximum power in the default speed mode of SDXC card. 
                                               //  0 -> MAX 0.36W, 1 -> MAX 0.54W          

//-------------------------------------------------------------------------------------------------
// power supply voltage (VDD) not command and data pins voltage
//  card is powered with 3.3V so command will be send with 2.7-3.6 option indicated 
localparam [3:0] VOL_SUPP              =  4'b0001; //*4'b0001 - 2.7V-3.6V
                                                   // 4'b0010 - reserved for low voltage
                                                    
//-------------------------------------------------------------------------------------------------
// card functions parameters to switch to:
localparam [3:0] FUN_NO_INFLUENC  = 4'hF;
localparam [3:0] POWER_LIMIT_DEF  = 4'h0;
localparam [3:0] POWER_LIMIT_UHSI = 4'h1;  
                                // 0 - default 0.72W (200mA)
                                //*1 - 1.44W (400mA) - max for UHS I and also required for UHS I high speed modes
                                // 2 - 2.16W (600mA)- only for embedded devices
                                // 3 - 2.88W (800mA)- only for embedded devices
                                // 4 - 1.80W (   mA)- for UHS II      
                                // F - when F is send than it has no influence on a function value
                                // other - reserved
localparam [3:0] UHS_DRIVE_STREN = 4'h0; 
                                // pure description of those modes, so default left
                                //*0 - default Type B
                                // 1 - Type A
                                // 2 - Type C
                                // 3 - Type D 
                                // F - when F is send than it has no influence on a function value
                                // other - reserved    
localparam [3:0] CMD_SYS     = 4'hF;  
                                // Choose if CMD34-37, CMD50 and CMD57 are supported:
                                // 0 - default no support
                                // 1 - interpreted as eC (mobile e-commerence extention)
                                // 2 - reserved
                                // 3 - interpreted as OTP
                                // 4 - interpreted as ASSD
                                //*F - when F is send than it has no influence on a function value
                                // other - reserved     
localparam [3:0] SPEED_MODE_S25 = 4'h1;   
localparam [3:0] SPEED_MODE_S50 = 4'h2;   
localparam [3:0] SPEED_MODE_S104= 4'h3;         
                                // 0 - default SDR12
                                //*1 - SDR25
                                //*2 - SDR50  - just for 1.8V signaling
                                //*3 - SDR104 - just for 1.8V signaling
                                // 4 - DDR50  - just for 1.8V signaling
                                // F - when F is send than it has no influence on a function value
                                // other - reserved
//================================================================================================= 
(* dont_touch = "true" *) reg         iclk_en_400K;
(* dont_touch = "true" *) reg         iclk_en_25M;
(* dont_touch = "true" *) reg         iclk_en_50M;
(* dont_touch = "true" *) reg         iclk_en_100M;
(* dont_touch = "true" *) reg         iclk_en_200M;

//------------------------------------------------------------------------------------------------- 
//(* fsm_extract = "yes", fsm_encoding = "one_hot" *) reg [ 15:0] h_str;                              
(* fsm_extract = "yes", fsm_encoding = "User" *) reg [ 15:0] h_str;                                
//reg [ 15:0] h_str;                                                                               
reg         card_det;                                             

//-------------------------------------------------------------------------------------------------   
wire        state_idle_f;      
wire        state_init0_f;  
wire        state_cmd0out_f;   
wire        state_cmd8out_f;   
wire        state_cmd8in_f;    
wire        state_v_ch_f;     
wire        state_cmd55out_f;
wire        state_cmd55in_f;
wire        state_acmd41out_f; 
wire        state_acmd41in_f; 

wire        state_cmd11out_f;
wire        state_cmd11in_f ; 
wire        state_volt_sw0_f;
wire        state_volt_sw1_f;
wire        state_volt_sw2_f; 
wire        state_clk_sw0_f;
wire        state_clk_sw1_f;
wire        state_cmd2out_f ;
wire        state_cmd2in_f  ; 
wire        state_cmd3out_f ;
wire        state_cmd3in_f  ;
wire        state_cmd9out_f ;
wire        state_cmd9in_f  ;
wire        state_cmd7out_f ;
wire        state_cmd7in_f  ;
wire        state_cmd42out_f;
wire        state_cmd42in_f ;
wire        state_cmd55out2_f;
wire        state_cmd55in2_f;
wire        state_acmd6out_f;
wire        state_acmd6in_f ;
wire        state_dataw_sw_f; 
wire        state_ch_cmd6out_f; 
wire        state_ch_cmd6in_f;  
wire        state_ch_fun_f;
wire        state_sw_cmd6out_f;  
wire        state_sw_cmd6in_f;
wire        state_ch_sw_fun_f;
wire        state_sw_fun_f;    

wire        state_data_idle_f ; 

wire        state_prep_rd_f;   
wire        state_cmd18out_f;
wire        state_cmd18in_f;
wire        state_blk_din_f;
wire        state_blk_din_ch_f;                  
                              
wire        state_prep_wr_f;  
wire        state_cmd32out_f;
wire        state_cmd32in_f;  
wire        state_cmd33out_f;
wire        state_cmd33in_f;  
wire        state_cmd38out_f;
wire        state_cmd38in_f; 
wire        state_erase_wait_f;
wire        state_cmd25out_f;
wire        state_cmd25in_f; 
wire        state_prep_dout_f;
wire        state_blk_dout_f;
wire        state_sd_st_on_d0_f;  
wire        state_blk_dout_ch_f; 

wire        state_cmd12out_f;
wire        state_cmd12in_f;  
wire        state_cmd12bsy_f;

wire        state_rdy_f;       
wire        state_unsuported_f;
wire        state_to_err_f;   
wire        state_crc_err_f; 
wire        state_flash_err_f;
                                 
wire        state_cardStat_upd_f;
reg         state_cardStat_upd_fx;
reg         state_cardStat_upd3_fx;
wire        state_cardStat_chg_f;
reg         state_cardStat_chg_fx;


//================================================================================================
// DATA TRANSFER EVENTS INPUT
//================================================================================================ 
wire        ix_bsy;
wire        ix_rd_stb;
wire        ix_wr_stb;
reg  [38:0] ix_mem_start_addr;
reg  [38:0] ix_sd_start_addr;
reg  [38:0] ix_sd_end_addr;
reg  [16:0] ix_blk_left_m2;
wire        ix_blk_last_f;   

wire        ix_rd_blk_end_f;
wire        ix_rd_blk_err_f;
wire        ix_rd_blk_ok_f; 

wire        ix_wr_blk_end_f;
wire        ix_wr_sts_got_f;
wire        ix_wr_blk_err_f;
wire        ix_wr_blk_ok_f; 
wire        ix_wr_flash_err_f;
                            
reg         ix_ch_cmd6_data;
reg         ix_sw_cmd6_data;    
                           
reg         o_wr_retry;
reg         o_rd_retry;  
reg  [ 3:0] o_retry_cnt;
//=================================================================================================
// Input                                                                                           
//================================================================================================= 
wire        i_cmd_end;
wire        i_cmd_end_ok;
wire        i_cmd_end_er;
wire        i_cmd_tout_f;
wire        i_crc_ok;                     
wire [40:0] i_cmd_addr;                   
wire [40:0] i_cmd_end_addr;                      
                               
//-------------------------------------------------------------------------------------------------
wire        i0_cmd_bit;   
wire        i0_state_cmd;
wire        i0_state_cmd48; 
wire        i0_state_cmd136;
                               
//-------------------------------------------------------------------------------------------------
wire        i1_cmd_en;
wire        i1_cmd_en_tic;
wire[125:0] i1_cmd_in;    
wire        i1_crc_valid;
wire [ 6:0] i1_crc;
wire        i1_timeout_f; 
                  
//-------------------------------------------------------------------------------------------------        
//R1                        
wire [ 5:0] i1_R1_cmdIdx;
wire [31:0] i1_R1_cardStat;

//R2                                                                                                   
wire[127:0] i1_R2_CID_CSD;

// R3 (response to ACMD41)                                                                          
wire [31:0] i1_R3_OCR;  
           
// R6 (response to CMD3 - get public RCA number)                                                                        
wire [15:0] i1_R6_RCA;
wire [15:0] i1_R6_cardStat;
            
// R7 (response to CMD8)
wire [ 3:0] i1_R7_v_supp;  
//-------------------------------------------------------------------------------------------------
reg         i2_cmd_en;
reg         i2_cmd_fin;
reg         i2_cmd_fin_ok; 
reg         i2_cmd_fin_er; 
reg         i2_crc_valid;
reg         i2_timeout_f;                                                                        

//-------------------------------------------------------------------------------------------------
reg         i2_v_match;
reg         i2_v_ok_valid;

reg  [31:0] i2_OCR ; 
reg         i2_OCR_valid; 
wire        i2_OCR_busy; 
wire        i2_OCR_CCS ; 
wire        i2_OCR_UHS2; 
wire        i2_OCR_S18A; 
wire [23:0] i2_OCR_VDD_sup;
                   
reg [127:0] i2_CID;
reg         i2_CID_valid;
                   
reg [127:0] i2_CSD;
reg         i2_CSD_valid;

reg [ 15:0] i2_RCA;    
reg         i2_RCA_valid;

reg [31:0]  i2_cardStat;       
reg         i2_cardStat_valid; 
reg         i2_cardStat_e_f;
                                                                                       
//=================================================================================================
// output
//=================================================================================================
wire        o0_cmd_state;   
reg  [31:0] o0_cmd_addr;
reg  [31:0] o0_cmd_addr_last;

//-------------------------------------------------------------------------------------------------
reg         o1_cmd_req;   
reg         o1_cmd_pend;   
reg  [37:0] o1_cmd;
wire        o1_cmd_ack;
reg  [ 3:0] o1_cmd_del_cnt;
wire        o1_cmd_del_f;
          
//-------------------------------------------------------------------------------------------------
wire        o2_cmd_bit;
wire        o2_cmd_en;
wire        o2_cmd_last_f;
wire        o2_cmd_body_f;
wire        o2_cmd_crc_f;

//-------------------------------------------------------------------------------------------------    
reg         o3_cmd_en; 

//-------------------------------------------------------------------------------------------------   
reg         o4_cmd_sent;

//-------------------------------------------------------------------------------------------------
reg         clk_cnt_ena;
reg         clk_cnt_load;
reg  [27:0] clk_cnt; 
reg  [27:0] clk_cnt_ini;
wire        clk_cnt_end;   
wire        i_dat_tout_f;
 
//================================================================================================= 
wire        sd_v_ok;
wire        sd_v_ok_valid;  

wire [31:0] sd_OCR;
wire        sd_OCR_valid;
wire        sd_OCR_busy;
wire        sd_OCR_R18A;
wire        sd_OCR_HC;
wire        sd_OCR_UHS2;

wire[127:0] sd_CID; 
wire        sd_CID_valid;   
wire [ 7:0] sd_CID_MID; 
wire [15:0] sd_CID_OID;
wire [39:0] sd_CID_PNM;
wire [ 7:0] sd_CID_PRV;
wire [31:0] sd_CID_PSN;
wire [11:0] sd_CID_MDT;
wire [ 7:0] sd_CID_CRC; 

wire[127:0] sd_CSD       ;  
wire        sd_CSD_valid ;  
wire        sd_CSD_VER1  ;  
wire        sd_CSD_VER2  ;  
wire [ 7:0] sd_CSD_TSPEED; 
wire [11:0] sd_CSD_CCC;
wire        sd_CSD_CMD_CLS10;
wire [11:0] sd_CSD_DSIZE_V1; 
wire [21:0] sd_CSD_DSIZE_V2; 
wire        sd_CSD_DSR_IM;  


wire [15:0] sd_RCA;
wire        sd_RCA_valid;

reg         sd_clk_oe; 
wire        sd_cmd_oe;
reg         sd_low_volt_f;
reg         sd_dat_4bit_f;
                       
wire [31:0] sd_cStat;
// at least one error's flag
wire        sd_cStat_e_f;
// parse card stats flags
wire        sd_cStat_eOOR;
wire        sd_cStat_eAE ;
wire        sd_cStat_eBLE;
wire        sd_cStat_eESE;
wire        sd_cStat_eEP ;
wire        sd_cStat_eWPV;
wire        sd_cStat_lck ;
wire        sd_cStat_eLUF;
wire        sd_cStat_eCRC;
wire        sd_cStat_eIC ;
wire        sd_cStat_eCEF;
wire        sd_cStat_eCCE;
wire        sd_cStat_eERR;                                                                                               
wire        sd_cStat_eCSD;
wire        sd_cStat_eWES;
wire        sd_cStat_ECCD;
wire        sd_cStat_ERst;
wire [3:0]  sd_cStat_Stat;
wire        sd_cStat_RdyD;
wire        sd_cStat_AppC;
wire        sd_cStat_eAKE;
                         
wire        sd_cStat_sIDL;
wire        sd_cStat_sRDY;
wire        sd_cStat_sIDN;
wire        sd_cStat_sSBY;
wire        sd_cStat_sTRN;
wire        sd_cStat_sDAT;
wire        sd_cStat_sRCV;
wire        sd_cStat_sPRG;
wire        sd_cStat_sDIS;
wire        sd_cStat_sUNK;                                                                        

//-------------------------------------------------------------------------------------------------   
reg          st512_valid_trg;
reg          st512_sw_valid;         
reg          st512_capp_valid;  

reg  [ 15:0] st512_max_curr_cons;

reg  [ 15:0] st512_fg6_supp;         
reg  [ 15:0] st512_fg5_supp;         
reg  [ 15:0] st512_fg4_supp;         
reg  [ 15:0] st512_fg3_supp;         
reg  [ 15:0] st512_fg2_supp;         
reg  [ 15:0] st512_fg1_supp;   

reg  [  3:0] st512_fg6_can_sw;       
reg  [  3:0] st512_fg5_can_sw;       
reg  [  3:0] st512_fg4_can_sw;       
reg  [  3:0] st512_fg3_can_sw;       
reg  [  3:0] st512_fg2_can_sw;       
reg  [  3:0] st512_fg1_can_sw;  
        
reg  [  3:0] st512_fg6_sw;          
reg  [  3:0] st512_fg5_sw;          
reg  [  3:0] st512_fg4_sw;          
reg  [  3:0] st512_fg3_sw;          
reg  [  3:0] st512_fg2_sw;          
reg  [  3:0] st512_fg1_sw;   

reg  [  7:0] st512_version; 

reg  [ 15:0] st512_fg6_bsy;          
reg  [ 15:0] st512_fg5_bsy;          
reg  [ 15:0] st512_fg4_bsy;          
reg  [ 15:0] st512_fg3_bsy;          
reg  [ 15:0] st512_fg2_bsy;          
reg  [ 15:0] st512_fg1_bsy;  
                                                          
//-------------------------------------------------------------------------------------------------   
wire         sd_supp_sdr25;
wire         sd_supp_sdr50;  
wire         sd_supp_sdr104;
wire         sd_supp_ddr50;  
             
wire         sd_supp_400mA;
wire         sd_supp_600mA;  
wire         sd_supp_800mA;  

//-------------------------------------------------------------------------------------------------      
wire         sd_fun_sdr12;     
wire         sd_fun_sdr25;
wire         sd_fun_sdr50;  
wire         sd_fun_sdr104;
wire         sd_fun_ddr50; 
                          
//-------------------------------------------------------------------------------------------------                                                                    
reg          st512_pow_fun_bsy;
reg          st512_fun_speed_bsy;
reg          st512_fun_bsy;  
                                      
reg  [  3:0] st512_fg4_req;           
reg  [  3:0] st512_fg1_req; 
reg          st512_fun_match;     
//-------------------------------------------------------------------------------------------------
//output of packets with registers data
wire        rb_data_stb;
wire        rb_data_sof;
wire [71:0] rb_data_in;
wire        rb_data_in_ack; 
wire        rb_req_ack;  
//=================================================================================================
// Data input path                                                                                                                                                        
//=================================================================================================  
wire        id0_state_data;  
wire [ (AVAIL_DATA_BITS-'d1):0] id0_dat_bits;                                                                         
wire [38:0] id0_rd_addr; 
wire        id0_rd_internal; 
wire        id0_rd_int_mode;
wire        id1_crc_ok;
wire        id1_crc_err;                   
//wire        id1_timeout_f; 
wire        id1_rd_end; 
wire        id1_rd_rst;                                                                            
                                    
//-------------------------------------------------------------------------------------------------   
wire        id1_data_stb;
wire        id1_data_sof;
wire [71:0] id1_data_in;
wire        id1_data_in_ack; 
                            
//=================================================================================================
// id1s - parse recieved 512B status send on data line  
//=================================================================================================                                  
wire [71:0] id1s_data_in;                                
wire [ 2:0] id1s_data_in_ptr;
wire        id1s_data_in_ena; 
wire        id1s_data_mode;

//=================================================================================================
// Data request path                                                                                                                                                          
//=================================================================================================  
wire        dbuf_req_stb;
wire        dbuf_req_sof;
wire [71:0] dbuf_req_dat;
wire        dbuf_req_ack;

// SYS_CLK address input
wire        dbuf_i_stb;
wire [38:0] dbuf_i_adr;
wire [15:0] dbuf_i_mul_m2;
wire        dbuf_i_ack;
                                      
// SD_CLK domain output
wire        dbuf_sd_pkt_rdy;
wire [63:0] dbuf_sd_dat;
wire        dbuf_sd_ack;
wire        dbuf_sd_first;
wire        dbuf_sd_last;
wire [15:0] dbuf_sd_npkt_done;
wire        dbuf_sd_pkt_ack;
wire        dbuf_sd_pkt_ret;

//=================================================================================================
// Data output to SD card path                                                                                                                                                        
//================================================================================================= 
wire        dout_pkt_trg;
wire        dout_pkt_done;

wire [(AVAIL_DATA_BITS-'d1):0] dout_dat;
wire        dout_oe;
                      
//=================================================================================================
// DATA LINE STATE CHECK                                                                                                                                                          
//================================================================================================= 
wire        d0_check_trg0; 
wire        d0_check_trg1; 
wire        d0_check_ack0; 
wire        d0_check_ack1; 
wire        d0_check_ack;
wire        d0_st_dat; 

wire        d0_st_sdo_crc_ok;
wire        d0_st_sdo_crc_err;
wire        d0_st_sdo_bsy_end;
wire        d0_st_sdo_flash_err; 

//=================================================================================================
// CLOCK MULTIPLEXER  
//================================================================================================ 
initial  
    begin 
                        iclk_en_400K <=                                                       1'b1;
                        iclk_en_25M  <=                                                       1'b0;
                        iclk_en_50M  <=                                                       1'b0;
                        iclk_en_100M <=                                                       1'b0;
                        iclk_en_200M <=                                                       1'b0;
    end                                                          
  
always@(posedge CLK or posedge RST)                                                                 
 if(RST) 
    begin 
                        iclk_en_400K <=                                                       1'b1;
                        iclk_en_25M  <=                                                       1'b0;
                        iclk_en_50M  <=                                                       1'b0;
                        iclk_en_100M <=                                                       1'b0;
                        iclk_en_200M <=                                                       1'b0;
    end                                                          
 else if(state_cmd0out_f || state_init0_f) 
    begin 
                        iclk_en_400K <=                                                       1'b1;
                        iclk_en_25M  <=                                                       1'b0;
                        iclk_en_50M  <=                                                       1'b0;
                        iclk_en_100M <=                                                       1'b0;
                        iclk_en_200M <=                                                       1'b0;
    end                                                                                      
 else if(state_clk_sw0_f) 
    begin                                                                                      
                        iclk_en_400K <=                                                       1'b0;
                        iclk_en_25M  <=                                                       1'b1;
                        iclk_en_50M  <=                                                       1'b0;
                        iclk_en_100M <=                                                       1'b0;
                        iclk_en_200M <=                                                       1'b0; 
    end                                                                                      
 else if(state_sw_fun_f)                                                                       
    begin                                                                                      
                        iclk_en_400K <=                                                       1'b0;
                        iclk_en_25M  <=                                               sd_fun_sdr12;
                        iclk_en_50M  <=                                               sd_fun_sdr25;
                        iclk_en_100M <=                                               sd_fun_sdr50;
                        iclk_en_200M <=                                              sd_fun_sdr104;   
    end                                                         
 else                    
    begin 
                        iclk_en_400K <=                                                iclk_en_400K;
                        iclk_en_25M  <=                                                iclk_en_25M ;
                        iclk_en_50M  <=                                                iclk_en_50M ;
                        iclk_en_100M <=                                                iclk_en_100M;
                        iclk_en_200M <=                                                iclk_en_200M;
    end
  
//=================================================================================================
assign CLK_EN_400K    =                                                               iclk_en_400K;
assign CLK_EN_25M     =                                                               iclk_en_25M ;
assign CLK_EN_50M     =                                                               iclk_en_50M ;
assign CLK_EN_100M    =                                                               iclk_en_100M;
assign CLK_EN_200M    =                                                               iclk_en_200M;
//================================================================================================
// DATA TRANSFER EVENTS INPUT
//================================================================================================ 
assign ix_bsy           =                                                       !state_data_idle_f;
assign REQ_I_ACK        =                 (!ix_bsy & (REQ_I_RD_STB || REQ_I_WR_STB)) || rb_req_ack; 
assign ix_rd_stb        =                                                             REQ_I_RD_STB;
assign ix_wr_stb        =                                                             REQ_I_WR_STB;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)                                                                 
     if(state_data_idle_f                   ) ix_mem_start_addr  <=                 REQ_I_MEM_ADDR;     
else if(state_blk_din_ch_f  & ix_rd_blk_ok_f) ix_mem_start_addr  <=    ix_mem_start_addr + 39'd512;
else if(state_blk_dout_ch_f & ix_wr_blk_ok_f) ix_mem_start_addr  <=    ix_mem_start_addr + 39'd512;
else                                          ix_mem_start_addr  <=              ix_mem_start_addr;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)                                                   
     if(state_data_idle_f)                    ix_sd_start_addr   <=                  REQ_I_SD_ADDR;
else if(state_blk_din_ch_f  & ix_rd_blk_ok_f) ix_sd_start_addr   <=     ix_sd_start_addr + 39'd512;
else if(state_blk_dout_ch_f & ix_wr_blk_ok_f) ix_sd_start_addr   <=     ix_sd_start_addr + 39'd512; 
else                                          ix_sd_start_addr   <=               ix_sd_start_addr;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)                                                   
     if(state_data_idle_f)                    ix_sd_end_addr     <= REQ_I_SD_ADDR + {REQ_I_512B_MUL_M1, 9'd0};
else                                          ix_sd_end_addr     <=                 ix_sd_end_addr;
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)                                                   
     if(state_data_idle_f                   ) ix_blk_left_m2     <=      REQ_I_512B_MUL_M1 - 17'd1; 
else if(state_blk_din_ch_f  & ix_rd_blk_ok_f) ix_blk_left_m2     <=         ix_blk_left_m2 - 17'd1;
else if(state_blk_dout_ch_f & ix_wr_blk_ok_f) ix_blk_left_m2     <=         ix_blk_left_m2 - 17'd1; 
else                                          ix_blk_left_m2     <=                 ix_blk_left_m2; 
//------------------------------------------------------------------------------------------------- 
assign ix_blk_last_f   =                                                        ix_blk_left_m2[16];
//------------------------------------------------------------------------------------------------- 
assign i_cmd_addr       =                                                         ix_sd_start_addr;
assign i_cmd_end_addr   =                                                         ix_sd_end_addr  ;
                                                                                                    
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)                                                   
 if(RST)                                      ix_ch_cmd6_data    <=                           1'b0; 
else if(state_ch_cmd6out_f                  ) ix_ch_cmd6_data    <=                           1'b1;
else if(state_blk_din_ch_f & ix_rd_blk_ok_f ) ix_ch_cmd6_data    <=                           1'b0;
else                                          ix_ch_cmd6_data    <=                ix_ch_cmd6_data; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)                                                   
 if(RST)                                      ix_sw_cmd6_data    <=                           1'b0; 
else if(state_sw_cmd6out_f                  ) ix_sw_cmd6_data    <=                           1'b1;
else if(state_blk_din_ch_f & ix_rd_blk_ok_f ) ix_sw_cmd6_data    <=                           1'b0;
else                                          ix_sw_cmd6_data    <=                ix_sw_cmd6_data; 
//=================================================================================================
// STATE MACHINE
//=================================================================================================

always@(posedge CLK or posedge RST)
 if(RST)                                    h_str   <=                                        IDLE;
 else begin case(h_str)
 IDLE:          if(card_det               ) h_str   <=                                       INIT0; 
           else                             h_str   <=                                        IDLE;
 INIT0:         if(clk_cnt_end            ) h_str   <=                                    CMD0_OUT; 
           else                             h_str   <=                                       INIT0;
//-------------------------------------------------------------------------------------------------
// INITIALIZATION phase
//-------------------------------------------------------------------------------------------------
// reset card to *IDLE* state                                                                      
 CMD0_OUT:      if(o4_cmd_sent            ) h_str   <=                               V_CH_CMD8_OUT;  
           else                             h_str   <=                                    CMD0_OUT;  
//-------------------------------------------------------------------------------------------------
// check if supply voltage window for host and SD card match. 
// CMD8 required for SDHC & SDXC cards. If card did not recived CMD8 it will always indicate that 
//  it is busy (in ACMD41 response).
 V_CH_CMD8_OUT: if(o4_cmd_sent            ) h_str   <=                                V_CH_CMD8_IN;   
           else                             h_str   <=                               V_CH_CMD8_OUT;
 V_CH_CMD8_IN:  if(i_cmd_end_ok           ) h_str   <=                                    V_CH_END;
           else if(i_cmd_end_er           ) h_str   <=                               V_CH_CMD8_OUT; // try once more 
           else if(i_cmd_tout_f           ) h_str   <=                                  UNSUPORTED; // card version 1.0 do not recognize CMD8, do not response to CMD8 and are unsupported  
           else                             h_str   <=                                V_CH_CMD8_IN;
 V_CH_END:      if( sd_v_ok               ) h_str   <=                                   CMD55_OUT; 
           else                             h_str   <=                                  UNSUPORTED;  
//-------------------------------------------------------------------------------------------------
// check if card is a high cappacity card and if it can switch to 1.8V signals level
// check if card is still in power up state, if not than card goes to the *READY* state
 CMD55_OUT:     if(o4_cmd_sent            ) h_str   <=                                    CMD55_IN;  
           else                             h_str   <=                                   CMD55_OUT;
 CMD55_IN:      if(i_cmd_end_ok           ) h_str   <= (sd_cStat_AppC)?     ACMD41_OUT : CMD55_OUT; // if card do not expect ASC than retry sending CMD55
           else if(i_cmd_end_er           ) h_str   <=                                   CMD55_OUT; 
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart
           else                             h_str   <=                                    CMD55_IN;
             
 ACMD41_OUT:    if(o4_cmd_sent            ) h_str   <=                                  ACMD41_IN ; 
           else                             h_str   <=                                  ACMD41_OUT;
 ACMD41_IN:     if(sd_OCR_busy&&i_cmd_end ) h_str   <=                                   CMD55_OUT; // repeat CMD 55 and ACMD41 until card is not busy   
           else if(             i_cmd_end ) h_str   <= (sd_OCR_R18A)?          CMD11_OUT : CLK_SW0; // voltage switching vs card not cappable for 1.8V (skip voltage switching) 
         //else if(i_cmd_end_er           ) h_str   <=                                   CRC_ERROR; - for ACMD41 CRC is always equal 7'h7F
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart 
           else                             h_str   <=                                   ACMD41_IN;
           
//------------------------------------------------------------------------------------------------- 
//switch voltage to 1.8V (if already switched than will not response to this command)
//  and this can happen when host is reset but a card was not power down and was already switched 
//  to 1.8V. Need to deal with this problem.
 CMD11_OUT:     if(o4_cmd_sent            ) h_str   <=                                    CMD11_IN; 
           else                             h_str   <=                                   CMD11_OUT;
 CMD11_IN:      if(i_cmd_end_ok           ) h_str   <=                                    VOLT_SW0;
           else if(i_cmd_end_er           ) h_str   <=                                   CMD11_OUT; 
           else if(i_cmd_tout_f           ) h_str   <=                                     CLK_SW0; // timeout - maybe already switched and is not responding 
           else                             h_str   <=                                        IDLE; // restart
 // disable clk for 5ms and put CMD and DAT to high impedance. During this stage an SD card drive CMD and DAT[3:0] low - check it at the end of this period                                                                                                                                 
 VOLT_SW0:if(clk_cnt_end &!id0_dat_bits[0]) h_str   <=                                    VOLT_SW1; // Card started voltage switch procedure   
           else if(clk_cnt_end            ) h_str   <=                                        IDLE; // Voltage switch procedure error
           else                             h_str   <=                                    VOLT_SW0;
 // switch to 1.8V and provide SD Clock at 1.8V                                                                                                                                  
 VOLT_SW1:                                  h_str   <=                                    VOLT_SW2; 
 // card puts Cmd to high (1.8V) for one clock period and leave it to the high impedance state      
 // card puts DAT [3:0] to high (1.8V) for one clock period and leave it to the high impedance state  
 // check if it is done after 1ms
 VOLT_SW2:if(clk_cnt_end & id0_dat_bits[0]) h_str   <=                                     CLK_SW0; // after voltage switch card puts data bits high    
           else if(clk_cnt_end            ) h_str   <=                                        IDLE; // Voltage switch procedure error 
           else                             h_str   <=                                    VOLT_SW2; // Voltage switch procedure error 
//------------------------------------------------------------------------------------------------- 
// switch clock to higher clock
 CLK_SW0:                                   h_str   <=                                     CLK_SW1;  
//------------------------------------------------------------------------------------------------- 
// switch clock to higher clock
 CLK_SW1:       if(clk_cnt_end            ) h_str   <=                                    CMD2_OUT; // wait for clock change
           else                             h_str   <=                                     CLK_SW1; 
//------------------------------------------------------------------------------------------------- 
// Ask for a CID numbers  
// card goes to *IDENT* state
 CMD2_OUT:      if(o4_cmd_sent            ) h_str   <=                                     CMD2_IN;  
           else                             h_str   <=                                    CMD2_OUT;
 CMD2_IN:       if(i_cmd_end_ok           ) h_str   <=                                    CMD3_OUT;
           else if(i_cmd_end_er           ) h_str   <=                                    CMD2_OUT; 
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart  
           else                             h_str   <=                                     CMD2_IN; 
                                                                                                    
//-------------------------------------------------------------------------------------------------
// DATA transfer phase
//-------------------------------------------------------------------------------------------------
// Ask for a new relative card address (RCA) and 
// card goes from *IDENT* state to *STANDBY* state 
 CMD3_OUT:      if(o4_cmd_sent            ) h_str   <=                                     CMD3_IN;  
           else                             h_str   <=                                    CMD3_OUT;
 CMD3_IN:       if(i_cmd_end_ok           ) h_str   <= (!sd_RCA_valid)?        CMD3_OUT : CMD9_OUT; // if recived RCA was not valid (value 0 was received) than ask for a new RCA number
           else if(i_cmd_end_er           ) h_str   <=                                    CMD3_OUT; 
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart  
           else                             h_str   <=                                     CMD3_IN; 
           
//------------------------------------------------------------------------------------------------- 
// get Card Specific Data register (CSD)  
// card still in *STANDBY* state
 CMD9_OUT:      if(o4_cmd_sent            ) h_str   <=                                     CMD9_IN;  
           else                             h_str   <=                                    CMD9_OUT;
 CMD9_IN:       if(i_cmd_end_ok           ) h_str   <=                                    CMD7_OUT;                               
           else if(i_cmd_end_er           ) h_str   <=                                    CMD9_OUT; 
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart
           else                             h_str   <=                                     CMD9_IN; 
           
//------------------------------------------------------------------------------------------------- 
// card goes to *TRANS* state
 CMD7_OUT:      if(o4_cmd_sent            ) h_str   <=                                     CMD7_IN;  
           else                             h_str   <=                                    CMD7_OUT; 
 CMD7_IN:       if(i_cmd_end_ok           ) h_str   <= (sd_cStat_lck)?                   CARD_LCK : // unlocking card is not supported now. If card locked just go to CARD_LCK state
                                                       (AVAIL_DATA_BITS=='d4)?          CMD55_OUT2: // go to "set data width to 4", but only if (AVAIL_DATA_BITS==4)
                                                       (sd_CSD_CMD_CLS10)? CH_CMD6_OUT : DATA_IDLE; 
           else if(i_cmd_end_er           ) h_str   <=                                    CMD7_OUT; 
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart
           else                             h_str   <=                                     CMD7_IN; 
           
////------------------------------------------------------------------------------------------------- 
//// unlock locked card - lock/unlock password protected card is not supportd in this host driver
//// goes to *RCV* state
// CMD42_OUT:     if(o4_cmd_sent            ) h_str   <=                                     CMD42_IN;
// CMD42_IN:      if(i_cmd_end_ok           ) h_str   <=                                   CMD55_OUT2;
//           else if(i_cmd_end_er           ) h_str   <=                                    CMD42_OUT; 
//           else if(i_cmd_tout_f            ) h_str   <=                                    CMD42_OUT;
//                                                                                                   
//------------------------------------------------------------------------------------------------- 
// set data width to 4, but only if (AVAIL_DATA_BITS==4)
// card still in *TRANS* state
 CMD55_OUT2:    if(o4_cmd_sent            ) h_str   <=                                   CMD55_IN2;
           else                             h_str   <=                                  CMD55_OUT2; 
 CMD55_IN2:     if(i_cmd_end_ok           ) h_str   <=  (sd_cStat_AppC)?    ACMD6_OUT : CMD55_OUT2;
           else if(i_cmd_end_er           ) h_str   <=                                  CMD55_OUT2;
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart
           else                             h_str   <=                                   CMD55_IN2; 
                                                                                                    
 ACMD6_OUT:     if(o4_cmd_sent            ) h_str   <=                                    ACMD6_IN;
           else                             h_str   <=                                   ACMD6_OUT; 
 ACMD6_IN:      if(i_cmd_end_ok           ) h_str   <=                                    DATAW_SW; 
           else if(i_cmd_end_er           ) h_str   <=                                  CMD55_OUT2;  
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart
           else                             h_str   <=                                    ACMD6_IN;   
// if card supports commands class 10 than we can configure its functions with CMD6 - especially
// UHSI card functions.
 DATAW_SW:                                  h_str   <= (sd_CSD_CMD_CLS10)? CH_CMD6_OUT : DATA_IDLE; 
                                                                                                    
//------------------------------------------------------------------------------------------------- 
// read supported functions
 CH_CMD6_OUT:   if(o4_cmd_sent            ) h_str   <=                                  CH_CMD6_IN;
           else                             h_str   <=                                 CH_CMD6_OUT; 
 CH_CMD6_IN:    if(i_cmd_end_ok           ) h_str   <=                                     BLK_DIN; 
           else if(i_cmd_end_er           ) h_str   <=                                 CH_CMD6_OUT; 
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart
           else                             h_str   <=                                  CH_CMD6_IN; 
// check if selected functions are not busy. If so, retry sending switching request 
 CH_FUN:        if(!st512_valid_trg       ) h_str   <=                                      CH_FUN;  
           else if(!st512_fun_bsy         ) h_str   <=                                 SW_CMD6_OUT; 
           else                             h_str   <=                                 CH_CMD6_OUT;  
//------------------------------------------------------------------------------------------------- 
// set best available functions (highest available speed mode)
 SW_CMD6_OUT:   if(o4_cmd_sent            ) h_str   <=                                  SW_CMD6_IN;
           else                             h_str   <=                                 SW_CMD6_OUT; 
 SW_CMD6_IN:    if(i_cmd_end_ok           ) h_str   <=                                     BLK_DIN; 
           else if(i_cmd_end_er           ) h_str   <=                                 SW_CMD6_OUT; 
           else if(i_cmd_tout_f           ) h_str   <=                                        IDLE; // restart
           else                             h_str   <=                                  SW_CMD6_IN;
// check if switching was successfull - if returned functions match requested ones
 CH_SW_FUN:     if(!st512_valid_trg       ) h_str   <=                                   CH_SW_FUN;  
           else if(st512_fun_match        ) h_str   <=                                      SW_FUN;
           else                             h_str   <=                                 SW_CMD6_OUT; 
// switch host clock for selected speed mode                                                        
 SW_FUN:                                    h_str   <=                                   DATA_IDLE;
//------------------------------------------------------------------------------------------------- 
// Card and interface initialized, wait for data read/write requests
 DATA_IDLE:     if(!card_det              ) h_str   <=                                        IDLE; 
           else if( ix_rd_stb             ) h_str   <=                                     PREP_RD; 
           else if( ix_wr_stb             ) h_str   <=                                     PREP_WR; 
           else                             h_str   <=                                   DATA_IDLE;
                                                                                                   
//------------------------------------------------------------------------------------------------- 
//----------------------------------------- READ --------------------------------------------------
//------------------------------------------------------------------------------------------------- 
// start read                                                                               
 PREP_RD  :                                 h_str   <=                                   CMD18_OUT;  
                                                                                                               
//-------------------------------------------------------------------------------------------------  
// commands for multiple blocks
 CMD18_OUT:     if(o4_cmd_sent            ) h_str   <=                                    CMD18_IN;
           else                             h_str   <=                                   CMD18_OUT; 
 CMD18_IN:      if(i_cmd_end_ok           ) h_str   <=                                     BLK_DIN;                                                   
           else if(i_cmd_end_er           ) h_str   <=                                   CMD12_OUT; // stop and retry 
           else if(i_cmd_tout_f           ) h_str   <=                                   CMD12_OUT; // stop and retry
           else                             h_str   <=                                    CMD18_IN; 
             
//-------------------------------------------------------------------------------------------------
// actual data reception
 BLK_DIN:       if( i_dat_tout_f          ) h_str   <=                                   CMD12_OUT; // stop and retry  
           else if( ix_rd_blk_end_f       ) h_str   <=                                  BLK_DIN_CH; 
           else                             h_str   <=                                     BLK_DIN; 
// check the recieved data
 BLK_DIN_CH:    if( ix_rd_blk_ok_f        ) h_str   <= (ix_ch_cmd6_data)?                   CH_FUN: 
                                                       (ix_sw_cmd6_data)?                CH_SW_FUN: 
                                                       (ix_blk_last_f  )?      CMD12_OUT : BLK_DIN; 
           else if( ix_rd_blk_err_f       ) h_str   <= (ix_ch_cmd6_data)?                     IDLE: 
                                                       (ix_sw_cmd6_data)?                     IDLE:
                                                                                         CMD12_OUT;
           else                             h_str   <=                                  BLK_DIN_CH; 
                                                                                               
//------------------------------------------------------------------------------------------------- 
//----------------------------------------- WRITE -------------------------------------------------
//------------------------------------------------------------------------------------------------- 
// start write                                                                               
 PREP_WR  :                                 h_str   <=                                   CMD32_OUT;  
                                                                                                               
//-------------------------------------------------------------------------------------------------  
// commands for erase start address
 CMD32_OUT:     if(o4_cmd_sent            ) h_str   <=                                    CMD32_IN;
           else                             h_str   <=                                   CMD32_OUT; 
 CMD32_IN:      if(i_cmd_end_ok           ) h_str   <=                                   CMD33_OUT; 
           else if(i_cmd_end_er           ) h_str   <=                                   CMD12_OUT; // stop and retry  
           else if(i_cmd_tout_f           ) h_str   <=                                   CMD12_OUT; // stop and retry 
           else                             h_str   <=                                    CMD32_IN; 
                                                                                                    
//-------------------------------------------------------------------------------------------------  
// commands for erase end address
 CMD33_OUT:     if(o4_cmd_sent            ) h_str   <=                                    CMD33_IN;
           else                             h_str   <=                                   CMD33_OUT; 
 CMD33_IN:      if(i_cmd_end_ok           ) h_str   <=                                   CMD38_OUT; 
           else if(i_cmd_end_er           ) h_str   <=                                   CMD12_OUT; // stop and retry  
           else if(i_cmd_tout_f           ) h_str   <=                                   CMD12_OUT; // stop and retry 
           else                             h_str   <=                                    CMD33_IN; 
                         
//-------------------------------------------------------------------------------------------------  
// commands for erase operation start
 CMD38_OUT:     if(o4_cmd_sent            ) h_str   <=                                    CMD38_IN;
           else                             h_str   <=                                   CMD38_OUT; 
 CMD38_IN:      if(i_cmd_end_ok           ) h_str   <=                                  ERASE_WAIT; 
           else if(i_cmd_end_er           ) h_str   <=                                   CMD12_OUT; // stop and retry  
           else if(i_cmd_tout_f           ) h_str   <=                                   CMD12_OUT; // stop and retry 
           else                             h_str   <=                                    CMD38_IN; 
                                                                                                 
 ERASE_WAIT:    if( ix_wr_sts_got_f       ) h_str   <=                                   CMD25_OUT; 
           else                             h_str   <=                                  ERASE_WAIT; 
//-------------------------------------------------------------------------------------------------  
// commands for multiple blocks
 CMD25_OUT:     if(o4_cmd_sent            ) h_str   <=                                    CMD25_IN;
           else                             h_str   <=                                   CMD25_OUT; 
 CMD25_IN:      if(i_cmd_end_ok           ) h_str   <=                               PREP_BLK_DOUT; 
           else if(i_cmd_end_er           ) h_str   <=                                   CMD12_OUT; // stop and retry  
           else if(i_cmd_tout_f           ) h_str   <=                                   CMD12_OUT; // stop and retry 
           else                             h_str   <=                                    CMD25_IN; 
             
//------------------------------------------------------------------------------------------------- 
// actual data sending
 PREP_BLK_DOUT:                             h_str   <=                                    BLK_DOUT;
 BLK_DOUT:      if( ix_wr_blk_end_f       ) h_str   <=                                 SD_ST_ON_D0; 
           else                             h_str   <=                                    BLK_DOUT;
// data status receiving
 SD_ST_ON_D0:   if( i_dat_tout_f          ) h_str   <=                                   CMD12_OUT; // stop and retry  
           else if( ix_wr_sts_got_f       ) h_str   <=                                 BLK_DOUT_CH; 
           else                             h_str   <=                                 SD_ST_ON_D0; 
// check the received status
 BLK_DOUT_CH:   if( ix_wr_blk_ok_f        ) h_str   <= (ix_blk_last_f)?  CMD12_OUT : PREP_BLK_DOUT; 
           else if( ix_wr_blk_err_f       ) h_str   <=                                   CMD12_OUT; // stop and retry  
           else if( ix_wr_flash_err_f     ) h_str   <=                                   CMD12_OUT; // stop and retry 
           else                             h_str   <=                                 BLK_DOUT_CH; 
                                                                                                    
//------------------------------------------------------------------------------------------------- 
//-------------------------------------------------------------------------------------------------  
// stop operation command
 CMD12_OUT:     if(o4_cmd_sent            ) h_str   <=                                    CMD12_IN;
           else                             h_str   <=                                   CMD12_OUT; 
 CMD12_IN:      if(i_cmd_end_ok           ) h_str   <=                                   CMD12_BSY; 
           else if(i_cmd_end_er           ) h_str   <=                                   CMD12_OUT; 
           else if(i_cmd_tout_f           ) h_str   <= (o_retry_cnt[3]         )?             IDLE: 
                                                       (o_rd_retry | o_wr_retry)?        CMD12_BSY: // can be no answer if it is a retry attempt 
                                                                                         CMD12_OUT; 
           else                             h_str   <=                                    CMD12_IN; 
 CMD12_BSY:     if( ix_wr_sts_got_f       ) h_str   <=                     (o_wr_retry)? CMD32_OUT: // retry write from erase sequence            
                                                                           (o_rd_retry)? CMD18_OUT: // retry read from read request
                                                                                         DATA_IDLE; 
           else if( i_dat_tout_f          ) h_str   <=                                        IDLE; // dont know what was the operation so restart and reinitialize the card 
           else                             h_str   <=                                   CMD12_BSY; 
                                                                                                           
//------------------------------------------------------------------------------------------------- 
 RDY:                                       h_str   <=                                         RDY;
 UNSUPORTED:                                h_str   <=                                  UNSUPORTED;
 TO_ERROR:                                  h_str   <=                                    TO_ERROR;  
 CRC_ERROR:                                 h_str   <=                                   CRC_ERROR;  
 FLASH_ERROR:                               h_str   <=                                 FLASH_ERROR;
 CARD_LCK:                                  h_str   <=                                    CARD_LCK;
 default:                                   h_str   <=                                    TO_ERROR;
 endcase  
 end        
                                                                                                    
//=================================================================================================                   
always@(posedge CLK)
      if(state_idle_f                           ) o_retry_cnt  <=                             4'd0;  
 else if(state_cmd12in_f & i_cmd_end_ok         ) o_retry_cnt  <=                             4'd0; 
 else if(state_cmd12in_f & i_cmd_tout_f         ) o_retry_cnt  <=               o_retry_cnt + 4'd1;
 else                                             o_retry_cnt  <=               o_retry_cnt       ; 
//-------------------------------------------------------------------------------------------------                    
always@(posedge CLK or posedge RST)
 if(RST)                                          o_rd_retry   <=                             1'b0; 
 else if(state_blk_din_ch_f  & ix_rd_blk_err_f  ) o_rd_retry   <=                             1'b1; 
 else if(state_cmd18in_f & i_cmd_end_er         ) o_rd_retry   <=                             1'b1;
 else if(state_cmd18in_f & i_cmd_tout_f         ) o_rd_retry   <=                             1'b1;
 else if(state_blk_din_f & i_cmd_tout_f         ) o_rd_retry   <=                             1'b1;
 else if(state_blk_din_f                        ) o_rd_retry   <=                             1'b0;
 else                                             o_rd_retry   <=                       o_rd_retry;
//-------------------------------------------------------------------------------------------------                    
always@(posedge CLK or posedge RST)
 if(RST)                                          o_wr_retry <=                               1'b0;  
 else if(state_blk_dout_ch_f & ix_wr_blk_err_f  ) o_wr_retry <=                               1'b1;  
 else if(state_blk_dout_ch_f & ix_wr_flash_err_f) o_wr_retry <=                               1'b1; 
 else if(state_cmd32in_f     & i_cmd_end_er     ) o_wr_retry <=                               1'b1;
 else if(state_cmd32in_f     & i_cmd_tout_f     ) o_wr_retry <=                               1'b1; 
 else if(state_cmd33in_f     & i_cmd_end_er     ) o_wr_retry <=                               1'b1;
 else if(state_cmd33in_f     & i_cmd_tout_f     ) o_wr_retry <=                               1'b1; 
 else if(state_cmd38in_f     & i_cmd_end_er     ) o_wr_retry <=                               1'b1;
 else if(state_cmd38in_f     & i_cmd_tout_f     ) o_wr_retry <=                               1'b1;
 else if(state_cmd25in_f     & i_cmd_end_er     ) o_wr_retry <=                               1'b1; 
 else if(state_cmd25in_f     & i_cmd_tout_f     ) o_wr_retry <=                               1'b1; 
 else if(state_sd_st_on_d0_f & i_cmd_tout_f     ) o_wr_retry <=                               1'b1;                                                     
 else if(state_blk_dout_f                       ) o_wr_retry <=                               1'b0; 
 else                                             o_wr_retry <=                         o_wr_retry;
//=================================================================================================
// Card detection
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                    card_det <=                                                          0;
 else                       card_det <=                                                SD_CARD_PIN;
//------------------------------------------------------------------------------------------------- 
assign state_idle_f         =                                             (h_str == IDLE         );
assign state_init0_f        =                                             (h_str == INIT0        );
assign state_cmd0out_f      =                                             (h_str == CMD0_OUT     ); 
assign state_cmd8out_f      =                                             (h_str == V_CH_CMD8_OUT);
assign state_cmd8in_f       =                                             (h_str == V_CH_CMD8_IN );
assign state_v_ch_f         =                                             (h_str == V_CH_END     ); 
assign state_cmd55out_f     =                                             (h_str == CMD55_OUT    ); 
assign state_cmd55in_f      =                                             (h_str == CMD55_IN     );
assign state_acmd41out_f    =                                             (h_str == ACMD41_OUT   ); 
assign state_acmd41in_f     =                                             (h_str == ACMD41_IN    ); 

assign state_cmd11out_f     =                                             (h_str == CMD11_OUT    ); 
assign state_cmd11in_f      =                                             (h_str == CMD11_IN     ); 
assign state_volt_sw0_f     =                                             (h_str == VOLT_SW0     ); 
assign state_volt_sw1_f     =                                             (h_str == VOLT_SW1     ); 
assign state_volt_sw2_f     =                                             (h_str == VOLT_SW2     ); 
                                                                                                   
assign state_clk_sw0_f      =                                             (h_str == CLK_SW0      );
assign state_clk_sw1_f      =                                             (h_str == CLK_SW1      );

assign state_cmd2out_f      =                                             (h_str == CMD2_OUT     ); 
assign state_cmd2in_f       =                                             (h_str == CMD2_IN      );
assign state_cmd3out_f      =                                             (h_str == CMD3_OUT     ); 
assign state_cmd3in_f       =                                             (h_str == CMD3_IN      );
assign state_cmd9out_f      =                                             (h_str == CMD9_OUT     ); 
assign state_cmd9in_f       =                                             (h_str == CMD9_IN      );
assign state_cmd7out_f      =                                             (h_str == CMD7_OUT     ); 
assign state_cmd7in_f       =                                             (h_str == CMD7_IN      );
assign state_cmd42out_f     =                                             (h_str == CMD42_OUT    ); 
assign state_cmd42in_f      =                                             (h_str == CMD42_IN     );
assign state_cmd55out2_f    =                                             (h_str == CMD55_OUT2   ); 
assign state_cmd55in2_f     =                                             (h_str == CMD55_IN2    );
assign state_acmd6out_f     =                                             (h_str == ACMD6_OUT    ); 
assign state_acmd6in_f      =                                             (h_str == ACMD6_IN     ); 
assign state_dataw_sw_f     =                                             (h_str == DATAW_SW     );  
assign state_ch_cmd6out_f   =                                             (h_str == CH_CMD6_OUT  );   
assign state_ch_cmd6in_f    =                                             (h_str == CH_CMD6_IN   );              
assign state_ch_fun_f       =                                             (h_str == CH_FUN       );  
assign state_sw_cmd6out_f   =                                             (h_str == SW_CMD6_OUT  );             
assign state_sw_cmd6in_f    =                                             (h_str == SW_CMD6_IN   );  
assign state_ch_sw_fun_f    =                                             (h_str == CH_SW_FUN    ); 
assign state_sw_fun_f       =                                             (h_str == SW_FUN       ); 
                                                                                                   
assign state_data_idle_f    =                                             (h_str == DATA_IDLE    ); 

assign state_prep_rd_f      =                                             (h_str == PREP_RD      );   
assign state_cmd18out_f     =                                             (h_str == CMD18_OUT    );
assign state_cmd18in_f      =                                             (h_str == CMD18_IN     ); 
assign state_blk_din_f      =                                             (h_str == BLK_DIN      ); 
assign state_blk_din_ch_f   =                                             (h_str == BLK_DIN_CH   ); 

assign state_prep_wr_f      =                                             (h_str == PREP_WR      );    
assign state_cmd32out_f     =                                             (h_str == CMD32_OUT    );
assign state_cmd32in_f      =                                             (h_str == CMD32_IN     );    
assign state_cmd33out_f     =                                             (h_str == CMD33_OUT    );
assign state_cmd33in_f      =                                             (h_str == CMD33_IN     );    
assign state_cmd38out_f     =                                             (h_str == CMD38_OUT    ); 
assign state_cmd38in_f      =                                             (h_str == CMD38_IN     ); 
assign state_erase_wait_f   =                                             (h_str == ERASE_WAIT   );    
assign state_cmd25out_f     =                                             (h_str == CMD25_OUT    );
assign state_cmd25in_f      =                                             (h_str == CMD25_IN     );
assign state_prep_dout_f    =                                             (h_str == PREP_BLK_DOUT); 
assign state_blk_dout_f     =                                             (h_str == BLK_DOUT     );
assign state_sd_st_on_d0_f  =                                             (h_str == SD_ST_ON_D0  ); 
assign state_blk_dout_ch_f  =                                             (h_str == BLK_DOUT_CH  );

assign state_cmd12out_f     =                                             (h_str == CMD12_OUT    );
assign state_cmd12in_f      =                                             (h_str == CMD12_IN     );
assign state_cmd12bsy_f     =                                             (h_str == CMD12_BSY    ); 

assign state_rdy_f          =                                             (h_str == RDY          );
assign state_unsuported_f   =                                             (h_str == UNSUPORTED   );
assign state_to_err_f       =                                             (h_str == TO_ERROR     ); 
assign state_crc_err_f      =                                             (h_str == CRC_ERROR    );
assign state_flash_err_f    =                                             (h_str == FLASH_ERROR  );
                                                                                                                            
assign state_cardStat_upd_f =                       state_cmd7in_f  || state_cmd42in_f  || state_cmd55in2_f  || state_cmd55in_f  || state_acmd6in_f  || state_ch_cmd6in_f  || state_sw_cmd6in_f  || state_cmd18in_f  || state_cmd32in_f  || state_cmd33in_f  || state_cmd38in_f  || state_cmd25in_f  || state_cmd12in_f ;
assign state_cardStat_chg_f =   state_cmd3out_f || state_cmd7out_f || state_cmd42out_f || state_cmd55out2_f || state_cmd55out_f || state_acmd6out_f || state_ch_cmd6out_f || state_sw_cmd6out_f || state_cmd18out_f || state_cmd32out_f || state_cmd33out_f || state_cmd38out_f || state_cmd25out_f || state_cmd12out_f; 

//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                    state_cardStat_upd_fx <=                                          1'b0;
 else                       state_cardStat_upd_fx <=                          state_cardStat_upd_f;
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                    state_cardStat_upd3_fx<=                                          1'b0;
 else                       state_cardStat_upd3_fx<=                               state_cmd3out_f; 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                    state_cardStat_chg_fx <=                                          1'b0;
 else                       state_cardStat_chg_fx <=                          state_cardStat_chg_f;
   
//-------------------------------------------------------------------------------------------------
assign err_unsuported_card  =                                                   state_unsuported_f; 
assign err_crc              =                                                      state_crc_err_f; 
assign err_flash            =                                                    state_flash_err_f; 
assign err_timeout          =                                                       state_to_err_f;

//=================================================================================================
// timeout counter - in SD card clock domain
//-------------------------------------------------------------------------------------------------
// initial value of timeout counter                                                                                                                                                
always@(posedge CLK or posedge RST)
 if(RST)                                            clk_cnt_ini <=                  TIME_POWER_INI;
 else if(state_idle_f                           )   clk_cnt_ini <=                  TIME_POWER_INI;
 else if(state_cmd11in_f                        )   clk_cnt_ini <=                    TIME_VOL_SW0; // 5ms at 400kHz
 else if(state_volt_sw1_f                       )   clk_cnt_ini <=                    TIME_VOL_SW2; // 1ms at 400kHz                                                                                
 else if(state_clk_sw0_f                        )   clk_cnt_ini <=                         28'd100; // for waiting for a new clock to start to operate                                                 
 else if(state_cmd18in_f | state_blk_din_ch_f | state_sw_cmd6in_f | state_ch_cmd6in_f)  // number of clocks for 250ms - time in which data should be received     
                                                    clk_cnt_ini <= (iclk_en_400K)?      28'd100000: 
                                                                   (iclk_en_25M )?     28'd6250000:  
                                                                   (iclk_en_50M )?    28'd12500000: 
                                                                   (iclk_en_100M)?    28'd25000000:  
                                                                 /*(iclk_en_200M)?*/  28'd50000000; 
 else if(state_blk_dout_f | state_cmd12in_f     )// number of clocks for 500ms - time in which busy signal on DAT0 should go low     
                                                    clk_cnt_ini <= (iclk_en_400K)?      28'd200000: 
                                                                   (iclk_en_25M )?    28'd12500000:  
                                                                   (iclk_en_50M )?    28'd25000000: 
                                                                   (iclk_en_100M)?    28'd50000000:  
                                                                 /*(iclk_en_200M)?*/ 28'd100000000;
 else                                               clk_cnt_ini <=                     clk_cnt_ini; 
//------------------------------------------------------------------------------------------------- 
// timeout counter load signal                                                                                                                                                
always@(posedge CLK or posedge RST)
 if(RST)                                            clk_cnt_load <=                           1'b1;
 else if(state_idle_f                          )    clk_cnt_load <=                           1'b1;
 else if(state_cmd11in_f                       )    clk_cnt_load <=                           1'b1;
 else if(state_volt_sw1_f                      )    clk_cnt_load <=                           1'b1;                                                                               
 else if(state_clk_sw0_f                       )    clk_cnt_load <=                           1'b1;                                                
 else if(state_cmd18in_f | state_blk_din_ch_f | state_sw_cmd6in_f | state_ch_cmd6in_f)        
                                                    clk_cnt_load <=                           1'b1; 
 else if(state_blk_dout_f | state_cmd12in_f    )    clk_cnt_load <=                           1'b1;
 else                                               clk_cnt_load <=                           1'b0;
//------------------------------------------------------------------------------------------------- 
// timeout counter enable signal                               
always@(posedge CLK or posedge RST)   
 if(RST)                                            clk_cnt_ena  <=                           1'b0; 
 else if(clk_cnt_end                           )    clk_cnt_ena  <=                           1'b0;
 else if(state_init0_f                         )    clk_cnt_ena  <=                           1'b1;
 else if(state_volt_sw0_f                      )    clk_cnt_ena  <=                           1'b1;
 else if(state_volt_sw2_f                      )    clk_cnt_ena  <=                           1'b1;                                                                            
 else if(state_clk_sw1_f                       )    clk_cnt_ena  <=                           1'b1;                                                
 else if(state_blk_din_f                       )    clk_cnt_ena  <=                           1'b1; 
 else if(state_sd_st_on_d0_f | state_cmd12bsy_f)    clk_cnt_ena  <=                           1'b1;
 else                                               clk_cnt_ena  <=                           1'b0;
//------------------------------------------------------------------------------------------------- 
   
always@(posedge CLK or posedge RST)
 if(RST)                                            clk_cnt      <=                          28'd0;
 else if(clk_cnt_load                          )    clk_cnt      <=                    clk_cnt_ini;
 else if(clk_cnt_end                           )    clk_cnt      <=                          28'd0;
 else if(clk_cnt_ena                           )    clk_cnt      <=                clk_cnt - 28'd1; 
 else                                               clk_cnt      <=                          28'd0;
                      
//-------------------------------------------------------------------------------------------------                                     
assign  clk_cnt_end       =                                                            clk_cnt[27];
assign  i_dat_tout_f      =                                                            clk_cnt_end;

//================================================================================================= 
// CMD PREPERE                                                                                       
//------------------------------------------------------------------------------------------------- 
assign                      o0_cmd_state   =  state_cmd0out_f   || state_cmd8out_f   || 
                                              state_cmd55out_f  || state_acmd41out_f || 
                                              state_cmd11out_f  ||  
                                              state_cmd2out_f   ||
                                              state_cmd3out_f   || state_cmd9out_f   ||
                                              state_cmd7out_f   ||
                                              state_cmd42out_f  ||
                                              state_cmd55out2_f || state_acmd6out_f  || 
                                              state_ch_cmd6out_f||                      
                                              state_sw_cmd6out_f||                       
                                            /*state_cmd17out_f||*/ state_cmd18out_f  ||
                                            /*state_cmd24out_f||*/ state_cmd25out_f  ||
                                              state_cmd32out_f  || state_cmd33out_f  || state_cmd38out_f  ||
                                              state_cmd12out_f
                                              ;
                                                                                                               
//-------------------------------------------------------------------------------------------------
// < byte / 512B block > addressing convencion for < SD / SDHC, SDXC > cards
always@(posedge CLK)                                                                  
      if (!i2_OCR_CCS  )    o0_cmd_addr      <=                                   i_cmd_addr[31:0]; //SD standard capacity
 else                       o0_cmd_addr      <=                                   i_cmd_addr[40:9]; //SDHC, SDXC 
   
//-------------------------------------------------------------------------------------------------
// < byte / 512B block > addressing convencion for < SD / SDHC, SDXC > cards
always@(posedge CLK)                                                                  
      if (!i2_OCR_CCS  )    o0_cmd_addr_last <=                               i_cmd_end_addr[31:0]; //SD standard capacity
 else                       o0_cmd_addr_last <=                               i_cmd_end_addr[40:9]; //SDHC, SDXC 
                           
//================================================================================================= 
// delay next command if:
//  1) response was received      less than 8 cycles in the past,
//  2) previous command was send  less than 8 cycles in the past,
always@(posedge CLK or posedge RST)                                                                  
 if(RST)                    o1_cmd_del_cnt <=                                                 4'hF; 
 else if(o2_cmd_last_f    ) o1_cmd_del_cnt <=                                                 4'd6; 
 else if(i2_cmd_fin       ) o1_cmd_del_cnt <=                                                 4'd5;   
 else if(o1_cmd_del_f     ) o1_cmd_del_cnt <=                                o1_cmd_del_cnt - 4'd1;
 else                       o1_cmd_del_cnt <=                                o1_cmd_del_cnt       ;
//-------------------------------------------------------------------------------------------------  
assign o1_cmd_del_f =                                                           !o1_cmd_del_cnt[3]; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)                                                                  
 if(RST)                    o1_cmd_req     <=                                                 1'b0; 
 else                       o1_cmd_req     <=          o0_cmd_state & !o1_cmd_pend & !o1_cmd_del_f; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)                                                                  
 if(RST)                    o1_cmd_pend    <=                                                 1'b0;
 else if (o4_cmd_sent  )    o1_cmd_pend    <=                                                 1'b0;
 else                       o1_cmd_pend    <=                            o1_cmd_pend || o1_cmd_ack; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
                                              //    CMD, stuff bits
      if(state_cmd0out_f   )o1_cmd <=            { 6'd0,      32'd0};    
                                              //    CMD,   RSV,   volt supply, CHPAT
 else if(state_cmd8out_f   )o1_cmd <=            { 6'd8, 20'd0, VOL_SUPP[3:0], 8'hAA};  
   
                                              //    CMD,   SD RCA, stuff bits   
 else if(state_cmd55out_f  )o1_cmd <=            {6'd55,    16'd0,      16'd0};  // initialization stage with no RCA so use 0
   
                                              //    CMD,  rsv,  High Cap Supp,  rsv,     power ctrl,  rsv,     switch 1.8V, V WINDOW 3.6 - 2.7 V
 else if(state_acmd41out_f )o1_cmd <=            {6'd41, 1'b0, OP_COND_HCS[0], 1'b0, OP_COND_XPC[0], 3'd0, OP_COND_S18R[0], 24'hFF0000};                                
                                                                                                                              // V WINDOW from OCR Register  
                                                                                                                              // OCR:
                                                                                                                              //   [0-3] reserved
                                                                                                                              //   [4] 1.6-1.7
                                                                                                                              //   [5] 1.7-1.8
                                                                                                                              //   ...         
                                                                                                                              //   [23] 3.5-3.6
                                                                                                                              //   [24-30] reserved
                                                                                                                              //   [31] Card power up status bit (busy_n) 
                                                                                                                              
                                              //    CMD,   RSV
 else if(state_cmd11out_f  )o1_cmd <=            {6'd11, 32'd0};                                                             
                                              //    CMD, stuff bits
 else if(state_cmd2out_f   )o1_cmd <=            { 6'd2,      32'd0};                            
 else if(state_cmd3out_f   )o1_cmd <=            { 6'd3,      32'd0};                                               
                                              //    CMD,      SD RCA, stuff bits
 else if(state_cmd7out_f   )o1_cmd <=            { 6'd7, sd_RCA[15:0],     16'd0};                            
 else if(state_cmd9out_f   )o1_cmd <=            { 6'd9, sd_RCA[15:0],     16'd0};                                         
                                              //    CMD,   RSV
 else if(state_cmd42out_f  )o1_cmd <=            {6'd42, 32'd0};                                           
                                              //    CMD,      SD RCA, stuff bits     
 else if(state_cmd55out2_f )o1_cmd <=            {6'd55, sd_RCA[15:0],     16'd0};                                             
                                              //    CMD,   RSV, bus width
 else if(state_acmd6out_f  )o1_cmd <=            { 6'd6, 30'd0,     2'b10}; // bus width: 2'b00 - 1 bit; 2'b10 - 4 bits       
                                              //    CMD,  MODE CHECK FUN, RSV,                   FG6,                  FG5,          
 else if(state_ch_cmd6out_f)o1_cmd <=            { 6'd6,            1'b0, 7'd0, FUN_NO_INFLUENC[3:0], FUN_NO_INFLUENC[3:0],
             // Power limit - if 400mA is supported than choose it as it is need for UHSI full performance               
             st512_fg4_req, 
             // driver strenght - no change
             FUN_NO_INFLUENC[3:0],  
             // command system - no change
             FUN_NO_INFLUENC[3:0],  
             // speed mode (access mode) - highest that is supported
             st512_fg1_req};
                                              //    CMD, MODE SWITCH FUN, RSV,                   FG6,                  FG5,           
 else if(state_sw_cmd6out_f)o1_cmd <=            { 6'd6,            1'b1, 7'd0, FUN_NO_INFLUENC[3:0], FUN_NO_INFLUENC[3:0],  
             // Power limit - if 400mA is supported than choose it as it is need for UHSI full performance               
             st512_fg4_req, 
             // driver strenght - no change
             FUN_NO_INFLUENC[3:0],  
             // command system - no change
             FUN_NO_INFLUENC[3:0],  
             // speed mode (access mode) - highest that is supported
             st512_fg1_req};
                                                                           
                                              //    CMD,          Address   
 else if(state_cmd18out_f  )o1_cmd <=            {6'd18, o0_cmd_addr[31:0]}; // multiple block read  LSB deleted so multiplication of 512B is transmited 
 else if(state_cmd25out_f  )o1_cmd <=            {6'd25, o0_cmd_addr[31:0]}; // multiple block write LSB deleted so multiplication of 512B is transmited 
 else if(state_cmd32out_f  )o1_cmd <=            {6'd32, o0_cmd_addr[31:0]}; // erase start 
 else if(state_cmd33out_f  )o1_cmd <=            {6'd33, o0_cmd_addr_last[31:0]}; // erase last 
 else if(state_cmd38out_f  )o1_cmd <=            {6'd38,      32'd0}; // erase 
                                              //    CMD, stuff bits
 else if(state_cmd12out_f  )o1_cmd <=            {6'd12,      32'd0}; // end operation  
 else                       o1_cmd <=                                                o1_cmd       ;              
 
//=================================================================================================
// command packet formater       
//=================================================================================================
sd_cmd_48b_formater cmd_out_formater
(          
.CLK      (CLK),
.RST      (RST),
              
.I_STB    (o1_cmd_req),
.I_CMD    (o1_cmd),
.I_ACK    (o1_cmd_ack),
             
.O_BIT    (o2_cmd_bit),
.O_BIT_EN (o2_cmd_en),
.O_BIT_LST(o2_cmd_last_f),
.O_BODY_F (o2_cmd_body_f),
.O_CRC_F  (o2_cmd_crc_f)
);                                                                                                  
//=================================================================================================  
always@(posedge CLK or posedge RST)                                                                  
 if(RST)                    o3_cmd_en      <=                                                 1'b0; 
 else                       o3_cmd_en      <=                                            o2_cmd_en;
                                                                                                    
//================================================================================================= 
always@(posedge CLK or posedge RST)                                                                  
 if(RST)                    o4_cmd_sent    <=                                                 1'b0;
 else if (!o0_cmd_state)    o4_cmd_sent    <=                                                 1'b0;
 else                       o4_cmd_sent    <=                               o3_cmd_en & !o2_cmd_en;
                                

//=================================================================================================    
// Input i0 
//=================================================================================================
assign i0_cmd_bit      =                                                              SD_CMD_I_PIN;  
            
//-------------------------------------------------------------------------------------------------
assign i0_state_cmd136 =                      state_cmd2in_f    || state_cmd9in_f;
assign i0_state_cmd48  =                      state_cmd8in_f    || 
                                              state_cmd55in_f   || state_acmd41in_f  ||
                                              state_cmd11in_f   ||                 
                                              state_cmd3in_f    ||                 
                                              state_cmd7in_f    ||                 
                                              state_cmd42in_f   ||                 
                                              state_cmd55in2_f  || state_acmd6in_f   ||     
                                              state_ch_cmd6in_f ||
                                              state_sw_cmd6in_f ||
                                            /*state_cmd17in_f ||*/ state_cmd18in_f   || 
                                            /*state_cmd24in_f ||*/ state_cmd25in_f   || 
                                              state_cmd32in_f   || state_cmd33in_f   || state_cmd38in_f   ||                 
                                              state_cmd12in_f  ;
                                                                   
assign i0_state_cmd    =                                         i0_state_cmd48 || i0_state_cmd136;  
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)                                                                  
 if(RST)                    sd_clk_oe      <=                                                 1'b0; 
 else                       sd_clk_oe      <=                !state_volt_sw0_f & !state_volt_sw1_f;            
//-------------------------------------------------------------------------------------------------
assign sd_cmd_oe =                                                                       o2_cmd_en;            
//-------------------------------------------------------------------------------------------------
sd_cmd_136b_parser cmd_in
(          
.CLK          (CLK),
.RST          (RST),
              
.I_BIT        (i0_cmd_bit),   
.I_EN         (i0_state_cmd),   
.I_48         (i0_state_cmd48),
.I_136        (i0_state_cmd136),
                            
.O_CMD_EN     (i1_cmd_en), 
.O_CMD_EN_TIC (i1_cmd_en_tic),
.O_CMD        (i1_cmd_in),   
.O_CRC        (i1_crc),
.O_CRC_VALID  (i1_crc_valid),
.O_TIMEOUT    (i1_timeout_f)
);                   

//------------------------------------------------------------------------------------------------- 
// parse received command                                                                 

//R1                                                                                                   
assign i1_R1_cmdIdx      =                                                        i1_cmd_in[37:32];
assign i1_R1_cardStat    =                                                        i1_cmd_in[31: 0];

//R2                                                                                                   
assign i1_R2_CID_CSD     =                                     {i1_cmd_in[119:0],i1_crc[6:0],1'b0};
                    
// R3 (response to ACMD41)                                                                          
assign i1_R3_OCR          =                                                       i1_cmd_in[31: 0];  
           
// R6 (response to CMD3 - get public RCA number)                                                                        
assign i1_R6_RCA          =                                                       i1_cmd_in[31:16];
assign i1_R6_cardStat     =                                                       i1_cmd_in[15: 0]; 
            
// R7 (response to CMD8)
assign i1_R7_v_supp =                                                             i1_cmd_in[11: 8]; 
                                                                                                   
//=================================================================================================
// i1  
//=================================================================================================   
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_timeout_f <=                                 1'b0;  
 else                                         i2_timeout_f <=                         i1_timeout_f; 
                                                                                                    
//-------------------------------------------------------------------------------------------------   
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_crc_valid <=                                 1'b0;  
 else if(i1_cmd_en_tic                      ) i2_crc_valid <=                         i1_crc_valid; 
                                                                                                    
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_cmd_en    <=                                 1'b0;  
 else                                         i2_cmd_en    <=                            i1_cmd_en; 
                                                                                                   
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_cmd_fin   <=                                 1'b0;
 else                                         i2_cmd_fin   <=                        i1_cmd_en_tic; 
                                                                                                     
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_cmd_fin_ok<=                                 1'b0;
 else                                         i2_cmd_fin_ok<=        i1_crc_valid &  i1_cmd_en_tic; 
   
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_cmd_fin_er<=                                 1'b0;
 else                                         i2_cmd_fin_er<=       !i1_crc_valid &  i1_cmd_en_tic; 
  
//================================================================================================= 
sd_reg_bank sd_reg_bank
(                           
.CLK          (CLK),
.RST          (RST),

// read request
.I_REQ_RD     (REQ_I_REG_STB), 
.I_REQ_ADR    (REQ_I_MEM_ADDR),
.I_REQ_ACK    (rb_req_ack),

// registers input
.I_CMD_EN     (i1_cmd_en_tic),
.I_CMD        (i1_cmd_in),            
.I_CMD_STA    (state_cardStat_upd_fx),
.I_CMD_OCR    (state_acmd41in_f),
.I_CMD_CID    (state_cmd2in_f),
.I_CMD_CSD    (state_cmd9in_f),   
                       
.I_DAT_EN     (id1s_data_in_ena),
.I_DAT        (id1s_data_in[63:0]),
.I_DAT_PTR    (id1s_data_in_ptr),
                       
.I_HOST_STATE_EN(dbg_state_changed),
.I_HOST_STATE (dbg_state),
                               
// register bank data output - already formated into ringbus packets                     
.O_STB        (rb_data_stb),  
.O_SOF        (rb_data_sof),
.O_DAT        (rb_data_in),
.O_ACK        (rb_data_in_ack)
);                         
//=================================================================================================                     
                                 
// R1 (response to various command) and part of R6 (response to CMD3)                                                                         
always@(posedge CLK)
                                                                      //                 bits 23,22                    bit 19                bits 12-9
     if(i1_cmd_en_tic &state_cardStat_upd3_fx)i2_cardStat       <=      {8'd0, i1_R6_cardStat[15:14], 2'd0, i1_R6_cardStat[13], 6'd0, i1_R6_cardStat[12:0]};    
else if(i1_cmd_en_tic &state_cardStat_upd_fx )i2_cardStat       <=                  i1_R1_cardStat; 
else                                          i2_cardStat       <=                     i2_cardStat; 
                                                                        
always@(posedge CLK or posedge RST)                                     
 if(RST)                                      i2_cardStat_valid <=                            1'b0;    
else if(i1_cmd_en_tic &state_cardStat_upd3_fx)i2_cardStat_valid <=                            1'b1;    
else if(i1_cmd_en_tic &state_cardStat_upd_fx )i2_cardStat_valid <=                            1'b1;    
else if(               state_cardStat_chg_fx )i2_cardStat_valid <=                            1'b0; 
else                                          i2_cardStat_valid <=               i2_cardStat_valid; 
                                                                                                                                           
always@(posedge CLK)
     if(i1_cmd_en_tic &state_cardStat_upd3_fx)i2_cardStat_e_f   <= |{i1_R6_cardStat[15:14], i1_R6_cardStat[13], i1_R6_cardStat[3]};    
else if(i1_cmd_en_tic &state_cardStat_upd_fx )i2_cardStat_e_f   <= |{i1_R1_cardStat[31:26], i1_R1_cardStat[24:15], i1_R1_cardStat[3]}; 
else                                          i2_cardStat_e_f   <=                 i2_cardStat_e_f;  
//------------------------------------------------------------------------------------------------- 
// R2 (response to CMD2 and CMD10)                                                                         
always@(posedge CLK)
     if(i1_cmd_en_tic & state_cmd2in_f     )  i2_CID       <=                        i1_R2_CID_CSD; 
else                                          i2_CID       <=                               i2_CID; 
                                                                
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_CID_valid <=                                 1'b0;    
else if(i1_cmd_en_tic & state_cmd2in_f     )  i2_CID_valid <=                                 1'b1;    
else if(                state_cmd2out_f    )  i2_CID_valid <=                                 1'b0; 
else                                          i2_CID_valid <=                         i2_CID_valid; 
                                                                                                   
//------------------------------------------------------------------------------------------------- 
// R2 (response to CMD9)                                                                         
always@(posedge CLK)
     if(i1_cmd_en_tic & state_cmd9in_f     )  i2_CSD       <=                        i1_R2_CID_CSD; 
else                                          i2_CSD       <=                               i2_CSD; 
                                                                
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_CSD_valid <=                                 1'b0;    
else if(i1_cmd_en_tic & state_cmd9in_f     )  i2_CSD_valid <=                                 1'b1;    
else if(                state_cmd9out_f    )  i2_CSD_valid <=                                 1'b0; 
else                                          i2_CSD_valid <=                         i2_CSD_valid; 
                                                                                                  
//-------------------------------------------------------------------------------------------------
// R3 (response to ACMD41)                                                                         
always@(posedge CLK)
     if(i1_cmd_en_tic & state_acmd41in_f   )  i2_OCR       <=                            i1_R3_OCR; 
else                                          i2_OCR       <=                               i2_OCR; 
                                                                
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_OCR_valid <=                                 1'b0;    
else if(i1_cmd_en_tic & state_acmd41in_f   )  i2_OCR_valid <=                                 1'b1;    
else if(                state_acmd41out_f  )  i2_OCR_valid <=                                 1'b0; 
else                                          i2_OCR_valid <=                         i2_OCR_valid; 
                                                                                                  
//-------------------------------------------------------------------------------------------------
assign i2_OCR_busy        =                                                            !i2_OCR[31];
assign i2_OCR_CCS         =                                                             i2_OCR[30]; 
assign i2_OCR_UHS2        =                                                             i2_OCR[29];
assign i2_OCR_S18A        =                                                             i2_OCR[24];
assign i2_OCR_VDD_sup     =                                                           i2_OCR[23:0]; 
                                                                                                    
//-------------------------------------------------------------------------------------------------
// R6 (response to CMD3)                                                                         
always@(posedge CLK)
     if(i1_cmd_en_tic & state_cmd3in_f     )  i2_RCA       <=                            i1_R6_RCA; 
else                                          i2_RCA       <=                               i2_RCA; 
                                                                
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_RCA_valid <=                                 1'b0;    
else if(i1_cmd_en_tic & state_cmd3in_f     )  i2_RCA_valid <=           (i1_R6_RCA[15:0] != 16'd0); // if card return RCA == 0 than ask for a new RCA because value 0 is used for card deactivation    
else if(                state_cmd3out_f    )  i2_RCA_valid <=                                 1'b0; 
else                                          i2_RCA_valid <=                         i2_RCA_valid; 
                                                                                                   
//-------------------------------------------------------------------------------------------------
// R7 (response to CMD8)
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_v_match   <=                                 1'b0;
 else if(i1_cmd_en_tic & state_cmd8in_f     ) i2_v_match   <=        i1_R7_v_supp == VOL_SUPP[3:0]; 
 else                                         i2_v_match   <=                           i2_v_match; 
                                                                                                   
always@(posedge CLK or posedge RST)
 if(RST)                                      i2_v_ok_valid<=                                 1'b0;
 else if(i1_cmd_en_tic & state_cmd8in_f     ) i2_v_ok_valid<=                                 1'b1;
 else if(                state_cmd8out_f    ) i2_v_ok_valid<=                                 1'b0; 
 else                                         i2_v_ok_valid<=                        i2_v_ok_valid; 
                                                                                                                                                                                                  
//=================================================================================================
// signals for FSM and SD card type info
//================================================================================================= 
assign i_cmd_end    =                                                                   i2_cmd_fin;
assign i_cmd_end_ok =                                                                i2_cmd_fin_ok;
assign i_cmd_end_er =                                                                i2_cmd_fin_er;
assign i_cmd_tout_f =                                                                 i2_timeout_f;  
//-------------------------------------------------------------------------------------------------
assign i_crc_ok     =                                                                i2_cmd_fin_ok;

assign sd_v_ok      =                                                                   i2_v_match; 
assign sd_v_ok_valid=                                                                i2_v_ok_valid;

assign sd_OCR       =                                                                       i2_OCR;
assign sd_OCR_valid =                                                                 i2_OCR_valid; 
assign sd_OCR_busy  =                                                                  i2_OCR_busy; 
assign sd_OCR_R18A  =                                                                  i2_OCR_S18A; 
assign sd_OCR_HC    =                                                                   i2_OCR_CCS; 
assign sd_OCR_UHS2  =                                                                  i2_OCR_UHS2; 
                                                                                                   
assign sd_CID       =                                                              i2_CID[127:  0];
assign sd_CID_valid =                                                              i2_CID_valid   ;
assign sd_CID_MID   =                                                              sd_CID[127:120]; 
assign sd_CID_OID   =                                                              sd_CID[119:104];
assign sd_CID_PNM   =                                                              sd_CID[103: 64];
assign sd_CID_PRV   =                                                              sd_CID[ 63: 56];
assign sd_CID_PSN   =                                                              sd_CID[ 55: 24];
assign sd_CID_MDT   =                                                              sd_CID[ 19:  8];
assign sd_CID_CRC   =                                                              sd_CID[  7:  1];
                                                                                                  
assign sd_CSD       =                                                              i2_CSD[127:  0];
assign sd_CSD_valid =                                                              i2_CSD_valid   ;
assign sd_CSD_VER1  =                                                              sd_CSD[      0];// CSD version 1.0
assign sd_CSD_VER2  =                                                              sd_CSD[      1];// CSD version 2.0  
assign sd_CSD_TSPEED=                                                              sd_CSD[103: 96];// Transfer speed        
assign sd_CSD_CCC   =                                                              sd_CSD[ 95: 84];// card command classes - supported commands 
assign sd_CSD_CMD_CLS10=                                                       sd_CSD_CCC[     10];// Card support for CMD6 command   
assign sd_CSD_DSIZE_V1 =                                                           sd_CSD[ 73: 62];// device size for CSD version 1.0 
assign sd_CSD_DSIZE_V2 =                                                           sd_CSD[ 69: 48];// device size for CSD version 2.0
assign sd_CSD_DSR_IM=                                                              sd_CSD[     76];// DSR implemented

assign sd_RCA       =                                                              i2_RCA[ 15:  0];
assign sd_RCA_valid =                                                              i2_RCA_valid   ;
                                                                                                   
assign sd_cStat     =                                                         i2_cardStat[ 31:  0];
// at least one error's flag
assign sd_cStat_e_f =                                                              i2_cardStat_e_f;
// parse card stats flags
assign sd_cStat_eOOR=                                                            sd_cStat[     31];
assign sd_cStat_eAE =                                                            sd_cStat[     30];
assign sd_cStat_eBLE=                                                            sd_cStat[     29];
assign sd_cStat_eESE=                                                            sd_cStat[     28];
assign sd_cStat_eEP =                                                            sd_cStat[     27]; 
assign sd_cStat_eWPV=                                                            sd_cStat[     26];
assign sd_cStat_lck =                                                            sd_cStat[     25];
assign sd_cStat_eLUF=                                                            sd_cStat[     24];
assign sd_cStat_eCRC=                                                            sd_cStat[     23];
assign sd_cStat_eIC =                                                            sd_cStat[     22];
assign sd_cStat_eCEF=                                                            sd_cStat[     21];
assign sd_cStat_eCCE=                                                            sd_cStat[     20];
assign sd_cStat_eERR=                                                            sd_cStat[     19];                                                                                               
assign sd_cStat_eCSD=                                                            sd_cStat[     16];
assign sd_cStat_eWES=                                                            sd_cStat[     15];
assign sd_cStat_ECCD=                                                            sd_cStat[     14];
assign sd_cStat_ERst=                                                            sd_cStat[     13];
assign sd_cStat_Stat=                                                            sd_cStat[ 12:  9];
assign sd_cStat_RdyD=                                                            sd_cStat[      8];
assign sd_cStat_AppC=                                                            sd_cStat[      5];
assign sd_cStat_eAKE=                                                            sd_cStat[      3];
                                                                                                     
assign sd_cStat_sIDL=                                                        sd_cStat_Stat == 4'd0;
assign sd_cStat_sRDY=                                                        sd_cStat_Stat == 4'd1;
assign sd_cStat_sIDN=                                                        sd_cStat_Stat == 4'd2;
assign sd_cStat_sSBY=                                                        sd_cStat_Stat == 4'd3;
assign sd_cStat_sTRN=                                                        sd_cStat_Stat == 4'd4;
assign sd_cStat_sDAT=                                                        sd_cStat_Stat == 4'd5;
assign sd_cStat_sRCV=                                                        sd_cStat_Stat == 4'd6;
assign sd_cStat_sPRG=                                                        sd_cStat_Stat == 4'd7;
assign sd_cStat_sDIS=                                                        sd_cStat_Stat == 4'd8;
assign sd_cStat_sUNK=                                                 {1'b0, sd_cStat_Stat} > 4'd8;

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
 if(RST)                    sd_low_volt_f <=                                                  1'b0;
 else if(state_volt_sw0_f)  sd_low_volt_f <=                                                  1'b1; 
 else                       sd_low_volt_f <=                                         sd_low_volt_f;

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
 if(RST)                    sd_dat_4bit_f <=                                                  1'b0;
 else if(state_cmd0out_f )  sd_dat_4bit_f <=                                                  1'b0;// CMD0 reset bus width
 else if(state_dataw_sw_f)  sd_dat_4bit_f <=                                                  1'b1; 
 else                       sd_dat_4bit_f <=                                         sd_dat_4bit_f;

//=================================================================================================
// Output
//=================================================================================================
always@(posedge CLK or posedge RST)
 if(RST)                    initialized <=                                                       0;
 else                       initialized <=                        initialized || state_data_idle_f;
 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                    rd_led     <=                                                        0;
 else if(state_data_idle_f) rd_led     <=                                                     1'b0;
 else if(state_prep_rd_f  ) rd_led     <=                                                     1'b1;
 else                       rd_led     <=                                                   rd_led;
 
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
 if(RST)                    wr_led     <=                                                        0;
 else if(state_data_idle_f) wr_led     <=                                                     1'b0;
 else if(state_prep_wr_f  ) wr_led     <=                                                     1'b1;
 else                       wr_led     <=                                                   wr_led;
//=================================================================================================
// Tristate command output
//================================================================================================= 
assign SD_LV_F      =                                                                sd_low_volt_f; 
assign SD_HV_F      =                                                               !sd_low_volt_f; 
assign SD_DAT_4B_F  =                                                                sd_dat_4bit_f;

assign SD_CLK_OE    =                                                                    sd_clk_oe;
                                                                                                     
assign SD_CMD_O_PIN =                                                                   o2_cmd_bit;

assign SD_CMD_OE    =                                                                    sd_cmd_oe; 
assign SD_CMD_CMD_F =                                                                o2_cmd_body_f; 
assign SD_CMD_CRC_F =                                                                 o2_cmd_crc_f;
                                                                                                    
//=================================================================================================
// Data input path                                                                                                                                                        
//=================================================================================================  


//=================================================================================================
assign id0_dat_bits   =                                                              SD_DAT_I_PINS;
assign id0_state_data =  state_ch_cmd6in_f | state_sw_cmd6in_f | state_cmd18in_f | state_blk_din_f; 
assign id0_rd_addr    =                                                          ix_mem_start_addr;
assign id1_rd_rst     =                                                         state_blk_din_ch_f;
assign id0_rd_internal=                                         ix_ch_cmd6_data || ix_sw_cmd6_data;
assign id0_rd_int_mode=                                                            ix_sw_cmd6_data;

//------------------------------------------------------------------------------------------------- 
sd_data_rec
#(                                                                                   
.AVAIL_DATA_BITS(AVAIL_DATA_BITS)    // 1 - only one data lane available; 4 - four data lanes
) 
data_reciever
(                           
.CLK          (CLK),
.RST          (RST),
                
// SD data input
.I_BITS       (id0_dat_bits),  

// address input
.I_ADDR       (id0_rd_addr),
.I_ADDR_EN    (state_prep_rd_f),
                                
.I_RD_EN      (id0_state_data),
.I_RD_INT     (id0_rd_internal), // read internal data - response to the switch function command (CMD6) 
.I_RD_INT_MODE(id0_rd_int_mode), // mode for internal data read: 0-capabilities, 1-switched function
                           
.I_RD_END     (id1_rd_end),
.I_RD_ACK     (id1_crc_ok),
.I_RD_ERR     (id1_crc_err),
.I_RD_RST     (id1_rd_rst),

.O_RD_FF_AF   (),

//.O_TIMEOUT    (id1_timeout_f),
       
// data output - already formated into ringbus packets                     
.O_STB        (id1_data_stb),  
.O_SOF        (id1_data_sof),
.O_DAT        (id1_data_in),
.O_ACK        (id1_data_in_ack),

.O_INT_ENA    (id1s_data_in_ena),
.O_INT_PTR    (id1s_data_in_ptr),
.O_INT_DAT    (id1s_data_in),
.O_INT_MODE   (id1s_data_mode)
);   

//-------------------------------------------------------------------------------------------------  
assign      ix_rd_blk_end_f =                                                           id1_rd_end;
assign      ix_rd_blk_err_f =                                                          id1_crc_err;
assign      ix_rd_blk_ok_f  =                                                           id1_crc_ok;                                                            
                                                      
//-------------------------------------------------------------------------------------------------
// 512b functions status registers (4.3.10.4 Switch Function Status)
// fg1 - Access Mode: SD bus interface speed modes   
//       function 0 - SDR12             
//       function 1 - High-Speed / SDR25
//       function 2 - SDR50       
//       function 3 - SDR104
//       function 4 - DDR50
// fg2 - Command System: A specific function can be extended and controlled by a set of shared 
//       commands        
//       function 0 - Default             
//       function 1 - eC
//       function 2 - OTP      
//       function 3 - ASSD  
//       function B-E - eSD
// fg3 - Driver Strength: Selection of suitable output driver strength in UHS-I modes depends on 
//       host enviroment     
//       function 0 - Default / Type B            
//       function 1 - Type A
//       function 2 - Type C      
//       function 3 - Type D   
// fg4 - Current Limit: Selection to limit the maximum current of the card in UHS-I modes depends 
//       on host power supply capability and heat release capability 
//       function 0 - Default / 200 mA           
//       function 1 - 400 mA
//       function 2 - 600 mA      
//       function 3 - 800 mA     
//-------------------------------------------------------------------------------------------------                  
                     
always @(posedge CLK or posedge RST)
if(RST) 
  begin                                                                                             
    st512_valid_trg         <=                                                                1'd0; 
    st512_sw_valid          <=                                                                1'd0;
    st512_capp_valid        <=                                                                1'd0;
    /*
    st512_max_curr_cons     <=                                                               16'd0;  
    
    st512_fg6_supp          <=                                                               16'h0;
    st512_fg5_supp          <=                                                               16'h0;
    st512_fg4_supp          <=                                                               16'h0;
    st512_fg3_supp          <=                                                               16'h0;
    st512_fg2_supp          <=                                                               16'h0;
    st512_fg1_supp          <=                                                               16'h0;   
    
    st512_fg6_can_sw        <=                                                                4'h0;
    st512_fg5_can_sw        <=                                                                4'h0;
    st512_fg4_can_sw        <=                                                                4'h0;
    st512_fg3_can_sw        <=                                                                4'h0;
    st512_fg2_can_sw        <=                                                                4'h0;
    st512_fg1_can_sw        <=                                                                4'h0; 
    
    st512_fg6_sw            <=                                                                4'h0;
    st512_fg5_sw            <=                                                                4'h0;
    st512_fg4_sw            <=                                                                4'h0;
    st512_fg3_sw            <=                                                                4'h0;
    st512_fg2_sw            <=                                                                4'h0; 
    st512_fg1_sw            <=                                                                4'h0;
                                                                                                     
    st512_version           <=                                                                8'h0; 
    
    st512_fg6_bsy           <=                                                               16'h0;
    st512_fg5_bsy           <=                                                               16'h0;
    st512_fg4_bsy           <=                                                               16'h0;
    st512_fg3_bsy           <=                                                               16'h0;
    st512_fg2_bsy           <=                                                               16'h0; 
    st512_fg1_bsy           <=                                                               16'h0;*/
  end
else if(id1s_data_in_ena) 
  begin                                                                                           
    st512_valid_trg         <= (id1s_data_in_ptr == 3'd0                   )?                 1'd1:                1'b0;                  
    st512_capp_valid        <= (id1s_data_in_ptr == 3'd0 &&!id1s_data_mode )?                 1'd1:    st512_capp_valid;
    st512_sw_valid          <= (id1s_data_in_ptr == 3'd0 && id1s_data_mode )?                 1'd1:      st512_sw_valid; 
       
    st512_max_curr_cons     <= (id1s_data_in_ptr == 3'd7                   )? id1s_data_in[63:48] : st512_max_curr_cons; 
    
    st512_fg6_supp          <= (id1s_data_in_ptr == 3'd7                   )? id1s_data_in[47:32] :      st512_fg6_supp;
    st512_fg5_supp          <= (id1s_data_in_ptr == 3'd7                   )? id1s_data_in[31:16] :      st512_fg5_supp;
    st512_fg4_supp          <= (id1s_data_in_ptr == 3'd7                   )? id1s_data_in[15: 0] :      st512_fg4_supp;
    st512_fg3_supp          <= (id1s_data_in_ptr == 3'd6                   )? id1s_data_in[63:48] :      st512_fg3_supp;
    st512_fg2_supp          <= (id1s_data_in_ptr == 3'd6                   )? id1s_data_in[47:32] :      st512_fg2_supp;
    st512_fg1_supp          <= (id1s_data_in_ptr == 3'd6                   )? id1s_data_in[31:16] :      st512_fg1_supp;  
                                                                                                                      
    st512_fg6_can_sw        <= (id1s_data_in_ptr == 3'd6 && !id1s_data_mode)? id1s_data_in[15:12] :    st512_fg6_can_sw;
    st512_fg5_can_sw        <= (id1s_data_in_ptr == 3'd6 && !id1s_data_mode)? id1s_data_in[11: 8] :    st512_fg5_can_sw;
    st512_fg4_can_sw        <= (id1s_data_in_ptr == 3'd6 && !id1s_data_mode)? id1s_data_in[ 7: 4] :    st512_fg4_can_sw;
    st512_fg3_can_sw        <= (id1s_data_in_ptr == 3'd6 && !id1s_data_mode)? id1s_data_in[ 3: 0] :    st512_fg3_can_sw;
    st512_fg2_can_sw        <= (id1s_data_in_ptr == 3'd5 && !id1s_data_mode)? id1s_data_in[63:60] :    st512_fg2_can_sw;
    st512_fg1_can_sw        <= (id1s_data_in_ptr == 3'd5 && !id1s_data_mode)? id1s_data_in[59:56] :    st512_fg1_can_sw;   
                                                                                                
    st512_fg6_sw            <= (id1s_data_in_ptr == 3'd6 &&  id1s_data_mode)? id1s_data_in[15:12] :        st512_fg6_sw;  
    st512_fg5_sw            <= (id1s_data_in_ptr == 3'd6 &&  id1s_data_mode)? id1s_data_in[11: 8] :        st512_fg5_sw;  
    st512_fg4_sw            <= (id1s_data_in_ptr == 3'd6 &&  id1s_data_mode)? id1s_data_in[ 7: 4] :        st512_fg4_sw;               
    st512_fg3_sw            <= (id1s_data_in_ptr == 3'd6 &&  id1s_data_mode)? id1s_data_in[ 3: 0] :        st512_fg3_sw;  
    st512_fg2_sw            <= (id1s_data_in_ptr == 3'd5 &&  id1s_data_mode)? id1s_data_in[63:60] :        st512_fg2_sw;  
    st512_fg1_sw            <= (id1s_data_in_ptr == 3'd5 &&  id1s_data_mode)? id1s_data_in[59:56] :        st512_fg1_sw;  
    
    st512_version           <= (id1s_data_in_ptr == 3'd5                   )? id1s_data_in[55:48] :       st512_version;
    
    st512_fg6_bsy           <= (id1s_data_in_ptr == 3'd5                   )? id1s_data_in[47:32] :       st512_fg6_bsy;  
    st512_fg5_bsy           <= (id1s_data_in_ptr == 3'd5                   )? id1s_data_in[31:16] :       st512_fg5_bsy;  
    st512_fg4_bsy           <= (id1s_data_in_ptr == 3'd5                   )? id1s_data_in[15: 0] :       st512_fg4_bsy;               
    st512_fg3_bsy           <= (id1s_data_in_ptr == 3'd4                   )? id1s_data_in[63:48] :       st512_fg3_bsy;  
    st512_fg2_bsy           <= (id1s_data_in_ptr == 3'd4                   )? id1s_data_in[47:32] :       st512_fg2_bsy;  
    st512_fg1_bsy           <= (id1s_data_in_ptr == 3'd4                   )? id1s_data_in[31:16] :       st512_fg1_bsy; 
  end  
else 
  begin                                                                                                                 
    st512_valid_trg         <=                                                                                     1'd0;     
    st512_capp_valid        <=                                                                         st512_capp_valid;
    st512_sw_valid          <=                                                                           st512_sw_valid;
    
    st512_max_curr_cons     <=                                                                      st512_max_curr_cons; 
    
    st512_fg6_supp          <=                                                                           st512_fg6_supp;
    st512_fg5_supp          <=                                                                           st512_fg5_supp;
    st512_fg4_supp          <=                                                                           st512_fg4_supp;
    st512_fg3_supp          <=                                                                           st512_fg3_supp;
    st512_fg2_supp          <=                                                                           st512_fg2_supp;
    st512_fg1_supp          <=                                                                           st512_fg1_supp; 
                                                                                                                      
    st512_fg6_can_sw        <=                                                                         st512_fg6_can_sw;
    st512_fg5_can_sw        <=                                                                         st512_fg5_can_sw;
    st512_fg4_can_sw        <=                                                                         st512_fg4_can_sw;
    st512_fg3_can_sw        <=                                                                         st512_fg3_can_sw;
    st512_fg2_can_sw        <=                                                                         st512_fg2_can_sw;
    st512_fg1_can_sw        <=                                                                         st512_fg1_can_sw;   
                                                                                                   
    st512_fg6_sw            <=                                                                             st512_fg6_sw;  
    st512_fg5_sw            <=                                                                             st512_fg5_sw;  
    st512_fg4_sw            <=                                                                             st512_fg4_sw;               
    st512_fg3_sw            <=                                                                             st512_fg3_sw;  
    st512_fg2_sw            <=                                                                             st512_fg2_sw;  
    st512_fg1_sw            <=                                                                             st512_fg1_sw;  
                                                                                                   
    st512_version           <=                                                                            st512_version;
                                                                                                   
    st512_fg6_bsy           <=                                                                            st512_fg6_bsy;  
    st512_fg5_bsy           <=                                                                            st512_fg5_bsy;  
    st512_fg4_bsy           <=                                                                            st512_fg4_bsy;               
    st512_fg3_bsy           <=                                                                            st512_fg3_bsy;  
    st512_fg2_bsy           <=                                                                            st512_fg2_bsy;  
    st512_fg1_bsy           <=                                                                            st512_fg1_bsy; 
  end
                                                                                                    
//-------------------------------------------------------------------------------------------------      
assign sd_supp_sdr25 =                                                           st512_fg1_supp[1];
assign sd_supp_sdr50 =                                                           st512_fg1_supp[2];  
assign sd_supp_sdr104=                                                           st512_fg1_supp[3];
assign sd_supp_ddr50 =                                                           st512_fg1_supp[4];
//-------------------------------------------------------------------------------------------------      
assign sd_supp_400mA =                                                           st512_fg4_supp[1];
assign sd_supp_600mA =                                                           st512_fg4_supp[2];  
assign sd_supp_800mA =                                                           st512_fg4_supp[3];
//-------------------------------------------------------------------------------------------------      
assign sd_fun_sdr12  =                                                   st512_fg1_sw[3:0] == 4'd0;     
assign sd_fun_sdr25  =                                                   st512_fg1_sw[3:0] == 4'd1;
assign sd_fun_sdr50  =                                                   st512_fg1_sw[3:0] == 4'd2;  
assign sd_fun_sdr104 =                                                   st512_fg1_sw[3:0] == 4'd3;
assign sd_fun_ddr50  =                                                   st512_fg1_sw[3:0] == 4'd4;
                                                                                                   
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if(!st512_capp_valid            ) st512_pow_fun_bsy   <=                                 1'b0;
else if(sd_supp_400mA                ) st512_pow_fun_bsy   <=                     st512_fg4_bsy[1];
else                                   st512_pow_fun_bsy   <=                                 1'b0; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)
     if(!st512_capp_valid            ) st512_fun_speed_bsy <=                                 1'b0;   
else if(sd_supp_sdr104               ) st512_fun_speed_bsy <=                     st512_fg4_bsy[3];  
else if(sd_supp_sdr50                ) st512_fun_speed_bsy <=                     st512_fg4_bsy[2];  
else if(sd_supp_sdr25                ) st512_fun_speed_bsy <=                     st512_fg4_bsy[1];  
else                                   st512_fun_speed_bsy <=                                 1'b0; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK)                   st512_fun_bsy <=  (st512_version[7:0] == 8'd1)? 
                                                          st512_pow_fun_bsy || st512_fun_speed_bsy:
                                                          1'b0; // if busy flags are not defined try switching and after switching command check if it was effective     
                                                            
                                                                                                      
// Power limit - if 400mA is supported than choose it as it is need for UHSI full performance 
always@(posedge CLK)                  st512_fg4_req <= (!st512_capp_valid)?   FUN_NO_INFLUENC[3:0]:
                                                       (sd_supp_400mA    )?  POWER_LIMIT_UHSI[3:0]: 
                                                                              FUN_NO_INFLUENC[3:0];                     
                                                                               
// speed mode (access mode) - highest that is supported
always@(posedge CLK)                  st512_fg1_req <= (!st512_capp_valid)?   FUN_NO_INFLUENC[3:0]:
                                                       (sd_supp_sdr104   )?   SPEED_MODE_S104[3:0]: 
                                                       (sd_supp_sdr50    )?   SPEED_MODE_S50 [3:0]: 
                                                       (sd_supp_sdr25    )?   SPEED_MODE_S25 [3:0]: 
                                                                              FUN_NO_INFLUENC[3:0];
             
             
always@(posedge CLK) st512_fun_match<= ((st512_fg4_req == 4'hF) | (st512_fg4_req == st512_fg4_sw))& 
                                       ((st512_fg1_req == 4'hF) | (st512_fg1_req == st512_fg1_sw));
//=================================================================================================
// DATA-TO-BE-WRITE BUFFER MODULE
//================================================================================================= 
assign dbuf_i_stb       =                                                          state_prep_wr_f; 
assign dbuf_i_adr       =                                                        ix_mem_start_addr;
assign dbuf_i_mul_m2    =                                                        ix_blk_left_m2   ; 
                                                                                                    
assign dbuf_sd_pkt_ack  =                                 state_blk_dout_ch_f && d0_st_sdo_crc_ok ;
assign dbuf_sd_pkt_ret  =                                 state_blk_dout_ch_f && d0_st_sdo_crc_err; 
//------------------------------------------------------------------------------------------------- 
sd_data_out_buff data_out_buff 
(
.CLK                (CLK),
.RST                (RST),

// address input
.SYS_I_REQ_STB      (dbuf_i_stb),
.SYS_I_REQ_MEM_ADDR (dbuf_i_adr),
.SYS_I_REQ_MUL_M2   (dbuf_i_mul_m2),
.SYS_I_REQ_ACK      (dbuf_i_ack),     

// output
.SD_O_PKT_RDY       (dbuf_sd_pkt_rdy),
.SD_O_DAT           (dbuf_sd_dat),
.SD_O_ACK           (dbuf_sd_ack),
.SD_O_FIRST         (dbuf_sd_first),
.SD_O_LAST          (dbuf_sd_last),
.SD_O_512B_DONE     (dbuf_sd_npkt_done),

.SD_I_PKT_ACK       (dbuf_sd_pkt_ack),
.SD_I_PKT_RET       (dbuf_sd_pkt_ret),
        
// ringbus interface
.I_EN               (SYS_I_STB),
.I_SOF              (SYS_I_SOF),
.I_DAT              (SYS_I_DAT),
.I_AF9              (SYS_I_AF[1]),

.O_STB              (dbuf_req_stb),
.O_SOF              (dbuf_req_sof),
.O_DAT              (dbuf_req_dat),
.O_ACK              (dbuf_req_ack)
);                                                                                              
//------------------------------------------------------------------------------------------------- 
assign SYS_I_AF[0] =                                                                          1'b0;
//=================================================================================================
// DATA OUT MODULE
//=================================================================================================
assign dout_pkt_trg  =                                                           state_prep_dout_f;
//------------------------------------------------------------------------------------------------- 
sd_data_form 
#(                                                                                   
.AVAIL_DATA_BITS(AVAIL_DATA_BITS)    // 1 - only one data lane available; 4 - four data lanes
) 
data_out 
(
.SD_CLK           (CLK),
.RST              (RST),
   
// data send request   
.SD_I_TRG         (dout_pkt_trg),  
.SD_I_DONE        (dout_pkt_done),

// buffered data input
.SD_I_PKT_RDY     (dbuf_sd_pkt_rdy),
.SD_I_DAT         (dbuf_sd_dat),
.SD_I_ACK         (dbuf_sd_ack),
.SD_I_FIRST       (dbuf_sd_first),
.SD_I_LAST        (dbuf_sd_last),

// output
.SD_O_DAT         (dout_dat),
.SD_OE            (dout_oe)
);                                                                                               
//------------------------------------------------------------------------------------------------- 
assign ix_wr_blk_end_f =                                                             dout_pkt_done;
//=================================================================================================
// DATA LINE STATE CHECK MODULE
//================================================================================================= 
assign d0_check_trg0  =                                        state_blk_dout_f && ix_wr_blk_end_f; 
assign d0_check_ack0  =                                                        state_blk_dout_ch_f;
assign d0_check_trg1  =            (state_cmd38in_f    ||  state_cmd12in_f) & i_crc_ok;
assign d0_check_ack1  =            (state_erase_wait_f || state_cmd12bsy_f) &    d0_st_sdo_bsy_end;
assign d0_check_ack   =                                             d0_check_ack0 || d0_check_ack1;
assign d0_st_dat      =                                                           SD_DAT_I_PINS[0];

//------------------------------------------------------------------------------------------------- 
sd_data_state d0_line_state 
(
.CLK              (CLK),
.RST              (RST),

// input                          
.SD_I_CRC_BSY_TRG (d0_check_trg0),
.SD_I_BSY_TRG     (d0_check_trg1),
.SD_I_DAT0        (d0_st_dat),

// output                             
.SD_O_BSY_END     (d0_st_sdo_bsy_end),
.SD_O_CRC_OK      (d0_st_sdo_crc_ok),
.SD_O_CRC_ERR     (d0_st_sdo_crc_err),
.SD_O_FLASH_ERR   (d0_st_sdo_flash_err),
.SD_O_ACK         (d0_check_ack)
);                
                             
//================================================================================================= 
assign ix_wr_sts_got_f   =                                                     d0_st_sdo_bsy_end  ;
assign ix_wr_blk_err_f   =                                                     d0_st_sdo_crc_err  ;
assign ix_wr_blk_ok_f    =                                                     d0_st_sdo_crc_ok   ;
assign ix_wr_flash_err_f =                                                     d0_st_sdo_flash_err;
                                                                                                 
//=================================================================================================
// ringbus mux for
// - requests for data from memory that will be stored into SD, and 
// - data from SD to be stored in the memory
//================================================================================================= 
sd_ring_mux req_dat_mux (
.CLK      (CLK),
.RST      (RST),         

// Input for SD registers data
.I_G_STB  (rb_data_stb),
.I_G_SOF  (rb_data_sof),
.I_G_DATA (rb_data_in),
.I_G_ACK  (rb_data_in_ack),

// Input for SD read data
.I_D_STB  (id1_data_stb),
.I_D_SOF  (id1_data_sof),
.I_D_DATA (id1_data_in),
.I_D_ACK  (id1_data_in_ack),

// Input for requests
.I_R_STB  (dbuf_req_stb),
.I_R_SOF  (dbuf_req_sof),
.I_R_DATA (dbuf_req_dat),
.I_R_ACK  (dbuf_req_ack),

// Output to ringbus interface
.O_EN     (SYS_O_STB),
.O_SOF    (SYS_O_SOF),
.O_DATA   (SYS_O_DAT),
.O_AF     (SYS_O_AF)
); 

//=================================================================================================
// Data output to SD card
//=================================================================================================
assign SD_DAT_O_PINS=                                            dout_dat[(AVAIL_DATA_BITS-'d1):0];
assign SD_DAT_OE    =                                                                      dout_oe;
                                                                                                    
assign REQ_I_DONE   =                                           state_cmd12bsy_f & ix_wr_sts_got_f;
assign REQ_I_ERR    =                      state_unsuported_f | state_flash_err_f | state_to_err_f;
                
//=================================================================================================
// debug output 
//================================================================================================= 
// state change detect
always@(posedge CLK )             dbg_state              <=                                  h_str; 
//------------------------------------------------------------------------------------------------- 
// sd clock domain
always@(posedge CLK or posedge RST)
if(RST)                          dbg_state_changed      <=                                      0;
else                             dbg_state_changed      <=                    h_str != dbg_state ; 
//------------------------------------------------------------------------------------------------- 
assign dbg_st_reg =                        {i2_cardStat[31:2], i2_cardStat_e_f, i2_cardStat_valid};
assign dbg_ocr    =               {sd_OCR_valid, sd_OCR_busy, sd_OCR_R18A, sd_OCR_HC, sd_OCR_UHS2};
assign dbg_rca    =                                                                         sd_RCA;
//================================================================================================= 

endmodule

                  