set part   $::env(XPART)
set vlib   $::env(BSV_VLIB)
set syndir $::env(SYNDIR)
set repo   $::env(REPO)
set synv   $::env(SYN_V)
set outdir $::env(VIVDIR)

read_verilog -sv $vlib/SizedFIFO.v
read_verilog -sv $vlib/FIFO2.v
read_verilog -sv $syndir/bsv_blackbox.v
read_verilog -sv $repo/$synv
read_verilog -sv $syndir/specula_fpga_top.v
read_xdc $syndir/specula_syn.xdc

synth_design -top specula_fpga_top -part $part

write_checkpoint -force        $outdir/specula_synth.dcp
report_utilization             -file $outdir/utilization.rpt
report_utilization -hierarchical -file $outdir/utilization_hier.rpt
report_timing_summary -max_paths 20 -file $outdir/timing_summary.rpt
report_design_analysis -logic_level_distribution -file $outdir/logic_levels.rpt

puts "=== vivado-syn: synthesis complete; reports in $outdir ==="
