// pipelined_core.v
`include "instruction_defs.v"
module pipelined_core (
  input clk,
  input rst
);
parameter IMEM_SIZE = 256;
reg [15:0] imem [0:IMEM_SIZE-1];
reg [15:0] dmem [0:255];

// registers and pipeline registers
reg [15:0] pc;

reg [15:0] IF_ID_instr, IF_ID_pc;
reg [15:0] ID_EX_reg1, ID_EX_reg2, ID_EX_imm;
reg [2:0]  ID_EX_rs1, ID_EX_rs2, ID_EX_rd;
reg [3:0]  ID_EX_opcode;
reg [2:0]  ID_EX_funct;

reg [15:0] EX_MEM_alu;
reg [2:0]  EX_MEM_rd;
reg [3:0]  EX_MEM_opcode;
reg [15:0] MEM_WB_val;
reg [2:0]  MEM_WB_rd;
reg [3:0]  MEM_WB_opcode;

reg [15:0] regs [0:7];

integer i;
initial begin
  for (i=0;i<IMEM_SIZE;i=i+1) imem[i] = 16'h0000;
  for (i=0;i<256;i=i+1) dmem[i] = 16'h0000;
  pc = 0;
  for (i=0;i<8;i=i+1) regs[i] = 16'h0000;
end

wire [15:0] instr_if = imem[pc];

// IF stage
always @(posedge clk or posedge rst) begin
  if (rst) begin
    pc <= 0;
    IF_ID_instr <= 16'h0000;
    IF_ID_pc <= 16'h0000;
  end else begin
    IF_ID_instr <= instr_if;
    IF_ID_pc <= pc;
    pc <= pc + 1;
  end
end

// ID stage - decode and read registers
wire [3:0] id_opcode = IF_ID_instr[15:12];
wire [2:0] id_rd     = IF_ID_instr[11:9];
wire [2:0] id_rs1    = IF_ID_instr[8:6];
wire [2:0] id_rs2    = IF_ID_instr[5:3];
wire [2:0] id_funct  = IF_ID_instr[2:0];
wire [5:0] id_imm6   = IF_ID_instr[5:0];
function [15:0] sext6; input [5:0] x; begin sext6 = {{10{x[5]}}, x}; end endfunction

always @(posedge clk) begin
  ID_EX_reg1 <= regs[id_rs1];
  ID_EX_reg2 <= regs[id_rs2];
  ID_EX_imm  <= sext6(id_imm6);
  ID_EX_rs1  <= id_rs1;
  ID_EX_rs2  <= id_rs2;
  ID_EX_rd   <= id_rd;
  ID_EX_opcode <= id_opcode;
  ID_EX_funct  <= id_funct;
end

// EX stage - ALU and FPU integration (simple)
wire [15:0] alu_result;
reg [15:0] fpu_result;
reg [15:0] ex_result;
reg zero_flag;

always @(*) begin
  // default
  ex_result = 16'h0000;
  zero_flag = 1'b0;
  case (ID_EX_opcode)
    `OPC_RTYPE: begin
      case(ID_EX_funct)
        `FUNCT_ADD: ex_result = ID_EX_reg1 + ID_EX_reg2;
        `FUNCT_SUB: ex_result = ID_EX_reg1 - ID_EX_reg2;
        `FUNCT_SLT: ex_result = ($signed(ID_EX_reg1) < $signed(ID_EX_reg2)) ? 16'h1 : 16'h0;
        `FUNCT_OR:  ex_result = ID_EX_reg1 | ID_EX_reg2;
        `FUNCT_AND: ex_result = ID_EX_reg1 & ID_EX_reg2;
        `FUNCT_SRL: ex_result = (ID_EX_reg1 >> ID_EX_reg2[2:0]);
        `FUNCT_SLL: ex_result = (ID_EX_reg1 << ID_EX_reg2[2:0]);
        `FUNCT_SRA: ex_result = ($signed(ID_EX_reg1) >>> ID_EX_reg2[2:0]);
        default: ex_result = 16'h0000;
      endcase
    end
    `OPC_ITYPE: begin
      case(ID_EX_funct)
        `IFUN_ADD: ex_result = ID_EX_reg1 + ID_EX_imm;
        `IFUN_SUB: ex_result = ID_EX_reg1 - ID_EX_imm;
        `IFUN_OR:  ex_result = ID_EX_reg1 | ID_EX_imm;
        `IFUN_AND: ex_result = ID_EX_reg1 & ID_EX_imm;
        `IFUN_SLT: ex_result = ($signed(ID_EX_reg1) < $signed(ID_EX_imm)) ? 16'h1 : 16'h0;
        `IFUN_SRL: ex_result = (ID_EX_reg1 >> ID_EX_imm[2:0]);
        `IFUN_SLL: ex_result = (ID_EX_reg1 << ID_EX_imm[2:0]);
        `IFUN_SRA: ex_result = ($signed(ID_EX_reg1) >>> ID_EX_imm[2:0]);
        default: ex_result = 16'h0000;
      endcase
    end
    `OPC_LW, `OPC_SW: begin
      ex_result = ID_EX_reg1 + ID_EX_imm;
    end
    `OPC_FPU: begin
      // use fpu module (combinational)
      // fpu uses rs1 and rs2 registers as half precision floats
      // simple: call instantiated fpu (met below)
      ex_result = fpu_result;
    end
    default: ex_result = 16'h0000;
  endcase
  zero_flag = (ex_result == 16'h0000);
end

// Instantiate FPU (combinational)
reg [3:0] fpu_ctrl;
wire [15:0] fpu_out;
wire fpu_zero;
fpu fpu0 (
  .a(ID_EX_reg1),
  .b(ID_EX_reg2),
  .aluctrl(fpu_ctrl),
  .result(fpu_out),
  .zero(fpu_zero)
);

// decide fpu_ctrl based on some bits of instruction (here we use ID_EX_funct low bits)
always @(*) begin
  fpu_ctrl = 4'b0000;
  // For simplicity, we map funct==0 -> FADD, funct==1 -> FMUL
  if (ID_EX_opcode == `OPC_FPU) begin
    if (ID_EX_funct == 3'b000) fpu_ctrl = `FPU_FADD;
    else if (ID_EX_funct == 3'b001) fpu_ctrl = `FPU_FMUL;
  end
  fpu_result = fpu_out;
end

// MEM stage
always @(posedge clk) begin
  EX_MEM_alu <= ex_result;
  EX_MEM_rd <= ID_EX_rd;
  EX_MEM_opcode <= ID_EX_opcode;
end

// memory operations and WB stage
always @(posedge clk) begin
  // MEM to WB
  if (EX_MEM_opcode == `OPC_SW) begin
    dmem[EX_MEM_alu] <= regs[EX_MEM_rd]; // store source in rd field
    MEM_WB_val <= 16'h0000;
    MEM_WB_rd <= 3'b000;
    MEM_WB_opcode <= EX_MEM_opcode;
  end else if (EX_MEM_opcode == `OPC_LW) begin
    MEM_WB_val <= dmem[EX_MEM_alu];
    MEM_WB_rd <= EX_MEM_rd;
    MEM_WB_opcode <= EX_MEM_opcode;
  end else begin
    MEM_WB_val <= EX_MEM_alu;
    MEM_WB_rd <= EX_MEM_rd;
    MEM_WB_opcode <= EX_MEM_opcode;
  end
end

// WB: write back to regfile
always @(posedge clk) begin
  if (!rst) begin
    if (MEM_WB_opcode == `OPC_RTYPE || MEM_WB_opcode == `OPC_ITYPE || MEM_WB_opcode == `OPC_FPU) begin
      regs[MEM_WB_rd] <= MEM_WB_val;
    end else if (MEM_WB_opcode == `OPC_JAL) begin
      regs[MEM_WB_rd] <= MEM_WB_val; // assuming earlier pipeline set val to return addr
    end
  end
end

endmodule
