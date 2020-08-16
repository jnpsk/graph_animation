## Introduction
This app draws animated graph using input data. The process of
animation drawing can be influenced by various parameters. See
included man pages `man -l ./draw_man.1` for further info.

## Project structure

```
graph_animation
+-- lib/
    +-- draw_lib.pm  module with functions definitions
+-- tests/           example input and configuration
    +-- conf/
    +-- data/
+-- output/          example output sin(x)
    +-- out_4/*.mp4
+-- draw_man.1       man page; user manual
+-- draw.pl          main file
+-- test.sh          run script
```

## Animation

Input data (local file or URL) will be divided into parts,
which results into multiple starting points in animation.
Count of this starting points is defined using argument
`--EffectParam "split=n"*` (let `n` be nonnegative integer,
if `n` equals 0 graph will be continuous from beginning).
Another interesting setup is `--EffectParam "reverse=1"`,
which reverse direction of animation.

## Logical structure

Code is well self-documented.  

1. Read input arguments
    - Module *Getopt::Long* loads command line arguments.
    - If config file is specified, its key-value pairs will
      be loaded into hash structure. That could override
      default settings. *load_conf_file($opts{'configfile'})*
    - Both input arguments will be merged. Default setup
      has the lowest priority, cmd args have highest. *merge_opts(\%opts)*

2. Prepare data source
    - Data from URL (if specified) are downloaded into local file, merged
      with specified local files (if any) and sorted into chronological
      order. During merging global maxima and minima are found, together
      with row count. *merge_args(\@ARGV, $opts{'timeformat'})*
    - Value *splitCnt* specifies number of starting points. E.g. if
      `splitCnt = n`, dataset will be divided into `2n` sets. *split_file($dataFile, $lineCnt, $splitCnt)*
    - According to *reverse* parameter, either odd-indexed or even-indexed
      sets are inverted, so it creates desired animation effect. *reverse_file*

3. Compute *speed, fps and time*
    - `speed = #lines / (splitCnt * time * fps)`
    - If *time* is set, default *fps* is used and *speed* is computed.
    - All possible combinations are allowed.

4. Run gnuplot and create animation from its output
    - `ffmpeg -y -framerate $fps -i $tmpDir/out_%0${n}d.png $outDir/anim.mp4`
    - If *ending* was specified, last frame of video is freezed for `n` seconds
