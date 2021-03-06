# Design philosophy:
# * Keep simple things simple
# * Copy paste is evil (see Clone and Modify, Snarf and Barf Programming)
# * Inputs AND CODE will inevitably change during the course of workflow execution -- the user should have the power to decide whether to ignore these changes or invalidate dependents of these changes
# * Documentation and visual representations are useful for understanding, but less so for authoring
# * Separation of workflow (defines dataflow and high-level resource requirements) from configuration (local paths to input files and low-level resource mappings such as machine names) should be easy, but not required to get up and running

# Other high-level notes:
# * CONFIG file should end up looking like a Moses EMS config
# How to insert realizations from the config file w/o including them here? | syntax?

# Global variables can be defined like this:
x=$CONFIG

# Actual machine information goes in config file
# * & specifies a tool Versioner (e.g. moses), defined in repos.txt:
#   this tool can be a binary on disk or ducttape can fetch it
#   from git/svn and then build the current version of it, remembering which revision was used
# * This also demonstrates that outputs with hardcoded output filenames
#   (e.g. Joshua's grammar extractor) can be specified in the IO declaration
# * a Submitter
# * @ specifies a key-value annotation that is associated with this step
#   these will be available as variables in the submitter and versioner
#   This allows you to specify things such as Sun Grid Engine resources (vmem)
#   TODO: How do we specify different resources for different inputs?
[g1.step1] moses < a=/home/jhclark/file b > x y=hardcoded.txt :: N=5 @vmem=32gb @cpus=8 @hostname=localhost @submitter=pbs
   cat < $a > $x
   cat < $b > hardcoded.txt
   $moses/cmd/src/moses -f x

# @@ indicates an "annotation group" that is pulled from an earlier definition or config file
# here, @@big might be annotations that describe how to schedule a job on a big machine using Torque/PBS/SGE
[g1.step2] a=$g1.step1/a b=$g1.step1/b > x y :: @@big
   cat < $a > $x
   cat < $b > $y

# This step shows the simplest way to pack (i.e. create a hyperworkflow)
# Parentheses with "(name: a=x, b=y)" indicates packing a single file
# Branch names are specified before =
# Pack name is specified before :
# Baseline is always first element by default
[g3.simplePack] in=(whichSize: smaller=$g1.step1/a, bigger=$g2.step1/b) > out
  cat < $in > $out

# Multiple *branches* are *packed* together
# Variable assignment must be done on + line
# Bash commands are listed under + line
# Hyperedges can specify *inputs* separately, but NOT outputs
# - This does lead to confusion in reports:
#   A report defaults to running for all hyperedges, unless some specializations are specified
[whichThing] a > aOut :: paramA
  # TODO: Need a better way of specifying individual inputs to packed realizations
  +baseline [choiceA] b :: param=$paramA
    cat $a $b $aOut
  +alt [choiceB] param=$x
    ln -s $a $aOut
  +alt [choiceC] param=$x
    ln -s $a $aOut
  +report reportA # Basic report, run for all non-specialized hyperedges (B/C), since only choiceA is specialized below
    echo "Line1=$(head -n1 $a)"
  +report reportA!(choiceA) # Specializations listed after ! inside () -- node not necessary, since it it always this one
    echo "Line1=$(head -n1 $a)"
    echo "Line1B=$(head -n1 $b)"

# Packing can also be done based on re-running the task multiple times
# * This can be useful when the underlying task makes calls to a random number generator (e.g. optimizers)
# * The step receives the integer ID of this trial as a parameter
# * Ducttape handles the assignment of sequential ID numbers to whichTrial by the 1..10 construction
[g2.runSeveralTimes] > x :: trial=(whichTrial: 1..10)
  echo $RANDOM > $x

# what about a simple step with only a report?  
[g2.simpleReport] a > x
  cat $a > $x
  +report reportA
    echo "Line1=$(fgrep error $x)"

# the following step will get run for each of the realizations in whichThing
[g2.doStuff] a=$g2.whichThing.a > x
   cat < $a > $b

# ! is the unpack operator
[g2.unpack] a=$g2.doStuff/a!whichThing(choiceA) > x
   cat < $a > $x

# Globbing realizations...
# $x will be a space-delimited string
[g2.globRealization] x=$g2.doStuff/a!whichThing(*) > y
  for file in $x; do echo $file; done

# Glob all output files from step1 and concatenate them
# $x is again a space-delimited string
[g2.globFiles] x=$g1.step1/* > y
  cat $x > $y

# To ease writing using subworkflows, the available inputs/outputs can be discovered by a CLI invocation
# Subworkflows' inputs and outputs can be determined by using a simple command line utility
# Any "unbound" inputs and any output can be used here
# $SUB is a reserved variable indicating that the subworkflow be used
# All branches from the subworkflow will be appended with this name to avoid conflicts
[g3.sub] < a > b
  =Makelike.simple: b=$SUB.head-5/b


# what about doing automatic/transparent compression of files (i.e. loonybin file tags)
[g5.compress-out] a > x+compress
  cat $a > $x

# this task has its input decompressed as a pre-processing step
# tag doesn't specify that it knows how to receive streamed or compressed input
[g5.slow-in] a=$g5.compress-out/x > x
  cat $a > $x

# this task receives a gzip file as input since it specifies it *can* handle that
# however, if there are multiple realizations upstream, it is *not guaranteed* to receive
# compressed input
[g5-fast-in] a:gz=$g5.compress-out/x > x
  zcat -f $a > $x

# this task receives a process substition as input since it specified that is can
# handle streaming output. this allows ducttape the most flexibility in optimization
# The actual command passed to bash will be cat <(zcat /some/file) > $x
# Unlike other file types, this substitution will be done as a string
# substition rather than a simple export at the beginning of the script 
[g5.fastest-in] a:stream=$g5.compress-out/x > x
  cat $a > $x

# this task reads a file from HDFS. the tag allows ducttape to still check that the file exists
[g5.hadoop-rw] a:hdfs > x:hdfs
  hadoop dfs -cp $a $x

# this task reads a file from HDFS that is already on HDFS[
[g5.hdfs-to-hdfs] a:hdfs=$g5.hadoop-rw/x > x:hdfs
  hadoop dfs -cp $a $x

# this task expects a normal UNIX file, but supports streaming
# so the file is streamed directly off of HDFS to the task as a bash process substitution
# The actual command run will look something like cat <(hadoop dfs -cat $a) > $x
[g5.read-plain] a:stream=$g5.hadoop-rw/x > x
  cat $a > $x

# Defining work plans to get more than just one-off experiments (this is intended primarily for config files)
+plan Basics
  # 4 experiments/realizations: all combinations of small and medium
  (whichTM: small, medium) * (whichLM: small, medium)
  # 1 experiment/realization: just the large model
  (whichLM: large) * (whichLM: large)

# TODO: User can specify shortened names when they are unambiguous. (e.g. drop a prefix of group qualifiers?)

# TODO: "Collaborative workflows"

# Fixed:
# Multiple inputs are never a problem since we change the command directly
# Comments are propagated to the UI and documentation as long as they are directly above the step
# Output parameters are available for packing steps
# $CONFIG is a reserved variable since it is in all caps

# IMPLEMENTATION:
# The resulting program should provide a lockable agenda that can be explored by:
# a depth-first or breadth-first algorithm with integrated search

# SCHEDULING CONSTRAINTS:
# Sanity checks should be done ASAP, but copies and decompression should be done with
# a set limit per machine, optionally outside of scheduling -- we must track
# how many connections there are between machines, too. (a single ducttape server per user-machine?)
# - User should be able to specify compression codec for cross-machine file transfers
