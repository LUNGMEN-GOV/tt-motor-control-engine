# Simulation

From this directory, run ModelSim in command-line mode:

```powershell
& 'D:\modeltech64_10.1c\win64\vsim.exe' -c -do run_modelsim.do
```

The self-checking testbench prints `TINY_MCE_TEST_PASS` when all register,
PWM, deadtime-safety, immediate-fault, encoder, capture, compare and enable
checks pass.
