//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module dev_sd_box
#(
parameter  [ 0:0] OP_COND_S18R         =  1'b0,      // try switch to 1.8V - request UHS1 modes 
parameter  [31:0] TIME_POWER_INI       =  32'd100000,// count in tic of SD clock. For 400KHz SD CLK period equals 2.5us, so 100000 clocks is 250ms  
parameter  [31:0] AVAIL_DATA_BITS      =  32'd4      // 1 - only one data lane available; 4 - four data lanes
)
(                                  
input  wire        I_CLK_25M,      
input  wire        I_CLK_50M,      
input  wire        I_CLK_100M,      
input  wire        I_CLK_200M,         
input  wire        SYS_RST, 

output wire        SD_CLK, 
output wire        SD_RST,            

// ringbus events interface                              
input  wire        REQ_I_RD_STB,                             
input  wire        REQ_I_WR_STB,                         
input  wire        REQ_I_REG_STB,    
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
// 3.3V signals
output wire        SD_CLK_HVPIN, 
inout  wire        SD_CMD_HVPIN,  
inout  wire [(AVAIL_DATA_BITS-'d1):0] SD_DAT_HVPINS,  

// 1.8V signals
output wire        SD_CLK_LVPIN, 
inout  wire        SD_CMD_LVPIN,  
inout  wire [(AVAIL_DATA_BITS-'d1):0] SD_DAT_LVPINS,

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
output wire        initialized,
output wire        rd_led,         
output wire        wr_led,          

output wire        err_unsuported_card,
output wire        err_crc,
output wire        err_flash,
output wire        err_timeout,
                                
output wire        dbg_state_changed,     
output wire [15:0] dbg_state,
output wire [31:0] dbg_st_reg, 
output wire [ 4:0] dbg_ocr,      
output wire [15:0] dbg_rca       
);                                 
//=================================================================================================
// local clock signals names needed for constraints. 
//  DONT_TOUCH attribute can not be assigned to the module ports so additional signals need to be 
//  created, marked for preservation (DONT_TOUCH attribute), and assigned to original ports names.
(* dont_touch = "true" *)wire        ix_clk_25M   =  I_CLK_25M ;
(* dont_touch = "true" *)wire        ix_clk_50M   =  I_CLK_50M ;
(* dont_touch = "true" *)wire        ix_clk_100M  =  I_CLK_100M; 
(* dont_touch = "true" *)wire        ix_clk_200M  =  I_CLK_200M;
                                                   
(* dont_touch = "true" *)wire        ox_SD_CLK;
assign      SD_CLK   = ox_SD_CLK  ;
//=================================================================================================

wire        clk_en_400K;
wire        clk_en_25M;
wire        clk_en_50M;
wire        clk_en_100M;
wire        clk_en_200M;

wire        mux_clk;
wire        mux_rst;
                       
wire        cmd_bit_i;
wire [(AVAIL_DATA_BITS-'d1):0]  dat_bits_i;
wire        cmd_bit_o;
wire [(AVAIL_DATA_BITS-'d1):0]  dat_bits_o;
//=================================================================================================
// CLOCK MULTIPLEXER  
//=================================================================================================
sd_clk_mux clk_mux 
(
  .SYS_RST      (SYS_RST),
  
  .CLK_25M      (ix_clk_25M),
  .CLK_50M      (ix_clk_50M),
  .CLK_100M     (ix_clk_100M),
  .CLK_200M     (ix_clk_200M),
  
  .I_EN_400K    (clk_en_400K),
  .I_EN_25M     (clk_en_25M ),
  .I_EN_50M     (clk_en_50M ),
  .I_EN_100M    (clk_en_100M),
  .I_EN_200M    (clk_en_200M),
  
  .SD_CLK       (mux_clk),
  .SD_RST       (mux_rst)
);                                                                                                 
//=================================================================================================   
assign ox_SD_CLK =                                                                         mux_clk;
assign SD_RST =                                                                            mux_rst;
//=================================================================================================    
// LV / HV / OE multiplexer 
//=================================================================================================
//clk
assign SD_CLK_HVPIN = (SD_HV_F & SD_CLK_OE)?                                        mux_clk : 1'bz;      
assign SD_CLK_LVPIN = (SD_LV_F & SD_CLK_OE)?                                        mux_clk : 1'bz; 
 
//cmd 
assign cmd_bit_i    = (SD_LV_F            )?                                          SD_CMD_LVPIN:
                    /*(SD_HV_F            )?*/                                        SD_CMD_HVPIN;  
assign SD_CMD_HVPIN = (SD_HV_F & SD_CMD_OE)?                                      cmd_bit_o : 1'bz;      
assign SD_CMD_LVPIN = (SD_LV_F & SD_CMD_OE)?                                      cmd_bit_o : 1'bz; 

//data
assign dat_bits_i   = (SD_LV_F            )?                                         SD_DAT_LVPINS:
                    /*(SD_HV_F            )?*/                                       SD_DAT_HVPINS;  
assign SD_DAT_HVPINS= (SD_HV_F & SD_DAT_OE)?                                     dat_bits_o :  'hz;      
assign SD_DAT_LVPINS= (SD_LV_F & SD_DAT_OE)?                                     dat_bits_o :  'hz;

//=================================================================================================    
// sd_box 
//=================================================================================================
dev_sd_box_pure 
#(
.TIME_POWER_INI (TIME_POWER_INI ), // restrict power up time for simulation  
.OP_COND_S18R   (OP_COND_S18R   ), // 0: do not try switch to 1.8V - do not request UHS1 modes  
.AVAIL_DATA_BITS(AVAIL_DATA_BITS)  // 1 - only one data lane available; 4 - four data lanes
)
sd_box_pure (          
.CLK          (mux_clk),          
.RST          (mux_rst),
              
// ringbus events interface                              
.REQ_I_RD_STB     (REQ_I_RD_STB),                                    
.REQ_I_WR_STB     (REQ_I_WR_STB),
.REQ_I_REG_STB    (REQ_I_REG_STB),
.REQ_I_MEM_ADDR   (REQ_I_MEM_ADDR), 
.REQ_I_SD_ADDR    (REQ_I_SD_ADDR),  
.REQ_I_512B_MUL_M1(REQ_I_512B_MUL_M1), // (number of 512B blocks) minus 1  
.REQ_I_ACK        (REQ_I_ACK),            

.REQ_I_DONE     (REQ_I_DONE), 
.REQ_I_ERR      (REQ_I_ERR),

// ringbus interface         
.SYS_I_STB    (SYS_I_STB),     
.SYS_I_SOF    (SYS_I_SOF), 
.SYS_I_DAT    (SYS_I_DAT),
.SYS_I_AF     (SYS_I_AF),   
                         
.SYS_O_STB    (SYS_O_STB),  
.SYS_O_SOF    (SYS_O_SOF), 
.SYS_O_DAT    (SYS_O_DAT),
.SYS_O_AF     (SYS_O_AF), 
                 
// CLOCK selection signals
.CLK_EN_400K  (clk_en_400K),
.CLK_EN_25M   (clk_en_25M ),
.CLK_EN_50M   (clk_en_50M ),
.CLK_EN_100M  (clk_en_100M),
.CLK_EN_200M  (clk_en_200M),

//SD card interface          
.SD_LV_F      (SD_LV_F),    
.SD_HV_F      (SD_HV_F),
                    
// signals               
.SD_CMD_I_PIN (cmd_bit_i),
.SD_CMD_O_PIN (cmd_bit_o),
.SD_DAT_I_PINS(dat_bits_i),
.SD_DAT_O_PINS(dat_bits_o),
                      
// common signals           
.SD_CLK_OE    (SD_CLK_OE),   
.SD_DAT_OE    (SD_DAT_OE),   
.SD_CMD_OE    (SD_CMD_OE),   
.SD_CMD_CMD_F (SD_CMD_CMD_F),
.SD_CMD_CRC_F (SD_CMD_CRC_F),
                          
.SD_CARD_PIN  (SD_CARD_PIN), 
                     
// error indicators and debug signals
.SD_DAT_4B_F  (SD_DAT_4B_F),

.initialized  (initialized),
.rd_led       (rd_led),
.wr_led       (wr_led),

.err_unsuported_card  (err_unsuported_card),  
.err_crc              (err_crc),
.err_flash            (err_flash),
.err_timeout          (err_timeout),

.dbg_state_changed    (dbg_state_changed),
.dbg_state            (dbg_state),
.dbg_st_reg           (dbg_st_reg),
.dbg_ocr              (dbg_ocr),      
.dbg_rca              (dbg_rca)
);                                                   
//================================================================================================= 

endmodule

                  