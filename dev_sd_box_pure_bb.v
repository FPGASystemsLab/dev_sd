//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
(* black_box *) module dev_sd_box_pure
(                                  
input  wire        CLK,              
input  wire        RST,                

// ringbus events interface                              
input  wire        REQ_I_RD_STB,                             
input  wire        REQ_I_WR_STB,  
input  wire [38:0] REQ_I_MEM_ADDR,  
input  wire [38:0] REQ_I_SD_ADDR,  
input  wire [15:0] REQ_I_512B_MUL_M1,  
output wire        REQ_I_ACK,       

output wire        REQ_I_DONE, 
output wire        REQ_I_ERR,

// ringbus interface         
input  wire        SYS_I_STB, 
input  wire        SYS_I_SOF, 
input  wire [71:0] SYS_I_DAT,
output wire [ 1:0] SYS_I_AF,
 
output wire        SYS_O_STB,
output wire        SYS_O_SOF, 
output wire [71:0] SYS_O_DAT,
input  wire [ 1:0] SYS_O_AF,
 
//SD card interface             
input  wire        SD_CMD_I_PIN,
input  wire [ 3:0] SD_DAT_I_PINS,  
output wire        SD_CMD_O_PIN,   
output wire [ 3:0] SD_DAT_O_PINS,  

// CLOCK selection signals
output wire        CLK_EN_400K,
output wire        CLK_EN_25M,
output wire        CLK_EN_50M,
output wire        CLK_EN_100M,
output wire        CLK_EN_200M,

// common signals        
output wire        SD_LV_F,
output wire        SD_HV_F,
output wire        SD_DAT_4B_F,         
output wire        SD_CLK_OE,
output wire        SD_DAT_OE,
output wire        SD_CMD_OE, 
output wire        SD_CMD_CMD_F,
output wire        SD_CMD_CRC_F, 

input  wire        SD_CARD_PIN, 

// error indicators and debug signals
output reg         initialized,

output wire        err_unsuported_card,
output wire        err_crc,
output wire        err_flash,
output wire        err_timeout,
                                
output reg         dbg_state_changed,     
output reg  [15:0] dbg_state,
output wire [31:0] dbg_st_reg
);  
//================================================================================================= 

endmodule

                  