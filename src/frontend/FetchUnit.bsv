package FetchUnit;

  import Common::*;
  import ProgramImage::*;
  import RegFile::*;

  // Instruction memory for Specula.
  //
  // M1: the instruction stream is an externally generated image (`program.hex`,
  // one 32-bit word per line, program order) produced from `sw/test.c` by the
  // Makefile. The compiled program occupies the first `progWords` entries; the
  // Makefile pads the file with NOPs out to `imemWords` so fetch past the end
  // of the program lands on NOPs rather than out-of-bounds reads. Both counts
  // come from the generated `ProgramImage` package.
  //
  // The word at byte address `pc` lives at `imem[pc >> 2]`.

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
