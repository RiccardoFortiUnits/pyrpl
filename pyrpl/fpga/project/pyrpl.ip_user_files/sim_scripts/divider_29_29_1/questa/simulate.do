onbreak {quit -f}
onerror {quit -f}

vsim -lib xil_defaultlib divider_29_29_opt

do {wave.do}

view wave
view structure
view signals

do {divider_29_29.udo}

run -all

quit -force
