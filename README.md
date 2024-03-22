# CSE 148
Optimizations: 
1.  Branch Predictor 
2.  Hardware Prefetching
3.  Value Prediction
4.  Cache Set Dueling

### Branch Predictor - Perceptron
Modified Files:
- `branch_controllver.sv`
- `verilator_main.cpp` (only custom stats)

### Hardware Prefetching - I-Cache Stream Buffer
Modified Files:
- `i_stream_buffer.sv`
- `mips_core.sv`

### Value Prediction 
Modified Files:
- `hazard_controller.sv`
- `value_prediction.sv`
- `reg_file.sv`
- `register_snapshot.sv`
- `mips_core.sv`
- `verilator_main.cpp` (only the custom stats)