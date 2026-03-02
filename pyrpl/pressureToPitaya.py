# import sys
# def install_and_import(package):
# 	import subprocess
# 	try:
# 		__import__(package)
# 	except ImportError:
# 		try:
# 			subprocess.check_call([sys.executable, "-m", "pip", "install", package])
# 		except:
# 			subprocess.check_call([sys.executable, "-m", "pip", "install", f"py{package}"])
# 		__import__(package)

# install_and_import("ruuvitag-sensor")
# install_and_import("paramiko")

import asyncio
from ruuvitag_sensor.ruuvi import *# RuuviTagSensor
import paramiko
import pathlib
import time
from base64 import decodebytes

def find_line_starting_with_string(file_path, target_string, alsoContaining = ""):
    try:
        with open(file_path, 'r') as file:
            for line in file:
                if line.startswith(target_string) and alsoContaining in line:
                    
                    return line.strip()  # Return the line without leading/trailing spaces
        print(f"No line starting with '{target_string}' found in the file.")
        raise Exception("connection not found. Try connecting in ssh from terminal first")
    except FileNotFoundError as e:
        print(f"File '{file_path}' not found.")
        raise e
        
class ShellHandler:

	def __init__(self, host=None, user=None, psw=None, keyType=None, key=None):
		if host is not None:
			self.ssh = paramiko.SSHClient()
			self.ssh.get_host_keys().add(host, keyType, key)
			self.ssh.connect(host, username=user, password=psw)

			self.channel = self.ssh.invoke_shell()
			self.stdin = self.channel.makefile('wb')
			self.stdout = self.channel.makefile('r')

	def __del__(self):
		self.ssh.close()

	def close(self):
		self.ssh.close()
	# known_hosts_file = "C:/Users/lastline/.ssh/known_hosts"
	known_hosts_file = str(pathlib.Path.home() / ".ssh/known_hosts")
	def connect(self, ssh_siteAddress = "rp-xxxxxx.local"):
		#example of ssh_siteAddress: 
		keyData = find_line_starting_with_string(ShellHandler.known_hosts_file, 
							ssh_siteAddress, "ssh-ed25519").split(" ")[2]
		# keyData = b"""AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHTehAYPnnZWXRlnhr/4rgY/jiDpbEvyUv2JVCgHapqWm6N8mDwOV6XJxQr3gPRhGYBNi/rwfi/bkMGfIG/hpeI="""
		key = paramiko.Ed25519Key(data=decodebytes(bytes(keyData, "utf-8")))
		self.__init__(ssh_siteAddress, "root", "root", 'ssh-ed25519', key)
		self.execute("echo")
		time.sleep(.1)
		
	def standardConnection(self):
		self.connect("rp-f0be3a.local")        

	def modifiedConnection(self):
		self.connect("rp-f0be72.local")
	
	def intensityStabilization(self):
		self.connect("rp-f0bd67.local")     

	def execute(self, cmd, delayTime = 0.05):
		response = self.roughCommand(cmd,delayTime=delayTime)
		
		# Remove the command and prompt lines from the response
		lines = response.splitlines()
		# print(lines)
		#warning! when using different pitayas, check how the response is structured! you might have to change this line of code to
		#  response = '\n'.join(lines[ 2 :len(lines) - 1])
		response = '\n'.join(lines[1:len(lines) - 1])
		
		return response
	
	
	def getCurrentFolder(self, cmd, delayTime = 0.05):
		response = self.roughCommand(cmd,delayTime=delayTime)
		
		# Remove the command and prompt lines from the response
		lines = response.splitlines()
		response = '\n'.join(lines[2:len(lines) - 1])
	
	def roughCommand(self, cmd, delayTime = 0.05):
		cmd = cmd.strip('\n')
		
		# Clear any pending data in the input and output streams
		while self.channel.recv_ready():
			self.channel.recv(1024)
		
		# Write the command to the input stream
		self.stdin.write(cmd + '\n')

		# Wait for the shell prompt
		time.sleep(delayTime)  # Adjust as needed

		# Set the channel to non-blocking
		self.channel.setblocking(0)

		response = ""
		while True:
			try:
				# Attempt to receive data
				data = self.channel.recv(1024)
				if not data:
					break
				response += data.decode('utf-8')

				# Check for the shell prompt to indicate the end of the command response
				if response.endswith('# '):
					break
			except paramiko.SSHException as e:
				# Break the loop on SSHException
				break
			except Exception as e:
				# Handle other exceptions if needed
				break

		# Set the channel back to blocking
		self.channel.setblocking(1)

		return response
	

	
	def copyFile(self, localpath, remotepath):
		sftp = self.ssh.open_sftp()
		sftp.put(localpath, remotepath)
		sftp.close()
		
		
	#functions to set the values of the RAM, which will be read by the FPGA
	
	#generic function
	def pidSetValue(self, address, multiplier, value, shift=0):
		value_toFpgaNumber = int(value * multiplier) << shift
		print(f"{hex(address)}, {hex(value_toFpgaNumber)}")
		self.execute("monitor "+ str(address) + " " + str(value_toFpgaNumber))
	
	
	# def setRegister(self, address, value):
	#     self.execute("monitor "+ str(address) + " " + str(value))
		
	def setBitString(self, address, value, startBit, stringSize):#the value isn't shifted yet
		value = int(value)
		prevRegValue = int(self.execute("monitor "+ str(address)), 0x10)
		bitMask = (((1 << stringSize) - 1) << startBit)
		prevRegValue = prevRegValue & ( -1 - bitMask)#remove previous value
		value_toFpgaNumber = prevRegValue | ((value << startBit) & bitMask)
		self.execute("monitor "+ str(address) + " " + str(value_toFpgaNumber))
		
	def setBit(self, address, value, bitPosition):
		self.setBitString(address, value, bitPosition, 1)
	
	@staticmethod
	def getSignedNumber(n, bitSize):
		if n>>(bitSize-1) == 1:#negative number?
			n = n | ~((1<<bitSize) - 1)
		return n
	
	def getBitString(self, address, startBit = 0, stringSize = 32, convertToSigned = False):
		try:
			register = int(self.execute("monitor "+ str(address)), 0x10)        
		except Exception as e:
			print("check the received message in function execute()")
			print(e)
			raise Exception("check the received message in function execute()")
		bitMask = ((1 << stringSize) - 1)

		value =  (register >> startBit) & bitMask
		
		if convertToSigned:
			return ShellHandler.getSignedNumber(value, stringSize)
		else:
			return value
		
		 
	def pidSetSetPoint(self, value):
		self.pidSetValue(0x40300010, (2**23) - 1, value) 
		
	def pidSetProportional(self, value):
		self.pidSetValue(0x40300014, 2**12, value)   
	def pidSetProportional2(self, value):
		self.pidSetValue(0x40300024, 2**12, value)   
		
	def pidSetIntegral(self, value):
		self.pidSetValue(0x40300018, 2**24, value)   
	def pidSetIntegral2(self, value):
		self.pidSetValue(0x40300028, 2**24, value)   
		
	def pidSetDerivative(self, value):
		self.pidSetValue(0x4030001c, 2**10, value)  
		
	def pidDisableIntegral(self):
		self. pidSetValue(0x40300000, 1, 0xf)    

	def pidEnableIntegral(self):
		self.pidSetValue(0x40300000, 1, 0xc)
	configValValue = 0
	def pidSetLpFilter(self, enable, coefficient = 0):
		ShellHandler.configValValue = ShellHandler.configValValue & ~(1 << 13) | (enable << 13)
		self.pidSetValue(0x40300004, 1, ShellHandler.configValValue)
		self.pidSetValue(0x40300008, 2**(30), coefficient)
	def pidSetDelay(self, enable, delay = 0):
		ShellHandler.configValValue = ShellHandler.configValValue & ~((1 << 2) | (0x3FF << 3)) | (enable << 2) | (int(delay) << 3)
		self.pidSetValue(0x40300004, 1, ShellHandler.configValValue)
	def pidSetPwmSetpoint(self, enable, value = 0):
		if not enable:
			value = 0
		self.setBitString(0x40400020, value * 255 / 1.8, 16, 8)
		
	def pidSetFeedback(self, enable):
		ShellHandler.configValValue = ShellHandler.configValValue & ~(0x3 << 0) | (enable << 0)
		self.pidSetValue(0x40300004, 1, ShellHandler.configValValue)
	def pidSetSafeSwitch(self, value):
		ShellHandler.configValValue = ShellHandler.configValValue & ~(0x3 << 16) | (value << 16)
		self.pidSetValue(0x40300004, 1, ShellHandler.configValValue)
	def pidSetCommonModeReject(self, enable):
		ShellHandler.configValValue = ShellHandler.configValValue & ~(0x1 << 18) | (enable << 18)
		self.pidSetValue(0x40300004, 1, ShellHandler.configValValue)
	def pidSetPidDisabler(self, enable):
		self.setBit(0x4030000C, enable, 0)
		
	def pidSetGenFilter(self, enable, coefficientString):
		maxCoefficients = 8
		numbers, denNumSplit = extract_numbers_and_count(coefficientString)
		numbers, denNumSplit = convertToGenericFilterCoefficients(numbers, denNumSplit)
		if len(numbers) > maxCoefficients:
			raise Exception("too many coefficients!")
		
		numbers.extend([0] * (maxCoefficients - len(numbers)))
		
		ShellHandler.configValValue = ShellHandler.configValValue & ~(1 << 14) | (enable << 14)
		self.pidSetValue(0x40300004, 1, ShellHandler.configValValue)
		
		self.pidSetValue(0x40300060, 1, denNumSplit)
		for i in range(len(numbers)):
			self.pidSetValue(0x40300064 + i*4, 2**20, numbers[i])
	
	def asgSetOffset(self, enable, value=0):
		if not enable:
			value = 0
		self.pidSetValue(0x40200004, ((2**13)-1), value-1, 16)
	def asgSetOffset2(self, enable, value=0):
		if not enable:
			value = 0
		self.pidSetValue(0x40200024, ((2**13)-1), value-1, 16)
	
	def pidSetLinearizer(self, enable, samplesString):
		maxSamples = 8
		numbers, denNumSplit = extract_numbers_and_count(samplesString)
		x = np.array(numbers[0:denNumSplit])
		y = np.array(numbers[denNumSplit:])
		if(len(x) > maxSamples+1 or len(y) != len(x)):
			raise Exception("incorrect number of samples!")
		
		(s,q,m) = segmentedCoefficient(x,y)
		
		s = np.append(s,[-1] * (maxSamples - len(m)))
		q = np.append(q,[0] * (maxSamples - len(m)))
		m = np.append(m,[0] * (maxSamples - len(m)))
		
		for i in range(maxSamples):
			self.setBitString(0x403000A0 + i*8, s[i]*(2**13-1), 0, 15)
			self.setBitString(0x403000A0 + i*8, q[i]*(2**13-1), 15, 15)
			self.setBitString(0x403000A4 + i*8, m[i]*(2**24-1), 0, 32)
			
		ShellHandler.configValValue = ShellHandler.configValValue & ~(0x1 << 15) | (enable << 15)
		self.pidSetValue(0x40300004, 1, ShellHandler.configValValue)
			
	def pidSetPWMLinearizer(self, enable, samplesString):
		maxSamples = 8
		numbers, denNumSplit = extract_numbers_and_count(samplesString)
		x = np.array(numbers[0:denNumSplit])
		y = np.array(numbers[denNumSplit:])
		if(len(x) > maxSamples+1 or len(y) != len(x)):
			raise Exception("incorrect number of samples!")
		
		(s,q,m) = segmentedCoefficient(x,y)
		
		s = np.append(s,[0] * (maxSamples - len(m)))
		q = np.append(q,[0] * (maxSamples - len(m)))
		m = np.append(m,[0] * (maxSamples - len(m)))
		
		for i in range(maxSamples):
			self.setBitString(0x40400080 + i*4, s[i]*255, 0, 8)
			self.setBitString(0x40400080 + i*4, q[i]*255, 8, 8)
			self.setBitString(0x40400080 + i*4, m[i]*255, 16, 16)
			
		self.setBitString(0x40400020, enable, 3, 1)
			
	def pidSetPWMRamp(self, enable, samplesString):
		numbers, _ = extract_numbers_and_count(samplesString)
		x = np.array(numbers)
		if(len(x)  != 4):
			raise Exception("incorrect number of variables! expected format [startValue, endValue, rampTime, triggerPin]")
			
		startValue = int(x[0]*255/1.8)
		endValue = x[1]*255/1.8
		rampTime = x[2]/8e-9
		valueIncrementer = 1 if startValue < endValue else -1#let's always use the smallest incrementer possible, to have the highest resolution
			
		nOfSteps = valueIncrementer * (endValue - startValue)
		stepTime = int(rampTime / nOfSteps)
		if not enable:
			self.setBitString(0x40400020, 0x0, 0, 2)
					
		self.setBitString(0x40400040, startValue	    , 0, 8)		#PWM0_ramp_startValue
		self.setBitString(0x40400040, valueIncrementer  , 8, 8)		#PWM0_ramp_valueIncrementer
		self.setBitString(0x40400050, stepTime	        , 0, 24)	#PWM0_ramp_stepTime
		self.setBitString(0x40400050, nOfSteps			, 24, 8)	#PWM0_ramp_nOfSteps
		
		if enable:
			self.setBitString(0x40400020, x[3], 4, 4)
			self.setBitString(0x40400060, 0x3, 0, 2)
			self.setBitString(0x40400020, enable, 0, 2)
			
	
	def pidSetPWMRamp0(self, enable, samplesString):
		maxSamples = 8
		numbers, denNumSplit = extract_numbers_and_count(samplesString)
		edges = np.array(numbers[0:denNumSplit])
		times = np.array(numbers[denNumSplit:-1])
		digitalPinTrigger = numbers[-1]
		if(len(times) > maxSamples):
			raise Exception("too many samples!")
			
		if not enable:
			self.setBitString(0x40400020, 0x0, 0, 2)
			
		for i in range(len(times)):
			startValue = edges[i]*255/1.8
			endValue = edges[i+1]*255/1.8
			rampTime = times[i]/8e-9
			if startValue == endValue:
				valueIncrementer = 0
				maxStepTime = 0.10 #should be (2^24 * 8e-9) = 0.134 s, but let's use a just sligthly lower one
				nOfSteps = np.ceil(times[i] / maxStepTime)#if times[i] < maxStepTime, we'll just use a single long step
			else:
				valueIncrementer = 1 if startValue < endValue else -1#let's always use the smallest incrementer possible, to have the highest resolution
				nOfSteps = valueIncrementer * (endValue - startValue)
				
			stepTime = int(rampTime / nOfSteps)
			self.setBitString(0x40400070+i*8, startValue	    , 0, 8)		#PWM0_ramp_startValue
			self.setBitString(0x40400070+i*8, valueIncrementer  , 8, 8)		#PWM0_ramp_valueIncrementer
			self.setBitString(0x40400074+i*8, stepTime	        , 0, 24)	#PWM0_ramp_stepTime
			self.setBitString(0x40400074+i*8, nOfSteps			, 24, 8)	#PWM0_ramp_nOfSteps
					
		if enable:
			self.setBitString(0x40400060, 0x3, 0, 2)                        #PWM0 trigger = digital pin
			self.setBitString(0x40400060, 0x2, 2, 2)                        #PWM0 valueWhileIdle = currentValue (at the end of the ramps, the value will stay constant)
			self.setBitString(0x40400060, len(times), 20, 4)                #PWM0 number of ramps
			self.setBitString(0x40400020, digitalPinTrigger, 4, 4)          #PWM0 digital pin trigger
			self.setBitString(0x40400020, enable, 0, 2)                     #either enable the ramp, or use the DC value

setpointAddress = 0x40420104
setpointToBinaryRegister = 2**-13


setpointToMHzShift = 2/1800
pressureToMHzShift = -4.00688288
p0 = None#982.4945918367347
s0 = None



def setpointFromPressure(pressure):
	global pressureToMHzShift, setpointToMHzShift, setpointToBinaryRegister
	MHzShift = (pressure - p0) * pressureToMHzShift
	setpointShift = setpointToMHzShift * MHzShift / setpointToBinaryRegister
	return setpointShift + s0

async def main():
	global p0, s0
	async for found_data in RuuviTagSensor.get_data_async():
		pressure = found_data[1]["pressure"]
		if p0 is None:
			print(f"MAC: {found_data[0]}")
			print(f"Data: {found_data[1]}")
			p0 = pressure
			s0 = sh.getBitString(setpointAddress, convertToSigned=True)
			print(f"initial pressure: {p0}, initial setpoint: {hex(int(s0))}")
		setpoint = setpointFromPressure(pressure)
		print(f"pressure: {pressure}, new setpoint: {hex(int(setpoint))}")
		sh.pidSetValue(setpointAddress, 1, setpoint)


if __name__ == "__main__":	
	print("connecting to pitaya...")
	sh = ShellHandler()
	sh.connect("rp-f0be3a.local")
	print("connected to pitaya, connecting to ruuvi (might take a while...)")
	# data = RuuviTagSensor.get_data_async()
	# handle(data)
	asyncio.run(main())