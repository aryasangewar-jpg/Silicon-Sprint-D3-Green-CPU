
// Simple single-cycle CPU for the custom 16-bit ISA
// Register file: 8 registers (r0..r7) 16-bit
// Instruction encoding (16 bits):
// [15:12] opcode
// R-type: [15:12]=0000 [11:9] rd [8:6] rs1 [5:3] rs2 [2:0] funct
// I-type: [15:12]=0001 [11:9] rd [8:6] rs1 [5:0] imm6 (sign-extended)
// LH/SH:  [15:12]=0010/0011 [11:9] rd/rs2 [8:6] rs1 [5:0] imm6
// Branch: [15:12]=0100 [11:9] rs1 [8:6] rs2 [5:0] imm6 (signed pc offset)
parameter IMEM_SIZE = 256;
reg [15:0] imem [0:IMEM_SIZE-1];
reg [15:0] dmem [0:255];

reg [15:0] pc;
wire [15:0] instr;
assign instr = imem[pc];

integer i;
initial begin
  for (i=0; i<IMEM_SIZE; i=i+1) imem[i] = 16'h0000;
  for (i=0; i<256; i=i+1) dmem[i] = 16'h0000;
  pc = 16'h0000;
end

// register file
reg [15:0] regs [0:7];
always @(posedge clk or posedge rst) begin
  if (rst) begin
    for (i=0; i<8; i=i+1) regs[i] <= 16'h0000;
    pc <= 16'h0000;
  end else begin
    pc <= pc_next;
  end
end

// fields
wire [3:0] opcode = instr[15:12];
wire [2:0] rd     = instr[11:9];
wire [2:0] rs1    = instr[8:6];
wire [2:0] rs2    = instr[5:3];
wire [2:0] funct  = instr[2:0];
wire [5:0] imm6   = instr[5:0];
wire [8:0] imm9   = instr[8:0]; // for some branches if needed

function [15:0] sext6;
  input [5:0] x;
  begin
    sext6 = {{10{x[5]}}, x};
  end
endfunction

// ALU
reg [15:0] alu_out;
reg zero_flag;

always @(*) begin
  alu_out = 16'h0000;
  zero_flag = 1'b0;
  case(opcode)
    `OPC_RTYPE: begin
      case(funct)
        `FUNCT_ADD: alu_out = regs[rs1] + regs[rs2];
        `FUNCT_SUB: alu_out = regs[rs1] - regs[rs2];
        `FUNCT_SLT: alu_out = ( $signed(regs[rs1]) < $signed(regs[rs2]) ) ? 16'h0001 : 16'h0000;
        `FUNCT_OR:  alu_out = regs[rs1] | regs[rs2];
        `FUNCT_AND: alu_out = regs[rs1] & regs[rs2];
        `FUNCT_SRL: alu_out = (regs[rs1] >> regs[rs2][2:0]);
        `FUNCT_SLL: alu_out = (regs[rs1] << regs[rs2][2:0]);
        `FUNCT_SRA: alu_out = ($signed(regs[rs1]) >>> regs[rs2][2:0]);
        default: alu_out = 16'h0000;
      endcase
    end
    `OPC_ITYPE: begin
      case(funct)
        `IFUN_ADD: alu_out = regs[rs1] + sext6(imm6);
        `IFUN_SUB: alu_out = regs[rs1] - sext6(imm6);
        `IFUN_OR:  alu_out = regs[rs1] | sext6(imm6);
        `IFUN_AND: alu_out = regs[rs1] & sext6(imm6);
        `IFUN_SLT: alu_out = ($signed(regs[rs1]) < $signed(sext6(imm6))) ? 16'h1 : 16'h0;
        `IFUN_SRL: alu_out = regs[rs1] >> imm6[2:0];
        `IFUN_SLL: alu_out = regs[rs1] << imm6[2:0];
        `IFUN_SRA: alu_out = $signed(regs[rs1]) >>> imm6[2:0];
        default: alu_out = 16'h0000;
      endcase
    end
    `OPC_LW: begin
      alu_out = regs[rs1] + sext6(imm6); // address
    end
    `OPC_SW: begin
      alu_out = regs[rs1] + sext6(imm6);
    end
    default: alu_out = 16'h0000;
  endcase
  zero_flag = (alu_out == 16'h0000);
end

// next PC logic (branches/jumps)
reg [15:0] pc_next;
always @(*) begin
  pc_next = pc + 1;
  case(opcode)
    `OPC_BRANCH: begin
      case(funct)
        `BFUN_BEQ: if (regs[rs1] == regs[rs2]) pc_next = pc + $signed(sext6(imm6));
        `BFUN_BNE: if (regs[rs1] != regs[rs2]) pc_next = pc + $signed(sext6(imm6));
        `BFUN_BLT: if ($signed(regs[rs1]) < $signed(regs[rs2])) pc_next = pc + $signed(sext6(imm6));
        `BFUN_BGE: if ($signed(regs[rs1]) >= $signed(regs[rs2])) pc_next = pc + $signed(sext6(imm6));
        default: ;
      endcase
    end
    `OPC_JAL: begin
      pc_next = pc + $signed(sext6(imm6)); // simple PC relative jump
    end
    `OPC_JALR: begin
      pc_next = regs[rs1] + sext6(imm6);
    end
    default: ;
  endcase
end

// memory and register writeback
always @(posedge clk) begin
  if (rst) begin
    for (i=0; i<8; i=i+1) regs[i] <= 16'h0000;
  end else begin
    case (opcode)
      `OPC_RTYPE: begin
        regs[rd] <= alu_out;
      end
      `OPC_ITYPE: begin
        regs[rd] <= alu_out;
      end
      `OPC_LW: begin
        // load halfword from dmem (aligned)
        regs[rd] <= dmem[alu_out];
      end
      `OPC_SW: begin
        dmem[alu_out] <= regs[rd]; // here instr uses rd as source for store
      end
      `OPC_JAL: begin
        regs[rd] <= pc + 1; // store return address
      end
      `OPC_JALR: begin
        regs[rd] <= pc + 1;
      end
      default: ;
    endcase
  end
end

endmodule

//Add all your code here
  
endmodule
