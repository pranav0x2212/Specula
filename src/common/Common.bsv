package Common;

  Bool traceOn = False;

  typedef Bit#(5) RegIndex;
  typedef Bit#(32) Instruction;
  typedef Bit#(32) Data;
  typedef Bit#(32) Addr;
  typedef Maybe#(ROBTag) RATEntry;

  typedef struct {
    Instruction instr;
    Bit#(32)    npc;
    Bool        isComp;
    Bool        fault;
    Bit#(4)     faultCause;
  } FetchSlice deriving (Bits, FShow);

  typedef enum {
    OP_IMM, OP, LUI, AUIPC, JAL, JALR, BRANCH, LOAD, STORE, MISC_MEM, SYSTEM, INVALID
  } Opcode deriving (Bits, Eq, FShow);

  typedef enum {
    ALU_ADD, ALU_SUB, ALU_AND, ALU_OR,
    ALU_BEQ, ALU_BNE, ALU_BLT, ALU_BGE,
    ALU_LW, ALU_SW,
    ALU_JAL, ALU_JALR,
    ALU_SLL, ALU_SRL, ALU_SRA,
    ALU_SLT, ALU_SLTU,
    ALU_XOR,
    ALU_LUI,
    ALU_AUIPC, ALU_NOP,
    ALU_BLTU, ALU_BGEU,
    ALU_MUL, ALU_DIVU, ALU_REMU,
    ALU_CSR, ALU_MRET,
    ALU_AMOSWAP
  } ALUOp deriving (Bits, Eq, FShow);

  typedef struct {
    ALUOp opcode;
    RegIndex rd;
    RegIndex rs1;
    RegIndex rs2;
    Bit#(3) funct3;
    Bit#(7) funct7;
    Bit#(32) imm;
    Instruction raw;
  } Decoded deriving (Bits, FShow);

  typedef struct {
    Decoded instr;
    Bit#(32) pc;
    Bit#(32) fallPC;
    PhysRegTag src1Tag;
    Bool src1Ready;
    PhysRegTag src2Tag;
    Bool src2Ready;
    PhysRegTag destTag;
    ROBTag robTag;
  } RenamedInstr deriving (Bits, FShow);

  typedef 6 LogNumPhysRegs;
  typedef 64 NUM_PHYS_REGS;
  typedef Bit#(LogNumPhysRegs) PhysRegTag;

  typedef PhysRegTag ZERO_TAG;
  function ZERO_TAG zeroTag();
    return 0;
  endfunction

  function Decoded decode(Instruction instr, Bit#(32) pc);
    Bit#(7) actualOpcode = instr[6:0];
    Bit#(3) funct3 = instr[14:12];

    Bit#(1) f7bit30 = instr[30];  
    ALUOp aluOp;
    if (actualOpcode == 7'b0110011) begin  // R-type integer / RV32M
      if (instr[31:25] == 7'b0000001) begin  // M8: M-extension (funct7 = 0000001)
        case (funct3)
          3'b000:  aluOp = ALU_MUL;
          3'b101:  aluOp = ALU_DIVU;
          3'b111:  aluOp = ALU_REMU;
          default: aluOp = ALU_NOP;  // MULH/MULHSU/MULHU/DIV/REM: unused by xv6, not implemented
        endcase
      end else begin
        case (funct3)
          3'b000:  aluOp = (f7bit30 == 1) ? ALU_SUB : ALU_ADD;
          3'b001:  aluOp = ALU_SLL;
          3'b010:  aluOp = ALU_SLT;
          3'b011:  aluOp = ALU_SLTU;
          3'b100:  aluOp = ALU_XOR;
          3'b101:  aluOp = (f7bit30 == 1) ? ALU_SRA : ALU_SRL;
          3'b110:  aluOp = ALU_OR;
          default: aluOp = ALU_AND;                                 // 3'b111
        endcase
      end
    end else if (actualOpcode == 7'b0010011) begin  // OP-IMM
      case (funct3)
        3'b000:  aluOp = ALU_ADD;                                 // ADDI
        3'b001:  aluOp = ALU_SLL;                                 // SLLI
        3'b010:  aluOp = ALU_SLT;                                 // SLTI
        3'b011:  aluOp = ALU_SLTU;                                // SLTIU
        3'b100:  aluOp = ALU_XOR;                                 // XORI
        3'b101:  aluOp = (f7bit30 == 1) ? ALU_SRA : ALU_SRL;      // SRAI / SRLI
        3'b110:  aluOp = ALU_OR;                                  // ORI
        default: aluOp = ALU_AND;                                 // 3'b111  ANDI
      endcase
    end else if (actualOpcode == 7'b0110111) begin  // LUI
      aluOp = ALU_LUI;
    end else if (actualOpcode == 7'b0010111) begin  // AUIPC
      aluOp = ALU_AUIPC;
    end else if (actualOpcode == 7'b0001111) begin  // MISC-MEM (FENCE) -> retiring NOP
      aluOp = ALU_NOP;
    end else if (actualOpcode == 7'b0000011) begin  // LOAD (LW)
      aluOp = ALU_LW;
    end else if (actualOpcode == 7'b0100011) begin  // STORE (SW)
      aluOp = ALU_SW;
    end else if (actualOpcode == 7'b1100011) begin  // Branch (B-type)
      if (funct3 == 3'b000) aluOp = ALU_BEQ;
      else if (funct3 == 3'b001) aluOp = ALU_BNE;
      else if (funct3 == 3'b100) aluOp = ALU_BLT;
      else if (funct3 == 3'b101) aluOp = ALU_BGE;
      else if (funct3 == 3'b110) aluOp = ALU_BLTU;
      else if (funct3 == 3'b111) aluOp = ALU_BGEU;
      else aluOp = ALU_BEQ;
    end else if (actualOpcode == 7'b1101111) begin  // JAL  (J-type)
      aluOp = ALU_JAL;
    end else if (actualOpcode == 7'b1100111) begin  // JALR (I-type)
      aluOp = ALU_JALR;
    end else if (actualOpcode == 7'b1110011 && funct3[1:0] != 2'b00) begin
      aluOp = ALU_CSR;   // SYSTEM Zicsr: funct3 001/010/011/101/110/111 = CSRRW/S/C[I]
    end else if (actualOpcode == 7'b1110011 && funct3 == 3'b000 && instr[31:20] == 12'h302) begin
      aluOp = ALU_MRET;  // SYSTEM: MRET
    end else if (actualOpcode == 7'b0101111 && funct3 == 3'b010 && instr[31:27] == 5'b00001) begin
      aluOp = ALU_AMOSWAP;  // RV32A: AMOSWAP.W (aq/rl in bits 26:25 ignored)
    end else begin
      aluOp = ALU_ADD;
    end
    
    Bit#(32) imm = 0;
    RegIndex rs2Field = 0;
    
    if (actualOpcode == 7'b0010011) begin  // OP-IMM
      if (funct3 == 3'b001 || funct3 == 3'b101)
        imm = zeroExtend(instr[24:20]);      // SLLI/SRLI/SRAI: 5-bit shamt (RV32)
      else
        imm = signExtend(instr[31:20]);      // ADDI/SLTI/SLTIU/XORI/ORI/ANDI
      rs2Field = 0;
    end else if (actualOpcode == 7'b0110111) begin  // LUI - U-type immediate
      imm = {instr[31:12], 12'd0};
      rs2Field = 0;
    end else if (actualOpcode == 7'b0010111) begin  // AUIPC - U-type immediate
      imm = {instr[31:12], 12'd0};
      rs2Field = 0;
    end else if (actualOpcode == 7'b0001111) begin  // FENCE - no immediate, no source regs
      imm = 0;
      rs2Field = 0;
    end else if (actualOpcode == 7'b0000011) begin  // LOAD (LW) - I-type
      imm = signExtend(instr[31:20]);
      rs2Field = 0;
    end else if (actualOpcode == 7'b0100011) begin  // STORE (SW) - S-type
      Bit#(7) imm_hi = instr[31:25];
      Bit#(5) imm_lo = instr[11:7];
      imm = signExtend({imm_hi, imm_lo});
      rs2Field = instr[24:20];
    end else if (actualOpcode == 7'b1100011) begin  // B-type immediate (13-bit, LSB 0)
      Bit#(13) branchImm = {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
      imm = signExtend13(branchImm);
      rs2Field = instr[24:20];  // B-type uses rs2
    end else if (actualOpcode == 7'b1101111) begin  // JAL - J-type immediate (21-bit, LSB 0)
      Bit#(21) jalImm = {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
      imm = signExtend21(jalImm);
      rs2Field = 0;
    end else if (actualOpcode == 7'b1100111) begin  // JALR - I-type immediate
      imm = signExtend(instr[31:20]);
      rs2Field = 0;
    end else if (actualOpcode == 7'b1110011) begin  // SYSTEM - carry CSR address in imm[11:0]
      imm = zeroExtend(instr[31:20]);
      rs2Field = 0;
    end else begin
      rs2Field = instr[24:20];  // R-type and other types use rs2
    end

    RegIndex rdField = (actualOpcode == 7'b1100011) ? 0 : instr[11:7];

    RegIndex rs1Field = ((actualOpcode == 7'b1101111) || (actualOpcode == 7'b0110111)
                         || (actualOpcode == 7'b0010111) || (actualOpcode == 7'b0001111))
                        ? 0 : instr[19:15];

    return Decoded {
      opcode: aluOp,
      rd: rdField,
      rs1: rs1Field,
      rs2: rs2Field,
      funct3: funct3,
      funct7: 0,
      imm: imm,
      raw: instr
    };
  endfunction

  function Bit#(32) signExtend(Bit#(12) imm12);
    Bit#(32) extended;
    if (imm12[11] == 1)
      extended = {20'hFFFFF, imm12};
    else
      extended = {20'h00000, imm12};
    return extended;
  endfunction
  
  // Sign extend 13-bit immediate (for B-type)
  function Bit#(32) signExtend13(Bit#(13) imm13);
    Bit#(32) extended;
    if (imm13[12] == 1)
      extended = {19'h7FFFF, imm13};
    else
      extended = {19'h00000, imm13};
    return extended;
  endfunction
  
  // Sign extend 21-bit immediate (for J-type)
  function Bit#(32) signExtend21(Bit#(21) imm21);
    Bit#(32) extended;
    if (imm21[20] == 1)
      extended = {11'h7FF, imm21};
    else
      extended = {11'h000, imm21};
    return extended;
  endfunction

  function Bool signedLT(Bit#(32) a, Bit#(32) b);
    Int#(32) sa = unpack(a);
    Int#(32) sb = unpack(b);
    return sa < sb;
  endfunction

  function Bool signedGE(Bit#(32) a, Bit#(32) b);
    Int#(32) sa = unpack(a);
    Int#(32) sb = unpack(b);
    return sa >= sb;
  endfunction

  function Bool isMemoryOp(ALUOp op);
    return (op == ALU_LW || op == ALU_SW || op == ALU_AMOSWAP);
  endfunction

  function Bool isBranchOp(ALUOp op);
    return (op == ALU_BEQ || op == ALU_BNE || op == ALU_BLT || op == ALU_BGE
            || op == ALU_BLTU || op == ALU_BGEU);
  endfunction

  function Bool isJumpOp(ALUOp op);
    return (op == ALU_JAL || op == ALU_JALR);
  endfunction

  function Bool isControlFlowOp(ALUOp op);
    return isBranchOp(op) || isJumpOp(op);
  endfunction

  function Bool isControlFlowInstr(Instruction instr);
    let opc = instr[6:0];
    return (opc == 7'b1100011) || (opc == 7'b1101111) || (opc == 7'b1100111);
  endfunction

  function Bool isCsrOp(ALUOp op);
    return (op == ALU_CSR);
  endfunction

  function Bool isMretOp(ALUOp op);
    return (op == ALU_MRET);
  endfunction

  function Bool isSerializingOp(ALUOp op);
    return (op == ALU_CSR) || (op == ALU_MRET);
  endfunction

  function Bool isSerializingInstr(Instruction instr);
    Bit#(7) opc = instr[6:0];
    Bit#(3) f3  = instr[14:12];
    Bool isCsr  = (f3[1:0] != 2'b00);
    Bool isMret = (f3 == 3'b000) && (instr[31:20] == 12'h302);
    return (opc == 7'b1110011) && (isCsr || isMret);
  endfunction
  
  function Bool isLoadOp(ALUOp op);
    return (op == ALU_LW);
  endfunction
  
  function Bool isStoreOp(ALUOp op);
    return (op == ALU_SW);
  endfunction

  function Bool needsPhysDest(Decoded d);
    return (d.rd != 0) && (d.opcode != ALU_SW);
  endfunction

  typedef struct {
    UInt#(6) idx;
  } ROBTag deriving (Bits, FShow);

  function Bool isOlderRob(ROBTag a, ROBTag b, ROBTag head);
    UInt#(6) da = a.idx - head.idx;
    UInt#(6) db = b.idx - head.idx;
    return da < db;
  endfunction

  typedef struct {
    ALUOp opcode;
    PhysRegTag src1;
    PhysRegTag src2;
    PhysRegTag dest;
  } ALUInstr deriving (Bits, FShow);

  typedef struct {
    ALUOp opcode;
    PhysRegTag src1;
    Bool src1Ready;
    PhysRegTag src2;
    Bool src2Ready;
    Data immediate;
    Bool useImmediate;
    PhysRegTag dest;
    ROBTag robTag;
    Addr pc;
    Addr fallPC;
  } RSEntry deriving (Bits, FShow);

  typedef struct {
    Bool isBranch;
    Addr pc;
    Addr predictedTarget;
  } BranchMetadata deriving (Bits, FShow);

endpackage
