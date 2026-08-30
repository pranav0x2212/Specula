package BranchPredictor;

  import Vector::*;
  import RegFile::*;
  import FIFO::*;
  import GetPut::*;

  typedef Bit#(32) Addr;
  typedef Bit#(2) PHTEntry; // 2-bit saturating counter: 0=StronglyNT, 3=StronglyT
  typedef Bit#(6) GlobalHistory;
  typedef Bit#(6) PHT_Index;

  typedef struct {
    Bool prediction;
    Bool isValid;
    Addr targetAddr;
  } PredictionResult deriving (Bits, Eq, FShow);

  typedef struct {
    Addr pc;
    Addr targetAddr;
    Bool taken;
    GlobalHistory newHistory;
  } BranchUpdate deriving (Bits, Eq, FShow);

  interface BranchPredictor_IFC;
    method ActionValue#(PredictionResult) predict (Addr pc);
    method Action update(BranchUpdate upd);
    method Action flushHistory;
  endinterface

  module mkBranchPredictor(BranchPredictor_IFC);
    Vector#(64, Reg#(PHTEntry)) pht <- replicateM(mkReg(1));
    Vector#(16, Reg#(Tuple3#(Bool, Bit#(24), Addr))) btb <- replicateM(mkReg(tuple3(False, 0, 0)));
    Reg#(GlobalHistory) globalHistory <- mkReg(0);

    method ActionValue#(PredictionResult) predict (Addr pc);
      PHT_Index pc_hash = truncate(pc >> 2);
      PHT_Index pht_idx = truncate(globalHistory ^ pc_hash);
      PHTEntry counter = pht[pht_idx];
      Bool predicted_taken = (counter >= 2);

      Bit#(4) btb_idx = truncate(pc >> 2);
      match {.btb_valid, .btb_tag, .btb_target} = btb[btb_idx];

      Bool btb_hit = btb_valid && (btb_tag == truncate(pc >> 6));
      Addr target = btb_hit ? btb_target : (pc + 4);

      return PredictionResult {
        prediction: predicted_taken, 
        targetAddr: predicted_taken ? target : (pc + 4),
        isValid: btb_hit && predicted_taken
      };
    endmethod

    method Action update(BranchUpdate upd);
      PHT_Index pc_hash = truncate(upd.pc >> 2);
      PHT_Index pht_idx = truncate(globalHistory ^ pc_hash);
      PHTEntry current_counter = pht[pht_idx];

      PHTEntry new_counter;
      if(upd.taken) begin
        new_counter = (current_counter == 3) ? 3 : (current_counter + 1);
      end else begin
        new_counter = (current_counter == 0) ? 0 : (current_counter - 1);
      end
      pht[pht_idx] <= new_counter;

      GlobalHistory new_history = {globalHistory[4:0], pack(upd.taken)};
      globalHistory <= new_history;

      if(upd.taken) begin
        Bit#(4) btb_idx = truncate(upd.pc >> 2);
        Bit#(24) btb_tag = truncate(upd.pc >> 6);
        btb[btb_idx] <= tuple3(True, btb_tag, upd.targetAddr);
      end
    endmethod

    method Action flushHistory;
      globalHistory <= 0;
    endmethod

  endmodule
endpackage