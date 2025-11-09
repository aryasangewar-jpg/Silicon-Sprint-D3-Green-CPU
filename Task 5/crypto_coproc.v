// pipelind_core_crypto.v
`include "instruction_defs.v"
module pipelind_core_crypto (
  input clk,
  input rst
);
parameter IMEM_SIZE = 256;
reg [15:0] imem [0:IMEM_SIZE-1];
reg [15:0] dmem [0:255];

reg [15:0] pc;
reg [15:0] regs [0:7];

integer i;
initial begin
  for (i=0;i<IMEM_SIZE;i=i+1) imem[i]=16'h0000;
  for (i=0;i<256;i=i+1) dmem[i]=16'h0000;
  pc = 0;
  for (i=0;i<8;i=i+1) regs[i] = 16'h0000;
end

// Simple single-stage fetch/execute for demo integrating crypto
always @(posedge clk or posedge rst) begin
  if (rst) pc <= 0;
  else begin
    reg [15:0] instr;
    instr = imem[pc];
    pc <= pc + 1;
    reg [3:0] opcode = instr[15:12];
    reg [2:0] rd = instr[11:9];
    reg [2:0] rs1 = instr[8:6];
    reg [2:0] rs2 = instr[5:3];
    reg [2:0] funct = instr[2:0];
    reg [15:0] result;
    case(opcode)
      `OPC_CRYPTO: begin
        // ENC: funct==0, DEC: funct==1
        if (funct == 3'b000) begin
          // encrypt regs[rs1] using regs[rs2] as key (example)
          result = crypto_encrypt(regs[rs1], regs[rs2]);
          regs[rd] <= result;
        end else if (funct == 3'b001) begin
          result = crypto_decrypt(regs[rs1], regs[rs2]);
          regs[rd] <= result;
        end
      end
      default: ;
    endcase
  end
end

// Simple crypto core combinational functions (replace with provided core's logic)
// Example algorithm (toy): cipher = ((data ^ key) << 3) | ((data ^ key) >> 13)
function [15:0] crypto_encrypt;
  input [15:0] data;
  input [15:0] key;
  reg [15:0] t;
  begin
    t = data ^ key;
    crypto_encrypt = ((t << 3) | (t >> 13));
  end
endfunction

// Decrypt reverses the rotate and xor
function [15:0] crypto_decrypt;
  input [15:0] data;
  input [15:0] key;
  reg [15:0] t;
  begin
    t = ((data >> 3) | (data << 13));
    crypto_decrypt = t ^ key;
  end
endfunction

endmodule
