use v5.28.0;
use warnings;
use strict;

my ($SCRIPT_NAME) = $0 =~ (/(\w+.pl)$/);
my $DEBUG;
my $IGNORE = 0;

### GENERAL FUNCTIONS ###

sub script_name {
    return $SCRIPT_NAME;
}

# vola se po nacteni parametru z cmd line
sub set_debug {
    $DEBUG = 1;
}

sub set_ignore {
    $IGNORE = 10;
}

### LOGGIGNG FUNCTIONS ###
use Term::ANSIColor qw(:constants);
# colorful output

sub ERROR {
    print STDERR BOLD RED, "[ERROR] ", RESET . "$SCRIPT_NAME: $_[0]";
    if(defined $_[1]) {
        exit $_[1] if ($_[1] > $IGNORE);
    }
}

sub INFO {
    print BOLD GREEN, "[INFO] ", RESET . "$SCRIPT_NAME: @_";
}

sub WARN {
    print STDERR BOLD MAGENTA, "[WARNING] ", RESET . "$SCRIPT_NAME: @_";
}

sub DEBUG {
    print BOLD YELLOW, "[DEBUG] ", RESET . "$SCRIPT_NAME: @_" if $DEBUG;
}

### CONFIG FILE ###

# defautlt OPTS
my %DEFAULT = ('timeformat' => '[%Y-%m-%d %H:%M:%S]',
               'xmax' => 'max',
               'xmin' => 'min',
               'ymax' => 'auto',
               'ymin' => 'auto',
               'speed' => undef,
               'time' => undef,
               'fps' => undef,
               'criticalvalue' => undef,
               'legend' => "",
               'gnuplotparams' => undef,
               'effectparams' => undef,
               'configfile' => undef,
               'name' => undef,
               'ignoreerrors' => 0);

# Load conf to %DEFAULT
# arg1 = path/to/file.conf
sub load_conf_file {
    my $filename = defined $_[0] ? "$_[0]" 
                                 : ERROR("Missing path to config file\n". 10);

    DEBUG ("Config file specified: '$filename'\n");

    ERROR("Config file '$filename' does not exists.\n", 5) unless (-e "$filename");

    open(my $FILE, '<', $filename) || ERROR("Cannot open file '$filename' $!\n", 1);

    # save last use of directive and row
    my %redundacy;

    while (<$FILE>) {
        # ignore empty, comments, if value starts with ", read until "
        if (/^\s*(\w+)\s+(".*"|\S+)/) {
            my $key = lc($1);
            my $val = ($2 =~ s/"//r);

            ERROR("In '$filename' on line $.: Invalid directive '$key'\n", 2) unless exists $DEFAULT{$key};
            if ($key eq 'criticalvalue' or $key eq 'effectparams' ) {
                push( @{$DEFAULT{$key}}, split(':', $val) );
            }
            elsif ($key eq 'gnuplotparams') {
                push( @{$DEFAULT{$key}}, split(' ', $val) );
            }
            else {
                WARN("Double definiton of '$key' on line $redundacy{$key} in '$filename'\n") if defined $redundacy{$key};
                $redundacy{$key} = $.;
                $DEFAULT{$key} = $val;
            }
        }
    }
    close($FILE) || ERROR("Cannot close file '$filename' $!\n", 1);
}

# merge two hashes full of opts
# arg1 = Hash of cli opts
sub merge_opts {
    DEBUG("MERGING OPT HASHES\n");
    my ($opts) = defined $_[0] ? @_
                            : ERROR("Missing opts hash to merge file\n", 15);
    foreach (keys %DEFAULT) {
        next unless defined $DEFAULT{$_};
        $opts->{$_} = $DEFAULT{$_} unless defined $opts->{$_};
    }
}

# debug only, print opt hash
sub print_opts {
    return unless $DEBUG;
    my ($opts) = defined $_[0] ? @_
                               : ERROR("Missing opts hash to print\n", 15);
    DEBUG("Printing opts ...\n");

    foreach my $key (keys %$opts) {
        if ($key eq 'criticalvalue' or $key eq 'effectparams' or $key eq 'gnuplotparams') {
            say "\t\t$key -> [@$_]" foreach ($opts->{$key});
        }
        else {
            say "\t\t". $key ." -> ". $opts->{$key};
        }
    }

}

### TMP FILES ###
use File::Temp qw(tempfile tempdir);
my $TMP_DIR;

# returns name of free to use tepmporary directory
# arg1 = path/to/tmpdir 
#   if ( no argument || permission denied ) => use standard temporary /tmp
sub create_tmp_dir {

    if(defined $_[0]) {
        eval {
            local $SIG{'__WARN__'} = sub {die("");};
            $TMP_DIR = tempdir( CLEANUP => 1, DIR => "$_[0]", TEMPLATE => $SCRIPT_NAME."_XXXXX" );
        };
        if ($@) {
            WARN("Temporary directory could not be created in '$_[0]', using standard temporary directory instead\n");
        }
        else {
            return $TMP_DIR;
        }
    }

    eval {
        local $SIG{'__WARN__'} = sub {die("");};
        $TMP_DIR = tempdir( CLEANUP => 1, TMPDIR => 1, TEMPLATE => $SCRIPT_NAME."_XXXXX" );
    };
    if ($@) {
        DEBUG("$@");
        ERROR("Temporary directory could not be created in standard temporary directory\n", 15);
    }
    return $TMP_DIR;
}

# returns name of free to use tepmporary file
# arg1 = name prefix
# if no argument => prefix = 'data_'
sub create_tmp_file {

    my $template = defined $_[0] ? "$_[0]_XXXXX"
                                 : "data_XXXXX";
    my $filename;
    my $fh;

    eval {
        local $SIG{'__WARN__'} = sub {die("@_");};
        ($fh, $filename) = tempfile( DIR => $TMP_DIR, TEMPLATE => $template)
    };
    if ($@) {
        ERROR("Temporary file '$template' could not be created in '$TMP_DIR'\n", 15);
    }

    return $filename;
}

### MERGE FILES|URL TO ONE DATAFILE
use Time::Piece;

# returns timestamp and data parsed from line
# arg1 = line from file
# arg2 = time format to match
sub parse_line {
    my $line = defined $_[0] ? $_[0]
                             : ERROR("Missing line to parse\n", 15);
    my $tmfmt = defined $_[1] ? $_[1]
                              : ERROR("Missing time format parse pattern\n", 15);

    my ($timestamp, $data) = ($line =~ /(.+) ([+-]?\d+(.\d+)?+)$/);

    eval {
        $timestamp = Time::Piece->strptime($timestamp, $tmfmt)->epoch;
    };
    if ($@) {
        DEBUG("Timestamp '$timestamp' does not match format '$tmfmt'\n");
        # ERROR("Timestamp in file '$file' does not match format '$tmfmt'\n", 10);
    }
    return ($timestamp, $data);
}

# merge all filles into one from start of array
# exits if not in chronological order
# returns name of merged file, count of lines, {x,y}{max,min} values
# arg1 = array of filenames
# arg2 = time format to match
sub merge_files {
    my $files = defined $_[0] ? $_[0]
                              : ERROR("Missing file to merge\n", 15);
    my $tmfmt = defined $_[1] ? "$_[1]"
                              : ERROR("Missing time format merge pattern\n", 15);

    my ($xMax, $xMin, $yMax, $yMin, $timestamp, $data, $line);

    open(my $FILE, '<', "@$files[0]") || ERROR("Cannot open file '@$files[0]' $!\n", 15);
    chomp($line = <$FILE>) until ($line);
    ($timestamp, $data) = parse_line("$line", $tmfmt);
    $xMin = $line =~ s/ [+-]?[\d.]+$//r;
    close($FILE) || ERROR("Cannot close file '@$files[0]' $!\n", 1);

    $xMax = $timestamp;
    $yMax = $yMin = $data;

    my $mergedFile = create_tmp_file();

    open(my $MFILE, '>>', $mergedFile) || ERROR("Cannot open file '$mergedFile' $!\n", 15);

    my $lineCnt = 0;
    foreach my $file (@$files) {
        open(my $FILE, '<', $file) || ERROR("Cannot open file '$file' $!\n", 15);
        while(<$FILE>) {
            next if (/^$/);
            ++$lineCnt;
            print $MFILE $_;
            chomp;
            # say $MFILE $_;
            ($timestamp, $data) = parse_line("$_", $tmfmt);
            ERROR("x-value mishmash on line $. of '$file'\n", 8) if ($xMax > $timestamp);
            $xMax = $timestamp;
            $yMax = $data if ($data > $yMax);
            $yMin = $data if ($data < $yMin);
            $line = $_;
        }
        close($FILE) || ERROR("Cannot close file '$file' $!\n", 1);
    }

    close($MFILE) || ERROR("Cannot close file '$mergedFile' $!\n", 1);

    $xMax = $line =~ s/ [+-]?[\d.]+$//r;
    return ($mergedFile, $lineCnt, $xMin, $xMax, $yMin, $yMax);
}

# check if time data match time format
# returns 1 if ok
# arg1 = time string
# arg2 = time format to match
sub check_tmfmt {
    my $time = defined $_[0] ? $_[0]
                              : ERROR("Missing time to verify\n", 15);
    my $format = defined $_[1] ? $_[1]
                               : ERROR("Missing time format as verifying pattern\n", 15);

    eval {
        local $SIG{'__WARN__'} = sub {die "@_";};
        Time::Piece->strptime($time, $format);
    };
    if ($@) {
        return ();
    }
    return 1;
}

# take first row and try to match format
# returns epoch time, else exits
# arg1 = file to verify
# arg2 = time format to match
sub verify_file {
    my $file = defined $_[0] ? $_[0]
                             : ERROR("Missing file to verify\n", 15);
    my $tmfmt = defined $_[1] ? $_[1]
                              : ERROR("Missing time format as verifying pattern\n", 15);

    open(my $FILE, '<', $file) || ERROR("Cannot open file '$file' $!\n", 1);
    my $timestamp;
    chomp ($timestamp = <$FILE>) until ($timestamp); #kdyby soubor zacinal prazdnyma radkama
    close($FILE) || ERROR("Cannot close file '$file' $!\n", 1);
    $timestamp =~ s/ [+-]?[\d.]+$//;
    eval {
        local $SIG{'__WARN__'} = sub {die "@_";};
        $timestamp = Time::Piece->strptime($timestamp, $tmfmt)->epoch;
    };
    if ($@) {
        DEBUG("Timestamp '$timestamp' in file '$file' does not match format '$tmfmt'\n");
        ERROR("Timestamp '$timestamp' in file '$file' does not match format '$tmfmt'\n", 1);
    }
    return $timestamp;
}

# sort all input file into chronological order
# returns array of filenames
# arg1 = array of files names
# arg2 = time format to match
sub sort_files {
    my $files = defined $_[0] ? $_[0]
                             : ERROR("Missing files to sort\n", 15);
    my $tmfmt = defined $_[1] ? $_[1]
                              : ERROR("Missing time format as sorting pattern\n", 15);

    my %tmp;
    $tmp{verify_file("$_", $tmfmt)} = "$_" foreach(@$files);

    my @sorted;
    push(@sorted, $tmp{$_}) foreach(sort keys %tmp);

    return @sorted;
}

# fetch url data into tmpDir/tmpFile
# returns filename if ok, else exits
# arg1 = http||https url
sub fetch_url {
    my $url = defined $_[0] ? "$_[0]"
                            : ERROR("Missing url to fetch\n", 15);

    unless ("$url" =~ /^https?:\/\//) { # je to pravdepodobne soubor na disku
        DEBUG("'$url' does not look like http/https URL\n");
        return "$url";
    }

    my ($name) = ("$url" =~ /([\w.]+)$/); # ziskej jmeno z url
    my $tmpFile = create_tmp_file("$name");

    qx{wget --quiet --output-document="$tmpFile" "$url" 2>/dev/null};
    ERROR("Can't fetch '$url'\n", $?>>8) if $?;
    DEBUG("'$url' fetched to '$tmpFile'\n");
    return $tmpFile;
}

# take all arguments (url or file), if url => fetch
# returns array of filenames
# arg1 = ARGV
# arg2 = timeformat to match
sub merge_args {
    my ($args) = defined $_[0] ? $_[0]
                               : ERROR("Missing array of files|urls to merge\n", 15);
    my $tmfmt = defined $_[1] ? $_[1]
                              : ERROR("Missing time format as merging pattern\n", 15);

    my @files;
    push(@files, fetch_url("$_")) foreach(@$args);

    @files = sort_files(\@files, $tmfmt);
    
    return merge_files(\@files, $tmfmt);
}

# split file into tmpfiles 
# returns array of files
# arg1 = file to split
# arg2 = count of line total
# arg3 = how many subfiles should be created
sub split_file {
    my $mergedFile = defined $_[0] ? $_[0]
                                   : ERROR("Missing merged file\n", 15);
    my $lines = defined $_[1] ? $_[1]
                              : ERROR("Missing number of lines\n", 15);                               
    my $cnt = defined $_[2] ? $_[2]
                            : ERROR("Missing number of cuts\n", 15);

    if($cnt <= 0) {
        my @newFiles;
        push(@newFiles, $mergedFile);
        return @newFiles;
    }

    ERROR("Not enough lines\n", 7) if $lines < $cnt;
    $lines /= $cnt;
    ERROR("Cant create so many starting points\n", 7) if($lines < 1);
    my ($newFile, $NEWFILE);
    my @newFiles;
    open(my $MFILE, '<', "$mergedFile") || ERROR("Cannot open file '$mergedFile' $!\n", 15);
    $newFile = create_tmp_file("fragment");
    push(@newFiles, $newFile);
    my $lineNum = $lines;
    open($NEWFILE, '>>', "$newFile") || ERROR("Cannot open file '$newFile' $!\n", 15);
    while(<$MFILE>) {
        print $NEWFILE $_;
        last if eof;
        if($. == int($lineNum)) {
            $newFile = create_tmp_file("fragment");
            push(@newFiles, $newFile);
            open($NEWFILE, '>>', "$newFile") || ERROR("Cannot open file '$newFile' $!\n", 15);
            $lineNum += $lines;
        }
    }
    close($NEWFILE) || ERROR("Cannot close file '$newFile' $!\n", 1);
    close($MFILE) || ERROR("Cannot close file '$mergedFile' $!\n", 1);
    return @newFiles;
}

# take file and rewrite it in reverse order
# returns name of reversed file
# arg1 = file to reverse
sub reverse_file {
    my $file = defined $_[0] ? $_[0]
                             : ERROR("Missing file to reverse\n", 15);

    my $newFile = create_tmp_file("fragmentR");
    open(my $FILE, '<', "$file") || ERROR("Cannot open file '$file' $!\n", 15);
    open(my $NEWFILE, '>>', "$newFile") || ERROR("Cannot open file '$newFile' $!\n", 15);

    print $NEWFILE reverse <$FILE>;

    close($NEWFILE) || ERROR("Cannot close file '$newFile' $!\n", 1);
    close($FILE) || ERROR("Cannot close file '$file' $!\n", 1);
    return $newFile;
}

### OUTPUT

use File::Path qw(make_path);

# create directory name_i where i = max(i,0)+1
# returns name of new dir
# arg1 = name prefix (else base scriptname is used)
sub create_out_dir {
    my $name = defined $_[0] ? "$_[0]"
                             : ($SCRIPT_NAME =~ (s/.pl$//r));

    my $num = -1;

    while (<"$name*">) {
        if(/$name(?:_(\d+))?$/) {
            next unless(defined $1);
            $num = $1 if ($1 > $num);
        }
    }

    $name .= $num < 0 ? "_1"
                      : '_'.++$num;
    make_path("$name");
    return "$name";
}

1;