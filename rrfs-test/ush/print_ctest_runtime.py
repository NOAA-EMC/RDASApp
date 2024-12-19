#!/usr/bin/env python
import os, sys

# Normal ctest output includes waiting time in the queue
# This quick utility instead prints the actual runtime

infile = '../../build/rrfs-test/Testing/Temporary/LastTest.log'
if not os.path.exists(infile):
    print(f"Error: cannot find file {infile}.")
    print(f"Did you finish running the ctests?")
    sys.exit()

test_numb = []; test_name = []; test_time = []
with open(infile, 'r') as fin:
    for line in fin:
        if 'Testing' in line:
            dat = line.split(' ')
            test_numb.append(int(dat[0][0]))
            test_name.append(dat[-1].strip())
        if 'time elapsed:' in line:
            test_time.append(line.strip())

# Loop over number of tests to print in order
ntest = len(test_numb)
for itest in range(ntest):
    # Now find the test name corresponding to this number
    for itn, tn in enumerate(test_numb):
        if itest == tn-1:
            # And find the output time corresponding to this test
            for itime, time in enumerate(test_time):
                if test_name[itn] in time:
                    runtime = time.split(' ')[-1]
                    break
            print(f'#{itest+1}: {test_name[itn]} = {runtime}')
            break
