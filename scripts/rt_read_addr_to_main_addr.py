n_motors = 10
n_encoders = 7
n_boardreg = 4

case_rt_read_addr_to_main_addr = ''


case_rt_read_addr_to_main_addr += '''1: reg_raddr = \'h0; // status
2: reg_raddr = \'hb021; // digital io
3: reg_raddr = \'hb020; // temperature
'''

rt_read_addr = n_boardreg

structure = \
    (('adc_in', 0x0, n_motors),
    ('enc_pos', 0x5, n_encoders),
    ('enc_period', 0x6, n_encoders),
    ('enc_qtr1', 0x7, n_encoders),
    ('enc_qtr5', 0x9, n_encoders),
    ('enc_run', 0xa, n_encoders),
    ('motor_status', 0xc, n_motors))


for name, main_offset, n in structure:
    for i in range(n):
        case_rt_read_addr_to_main_addr += f'{rt_read_addr}: reg_raddr = \'h{((i + 1) << 4) + main_offset :02x}; // {name} {i + 1}\n'
        rt_read_addr += 1

case_rt_read_addr_to_main_addr += f'default: reg_raddr = \'d0;\n'


with open('../FPGA1394_QLA/Verilog/case_rt_read_addr_to_main_addr.v', 'w') as f:
    f.write(case_rt_read_addr_to_main_addr)


