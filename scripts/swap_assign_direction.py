input_text = '''\
assign IO1[5] = EXTRA_IO;
assign IO1[6] = FRONT_PANEL_LED;
assign ADC_CUR_SDO[6] = IO1[7];
assign PWM_P[6] = IO1[8];
assign RESETn[6] = IO1[9];
assign PWM_N[6] = IO1[10];
assign PWM_P[3] = IO1[11];
assign RESETn[3] = IO1[12];
assign PWM_N[3] = IO1[13];
assign FAULTn[4] = IO1[14];
assign OTWn[4] = IO1[15];
assign ADC_CUR_SDO[3] = IO1[16];
assign ADC_CUR_SDO[7] = IO1[17];
assign PWM_P[7] = IO1[18];
assign RESETn[7] = IO1[19];
assign PWM_N[7] = IO1[20];
assign IO1[21] = MV_EN;
assign PWM_P[4] = IO1[22];
assign RESETn[4] = IO1[23];
wire SAFETY_CHAIN_GOOD = IO1[24];
assign PWM_N[4] = IO1[25];
wire RELAY_GOODn = IO1[26];
assign FAULTn[5] = IO1[27];
wire ESPMV_EN = IO1[28];
assign OTWn[5] = IO1[29];
wire ESPMV_GOODn = IO1[30];
assign ADC_CUR_SDO[4] = IO1[31];
wire RELAY_EN = IO1[32];

wire LVDS_TCLK = IO2[1];
assign ADC_CUR_SDO[2] = IO2[2];
wire LVDS_TDAT = IO2[3];
assign OTWn[3] = IO2[4];
assign FAULTn[3] = IO2[5];
wire LVDS_RCLK = IO2[6];
wire LVDS_RDAT = IO2[7];
assign PWM_N[2] = IO2[8];
assign IO2[9] = CONV_ADC;
assign RESETn[2] = IO2[10];
wire ADC_MV_SDO = IO2[11];
assign PWM_P[2] = IO2[12];
assign PWM_N[5] = IO2[13];
wire SCLK_ADC = IO2[14];
assign RESETn[5] = IO2[15];
wire SDI_ADC = IO2[16];
assign PWM_P[5] = IO2[17];
assign ADC_CUR_SDO[8] = IO2[18];
assign ADC_CUR_SDO[5] = IO2[19];
assign PWM_P[8] = IO2[20];
assign ADC_CUR_SDO[1] = IO2[21];
assign RESETn[8] = IO2[22];
assign OTWn[2] = IO2[23];
assign PWM_N[8] = IO2[24];
assign FAULTn[2] = IO2[25];
assign PWM_N[1] = IO2[26];
assign PWM_P[9] = IO2[27];
assign RESETn[1] = IO2[28];
assign RESETn[9] = IO2[29];
assign PWM_P[1] = IO2[30];
assign PWM_N[9] = IO2[31];
assign PWM_N[10] = IO2[32];
assign FAULTn[1] = IO2[33];
assign RESETn[10] = IO2[34];
assign OTWn[1] = IO2[35];
assign PWM_P[10] = IO2[36];
assign ADC_CUR_SDO[9] = IO2[37];
assign ADC_CUR_SDO[10] = IO2[38];'''

output = []

for line in input_text.splitlines():
    tokens = line.split(' ')
    if len(tokens) == 4 and tokens[1].startswith(('PWM_P', 'PWM_N', 'RESETn')):
            output.append(' '.join((tokens[0], tokens[3][:-1], tokens[2], tokens[1]))+';')
    else:
        output.append(line)

print('\n'.join(output))
            

