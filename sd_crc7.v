//=============================================================================
// \author
//    Main contributors
//      - Jakub Siast         <mailto:jakubsiast@gmail.com>                  
//=============================================================================
// Just for SD startup module - use CRC register for shifting out crc when
// SH signal is high and add one bit with value 1'b1 for command End bit. 
//=============================================================================
`default_nettype none
//-----------------------------------------------------------------------------
module sd_crc7(
  input  wire       CLK,    
  input  wire       RST,   
  
  input  wire       IN,  
  input  wire       SH, 
  input  wire       EN,  
  output reg  [6:0] CRC
); 
//=============================================================================
wire         xor6;
//-------------------------------------------------------------------------------------------------
assign xor6 = IN ^ CRC[6];  
//-------------------------------------------------------------------------------------------------
always @(posedge CLK or posedge RST) 
    if (RST) CRC = 0;  
    else if (EN || SH) 
        begin
            CRC[6] =        CRC[5];
            CRC[5] =        CRC[4];
            CRC[4] =        CRC[3];
            CRC[3] = SH?    CRC[2] : xor6 ^ CRC[2];
            CRC[2] =        CRC[1];
            CRC[1] =        CRC[0];
            CRC[0] = SH?      1'b1 : xor6         ; // End bit : input
        end
//-------------------------------------------------------------------------------------------------
endmodule

