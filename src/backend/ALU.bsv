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
    Bool isBranch;
    Bool actualTaken;
    Data actualTarget;
  } ALUResp deriving (Bits, FShow);

  interface ALU_IFC;
    method Bool notFull();
    method Bool notEmpty();
    method Action enq(ALUReq r);
    method ActionValue#(ALUResp) deq();
  endinterface

  module mkALU(ALU_IFC);

    FIFOF#(ALUReq) reqQ <- mkFIFOF();  // Input buffer
    FIFOF#(ALUResp) respQ <- mkFIFOF();  // Output buffer

    rule execute;
      let r = reqQ.first; reqQ.deq;

      Data res = 32'd0;
      Bool isBranch = False;
      Bool actualTaken = False;
      Data actualTarget = 32'd0;
      
      case (r.opcode) 
        ALU_ADD: res = r.a + r.b;
        ALU_SUB: res = r.a - r.b;
        ALU_AND: res = r.a & r.b;
        ALU_OR: res = r.a | r.b;
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
        default: res = 32'd0;
      endcase

      ALUResp out = ALUResp {
        result: res, 
        dest: r.dest,
        robTag: r.robTag,
        isBranch: isBranch,
        actualTaken: actualTaken,
        actualTarget: actualTarget
      };
      respQ.enq(out);
    endrule

    method Bool notFull() = reqQ.notFull;
    method Bool notEmpty() = respQ.notEmpty;

    method Action enq(ALUReq r);
      reqQ.enq(r);
    endmethod

    method ActionValue#(ALUResp) deq();
      let v = respQ.first; respQ.deq;
      return v;
    endmethod

  endmodule
endpackage