onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog ../src/project.v ../src/tiny_mce.v tb.v
vsim -c work.tb
run -all
quit -code 0
