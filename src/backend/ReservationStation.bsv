package ReservationStation;

  import Common::*;
  import Vector::*;

  typedef 8 RS_SIZE;
  typedef UInt#(TLog#(RS_SIZE)) RSIdx;

  interface ReservationStationIfc;
    method Action enq(RSEntry entry);
    method ActionValue#(RSEntry) deq();
    method Bool notFull;
    method Bool notEmpty;
    method Action wakeup(PhysRegTag tag);
  endinterface

  module mkReservationStation(ReservationStationIfc);
    Vector#(RS_SIZE, Reg#(RSEntry))       payload <- replicateM(mkRegU);
    Vector#(RS_SIZE, Array#(Reg#(Bool)))  valid   <- replicateM(mkCReg(2, False));
    Vector#(RS_SIZE, Array#(Reg#(Bool)))  s1Ready <- replicateM(mkCReg(3, False));
    Vector#(RS_SIZE, Array#(Reg#(Bool)))  s2Ready <- replicateM(mkCReg(3, False));

    function Maybe#(RSIdx) firstFree();
      Maybe#(RSIdx) r = tagged Invalid;
      for (Integer i = valueOf(RS_SIZE) - 1; i >= 0; i = i - 1)
        if (!valid[i][1]) r = tagged Valid fromInteger(i);
      return r;
    endfunction

    function Maybe#(RSIdx) firstReady();
      Maybe#(RSIdx) r = tagged Invalid;
      for (Integer i = valueOf(RS_SIZE) - 1; i >= 0; i = i - 1)
        if (valid[i][0] && s1Ready[i][0] && s2Ready[i][0]) r = tagged Valid fromInteger(i);
      return r;
    endfunction

    Bool rsDebug = False;

    rule show_rs (rsDebug);
      for (Integer i = 0; i < valueOf(RS_SIZE); i = i + 1)
        if (valid[i][0])
          $display("[RS] slot %0d: op=%0d dest=p%0d src1=p%0d r=%0d src2=p%0d r=%0d rob=%0d",
                   i, payload[i].opcode, payload[i].dest,
                   payload[i].src1, s1Ready[i][0], payload[i].src2, s2Ready[i][0],
                   payload[i].robTag.idx);
    endrule

    method Action enq(RSEntry entry);
      let f = firstFree();
      $display("[RS][ENQ] opcode=%0d dest=p%0d src1=p%0d(r%0d) src2=p%0d(r%0d) rob=%0d",
               entry.opcode, entry.dest, entry.src1, entry.src1Ready,
               entry.src2, entry.src2Ready, entry.robTag.idx);
      if (f matches tagged Valid .idx) begin
        payload[idx]    <= entry;
        valid[idx][1]   <= True;             // port 1
        s1Ready[idx][2] <= entry.src1Ready;  // port 2
        s2Ready[idx][2] <= entry.src2Ready;  // port 2
        $display("[RS][ENQ] placed in slot %0d", idx);
      end else
        $display("[RS][ENQ] FAILED: RS full");
    endmethod

    method ActionValue#(RSEntry) deq();
      let r = firstReady();
      if (r matches tagged Valid .idx) begin
        valid[idx][0] <= False;              // port 0
        RSEntry e = payload[idx];
        e.src1Ready = True;
        e.src2Ready = True;
        $display("[RS][DEQ] slot %0d opcode=%0d dest=p%0d rob=%0d", idx, e.opcode, e.dest, e.robTag.idx);
        return e;
      end else begin
        $display("[RS][DEQ] attempted but no ready entry");
        return ?;
      end
    endmethod

    method Bool notFull  = isValid(firstFree());
    method Bool notEmpty = isValid(firstReady());

    method Action wakeup(PhysRegTag tag);
      for (Integer i = 0; i < valueOf(RS_SIZE); i = i + 1) begin
        if (valid[i][1]) begin
          if (payload[i].src1 == tag && !s1Ready[i][1]) begin
            s1Ready[i][1] <= True;           // port 1
            $display("[RS] wakeup: slot %0d src1 now ready (p%0d)", i, tag);
          end
          if (payload[i].src2 == tag && !s2Ready[i][1]) begin
            s2Ready[i][1] <= True;           // port 1
            $display("[RS] wakeup: slot %0d src2 now ready (p%0d)", i, tag);
          end
        end
      end
    endmethod

  endmodule
endpackage
