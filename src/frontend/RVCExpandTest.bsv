package RVCExpandTest;

  import Common::*;
  import RVCExpand::*;

  typedef 34 NumTests;

  function Tuple2#(Bit#(16), Bit#(32)) testVec(Integer i);
    return (case (i)
      0:  tuple2(16'h912a, 32'h00a10133);   // c.add       -> add   sp,sp,a0
      1:  tuple2(16'h0585, 32'h00158593);   // c.addi      -> addi  a1,a1,1
      2:  tuple2(16'h7139, 32'hfc010113);   // c.addi16sp  -> addi  sp,sp,-64
      3:  tuple2(16'h0800, 32'h01010413);   // c.addi4spn  -> addi  s0,sp,16
      4:  tuple2(16'h8ff9, 32'h00e7f7b3);   // c.and       -> and   a5,a5,a4
      5:  tuple2(16'h8b85, 32'h0017f793);   // c.andi      -> andi  a5,a5,1
      6:  tuple2(16'hc391, 32'h00078263);   // c.beqz      -> beq   a5,x0,+4
      7:  tuple2(16'he7b5, 32'h06079663);   // c.bnez      -> bne   a5,x0,+108
      8:  tuple2(16'ha001, 32'h0000006f);   // c.j         -> jal   x0,+0
      9:  tuple2(16'h28bd, 32'h07e000ef);   // c.jal       -> jal   x1,+126
      10: tuple2(16'h9782, 32'h000780e7);   // c.jalr      -> jalr  x1,0(a5)
      11: tuple2(16'h8082, 32'h00008067);   // c.jr        -> jalr  x0,0(ra)
      12: tuple2(16'h4781, 32'h00000793);   // c.li        -> addi  a5,x0,0
      13: tuple2(16'h6505, 32'h00001537);   // c.lui       -> lui   a0,0x1
      14: tuple2(16'h4d1c, 32'h01852783);   // c.lw        -> lw    a5,24(a0)
      15: tuple2(16'h40b2, 32'h00c12083);   // c.lwsp      -> lw    ra,12(sp)
      16: tuple2(16'h823e, 32'h00f00233);   // c.mv        -> add   tp,x0,a5
      17: tuple2(16'h8fd9, 32'h00e7e7b3);   // c.or        -> or    a5,a5,a4
      18: tuple2(16'h078e, 32'h00379793);   // c.slli      -> slli  a5,a5,3
      19: tuple2(16'h8499, 32'h4064d493);   // c.srai      -> srai  s1,s1,6
      20: tuple2(16'h80b1, 32'h00c4d493);   // c.srli      -> srli  s1,s1,12
      21: tuple2(16'h8f99, 32'h40e787b3);   // c.sub       -> sub   a5,a5,a4
      22: tuple2(16'hc38c, 32'h00b7a023);   // c.sw        -> sw    a1,0(a5)
      23: tuple2(16'hc606, 32'h00112623);   // c.swsp      -> sw    ra,12(sp)
      24: tuple2(16'h8ebd, 32'h00f6c6b3);   // c.xor       -> xor   a3,a3,a5
      25: tuple2(16'h0001, 32'h00000013);   // c.nop       -> addi  x0,x0,0
      26: tuple2(16'h557d, 32'hfff00513);   // c.li a0,-1  -> addi  a0,x0,-1
      27: tuple2(16'h717d, 32'hff010113);   // c.addi16sp -16
      28: tuple2(16'h77fd, 32'hfffff7b7);   // c.lui a5,0xfffff (neg)
      29: tuple2(16'hb7f5, 32'hfedff06f);   // c.j (backward)
      30: tuple2(16'hdd7d, 32'hfe050fe3);   // c.beqz (backward)
      31: tuple2(16'h9002, 32'h00000000);   // c.ebreak    -> illegal
      32: tuple2(16'h0000, 32'h00000000);   // all-zero    -> illegal
      33: tuple2(16'h2002, 32'h00000000);   // c.fldsp     -> illegal (FP)
      default: tuple2(16'h0000, 32'h00000000);
    endcase);
  endfunction

  function Bool opcodeRecognised(Instruction w);
    Bit#(7) op = w[6:0];
    return (op == 7'b0110011) || (op == 7'b0010011) || (op == 7'b0110111)
        || (op == 7'b0010111) || (op == 7'b0001111) || (op == 7'b0000011)
        || (op == 7'b0100011) || (op == 7'b1100011) || (op == 7'b1101111)
        || (op == 7'b1100111);
  endfunction

  module mkRVCExpandTest(Empty);
    Reg#(Bool) done <- mkReg(False);

    rule go (!done);
      Bit#(32) fails = 0;
      for (Integer i = 0; i < valueOf(NumTests); i = i + 1) begin
        match {.enc, .expd} = testVec(i);
        let got = expandRVC(enc);
        Bool isIll = (got == 32'h00000000);
        let d = decode(got, 32'h80000000);
        Bool decodeOk = isIll || opcodeRecognised(got);

        if (got != expd) begin
          $display("[RVC-TEST] FAIL  i=%0d  enc=%04h  expected=%08h  got=%08h", i, enc, expd, got);
          fails = fails + 1;
        end else if (!decodeOk) begin
          $display("[RVC-TEST] FAIL  i=%0d  enc=%04h  -> %08h  decodes to UNRECOGNISED opcode", i, enc, got);
          fails = fails + 1;
        end else begin
          $display("[RVC-TEST] ok    i=%0d  enc=%04h  ->  %08h  (decode opcode=%0d%s)",
                   i, enc, got, d.opcode, isIll ? " [illegal->inert]" : "");
        end
      end
      if (fails == 0)
        $display("[RVC-TEST] PASS - all %0d vectors expand + decode correctly", valueOf(NumTests));
      else
        $display("[RVC-TEST] FAIL - %0d/%0d vectors wrong", fails, valueOf(NumTests));
      done <= True;
      $finish(0);
    endrule
  endmodule

endpackage
