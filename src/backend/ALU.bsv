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
    Bit#(32) fallPC;
    Bit#(32) branchOffset;
  } ALUReq deriving (Bits, FShow);

  typedef struct {
    Data result;
    PhysRegTag dest;
    ROBTag robTag;
    Bool isBranch;
    Bool isJump;
    Bool isJalr;
    Bool actualTaken;
    Data actualTarget;
    Bit#(32) pc;
    Bit#(32) fallPC;
  } ALUResp deriving (Bits, FShow);

  interface ALU_IFC;
    method Bool notFull();
    method Bool notEmpty();
    method Action enq(ALUReq r);
    method ActionValue#(ALUResp) deq();
    method Action flush();  
    method Bool busy();      
  endinterface

  typedef enum { DIV_IDLE, DIV_RUN, DIV_DONE } DivState deriving (Bits, Eq, FShow);

  module mkALU(ALU_IFC);

    FIFOF#(ALUReq) reqQ <- mkFIFOF();  // Input buffer
    FIFOF#(ALUResp) respQ <- mkFIFOF();  // Output buffer

    Array#(Reg#(Bool)) flushReq <- mkCReg(2, False);

    Reg#(DivState)  divSt     <- mkReg(DIV_IDLE);
    Reg#(Bit#(6))   divCount  <- mkReg(0);
    Reg#(Bit#(32))  divRem    <- mkReg(0);
    Reg#(Bit#(32))  divQuot   <- mkReg(0);
    Reg#(Bit#(32))  divDsor   <- mkReg(0);
    Reg#(Bit#(32))  divDvnd   <- mkReg(0);
    Reg#(Bool)      divIsRem  <- mkReg(False);
    Reg#(Bool)      divByZero <- mkReg(False);
    Reg#(ALUReq)    divReq    <- mkRegU;

    function Bool isDivOp(ALUOp op) = (op == ALU_DIVU) || (op == ALU_REMU);

    rule finishFlush (flushReq[0]);
      reqQ.clear;
      respQ.clear;
      flushReq[0] <= False;
      divSt <= DIV_IDLE;
      if (traceOn) $display("[ALU] flushed in-flight requests/results");
    endrule

    rule divStep (!flushReq[0] && divSt == DIV_RUN);
      Bit#(33) shifted = { divRem, divQuot[31] };
      Bit#(33) diff    = shifted - { 1'b0, divDsor };
      Bool     fits    = (diff[32] == 1'b0);
      divRem   <= fits ? diff[31:0] : shifted[31:0];
      divQuot  <= { divQuot[30:0], pack(fits) };
      divCount <= divCount - 1;
      if (divCount == 1) divSt <= DIV_DONE;
    endrule

    rule divDrain (!flushReq[0] && divSt == DIV_DONE);
      Bit#(32) q   = divByZero ? 32'hFFFFFFFF : divQuot;
      Bit#(32) rem = divByZero ? divDvnd      : divRem;
      Bit#(32) res = divIsRem  ? rem : q;
      respQ.enq(ALUResp {
        result: res,
        dest: divReq.dest,
        robTag: divReq.robTag,
        isBranch: False,
        isJump: False,
        isJalr: False,
        actualTaken: False,
        actualTarget: 32'd0,
        pc: divReq.pc,
        fallPC: divReq.fallPC
      });
      divSt <= DIV_IDLE;
      if (traceOn) $display("[ALU] divider retire: rob=%0d %s -> %h",
               divReq.robTag.idx, divIsRem ? "REMU" : "DIVU", res);
    endrule

    rule execute (!flushReq[0] && divSt == DIV_IDLE);
      let r = reqQ.first;

      if (isDivOp(r.opcode)) begin
        reqQ.deq;
        divReq    <= r;
        divRem    <= 32'd0;
        divQuot   <= r.a;
        divDsor   <= r.b;
        divDvnd   <= r.a;
        divIsRem  <= (r.opcode == ALU_REMU);
        divByZero <= (r.b == 32'd0);
        divCount  <= 6'd32;
        divSt     <= DIV_RUN;
        if (traceOn) $display("[ALU] divider start: rob=%0d %s a=%h b=%h",
                 r.robTag.idx, (r.opcode == ALU_REMU) ? "REMU" : "DIVU", r.a, r.b);
      end
      else begin
      reqQ.deq;

      Data res = 32'd0;
      Bool isBranch = False;
      Bool isJump = False;
      Bool isJalr = False;
      Bool actualTaken = False;
      Data actualTarget = 32'd0;

      case (r.opcode)
        ALU_ADD: res = r.a + r.b;
        ALU_SUB: res = r.a - r.b;
        ALU_AND: res = r.a & r.b;
        ALU_OR: res = r.a | r.b;
        ALU_XOR: res = r.a ^ r.b;
        ALU_SLL: res = r.a << r.b[4:0];
        ALU_SRL: res = r.a >> r.b[4:0];
        ALU_SRA: res = signedShiftRight(r.a, r.b[4:0]);
        ALU_SLT:  res = signedLT(r.a, r.b) ? 32'd1 : 32'd0;
        ALU_SLTU: res = (r.a < r.b)        ? 32'd1 : 32'd0;
        ALU_LUI: res = r.b;
        ALU_AUIPC: res = r.pc + r.branchOffset;
        ALU_NOP: res = 32'd0;
        ALU_MUL:  res = r.a * r.b;
        ALU_JAL: begin
          isBranch = True; isJump = True; actualTaken = True;
          actualTarget = r.pc + r.branchOffset;
          res = r.fallPC;
        end
        ALU_JALR: begin
          isBranch = True; isJump = True; isJalr = True; actualTaken = True;
          actualTarget = (r.a + r.branchOffset) & 32'hFFFFFFFE;
          res = r.fallPC;
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
          actualTaken = (r.a < r.b);
          actualTarget = r.pc + r.branchOffset;
          res = 0;
        end
        ALU_BGEU: begin
          isBranch = True;
          actualTaken = (r.a >= r.b);
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
        isJalr: isJalr,
        actualTaken: actualTaken,
        actualTarget: actualTarget,
        pc: r.pc,
        fallPC: r.fallPC
      };
      respQ.enq(out);
      end
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
      return flushReq[0] || reqQ.notEmpty || respQ.notEmpty || divSt != DIV_IDLE;
    endmethod

  endmodule
endpackage