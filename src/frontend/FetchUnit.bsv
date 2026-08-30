package FetchUnit;

  import Common::*;
  import ProgramImage::*;
  import RegFile::*;

  interface IfcFetchUnit;
    method Action start(Bit#(32) pc);
    method Instruction getInstr(Bit#(32) pc);
  endinterface

  module mkFetchUnit(IfcFetchUnit);
    RegFile#(Bit#(32), Instruction) imem <-
      mkRegFileLoad("program.hex", 0, fromInteger(imemWords - 1));

    method Action start(Bit#(32) pc);
      $display("[Fetch] PC: %08x | instr: %08x", pc, imem.sub(pc >> 2));
    endmethod

    method Instruction getInstr(Bit#(32) pc);
      return imem.sub(pc >> 2);
    endmethod
  endmodule

endpackage
