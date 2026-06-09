This version of Pyrpl (Python RedPitaya Lockbox) is made to implement STCL (Scanning Transfer Cavity Loop) on a group of RedPitaya devices.

## Original PyPRL
The official PyRPL version (developed by Leonhard Neuhaus et al.) can be found at [http://pyrpl.readthedocs.io/](http://pyrpl.readthedocs.io). I suggest you get used to how the original PyRPL works before using this version

## Installation
The easiest way to use this version of PyRPL is to clone this repository, and then use pip to install it in your Python environmnent of choice. Just as with the original PyRPL version, this library requires python 3.8 or older.

If you are using an anaconda environment, run on an anaconda command prompt:
'''
conda activate <your environmnent>
cd <path of the pyrpl folder, example: C:/Git/PyRPL>
pip install -e .
'''
This ensures that only the selected environment will have this version of pyrpl installed. So, you can keep the original version of Pyrpl for other environments. Now you can execute PyrPL with the command
'''
python -m pyrpl <configuration name>
'''

If you're not using anaconda, and instead you use Python without an environment, you can run the following in a terminal
'''
cd <path of the pyrpl folder, example: C:/Git/PyRPL>
<your python executable file> -m pip install -e .
'''
and you can execute PyrPL with the command
'''
<your python executable file> -m pyrpl <configuration name>
''' 

## RedPitaya OS version
PyRPL is meant to communicate with an older version of the RedPitaya OS (<2.0). If you have a RedPitaya with a newer OS version, you will have to update its SD card, as described in [this page](https://redpitaya.readthedocs.io/en/latest/quickStart/SDcard/SDcard_advanced.html)