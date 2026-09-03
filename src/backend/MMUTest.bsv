package MMUTest;

  import Common::*;
  import MMU::*;

  Bit#(32) satpSv32 = 32'h80080010;
  Bit#(32) satpBare = 32'h00000010;   // MODE = 0

  function Bit#(32) ptw(Bit#(32) a);
    return (case (a)
              32'h80010000: 32'h20004401;  // root[0]    -> L0 table @ 0x80011000 (pointer, V)
              32'h80010004: 32'h2010000f;  // root[1]    -> 4 MiB superpage leaf RWX, PA base 0x80400000
              32'h80010ffc: 32'h20004801;  // root[1023] -> L0hi table @ 0x80012000 (pointer, V)
              32'h8001100c: 32'h2000140f;  // L0[3]      -> 4 KiB leaf RWX, PA 0x80005000
              32'h80011010: 32'h20001803;  // L0[4]      -> 4 KiB leaf R--, PA 0x80006000
              32'h80011014: 32'h20001c09;  // L0[5]      -> 4 KiB leaf --X, PA 0x80007000
              32'h80012ff8: 32'h20010807;  // L0hi[1022] -> 4 KiB leaf RW-, PA 0x80042000
              default:      32'h00000000;  // everything else: PTE invalid (V = 0)
            endcase);
  endfunction

  module mkMMUTest(Empty);
    Reg#(Bool)     done  <- mkReg(False);
    Reg#(Bit#(16)) fails <- mkReg(0);

    function ActionValue#(Bit#(16)) chk(String tag, Bit#(32) got, Bit#(32) want);
      actionvalue
        Bool ok = (got == want);
        if (ok) $display("[MMU-TEST] ok   %s : %08h", tag, got);
        else    $display("[MMU-TEST] FAIL %s : got %08h want %08h", tag, got, want);
        return ok ? 16'd0 : 16'd1;
      endactionvalue
    endfunction

    function ActionValue#(Bit#(16)) chkB(String tag, Bool got, Bool want);
      actionvalue
        Bool ok = (got == want);
        if (ok) $display("[MMU-TEST] ok   %s", tag);
        else    $display("[MMU-TEST] FAIL %s : got %0d want %0d", tag, got, want);
        return ok ? 16'd0 : 16'd1;
      endactionvalue
    endfunction

    rule run (!done);
      Bit#(16) f = 0;
      Bit#(16) t = 0;

      let r1 = sv32Translate(32'h12345678, DataLoad, 2'b11, satpSv32, ptw);
      t <- chk ("bare(M) pa",      r1.pa,    32'h12345678); f = f + t;
      t <- chkB("bare(M) no fault", r1.fault, False);        f = f + t;

      let r2 = sv32Translate(32'hDEADBEEF, InstFetch, 2'b01, satpBare, ptw);
      t <- chk ("bare(S,MODE0) pa",      r2.pa,    32'hDEADBEEF); f = f + t;
      t <- chkB("bare(S,MODE0) no fault", r2.fault, False);        f = f + t;

      let r3 = sv32Translate(32'h00003000, DataLoad, 2'b01, satpSv32, ptw);
      t <- chk ("walk pa",       r3.pa,    32'h80005000); f = f + t;
      t <- chkB("walk no fault", r3.fault, False);         f = f + t;

      let r4 = sv32Translate(32'h00003ABC, DataLoad, 2'b01, satpSv32, ptw);
      t <- chk ("walk+off pa", r4.pa, 32'h80005ABC); f = f + t;

      let r5 = sv32Translate(32'hFFFFE000, DataLoad, 2'b01, satpSv32, ptw);
      t <- chk ("highVA pa",       r5.pa,    32'h80042000); f = f + t;
      t <- chkB("highVA no fault", r5.fault, False);         f = f + t;

      let r6 = sv32Translate(32'hFFFFE123, DataStore, 2'b01, satpSv32, ptw);
      t <- chk ("highVA+off store pa", r6.pa,    32'h80042123); f = f + t;
      t <- chkB("highVA store no fault", r6.fault, False);       f = f + t;

      let r7 = sv32Translate(32'hFFFFE000, InstFetch, 2'b01, satpSv32, ptw);
      t <- chkB("highVA fetch faults", r7.fault, True); f = f + t;
      t <- chk ("highVA fetch cause",  zeroExtend(r7.cause), 32'd12); f = f + t;

      let r8a = sv32Translate(32'h00004000, DataLoad,  2'b01, satpSv32, ptw);
      let r8b = sv32Translate(32'h00004000, DataStore, 2'b01, satpSv32, ptw);
      let r8c = sv32Translate(32'h00004000, InstFetch, 2'b01, satpSv32, ptw);
      t <- chk ("R-only load pa",     r8a.pa,    32'h80006000); f = f + t;
      t <- chkB("R-only load ok",     r8a.fault, False);         f = f + t;
      t <- chkB("R-only store faults", r8b.fault, True);         f = f + t;
      t <- chk ("R-only store cause", zeroExtend(r8b.cause), 32'd15); f = f + t;
      t <- chkB("R-only fetch faults", r8c.fault, True);         f = f + t;
      t <- chk ("R-only fetch cause", zeroExtend(r8c.cause), 32'd12); f = f + t;

      let r9a = sv32Translate(32'h00005000, InstFetch, 2'b01, satpSv32, ptw);
      let r9b = sv32Translate(32'h00005000, DataLoad,  2'b01, satpSv32, ptw);
      t <- chk ("X-only fetch pa",     r9a.pa,    32'h80007000); f = f + t;
      t <- chkB("X-only fetch ok",     r9a.fault, False);         f = f + t;
      t <- chkB("X-only load faults",  r9b.fault, True);          f = f + t;
      t <- chk ("X-only load cause",   zeroExtend(r9b.cause), 32'd13); f = f + t;

      let r10a = sv32Translate(32'h00400123, DataLoad,  2'b01, satpSv32, ptw);
      let r10b = sv32Translate(32'h00400123, InstFetch, 2'b01, satpSv32, ptw);
      t <- chk ("superpage load pa",   r10a.pa,    32'h80400123); f = f + t;
      t <- chkB("superpage load ok",   r10a.fault, False);         f = f + t;
      t <- chk ("superpage fetch pa",  r10b.pa,    32'h80400123); f = f + t;
      t <- chkB("superpage fetch ok",  r10b.fault, False);         f = f + t;

      let r11 = sv32Translate(32'h10000000, DataLoad, 2'b01, satpSv32, ptw);
      t <- chkB("unmapped L1 faults", r11.fault, True); f = f + t;
      t <- chk ("unmapped L1 cause",  zeroExtend(r11.cause), 32'd13); f = f + t;

      let r12 = sv32Translate(32'h00002000, DataStore, 2'b01, satpSv32, ptw);
      t <- chkB("unmapped L0 faults", r12.fault, True); f = f + t;
      t <- chk ("unmapped L0 cause",  zeroExtend(r12.cause), 32'd15); f = f + t;

      let r13 = sv32Translate(32'hFFFFE000, DataStore, 2'b11, satpSv32, ptw);
      t <- chk ("M-mode bare pa",       r13.pa,    32'hFFFFE000); f = f + t;
      t <- chkB("M-mode bare no fault", r13.fault, False);         f = f + t;

      fails <= f;
      done  <= True;
    endrule

    rule finish (done);
      if (fails == 0) $display("[MMU-TEST] PASS - all checks ok");
      else            $display("[MMU-TEST] FAIL - %0d checks wrong", fails);
      $finish(0);
    endrule

  endmodule

endpackage
