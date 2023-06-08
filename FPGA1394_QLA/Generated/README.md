## How to generate MCS file from bit file using BATCH

Impact from ISE 13.4 crashes on Ubuntu 12.04, but luckily impact
has a BATCH command interface. The *GenMCSV1.cmd* (Rev 1) and *GenMCSV2.cmd* (Rev 2) contain all impact
batch commands to generate a MCS file from the bit file.

To generate, run from the *Generated* folder and run
```sh
impact -batch GenMCSV1.cmd
impact -batch GenMCSV2.cmd
```

Note that when using CMake, it is not necessary to do this manually
(MCS file generation is handled by CMake).
