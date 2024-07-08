# -*- coding: utf-8 -*-
"""
Created on Wed Jun 12 09:22:33 2024

@author: lastline
# """
# from pyrpl.redpitaya import RedPitaya
# import numpy as np
# import time

# rp=RedPitaya(
#     hostname='169.254.247.107', # the ip or hostname of the board
#     port=2222,  # port for PyRPL datacommunication
#     sshport=22,  # port of ssh server - default 22
#     user='root',
#     password='root',
#     delay=0.05,  # delay between ssh commands - console is too slow otherwise
#     autostart=True,  # autostart the client?
#     reloadserver=False,  # reinstall the server at startup if not necessary?
#     reloadfpga=True,  # reload the fpga bitfile at startup?
#     filename='C:/Users/lastline/site-packages/pyrpl/fpga/red_pitaya.bin',  # name of the bitfile for the fpga, None is default file
#     serverbinfilename='red_pitaya.bin',  # name of the binfile on the server
#     serverdirname = "//opt//pyrpl//",  # server directory for server app and bitfile
#     leds_off=True,  # turn off all GPIO lets at startup (improves analog performance)
#     frequency_correction=1.0,  # actual FPGA frequency is 125 MHz * frequency_correction
#     timeout=3,  # timeout in seconds for ssh communication
#     monitor_server_name='monitor_server',  # name of the server program on redpitaya
#     silence_env=False,   # suppress all environment variables that may override the configuration?
#     gui=False  # show graphical user interface or work on command-line only?
# )
# for i in range(20):
#     rp.hk.led = int(0xff*np.random.rand(1)[0])
#     time.sleep(0.5)
# # rp.end_all()

# # import pyrpl library
# import pyrpl

# # create an interface to the Red Pitaya
# r = pyrpl.Pyrpl().rp

# r.hk.led = 0b10101010  # change led pattern

# # measure a few signal values
# print("Voltage at analog input1: %.3f" % r.sampler.in1)
# print("Voltage at analog output2: %.3f" % r.sampler.out2)
# print("Voltage at the digital filter's output: %.3f" % r.sampler.iir)

# # output a function U(t) = 0.5 V * sin(2 pi * 10 MHz * t) to output2
# r.asg0.setup(waveform='sin',
#              amplitude=0.5,
#              frequency=10e6,
#              output_direct='out2')

# # demodulate the output signal from the arbitrary signal generator
# r.iq0.setup(input='asg0',   # demodulate the signal from asg0
#             frequency=10e6,  # demodulaltion at 10 MHz
#             bandwidth=1e5)  # demodulation bandwidth of 100 kHz

# # set up a PID controller on the demodulated signal and add result to out2
# r.pid0.setup(input='iq0',
#              output_direct='out2',  # add pid signal to output 2
#              setpoint=0.05, # pid setpoint of 50 mV
#              p=0.1,  # proportional gain factor of 0.1
#              i=100,  # integrator unity-gain-frequency of 100 Hz
#              input_filter = [3e3, 10e3])  # add 2 low-passes (3 and 10 kHz)

# # modify some parameters in real-time
# r.iq0.frequency += 2.3  # add 2.3 Hz to demodulation frequency
# r.pid0.i *= 2  # double the integrator unity-gain-frequency

# # take oscilloscope traces of the demodulated and pid signal
# data = r.scope.curve(input1='iq0', input2='pid0',
#                      duration=1.0, trigger_source='immediately')

# -*- coding: utf-8 -*-
"""
Created on Mon Jun 17 18:01:10 2024

@author: lastline
"""
from pyrpl.redpitaya import RedPitaya
import numpy as np
import time
try:
    rp.end_all()
except:
    pass
rp = RedPitaya(
    hostname='169.254.132.112', # the ip or hostname of the board
    port=2222,  # port for PyRPL datacommunication
    sshport=22,  # port of ssh server - default 22
    user='root',
    password='root',
    delay=0.05,  # delay between ssh commands - console is too slow otherwise
    autostart=True,  # autostart the client?
    reloadserver=False,  # reinstall the server at startup if not necessary?
    reloadfpga=True,  # reload the fpga bitfile at startup?
    filename='fpga//red_pitaya_modified.bin',  # name of the bitfile for the fpga, None is default file
    serverbinfilename='red_pitaya.bin',  # name of the binfile on the server
    serverdirname = "//opt//pyrpl//",  # server directory for server app and bitfile
    leds_off=True,  # turn off all GPIO lets at startup (improves analog performance)
    frequency_correction=1.0,  # actual FPGA frequency is 125 MHz * frequency_correction
    timeout=3,  # timeout in seconds for ssh communication
    monitor_server_name='monitor_server',  # name of the server program on redpitaya
    silence_env=False)  # suppress all environment variables that may override the configuration?)

rp.pidnouveau0.p = -1
rp.pidnouveau0.active = True
rp.pidnouveau0.setLLinearizer(x=[-1,0,1],y=[-1,1,-1])

rp.amsnouveau.staticValue = 1.5
# rp.amsnouveau.outputSource='ramp'
rp.amsnouveau.setRamp(True, TriggerType='now', useMultiTriggers = False, IdleConfig = 'endValue')

# rp.end_all()
