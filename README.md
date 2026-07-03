# DomFuzz: Combining general and directed, dominator-based fuzzing

## 1. Introduction

This Git repo provides the prototype of domfuzz.
It is based on the [Lysofuzzing framework](https://github.com/xiaobaozidi/Lysofuzzing).

The generated graphs for the paper can be found in the domfuzz_artifacts directory.
The final implementation can be found in the magma_dgf/fuzzers/domfuzzone directory.

## 2. Run Domfuzz on Magma

To run Domfuzz on the Magma benchmark, follow the [official Magma instructions](https://hexhive.epfl.ch/magma/docs/getting-started.html) to start fuzzing.

We provide a modified `magma_dgf` directory, which includes changes to the benchmark environment settings. Please use this version for compatibility.

The `magma_dgf` currently supports multiple DGFs, including:
- **Lyso**
- **Titan** 
- **SelectFuzz**
- **AFLGo**
- **FishFuzz**
- **ParmeSan**
- **Domfuzz**

To start, clone this repository on linux, and then run ```apt-get update &&
  apt-get install -y util-linux inotify-tools docker.io git```

Then navigate to the magma_dgf/tools/captain directory, and simply run the run.sh script.
This will run the fuzzers as configured for the last test, so domfuzzone, domfuzzuninstrumented and domfuzztwoinstrumented against all targets for three hours.

## 2. Gather results
Install the required dependancies for the benchd tool.
Then after running the campaign, navigate to the magma_dgf/tools directory.
Then you can save the results of the campaign in 'results.json' by running: ```python3 benchd/exp2json.py captain/workdir/ results.json```

To then generate the graphs, run ```report_df/python3 main.py output.json ./output```.
This will save the graphs in the 'magma_dgf/tools/output' directory.