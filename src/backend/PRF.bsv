package PRF;

  import Vector::*;
  import RegFile::*;
  import Common::*;

  interface PRF;
    method Maybe#(Data) read(PhysRegTag tag);
    method Action write(PhysRegTag tag, Data val);
    method Bool isReady(PhysRegTag tag);
    method Action markReady(PhysRegTag tag);
    // Mark a freshly allocated register as not-yet-written (p0 is exempt)
    method Action clear(PhysRegTag tag);
  endinterface

  // Physical register file with a per-register ready bit
  module mkPRF (PRF);

    Vector#(NUM_PHYS_REGS, Reg#(Data)) regs <- replicateM(mkRegU);
    Vector#(NUM_PHYS_REGS, Reg#(Bool)) readyBits <- replicateM(mkReg(False));

    // p0 is hard-wired to zero and always ready
    rule init_x0;
      regs[0] <= 0;
      readyBits[0] <= True;
    endrule

    method Maybe#(Data) read(PhysRegTag tag);
      // Reads only return a value once the producer has written it
      if (readyBits[tag]) 
        return Valid(regs[tag]);
      else 
        return Invalid;
    endmethod

    method Action write(PhysRegTag tag, Data val);
      regs[tag] <= val;
    endmethod

    method Bool isReady(PhysRegTag tag);
      return readyBits[tag];
    endmethod

    method Action markReady(PhysRegTag tag);
      readyBits[tag] <= True;
    endmethod

    method Action clear(PhysRegTag tag);
      if (tag != 0) begin
        readyBits[tag] <= False;
      end
    endmethod

  endmodule
endpackage