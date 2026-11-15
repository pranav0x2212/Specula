// Simple 5-stage in-order pipeline kept as a baseline / comparison to the OoO core
package InOrderCore;

  import Vector::*;
  import RegFile::*;
  import FIFO::*;
  import ClientServer::*;
  import GetPut::*;

  typedef Bit#(32) Instruction;
  typedef Bit#(32) Word;
  typedef Bit#(5) RegIndex;

  typedef struct {
    Bit #(7) opcode;
    RegIndex rd;
    RegIndex rs1;
    RegIndex rs2;
    Bit#(3) funct3;
    Bit#(7) funct7;
    Bit#(32) imm;
    Bit#(32) nextPC;
    Instruction raw;
  } Decoded deriving (Bits, FShow);

  // Tiny hard-coded instruction ROM
  function Bit#(32) getInstruction(Bit#(32) pc);
    case (pc)
      0: return 32'h00500113; // addi x2, x0, 5
      4: return 32'h002081B3; // add  x3, x1, x2
      8: return 32'h00000000; // nop
      12: return 32'h4062A3B3; // sub x7, x5, x6
      16: return 32'h00c2b433; // or x8, x5, x6
      20: return 32'h00c2c4b3; // xor x9, x5, x6
      24: return 32'h00c2d533; // sll x10, x5, x6
      28: return 32'h40c2e5b3; // sra x11, x5, x6
      32: return 32'hfe208ee3; // beq x1, x2, -4 (loop back)
      36: return 32'h00000000; // nop
      default: return 32'h00000013; // default: addi x0, x0, 0
    endcase
  endfunction

  function Decoded decode(Instruction i, Bit#(32) pc);
    Decoded d;
    d.opcode = i[6:0];
    d.rd = unpack(i[11:7]);
    d.funct3 = i[14:12];
    d.rs1 = unpack(i[19:15]);
    d.rs2 = unpack(i[24:20]);
    d.funct7 = i[31:25];
    d.imm = signExtend(i[31:20]);
    d.nextPC = pc + 4;

    case (d.opcode)
      7'b1100011: begin // B-type
        d.imm = signExtend({i[31], i[7], i[30:25], i[11:8], 1'b0});
      end

      7'b1101111: begin // JAL (J-type)
        d.imm = signExtend({i[31], i[19:12], i[20], i[30:21], 1'b0});
      end

      7'b1100111: begin // JALR (I-type)
        d.imm = signExtend(i[31:20]);
      end

      default: begin
        d.imm = signExtend(i[31:20]); // fallback I-type
      end
    endcase
    d.raw = i;
    return d;
  endfunction

  module mkSimpleRAM(RegFile#(Bit#(32), Bit#(32)));
    RegFile#(Bit#(32), Bit#(32)) mem <- mkRegFileFull;
    return mem;
  endmodule

  // IF > ID > EX > MEM > WB with a register file and small RAM
  module mkInOrderCore(Empty);
    Reg#(Bit#(32)) pc <- mkReg(0);
    Reg#(Bit#(3)) initState <- mkReg(0);
    RegFile#(RegIndex, Word) rf <- mkRegFileFull;
    RegFile#(Bit#(32), Bit#(32)) ram <- mkSimpleRAM;
    Reg#(Bool) flush <- mkReg(False);
    Reg#(Bool) done <- mkReg(False);
    Reg#(Bit#(32)) nextPC <- mkReg(0);
    Reg#(Bit#(32)) if_id_pc <- mkReg(0);
    Reg#(Instruction) if_id_instr <- mkReg(0);
    Reg#(Decoded) id_ex_decoded <-  mkReg(decode(32'h00000013, 0)); 
    Reg#(Tuple2#(Word, RegIndex)) ex_wb_result <- mkReg(?);
    Reg#(Tuple3#(Bit#(32), RegIndex, Bool)) mem_wb <- mkReg(?);
    Reg#(Tuple4#(Bit#(32), RegIndex, Bool, Bit#(32))) ex_mem <- mkReg(?);
    Reg#(Bool) id_ex_valid <- mkReg(False);

    // Preload a few registers with test values
    rule init1(initState == 0);
      rf.upd(1, 10); // x1 = 10 
      initState <= 1;
    endrule

    rule init2(initState == 1);
      rf.upd(2, 20); // x2 = 20
      initState <= 2;
    endrule

    rule init3(initState == 2);
      rf.upd(5, 100); // x5 = 100
      initState <= 3;
    endrule

    rule init4(initState == 3);
      rf.upd(6, 60); // x6 = 60
      initState <= 4;
    endrule

    // === Instruction Fetch ===
    rule stage_IF(initState == 4 && !done);
      if (flush) begin
        pc <= nextPC;
        if_id_instr <= 32'h00000013; // addi x0, x0, 0 (nop)
        if_id_pc <= pc;
        flush <= False;
        $display("[IF] FLUSH -> pc = %0d", nextPC);
      end else begin
        Instruction instr = getInstruction(pc);
        if_id_instr <= instr;
        if_id_pc <= pc;
        $display("[IF] pc = %0d", pc);
        pc <= pc + 4;
      end

      if (pc >= 40)
        done <= True;
    endrule

    // === Instruction Decode ===
    rule stage_ID(!done);
      if (if_id_instr != 32'h00000000) begin
        Decoded d = decode(if_id_instr, if_id_pc);
        id_ex_decoded <= d;
        id_ex_valid <= True;
      end
    endrule

    // === Execute ===
    rule stage_EX(!done && id_ex_valid);
      let d = id_ex_decoded;
      id_ex_valid <= False;
      let val1 = rf.sub(d.rs1);
      let val2 = rf.sub(d.rs2);
      Word result = 0;
      Bool isLoad = False;
      Bit#(32) storeVal = 0;

      if (d.opcode == 0 || d.raw == 32'h00000000) begin
        $display("[EX] Skipping NOP");
      end else begin
        if (d.opcode == 7'b0010011) begin
          case(d.funct3)
            3'b000: result = val1 + d.imm; // addi
            3'b111: result = val1 & d.imm; // andi
            3'b110: result = val1 | d.imm; // ori
            3'b100: result = val1 ^ d.imm; // xori
            3'b001: result = val1 << d.imm[4:0]; // slli
            default: result = 0;
          endcase
        end
        else if (d.opcode == 7'b0110011) begin
          case ({d.funct7, d.funct3})
            {7'b0000000, 3'b000}: result = val1 + val2;  // add
            {7'b0100000, 3'b000}: result = val1 - val2;  // sub
            {7'b0000000, 3'b111}: result = val1 & val2;  // and
            {7'b0000000, 3'b110}: result = val1 | val2;  // or
            {7'b0000000, 3'b100}: result = val1 ^ val2;  // xor
            {7'b0000000, 3'b001}: result = val1 << val2[4:0]; // sll
            {7'b0000000, 3'b101}: result = val1 >> val2[4:0]; // srl
            default: result = 0;
          endcase
        end

        else if (d.opcode == 7'b0000011) begin // Load
          isLoad = True;
          result = d.imm + val1; // address calculation
          end
        else if (d.opcode == 7'b0100011) begin // Store
          isLoad = False;
          storeVal = val2;
          result = d.imm + val1; // address calculation
          end

        if (d.opcode == 7'b1100011) begin // Branches
          Bool takeBranch = False;
          case (d.funct3)
            3'b000: takeBranch = (val1 == val2); // beq
            3'b001: takeBranch = (val1 != val2); // bne
          endcase
          
          if (takeBranch) begin
            flush <= True;
            nextPC <= pc + d.imm;
          end
        end
        else if (d.opcode == 7'b1101111) begin // JAL
          result = pc + 4;
          flush <= True;
          nextPC <= pc + d.imm;
        end
        else if (d.opcode == 7'b1100111) begin // JALR
          result = pc + 4;
          flush <= True;
          nextPC <= (val1 + d.imm) & ~1;
        end
        
        ex_mem <= tuple4(result, d.rd, isLoad, storeVal);
        $display("[EX] Instr: %h", d.raw);
        $display("     opcode: %b rd: %0d rs1: %0d val1: %0d rs2: %0d val2: %0d -> result: %0d", d.opcode, d.rd, d.rs1, val1, d.rs2, val2, result);
      end
    endrule

    // === Memory Access ===
    rule stage_MEM(!done);
      let { addr, rd, isLoad, storeVal } = ex_mem;

      if(isLoad) begin
        let loadVal = ram.sub(addr);
        mem_wb <= tuple3(loadVal, rd, True);
      end else begin
        ram.upd(addr, storeVal);
        mem_wb <= tuple3(0, rd, False);
      end
    endrule

    // === Write Back ===
    rule stage_WB(!done);
      let { val, rd, isLoad } = mem_wb;
      if (rd != 0 && isLoad)
        rf.upd(rd, val);
    endrule

  endmodule
endpackage