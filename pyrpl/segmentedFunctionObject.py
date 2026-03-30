
class segmentedFunctionObject:
	'''
		abstract class from which all the segmented functions inherit some functions from. 
		Since from the interface point of view it's not important how the segmented function 
		is implemented, let's treat all of them as similar objects
	'''
	def points(self):
		return [0],[0]
	def updateFromInterface(self, x, y):
		pass