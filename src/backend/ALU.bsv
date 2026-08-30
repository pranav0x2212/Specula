package ALU;

  import Common::*;
  import FIFOF::*;

  function Bit#(32) signedShiftRight(Bit#(32) val, Bit#(5) shamt);
    Int#(32) signedVal = unpack(val);
    Int#(32) shifted = signedVal >> shamt;
    return pack(shifted);
  endfunction

  typedef struct {
    ALUOp opcode;
    Data a;
    Data b;
    PhysRegTag dest;
    ROBTag robTag;
    Bit#(32) pc;
    Bit#(32) branchOffset;
  } ALUReq deriving (Bits, FShow);

  typedef struct {
    Data result;
    PhysRegTag dest;
    ROBTag robTag;
    Bool isBranch;      // resolves through the branch/recovery path (branches + jumps)
    Bool isJump;        // JAL/JALR: unconditional, writes a link reg, not predicted
    Bool actualTaken;
    Data actualTarget;
    Bit#(32) pc;
  } ALUResp deriving (Bits, FShow);

  interface ALU_IFC;
    method Bool notFull();
    method Bool notEmpty();
    method Action enq(ALUReq r);
    method ActionValue#(ALUResp) deq();
    method Action flush();  
    method Bool busy();      
  endinterface

  module mkALU(ALU_IFC);

    FIFOF#(ALUReq) reqQ <- mkFIFOF();  // Input buffer
    FIFOF#(ALUResp) respQ <- mkFIFOF();  // Output buffer

    Array#(Reg#(Bool)) flushReq <- mkCReg(2, False);

    rule finishFlush (flushReq[0]);
      reqQ.clear;
      respQ.clear;
      flushReq[0] <= False;
      $display("[ALU] flushed in-flight requests/results");
    endrule

    rule execute (!flushReq[0]);
      let r = reqQ.first; reqQ.deq;

      Data res = 32'd0;
      Bool isBranch = False;
      Bool isJump = False;
      Bool actualTaken = False;
      Data actualTarget = 32'd0;

      case (r.opcode)
        ALU_ADD: res = r.a + r.b;
        ALU_SUB: res = r.a - r.b;
        ALU_AND: res = r.a & r.b;
        ALU_OR: res = r.a | r.b;
        ALU_XOR: res = r.a ^ r.b;
        // Shifts: RV32 uses only the low 5 bits of the amount (register or shamt).
        ALU_SLL: res = r.a << r.b[4:0];
        ALU_SRL: res = r.a >> r.b[4:0];
        ALU_SRA: res = signedShiftRight(r.a, r.b[4:0]);
        ALU_SLT:  res = signedLT(r.a, r.b) ? 32'd1 : 32'd0;
        ALU_SLTU: res = (r.a < r.b)        ? 32'd1 : 32'd0;
        ALU_LUI: res = r.b;   // b carries the U-immediate (useImmediate)
        ALU_JAL: begin
          // rd <- pc+4 ; redirect to pc + J-immediate
          isBranch = True; isJump = True; actualTaken = True;
          actualTarget = r.pc + r.branchOffset;
          res = r.pc + 4;
        end
        ALU_JALR: begin
          // rd <- pc+4 ; redirect to (rs1 + I-immediate) & ~1
          isBranch = True; isJump = True; actualTaken = True;
          actualTarget = (r.a + r.branchOffset) & 32'hFFFFFFFE;
          res = r.pc + 4;
        end
        ALU_BEQ: begin
          isBranch = True;
          actualTaken = (r.a == r.b);
          actualTarget = r.pc + r.branchOffset;
          res = 0;
        end
        ALU_BNE: begin
          isBranch = True;
          actualTaken = (r.a != r.b);
          actualTarget = r.pc + r.branchOffset;
          res = 0;
        end
        ALU_BLT: begin
          isBranch = True;
          actualTaken = (signedLT(r.a, r.b));
          actualTarget = r.pc + r.branchOffset;
          res = 0;
        end
        ALU_BGE: begin
          isBranch = True;
          actualTaken = (signedGE(r.a, r.b));
          actualTarget = r.pc + r.branchOffset;
          res = 0;
        end
        ALU_BLTU: begin
          isBranch = True;
          actualTaken = (r.a < r.b);        // unsigned
          actualTarget = r.pc + r.branchOffset;
          res = 0;
        end
        ALU_BGEU: begin
          isBranch = True;
          actualTaken = (r.a >= r.b);       // unsigned
          actualTarget = r.pc + r.branchOffset;
          res = 0;
        end
        default: res = 32'd0;
      endcase

      ALUResp out = ALUResp {
        result: res,
        dest: r.dest,
        robTag: r.robTag,
        isBranch: isBranch,
        isJump: isJump,
        actualTaken: actualTaken,
        actualTarget: actualTarget,
        pc: r.pc
      };
      respQ.enq(out);
    endrule

    method Bool notFull() = reqQ.notFull;
    method Bool notEmpty() = respQ.notEmpty && !flushReq[0];

    method Action enq(ALUReq r);
      reqQ.enq(r);
    endmethod

    method ActionValue#(ALUResp) deq();
      let v = respQ.first; respQ.deq;
      return v;
    endmethod

    method Action flush();
      flushReq[1] <= True;
    endmethod

    method Bool busy();
      return flushReq[0] || reqQ.notEmpty || respQ.notEmpty;
    endmethod

  endmodule
endpackage