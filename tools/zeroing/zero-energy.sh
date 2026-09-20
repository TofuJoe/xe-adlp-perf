#!/bin/bash
# Energy cost of zeroing: package energy (RAPL) per GiB cleared, bulk vs 4 KiB chunks.
R=/sys/class/powercap/intel-rapl:0/energy_uj
sudo -n cat $R >/dev/null 2>&1 || { echo "no RAPL"; exit 1; }
BIN=$(dirname "$0")/zerowork

phase() { # $1 mode, $2 seconds
	local e0 t0 e1 t1
	e0=$(sudo -n cat $R); t0=$(date +%s.%N)
	local bytes
	bytes=$("$BIN" "$1" "$2")
	e1=$(sudo -n cat $R); t1=$(date +%s.%N)
	python3 - "$e0" "$e1" "$t0" "$t1" "$bytes" "$1" <<'EOF'
import sys
e0,e1,t0,t1,b,mode=int(sys.argv[1]),int(sys.argv[2]),float(sys.argv[3]),float(sys.argv[4]),int(sys.argv[5]),sys.argv[6]
j=(e1-e0)/1e6; s=t1-t0; g=b/2**30
print(f"  {mode:<12} {g:7.1f} GiB in {s:5.2f} s  package {j:6.2f} J  "
      f"{j/g:6.3f} J/GiB  {j/s:5.2f} W")
EOF
}

idle_e0=$(sudo -n cat $R); sleep 5; idle_e1=$(sudo -n cat $R)
python3 -c "print(f'  {\"idle\":<12} {\"\":7}          5.00 s  package {($idle_e1-$idle_e0)/1e6:6.2f} J  {\"\":6}          {($idle_e1-$idle_e0)/1e6/5:5.2f} W')"
phase bulk 5
phase chunk4k 5
