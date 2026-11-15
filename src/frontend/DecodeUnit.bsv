package DecodeUnit;

  import Common::*;

  interface IfcDecodeUnit;
    method Action start(Instruction instr, Bit#(32) pc);
    method Decoded getDecoded();
  endinterface

  // Registers the decoded form of one instruction (reset value is a NOP: addi x0,x0,0)
  module mkDecodeUnit(IfcDecodeUnit);
    Reg#(Decoded) decoded <- mkReg(Decoded {
      opcode: ALU_ADD,
      rd: 0,
      rs1: 0,
      rs2: 0,
      funct3: 0,
      funct7: 0,
      imm: 0,
      raw: 32'h00000013
    });

    method Action start(Instruction instr, Bit#(32) pc);
      // Pure combinational decode from Common, latched into a register
      decoded <= decode(instr, pc);
    endmethod

    method Decoded getDecoded();
      return decoded;
    endmethod
  endmodule

endpackage