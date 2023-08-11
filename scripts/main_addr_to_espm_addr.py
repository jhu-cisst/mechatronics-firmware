n_motors = 10
n_encoders = 7
n_boardreg = 4

offset_enc_pos_blk_addr = n_boardreg + n_motors
offset_motor_status_blk_addr = offset_enc_pos_blk_addr + 5 * n_encoders

case_main_addr_to_espm_addr = ''

blk_addr = offset_enc_pos_blk_addr + n_encoders
for espm_offset, main_offset in ((2, 6), (3, 7), (4, 9), (5, 10)): # per, q1, q5, run
    for i in range(n_encoders):
        espm_bram_addr = (espm_offset << 3) + i + 1
        case_main_addr_to_espm_addr += f'{main_offset + ((i+1) << 4)}: espm_bram_raddr = \'d{espm_bram_addr};\n'
        blk_addr += 1

case_main_addr_to_espm_addr += f'default: espm_bram_raddr = \'d0;\n'

with open('../FPGA1394_QLA/Verilog/case_main_addr_to_espm_addr.v', 'w') as f:
    f.write(case_main_addr_to_espm_addr)
