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
module sd_crc16(
  input  wire       CLK,    
  input  wire       RST,   
  
  input  wire       IN,  
  input  wire       SH, 
  input  wire       EN,  
  output reg [15:0] CRC
); 
//============================================================================= 
wire         xor15;
//-------------------------------------------------------------------------------------------------
assign xor15 = IN ^ CRC[15];  
//-------------------------------------------------------------------------------------------------
always @(posedge CLK or posedge RST) 
    if (RST) CRC = 16'd0;  
    else if (EN || SH) 
        begin                                        
            CRC[15]=        CRC[14];                 
            CRC[14]=        CRC[13];                 
            CRC[13]=        CRC[12];                 
            CRC[12]= SH?    CRC[11] : xor15 ^ CRC[11];           
            CRC[11]=        CRC[10];
            CRC[10]=        CRC[9];
            CRC[9] =        CRC[8];
            CRC[8] =        CRC[7];
            CRC[7] =        CRC[6];
            CRC[6] =        CRC[5];
            CRC[5] = SH?    CRC[4] : xor15 ^ CRC[4];
            CRC[4] =        CRC[3];
            CRC[3] =        CRC[2];
            CRC[2] =        CRC[1];
            CRC[1] =        CRC[0];
            CRC[0] = SH?      1'b1 : xor15         ; // End bit : input
        end
//-------------------------------------------------------------------------------------------------
endmodule
