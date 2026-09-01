package RVCExpand;

  import Common::*;

  Instruction rvcIll = 32'h00000000;

  function Instruction encR(Bit#(7) f7, Bit#(5) rs2, Bit#(5) rs1, Bit#(3) f3, Bit#(5) rd, Bit#(7) op)
    = { f7, rs2, rs1, f3, rd, op };
  function Instruction encI(Bit#(12) imm, Bit#(5) rs1, Bit#(3) f3, Bit#(5) rd, Bit#(7) op)
    = { imm, rs1, f3, rd, op };
  function Instruction encS(Bit#(12) imm, Bit#(5) rs2, Bit#(5) rs1, Bit#(3) f3, Bit#(7) op)
    = { imm[11:5], rs2, rs1, f3, imm[4:0], op };
  function Instruction encB(Bit#(13) imm, Bit#(5) rs2, Bit#(5) rs1, Bit#(3) f3, Bit#(7) op)
    = { imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], op };
  function Instruction encU(Bit#(32) imm, Bit#(5) rd, Bit#(7) op)
    = { imm[31:12], rd, op };
  function Instruction encJ(Bit#(21) imm, Bit#(5) rd, Bit#(7) op)
    = { imm[20], imm[10:1], imm[11], imm[19:12], rd, op };

  function Bit#(5) rvcReg(Bit#(3) x) = { 2'b01, x };
  function Bit#(12) sImm6 (Bit#(6)  v) = (v[5] == 1'b1) ? { 6'h3F, v } : { 6'h00, v };
  function Bit#(12) sImm10(Bit#(10) v) = (v[9] == 1'b1) ? { 2'b11, v } : { 2'b00, v };

  function Bit#(32) luiImm(Bit#(6) v);          // v = {c[12], c[6:2]} = nzimm[17:12]
    Bit#(14) hi = (v[5] == 1'b1) ? 14'h3FFF : 14'h0000;
    return { hi, v, 12'h000 };
  endfunction

  function Bit#(21) cjImm(Bit#(16) c);
    Bit#(11) mid = { c[12], c[8], c[10:9], c[6], c[7], c[2], c[11], c[5:3] };  // imm[11:1]
    return (c[12] == 1'b1) ? { 9'h1FF, mid, 1'b0 } : { 9'h000, mid, 1'b0 };
  endfunction

  function Bit#(13) cbImm(Bit#(16) c);
    Bit#(8) mid = { c[12], c[6:5], c[2], c[11:10], c[4:3] };                  // imm[8:1]
    return (c[12] == 1'b1) ? { 4'hF, mid, 1'b0 } : { 4'h0, mid, 1'b0 };
  endfunction

  function Instruction expandMiscAlu(Bit#(16) c);
    Bit#(5) rs1P = rvcReg(c[9:7]);   // rd' / rs1'
    Bit#(5) rs2P = rvcReg(c[4:2]);   // rs2'
    Bit#(6) i6   = { c[12], c[6:2] };
    return (case (c[11:10])
      2'b00: encR(7'b0000000, c[6:2], rs1P, 3'b101, rs1P, 7'b0010011);   // C.SRLI
      2'b01: encR(7'b0100000, c[6:2], rs1P, 3'b101, rs1P, 7'b0010011);   // C.SRAI
      2'b10: encI(sImm6(i6),           rs1P, 3'b111, rs1P, 7'b0010011);   // C.ANDI
      2'b11: (case ({ c[12], c[6:5] })
                3'b0_00: encR(7'b0100000, rs2P, rs1P, 3'b000, rs1P, 7'b0110011);   // C.SUB
                3'b0_01: encR(7'b0000000, rs2P, rs1P, 3'b100, rs1P, 7'b0110011);   // C.XOR
                3'b0_10: encR(7'b0000000, rs2P, rs1P, 3'b110, rs1P, 7'b0110011);   // C.OR
                3'b0_11: encR(7'b0000000, rs2P, rs1P, 3'b111, rs1P, 7'b0110011);   // C.AND
                default: rvcIll;                                                   // C.SUBW/ADDW (RV64)
              endcase);
      default: rvcIll;
    endcase);
  endfunction

  function Instruction expandCR(Bit#(16) c);
    Bit#(5) rdF  = c[11:7];
    Bit#(5) rs2F = c[6:2];
    return (case ({ c[12], pack(rs2F == 0) })
      2'b0_0: encR(7'b0000000, rs2F, 5'd0, 3'b000, rdF, 7'b0110011);                      // C.MV
      2'b0_1: ((rdF == 0) ? rvcIll : encI(12'd0, rdF, 3'b000, 5'd0, 7'b1100111));         // C.JR
      2'b1_0: encR(7'b0000000, rs2F, rdF,  3'b000, rdF, 7'b0110011);                      // C.ADD
      2'b1_1: ((rdF == 0) ? rvcIll : encI(12'd0, rdF, 3'b000, 5'd1, 7'b1100111));         // C.JALR (rdF==0 -> C.EBREAK)
      default: rvcIll;
    endcase);
  endfunction

  function Instruction expandRVC(Bit#(16) c);
    Bit#(5)  rdF  = c[11:7];
    Bit#(5)  rs2F = c[6:2];
    Bit#(5)  rdP  = rvcReg(c[4:2]);
    Bit#(5)  rs1P = rvcReg(c[9:7]);
    Bit#(6)  i6   = { c[12], c[6:2] };

    Bit#(12) offLW   = { 5'b0, c[5],   c[12:10], c[6], 2'b00 };            // C.LW / C.SW
    Bit#(12) off4SP  = { 2'b0, c[10:7], c[12:11], c[6], c[5], 2'b00 };     // C.ADDI4SPN
    Bit#(12) offLWSP = { 4'b0, c[3:2], c[12],    c[6:4], 2'b00 };          // C.LWSP
    Bit#(12) offSWSP = { 4'b0, c[8:7], c[12:9],  2'b00 };                  // C.SWSP
    Bit#(10) i16sp   = { c[12], c[4:3], c[5], c[2], c[6], 4'b0000 };       // C.ADDI16SP

    return (case ({ c[1:0], c[15:13] })
      5'b00_000: ((c[12:5] == 0) ? rvcIll                                          // reserved (nzuimm==0)
                                : encI(off4SP, 5'd2, 3'b000, rdP, 7'b0010011));    // C.ADDI4SPN
      5'b00_010: encI(offLW, rs1P, 3'b010, rdP, 7'b0000011);                       // C.LW
      5'b00_110: encS(offLW, rdP,  rs1P, 3'b010, 7'b0100011);                      // C.SW
      5'b01_000: encI(sImm6(i6), rdF, 3'b000, rdF, 7'b0010011);                    // C.ADDI / C.NOP
      5'b01_001: encJ(cjImm(c), 5'd1, 7'b1101111);                                 // C.JAL (RV32)
      5'b01_010: encI(sImm6(i6), 5'd0, 3'b000, rdF, 7'b0010011);                   // C.LI
      5'b01_011: ((rdF == 5'd2)
                   ? encI(sImm10(i16sp), 5'd2, 3'b000, 5'd2, 7'b0010011)           // C.ADDI16SP
                   : (((rdF == 0) || (i6 == 0)) ? rvcIll                           // C.LUI reserved
                      : encU(luiImm(i6), rdF, 7'b0110111)));                       // C.LUI
      5'b01_100: expandMiscAlu(c);                                                 // C.SRLI/SRAI/ANDI/SUB/XOR/OR/AND
      5'b01_101: encJ(cjImm(c), 5'd0, 7'b1101111);                                 // C.J
      5'b01_110: encB(cbImm(c), 5'd0, rs1P, 3'b000, 7'b1100011);                   // C.BEQZ
      5'b01_111: encB(cbImm(c), 5'd0, rs1P, 3'b001, 7'b1100011);                   // C.BNEZ

      5'b10_000: ((c[12] == 1'b1) ? rvcIll                                         // shamt[5]=1 illegal (RV32)
                                 : encR(7'b0000000, c[6:2], rdF, 3'b001, rdF, 7'b0010011)); // C.SLLI
      5'b10_010: ((rdF == 0) ? rvcIll                                              // C.LWSP rd=0 reserved
                            : encI(offLWSP, 5'd2, 3'b010, rdF, 7'b0000011));       // C.LWSP
      5'b10_100: expandCR(c);                                                      // C.JR/C.MV/C.JALR/C.ADD
      5'b10_110: encS(offSWSP, rs2F, 5'd2, 3'b010, 7'b0100011);                    // C.SWSP

      default: rvcIll;
    endcase);
  endfunction

  function Bool isCompressedParcel(Bit#(16) parcel) = (parcel[1:0] != 2'b11);

endpackage
