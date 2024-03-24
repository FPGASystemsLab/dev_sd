//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>
//=============================================================================
// Module that reads response send from SD card to host on DAT[0] line.
// It should be enabled after data transfer to SD card. Recognized states:
// - recognize "CRC error" or "CRC ok" messages
// - recognize busy state and end of a busy state send from SD card
//
// Module expects to read bits:
// 0 - start crc response bit
// C - crc-response bit 2
// C - crc-response bit 1
// C - crc-response bit 0
// 1 - crc-response end
// 0 - start busy-response bit
// 0 x # - # of busy bits
// 1 - busy end
//
// crc ok    by reading    3'b010 crc-response. 
// crc error by reading    3'b101 crc-response.
//
// But when flash error occurs than no crc response is send at all.
// In that case first low signal value indicate busy-flag start not a 
// crc-response start. That will result in reading 3'b000 or 3'b001 or 3'b011
// or 3'b111 as a crc-response and will activate SYS_O_FLASH_ERR and 
// SYS_O_FLASH_ERR errors flags.
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================
module sd_data_state
(                                  
input  wire        CLK,                 
input  wire        RST,            

// input                              
input  wire        SD_I_CRC_BSY_TRG, 
input  wire        SD_I_BSY_TRG, 
input  wire        SD_I_DAT0,  

// output                       
output wire        SD_O_BSY_END,
output wire        SD_O_CRC_OK,
output wire        SD_O_CRC_ERR, 
output wire        SD_O_FLASH_ERR,
input  wire        SD_O_ACK
); 
//================================================================================================= 
reg    [ 7:0] state_sr; 
reg           state_bsy;
reg           state_bsyx; 
reg    [ 3:0] crc_wait_start_cnt;
wire          crc_wait_start;
                       
wire          crc_resp_start;
wire          crc_resp_end;
//wire          crc_resp_pnd;
reg    [ 2:0] crc_resp_cnt;
reg    [ 2:0] crc_resp;
reg           bsy_end;
reg           no_crc_err;
reg           crc_err;
reg           crc_ok;                                                                              
//------------------------------------------------------------------------------------------------- 
// crc response timing is known: 2 clock periods after the end bit of data packet, but for UHS-I 
// in SDR50 and SDR104 it can be up to 8 clock periods (Physical Layer Specyfication 3.00 section 
// 4.12.5.1). That is why additional wait for crc start bit is needed -> crc_wait_start signal. 
always@(posedge CLK or posedge RST)
if(RST)                                        state_sr        <=                      8'b00000000;  
else if(crc_resp_start & crc_wait_start      ) state_sr        <=                      8'b00000010;  
else if(SD_I_CRC_BSY_TRG                     ) state_sr        <=                      8'b00000001;  
else if(SD_I_BSY_TRG                         ) state_sr        <=                      8'b01000000;     
else                                           state_sr        <=            {state_sr[6:0], 1'b0};
//------------------------------------------------------------------------------------------------- 
assign crc_resp_start =                                                               state_sr [1]; 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        crc_wait_start_cnt <=                          4'hF;  
else if(state_sr [0]                         ) crc_wait_start_cnt <=                          4'd6; 
else if(!crc_wait_start_cnt[3]               ) crc_wait_start_cnt <=     crc_wait_start_cnt - 4'd1;     
else                                           crc_wait_start_cnt <=     crc_wait_start_cnt       ;  
//------------------------------------------------------------------------------------------------- 
assign crc_wait_start =                                         !crc_wait_start_cnt[3] & SD_I_DAT0;    
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        state_bsy       <=                             1'b0; 
else if(state_sr != 8'h00                    ) state_bsy       <=                             1'b1; 
else if(SD_I_DAT0 != 1'b0                    ) state_bsy       <=                             1'b0;
else                                           state_bsy       <=                        state_bsy;  
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        state_bsyx      <=                             1'b0; 
else                                           state_bsyx      <=                        state_bsy; 
 
//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        bsy_end       <=                               1'b0; 
else if( SD_O_ACK                            ) bsy_end       <=                               1'b0;
else if(state_bsyx & !state_bsy              ) bsy_end       <=                               1'b1;
else                                           bsy_end       <=                            bsy_end;

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        crc_resp <=                                    3'h3; 
else if( state_sr [2]                        ) crc_resp <= {crc_resp[2], crc_resp[1],   SD_I_DAT0};
else if( state_sr [3]                        ) crc_resp <= {crc_resp[2],   SD_I_DAT0, crc_resp[0]};
else if( state_sr [4]                        ) crc_resp <= {  SD_I_DAT0, crc_resp[1], crc_resp[0]};  
else                                           crc_resp <=                                crc_resp; 
//------------------------------------------------------------------------------------------------- 
assign crc_resp_end =                                                                 state_sr [5];
//-------------------------------------------------------------------------------------------------
// detect of unexpected crc-response pattern. Can occure when no crc-response was sent at all. That 
// can indicate SD flash write error
always@(posedge CLK or posedge RST)
if(RST)                                        no_crc_err    <=                               1'b0; 
else if( SD_O_ACK                            ) no_crc_err    <=                               1'b0;
else if(crc_resp_end                         ) no_crc_err    <= (crc_resp != 3'b101) && (crc_resp != 3'b010);
else                                           no_crc_err    <=                         no_crc_err;
//-------------------------------------------------------------------------------------------------
always@(posedge CLK or posedge RST)
if(RST)                                        crc_err       <=                               1'b0;
else if( SD_O_ACK                            ) crc_err       <=                               1'b0; 
else if(crc_resp_end                         ) crc_err       <=                 crc_resp == 3'b101;
else                                           crc_err       <=                            crc_err;

//------------------------------------------------------------------------------------------------- 
always@(posedge CLK or posedge RST)
if(RST)                                        crc_ok        <=                               1'b0; 
else if( SD_O_ACK                            ) crc_ok        <=                               1'b0; 
else if(crc_resp_end                         ) crc_ok        <=                 crc_resp == 3'b010;
else                                           crc_ok        <=                             crc_ok;

//=================================================================================================
// SD clock domain output
//=================================================================================================
assign SD_O_CRC_OK    =                                                                     crc_ok;
assign SD_O_CRC_ERR   =                                                                    crc_err;
assign SD_O_BSY_END   =                                                                    bsy_end;
assign SD_O_FLASH_ERR =                                                                 no_crc_err;

//================================================================================================= 
endmodule
