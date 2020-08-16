#!/usr/bin/perl

use v5.28.0;
use warnings;
use strict;

use Getopt::Long qw(:config no_ignore_case bundling);
use Pod::Usage;

require './lib/draw_lib.pm';

use sigtrap handler => \&signal_handler, 'normal-signals';

### GATHERING OPTS
my %opts;

sub opt_assign {
    WARN("'$_[0]' already defined, using last value '$_[1]'\n") if $opts{lc($_[0])};
    $opts{lc($_[0])} = $_[1];
}

# sub { push( @{$opts{lc($_[0])}}, split(':', $_[1]) ); }
{
    local $SIG{'__WARN__'} = sub {ERROR("@_");};
    GetOptions ('TimeFormat|t=s' => \&opt_assign,
                'Xmax|X=s' => \&opt_assign,
                'Xmin|x=s' => \&opt_assign,
                'Ymax|Y=s' => \&opt_assign,
                'Ymin|y=s' => \&opt_assign,
                'Speed|S=f' => \&opt_assign,
                'Time|T=f' => \&opt_assign,
                'FPS|F=f' => \&opt_assign,
                'CriticalValue|c=s' => sub { push( @{$opts{lc($_[0])}}, split(/:(?=[xy])/, lc($_[1]))); },
                'Legend|l=s' => \&opt_assign,
                'GnuplotParams|g=s' => sub { push( @{$opts{lc($_[0])}}, split(' ', $_[1])); },
                'EffectParams|e=s' => sub { push( @{$opts{lc($_[0])}}, split(':', $_[1]) ); },
                'ConfigFile|f=s' => \&opt_assign,
                'Name|n=s' => \&opt_assign,
                'IgnoreErrors|E' => \&opt_assign,
                'Debug|d' => \&opt_assign) || pod2usage(-verbose => 1);
}

print_opts(\%opts);

# exit(10);

set_debug() if exists $opts{'debug'};
set_ignore() if exists $opts{'ignoreerrors'};

load_conf_file($opts{'configfile'}) if defined $opts{'configfile'};
merge_opts(\%opts);

print_opts(\%opts); #debug

### Define default, if not located in cli nor conf
my $speed = $opts{'speed'} if (defined $opts{'speed'});
my $time = $opts{'time'} if (defined $opts{'time'});
my $fps = $opts{'fps'} if (defined $opts{'fps'});

if($speed && $time && $fps) {
    ERROR("Choose max two from {Speed, Time, FPS}\n");
    pod2usage(-verbose => 1);
}

### Get effect params
my $splitCnt = 1;
my $color = 'red';
my $ending = 0;
my $reverse = 0;
foreach (@{$opts{'effectparams'}}) {
    if(/^split=(\d+)$/) { 
        $splitCnt = $1;
    }
    elsif(/^color=(red|green|blue)$/) {
        $color = "$1";
    }
    elsif(/^ending=(\d+)$/) {
        $ending = $1;
    }
    elsif(/^reverse=([10])$/) {
        $reverse = $1;
    }
    else {
        ERROR("Unknown EffectParam $_\n");
        pod2usage(-verbose => 1);
    }
}

$splitCnt *= 2;
my $name = defined $opts{'name'} ? $opts{'name'}
                                 : (script_name() =~ s/.pl$//r);

### GATHERING ARGS

unless (defined $ARGV[0]) {
    ERROR("Argument missing\n");
    pod2usage();
}

my $tmpDir = create_tmp_dir('.');

my ($dataFile, $lineCnt, $xMin, $xMax, $yMin, $yMax) = merge_args(\@ARGV, $opts{'timeformat'});
DEBUG("Printing merged file info:\n\tPath: $dataFile\n\t#Lines: $lineCnt\n\tXmin: $xMin\n\tXmax: $xMax\n\tYmin: $yMin\n\tYmax: $yMax\n");

$splitCnt = 1 if ($splitCnt == 0);
my @dataFiles = split_file($dataFile, $lineCnt, $splitCnt);
unlink $dataFile;
undef $dataFile;

# invert files
my $i = $reverse;
for( ; $i < $#dataFiles; $i+=2) {
    my $rev = reverse_file("$dataFiles[$i]");
    unlink "$dataFiles[$i]";
    $dataFiles[$i] = $rev;
}

my $defFPS = 25;
my $defSpeed = 1;

if($speed && $time) {
    $fps = ($lineCnt/$splitCnt)/($speed*$time);
    DEBUG("Counted FPS=$fps\n");
}
elsif($time && $fps) {
    $speed = ($lineCnt/$splitCnt)/($time*$fps);
    DEBUG("Counted Speed=$speed\n");
}
elsif($speed && $fps) {
    $time = ($lineCnt/$splitCnt)/($speed*$fps);
    DEBUG("Counted Time=$time\n");
}
elsif($speed) {
    $fps = $defFPS;
    $time = ($lineCnt/$splitCnt)/($speed*$fps);
    DEBUG("Using default FPS=$fps; counted time=$speed\n")
}
elsif($fps) {
    $speed = $defSpeed;
    $time = ($lineCnt/$splitCnt)/($speed*$fps);
    DEBUG("Using default speed=$speed; counted time=$time\n")
}
elsif($time) {
    $fps = $defFPS;
    $speed = ($lineCnt/$splitCnt)/($time*$fps);
    DEBUG("Using default FPS=$fps; counted speed=$speed\n");
}
else {
    $fps = $defFPS;
    $speed = $defSpeed;
    $time = ($lineCnt/$splitCnt)/($speed*$fps);
    DEBUG("Using default only\n");
}

DEBUG("Animation config: speed=$speed; fps=$fps; time=$time\n");
DEBUG("Files to plot in correct order '@dataFiles '\n");

my $n = length($lineCnt);

### GNUPLOT

open (my $GP, '|-', 'gnuplot 2>/dev/null') || ERROR("Could not pipe to gnuplot: $!",20);

say $GP "set terminal png size 640,480 font 'helvetica' 8";

my $wsCnt = $opts{'timeformat'} =~ tr/ //;

say $GP "set timefmt '$opts{timeformat}'";
say $GP 'set xdata time';

my $critLineLW = 3;
foreach (@{$opts{'criticalvalue'}}) {
    if(/^y=([+-]?\d+(.\d+)?)$/) {
        say $GP "set arrow from graph 0,first $1 to graph 1,first $1 nohead lw $critLineLW";
    }
    elsif(/^x=(.*)$/) {
        check_tmfmt($1, $opts{'timeformat'}) || ERROR("Wrong timeformat '$opts{'timeformat'}' of x-Critical Value '$1'\n", 8);
        say $GP "set arrow from '$1', graph 0 to '$1', graph 1 nohead lw $critLineLW";
    }
    else {
        ERROR("Unknown Crit Value '$_'\n");
        pod2usage(-verbose => 1) if ($opts{'ignoreerrors'} == 0);
    }
}

foreach (@{$opts{'gnuplotparams'}}) {
    qx {gnuplot <<< "set $_" 2>/dev/null};
    unless ($?) {
        say $GP "set $_" unless $?;
    }
    else {
        ERROR("Unknown Gnuplot param $_\n", 7);
    }
}
say $GP 'set xlabel "Time"';
say $GP 'set ylabel "Value"';
say $GP 'set y2label "Value"';
say $GP "set title '".$opts{'legend'}."'\n";
say $GP 'unset key';

## XSCALE
if ($opts{'xmax'} =~ /^auto$/) { () }
elsif ($opts{'xmax'} =~ /^max$/) { say $GP "set xrange[:'$xMax']"; }
elsif ($opts{'xmax'} =~ /^(.+)$/) {
    check_tmfmt($1, $opts{'timeformat'}) || ERROR("Wrong timeformat '$opts{'timeformat'}' of xMax '$opts{'xmax'}'\n", 10);
    say $GP "set xrange[:'$1']";
}
else {ERROR("Invalid xMax value $opts{'xmax'}\n");pod2usage(-verbose => 1) if ($opts{'ignoreerrors'} == 0);}

if ($opts{'xmin'} =~ /^auto$/) { () }
elsif ($opts{'xmin'} =~ /^min$/) { say $GP "set xrange['$xMin':]"; }
elsif ($opts{'xmin'} =~ /^(.+)$/) {
    check_tmfmt($1, $opts{'timeformat'}) || ERROR("Wrong timeformat '$opts{'timeformat'}' of xMin '$opts{'xmin'}'\n", 10);
    say $GP "set xrange['$1':]";
}
else {ERROR("Invalid xMin value $opts{'xmin'}\n");pod2usage(-verbose => 1) if ($opts{'ignoreerrors'} == 0);}


## YScale
if ($opts{'ymax'} =~ /^auto$/) { () }
elsif ($opts{'ymax'} =~ /^max$/) { say $GP "set yrange[:'$yMax']"; }
elsif ($opts{'ymax'} =~ /^([+-]?\d+(.\d+)?)$/) { say $GP "set yrange[:$1]"; }
else {ERROR("Invalid yMax value $opts{'ymax'}\n");pod2usage(-verbose => 1) if ($opts{'ignoreerrors'} == 0);}

if ($opts{'ymin'} =~ /^auto$/) { () }
elsif ($opts{'ymin'} =~ /^min$/) { say $GP "set yrange[$yMin:]"; }
elsif ($opts{'ymin'} =~ /^([+-]?\d+(.\d+)?)$/) { say $GP "set yrange[$1:]"; }
else {ERROR("Invalid yMin value $opts{'ymin'}\n");pod2usage(-verbose => 1) if ($opts{'ignoreerrors'} == 0);}


say $GP "set style lines 1 lt rgb '$color' lw 3";
say $GP "fs= '@dataFiles '";


$| = 1;

my $colCnt = $wsCnt+2;

my $limit = int(($lineCnt/($splitCnt))+1.999);
my $j = 0;
for( $i = 0; $i <= $limit ; $i+=$speed ) {
    printf $GP "set output '%s/out_%0${n}d.png'\n", $tmpDir, $j;
    ++$j;
    say $GP "plot for [file in fs] file using 1:$colCnt every ::0::$i with line ls 1";
}

close $GP || WARN("Couldn't close gnuplot\n");
undef $GP;

my $outDir = create_out_dir($name);

INFO("Creating video\n");
$ending > 0 ? INFO("Video duration approx ~ ".int($time+0.99)."s + $ending"."s freez\n")
            : INFO("Video duration approx ~ ".int($time+0.99)."s\n");


qx{ffmpeg -y -f image2 -framerate $fps -i $tmpDir/out_%0${n}d.png $outDir/anim.mp4 2>/dev/null};
ERROR("Video could not be created\n", 20) if $?;

# Add tail, if defined ending
if($ending > 0) {
    $ending += int($time);
    qx{ffmpeg -f lavfi -i nullsrc=s=640x480:d=$ending -i $outDir/anim.mp4 -filter_complex "[0:v][1:v]overlay[video]" -map "[video]" -shortest $outDir/anim_long.mp4 2>/dev/null }; 
    ERROR("Video could not be extended\n", $?>>8) if $?;
}

# Catch users sig
sub signal_handler {
    use File::Path qw(remove_tree);
    INFO ("Program was killed by user, SIG@_\n");
    my $err;
    remove_tree("$tmpDir", {error => \$err});
    remove_tree("$outDir", {error => \$err});
    close $GP if(defined $GP);
    exit (255);
}

__END__

=head1 SYNOPSIS

draw.pl [options] file|url...

=head1 DESCRIPTION

draw.pl creates animated plot from given data.
Data can be passed as an file or url.
Only http and https are supported.
It is necessary to choose correct time format.
All input data will be merged into one plot.
You can specify animation effect as seen below, the most interesting one is "split".
Ouput anim.mp4 will be stored to folder specified by -n or to './draw_i'

=head1 OPTIONS

=over 5

=item -t, --TimeFormat <strftime(3c)>

Timestamps format; default is '[%Y-%m-%d %H:%M:%S]'

=item -X, --Xmax <"auto"|"max"|vaulue>

Scale maximum of X axis; default is 'max'

=item -x, --Xmin <"auto"|"min"|vaulue>

Scale minimum of X axis; default is 'min'

=item -Y, --Ymax <"auto"|"max"|vaulue>

Scale maximum value of Y axis; default is 'auto'

=item -y, --Ymin <"auto"|"min"|vaulue>

Scale minimum value of Y axis; default is 'auto'

Max two of these tree options can be used:

=over 3

=item -S, --Speed <vaulue>

Set speed of animation; default is 1

=item -T, --Time <vaulue>

Set duration of animation; no default value

=item -F, --FPS <vaulue>

Set FPS of animation; default is 25

=back

=item -c, --CriticalValue <[xy]=value[:...]>

List of critical values. Shown as line in graph.

=item -l, --Legend <"text">

Title for graph

=item -g, --GnuplotParams <"gnuplot parameter ...">

man gnuplot

=item -e, --EffectParams <param=val:param=val>

=over 3

=item split=<value>

Set number of starting points; default is 1

=item color=<"red"|"green"|"blue">

Set color of line; defaul is 'red'

=item ending=<value>

Generates second output with freeze on last frame

=item reverse=<1|0>

Set to 1 to invert direction of lines; default is 0

=back

=item -f, --ConfigFile <"path">

Path to a config file

=item -n, --Name <"text">

Name of output folder

=item -E, --IgnoreErrors

Exit on serious error only

=item -d, --Debug

Print debug info

=back

=cut
