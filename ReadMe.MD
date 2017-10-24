# AutoBench v 0.1

So this script is thrown together to solve a personal problem and for sure has many bugs and errors!

Status: **Probably broken!**


## Setup

You need a VM in your subscription to work on. You should build it and wait for it to calm down. Update the image and install your benchmark software. This example will run Cinebench R15 in single/multi CPU mode.

You will see there are 2 places for a loop to execute the benchmark - one inside the VM, one outside. Azure has a time limit of (I think) 1 hour to run a script extension therefore I moved the benchmark loop out of the script that runs inside the VM to stay within that limit on smaller VMs.

### Cycle-VMs.PS1 

contains the main loop and is the one that will modify the VM type, execute the script, then loop through the available VM types.

### Push-Autobench.PS1 

contains the logic to upload and execute the Autobench.PS1 script inside the VM

### Autobench.PS1 

contains the script to run inside the VM - waits for CPU idle, downloads and executes Cinebench