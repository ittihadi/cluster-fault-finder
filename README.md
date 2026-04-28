# Cluster Compute Fault Finder Simulator

## Premise

In a cluster computing network of some size, there's one faulty node that's
slower than the others, isolate that faulty node assuming the following:

- Any cluster of nodes can be grouped together to perform a check
- Each check has a random time to complete, but each node should complete in
  the exact same time for each run
- The distance between nodes or the number of nodes in a cluster or sub-cluster
  doesn't affect the total time consistency
- The node that doesn't complete at the same time is the faulty node

This problem will be solved using the
[fake coin problem algorithm](fake-coin-problem.md)

## Usage

1. At the start of the program you will see a welcome screen with some
   information, click anywhere to close it
2. You will be taken to the setup screen, here you may place any number of
   computing nodes using the `Left Mouse Button`
   - To move around, hold `Space` or the `Middle Mouse Button` and drag the
     screen
   - To remove a node, hover over a node and press the `Right Mouse Button`
   - To mark a node as faulty, hover over an existing node and press the `Left
     Mouse Button`
3. Once the nodes are setup and the faulty node set, press the `Find Faulty`
   button on the top left of the screen
   - For comparison, the `Find Faulty Brute Force` button can be used to do a
     brute force solve
4. You will be taken to the visualization screen, use the `Play` button to see
   the solution step by step
   - Use the `Close` button to go back into the setup screen
   - Use the `Pause` button to pause the playback
   - Use the `Back` button to go back a step
   - Use the `Forward` button to go forward a step
   - Use the `Speed` button to change the playback speed
5. To see the instructions again, use the `Help` button on the top right to
   open the help screen

## Compiling

To compile this program, you will need an installation of
[Zig 0.16.0](https://ziglang.org/download/) in your `PATH` or somewhere valid,
afterwards simply

```sh
# Clone the repository
git clone https://github.com/ittihadi/cluster-fault-finder
cd cluster-fault-finder

# Build the application in release mode
zig build run --release=safe
```
