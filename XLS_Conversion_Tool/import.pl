#!/usr/bin/env perl
#
# import an Excel 2004 XML data model and report as a DT Instance

# XXX is use of namespace prefix in findvalue kosher (it could be anything)?

# XXX should sort out use of default namespace; then could use XPath and it
#     would be simpler...

# XXX for Jungo data models (in particular) should be able to handle things
#     like:
#     * InternetGatewayDevice.X_JUNGO_COM_TR_181...
#     * InternetGatewayDevice.Services.YYYService.{i}...
#     * InternetGatewayDevice...X_JUNGO_COM_YYY...
#     in the first two cases to generate TR-181i2 or Service data models, and
#     in the third case to generate a skeleton vendor-specific DM (this last
#     case is now supported)

# XXX should be able to have a go at --version from the value of DeviceSummary
#     (if present), hence --trversion via a lookup table

# XXX if DeviceInfo is there, could/should validate that the claimed profiles
#     are in fact supported

# XXX X_CISCO-COM_ or X_CISCO_COM_? doesn't matter, but consistency would be
#     nice (BBF is heading towards X_CISCO-COM_)

# XXX --reqlevel isn't really the right way to do it; could imagine integrating
#     this into DTM, e.g. "base" for MUSTs, then add the SHOULDs and then add
#     the MAYs; but this splits the functions: better to use tags / labels,
#     which links into some of the ideas being explored for the VSSBE STB (VGW)

# Begin documentation
=head1 NAME

import.pl - import Excel 2004 XML data model and report as a DT or DM Instance

=head1 SYNOPSIS

B<import.pl>
[--comment=s(comment)]
[--dm]
[--help]
[--model=s()]
[--namekey=s(Name)]
[--nooutput]
[--owner=s(owner)]
[--pedantic=i(0)]
[--phase=s(phase)]
[--reqlevel=s(may)]
[--requirement=s(requirement|support)]
[--table=s()]
[--trnum=s()]
[--trversion=s()]
[--vendormodel=s()]
[--vendorfile=s()]
[--vendorspec=s()]
[--vendorversion=s()]
[--verbose=i(0)]
[--version=s()]
Excel-2004-XML-spreadsheet...

The default action is to create a DT Instance. If the B<--dm> option is specified, a DM Instance defining the vendor extensions is created.

=head1 OPTIONS

=over

=item B<--comment=s(comment)>

a case-insensitive regular expression that determines which columns contain comments that should be included in the B<description> or B<annotation> element

=item B<--dm>

output a DM Instance containing vendor extensions

=item B<--help>

requests output of usage information

=item B<--model=s()>

the data model name; if not specified, is the first component of the first row's "Name" column (accounting for B<--namekey>)

=item B<--namekey=s(Name)>

a case-insensitive regular expression that determines which column contains the parameter and object names

=item B<--nooutput>

suppresses output of the XML

=item B<--owner=s(owner)>

a case-insensitive regular expression that determines which columns contain the owner and should be included in the B<description> or B<annotation> element

=item B<--pedantic=i(0)>

if set to a non-zero value causes more output than is enabled by B<--verbose> to be sent to B<stderr>

=item B<--phase=s(phase)>

applies only when generating DT Instances, i.e. when the B<--dm> option is not specified

a case-insensitive regular expression that determines which columns contain the phase and should be included in the B<annotation> element

=item B<--reqlevel=s(may)>

applies only when generating DT Instances

a case-independent requirement level that determines what is included in the DT; defaults to "may" (include MAY, SHOULD and MUST); can also be "should" (include only SHOULD and MUST) or "must" (include only MUST)

=item B<--requirement=s(requirement|support)>

applies only when generating DT Instances, i.e. when the B<--dm> option is not specified

a case-insensitive regular expression that determines which columns contain the requirement and should be included in the B<annotation> element

the requirement keys are also used to determine which objects and parameters to output; if the requirement (applying some heuristics) is MUST, SHOULD or MAY, the item is included; a child is included if a requirement is not specified for it but is specified for one its parents

=item B<--table=s()>

a case-insensitive regular expression that determines which table to use; if not specified or it matches multiple tables, the first matching table is used

=item B<--vendorfile=s()>

the vendor file; when generating a DM Instance this is the value of the file attribute and should also be the name of the file name (and MUST be specified); when generating a DT Instance,  if specified this is the file that is imported (and overrides the default derived from the values of the B<--trnum> and B<--trversion> options)

=item B<--vendormodel=s()>

the vendor data model name (not including the version); when generating a DM Instance this is the model that is created (and MUST be specified); when generating a DT Instance, if specified this is the model that is imported (and overrides the default, which is the value of the B<--model> option)

=item B<--vendorspec=s()>

the vendor spec; when generating a DM Instance this is the value of the spec attribute (and MUST be specified); when generating a DT Instance, if specified this is the spec that is imported (and overrides the default derived from the values of the B<--trnum> and B<--trversion> options)

=item B<--vendorversion=s()>

the vendor data model version as a string of the form "maj.min", e.g. "1.0"; when generating a DM Instance this is the model that is created (and MUST be specified); when generating a DT Instance, if specified this is the model that is imported (and overrides the default, which is the value of the B<--version> option)

=item B<--verbose=i(0)>

if set to a non-zero value causes additional output to be sent to B<stderr>

=item B<--version=s()>

the data model version as a string of the form "maj.min", e.g. "1.0"; if not specified, is derived from the table's B<Version> columns (it's the maximum version seen)

=back

=head1 LIMITATIONS

many

=cut
# End documentation

use strict;
no strict "refs";
use warnings;

# XXX uncomment to enable traceback on warnings and errors
#use Carp::Always;

use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use XML::LibXML;

use charnames ':full';
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

# command-line options
# XXX should put these into an options hash, as for publish.pl
my $comment = 'comment';
my $dm = 0;
my $help = 0;
my $model = '';
my $namekey = 'Name';
my $nooutput = 0;
my $owner = 'owner';
my $pedantic = 0;
my $phase = 'phase';
my $reqlevel = 'may';
my $requirement = 'requirement|support';
my $table = '';
my $trnum = '';
my $trversion = '';
my $vendorfile = '';
my $vendormodel = '';
my $vendorspec = '';
my $vendorversion = '';
my $verbose = 0;
my $version = '';

# main program
sub main {
    GetOptions(
        'comment:s' => \$comment,
        'dm' => \$dm,
        'help' => \$help,
        'model:s' => \$model,
        'namekey:s' => \$namekey,
        'model:s' => \$model,
        'nooutput' => \$nooutput,
        'owner:s' => \$owner,
        'pedantic' => \$pedantic,
        'phase:s' => \$phase,
        'reqlevel:s' => \$reqlevel,
        'requirement:s' => \$requirement,
        'table:s' => \$table,
        'trnum:s' => \$trnum,
        'trversion:s' => \$trversion,
        'vendorfile:s' => \$vendorfile,
        'vendormodel:s' => \$vendormodel,
        'vendorspec:s' => \$vendorspec,
        'vendorversion:s' => \$vendorversion,
        'verbose' => \$verbose,
        'version:s' => \$version) or pod2usage(2);
    pod2usage(1) if $help;
    
    if ($dm && (!$vendorfile || !$vendormodel || !$vendorspec ||
                !$vendorversion)){
        print STDERR "--dm requires --vendorfile, --vendormodel, ".
            "--vendorspec and --vendorversion\n";
        pod2usage(2);
    }

    if ($reqlevel !~ /^(may|should|must)$/i) {
        print STDERR "--reqlevel has to be 'may', 'should' or 'must'\n";
        pod2usage(2);
    }
    $reqlevel =
        ($reqlevel eq 'may') ? qr/^(may|should|must)$/i :
        ($reqlevel eq 'should') ? qr/^(should|must)$/i : qr/^(must)$/i;
    
    # parse files specified on the command line
    my $tables = [];
    foreach my $file (@ARGV) {
        my $ftables = parse_file($file);
        push @$tables, @$ftables;
    }

    # pre-process
    my $table = preprocess($tables);

    # output XML
    if (!$table) {
    } elsif ($dm) {
        output_dm_xml($table);
    } else {
        output_dt_xml($table);
    }
}

main();

# that's the end of the main program; all the rest is subroutines

# parse an Excel 2004 XML spreadsheet
sub parse_file {
    my ($file)= @_;

    print STDERR "processing file $file\n" if $verbose;

    my $ftables = [];

    # parse file
    my $parser = XML::LibXML->new();
    my $tree = $parser->parse_file($file);
    my $toplevel = $tree->getDocumentElement;

    foreach my $worksheet ($toplevel->getChildrenByLocalName('Worksheet')) {
	my $wtables = expand_Worksheet($worksheet);
        push @$ftables, @$wtables;
    }

    return $ftables;
}

# expand Worksheet
sub expand_Worksheet {
    my ($worksheet) = @_;

    my $wtables = [];

    my $name = findvalue($worksheet, '@ss:Name');
    print STDERR "expand_Worksheet $name\n" if $verbose;

    foreach my $table ($worksheet->getChildrenByLocalName('Table')) {
	my $wtable = expand_Worksheet_Table($table, $name);
        push @$wtables, $wtable if $wtable;
    }

    return $wtables;
}

# expand Worksheet Table
sub expand_Worksheet_Table {
    my ($table, $name) = @_;

    print STDERR "expand_Worksheet_Table $name\n" if $verbose;

    my $table_data = [];
    my $keys = undef;
    my $Keys = undef;
    foreach my $row ($table->getChildrenByLocalName('Row')) {
        if (!$keys) {
            ($keys, $Keys) = expand_Worksheet_Table_Header($row);
        } else {
            my $row_data = expand_Worksheet_Table_Row($keys, $row);
            push @$table_data, $row_data if $row_data;
        }
    }

    # ignore tables with no data
    my $wtable;
    if (!@$table_data) {
        print STDERR "expand_Worksheet_Table no data\n" if $verbose;
    } else {
        $wtable = {name => $name, keys => $keys, Keys => $Keys,
                   rows => $table_data};
    }

    return $wtable;
}

# expand Worksheet Table Header
# - returns two hashes; the first an array of keys to be used for labeling
#   column data, the second a hash mapping these keys to the original key
#   names
# - the keys are determined from the first row that contains at least one
#   non-empty (after stripping whitespace) cell
sub expand_Worksheet_Table_Header {
    my ($row) = @_;

    my $keys = [];
    my $Keys = {};

    my $any = 0;
    foreach my $cell ($row->getChildrenByLocalName('Cell')) {
        foreach my $data ($cell->getChildrenByLocalName('Data')) {
            my $okey = white_strip($data->textContent());
            my $key = $okey;

            # if necessary, map to canonical key names
            # XXX could generalise and warn if multiple keys match etc
            $key = 'Name' if $key =~ /$namekey/i;

            if ($key) {
                my $lkey = lc($key);
                push @$keys, $lkey;
                $Keys->{$lkey} = $okey;
                $any = 1;
            }
        }
    }

    print STDERR "expand_Worksheet_Table_Header [".join(',',@$keys)."]\n"
        if $verbose && $any;

    return $any ? ($keys, $Keys) : (undef, undef);
}

# expand Worksheet Table Row
sub expand_Worksheet_Table_Row {
    my ($keys, $row) = @_;

    my $num_keys = @$keys;

    my $hash = {};
    my $index = -1;
    foreach my $cell ($row->getChildrenByLocalName('Cell')) {

        # ss:Index is implicitly 1,2,... and overrides if present
        my $index1 = findvalue($cell, '@ss:Index');
        $index = ($index1 ne '') ? ($index1 - 1) : ($index + 1);

        foreach my $data ($cell->getChildrenByLocalName('Data')) {
            # XXX use last key if there is no key (which is probably a typo in
            #     the spreadsheet)
            # XXX this might overwrite data; should check
            my $key = ($index < $num_keys) ? $keys->[$index] : $keys->[-1];
            my $value = white_strip($data->textContent());

            $hash->{$key} = $value;
        }
    }

    # ignore if name or type is missing; perhaps this isn't a data model table
    # XXX note we don't currently attempt to concatenate data from spanned
    #     rows (which would mostly be descriptions)
    my $name = $hash->{name};
    my $type = $hash->{type};
    return undef unless $name && $type;

    # fix the name, which can contain a '>' that should be a '.'
    if ($name) {
        my $orig = $name;
        $name =~ s/\>/\./g;
        $hash->{name} = $name;
        print STDERR "expand_Worksheet_Table_Row: replaced '>' with '.' in ".
            "$orig\n" if $pedantic && $name ne $orig;
    }

    # fix the type, which can contain non-printing characters (quietly ignore
    # soft hyphens, which are very common, and probably come from having been
    # originally pasted from HTML &shy; characters!)
    if ($type) {
        $type =~ s/\N{SOFT HYPHEN}//g;
        my $orig = $type;
        $type =~ s/[[:^print:]]+//g;
        $hash->{type} = $type;
        print STDERR "expand_Worksheet_Table_Row: removed non-printing ".
            "characters from $orig\n" if $pedantic && $type ne $orig;
    }

    # fix the version number, which is numeric and might have rounding errors
    # XXX could do this unconditionally to all fields...
    my $version = $hash->{version};
    if ($version) {
        my ($major, $minor) = ($version =~ /^(\d)\d*\.?(\d?)\d*$/);
        $minor = '0' unless defined $minor && $minor ne '';
        $hash->{version} = qq{$major.$minor} if
            defined($major) && defined($minor);
    }

    # fix the requirement, which might be multi-line
    my @requirement_keys = grep {$_ =~ /$requirement/i} @$keys;
    foreach my $key (@requirement_keys) {
        $hash->{requirement} =
            white_strip($hash->{requirement},
                        {collapse => 1, ignoremultiblank => 1});
        $hash->{requirement} =~ s/(\s)/;$1/ if $hash->{requirement};        
    } 

    return $hash;
}

# find a value and tidy the resulting string
#
# white space options are passed to white_strip; other options processed
# here are:
#  - boolean: convert to boolean 0/1
#  - descr: special processing for descriptions
#
# XXX need to review all XPath usage vis a via namespaces
sub findvalue
{
    my ($node, $xpath, $opts) = @_;

    $opts->{ignoremultiblank} = $opts->{descr};
    my $string = white_strip($node->findvalue($xpath), $opts);

    # optionally convert to boolean 0/1
    if ($opts->{boolean}) {
	$string = boolean($string);
    }

    # optionally remove single newlines, change leading "-" to "*",
    # change 'value(n)' strings to 'Value' where "value" is one of the
    # possible enumerated values, and other sundry edits
    if ($opts->{descr}) {
	# XXX need to be a bit cleverer, e.g. retaining the list nature where
	#     indentation is used to set off items (including use of leading
	#     "--" characters)
	# XXX also doesn't catch cases where an enumerated value is referenced
	#     in another parameter's description
	$string =~ s/([^\n])\n/$1 /g;
	$string =~ s/\n-/\n*/g;
	foreach my $tvalue (@{$opts->{values}->{values}}) {
	    my $value = $tvalue->{value};
	    $string =~ s/(\s+)$value\(\d+\)/$1\"$value\"/ig;
	    $string =~ s/[\'\"]$value[\'\"]/\"$value\"/ig;
	}
        # change `word' and 'word' to "word"
        # XXX doesn't catch 'on top of' (for example)
        $string =~ s/(\W)[\`\'](\S+)\'(\W)/$1\"$2\"$3/g;

	$string =~ s/(false|true)\(\d+\)/$1/g;
	$string =~ s/\bdeprecated\b/DEPRECATED/g;
    }

    return $string;
}

# strip leading and trailing white space and, optionally, other space
sub white_strip
{
    my ($string, $opts) = @_;

    return undef unless defined $string;

    # always remove leading and trailing white space
    my $orig = $string;
    $string =~ s/^\s*//g;
    $string =~ s/\s*$//g;
    print STDERR "white_strip: removed leading/trailing white space in ".
        "$orig\n" if $pedantic > 1 && $string ne $orig;

    # also any spaces or tabs after newlines
    $orig = $string;
    $string =~ s/\n[ \t]*/\n/g;
    print STDERR "white_strip: removed white space after newlines in ".
        "$orig\n" if $pedantic > 1 && $string ne $orig;

    # optionally ignore multiple blank lines (usually a formatting error)
    $orig = $string;
    $string =~ s/\n([ \t]*\n){2,}/ /gs if $opts->{ignoremultiblank};
    print STDERR "white_strip: ignored multiple blank lines in ".
        "$orig\n" if $pedantic > 1 && $string ne $orig;

    # optionally collapse multiple spaces
    $orig = $string;
    $string =~ s/\s+/ /g if $opts->{collapse};
    print STDERR "white_strip: collapsed multiple spaces in ".
        "$orig\n" if $pedantic > 1 && $string ne $orig;

    # optionally remove all white space
    if ($opts->{black}) {
	$orig = $string;
	$string =~ s/\s+//g;
	print STDERR "white_strip: had to remove extra spaces in $orig\n" if
	    $pedantic > 1 && $opts->{blackwarn} && $string ne $orig;
    }

    return $string;
}

# return 0/1 given string representation of boolean
sub boolean {
    my ($value) = @_;
    return ($value && $value =~ /1|t|y|true|yes/i) ? 1 : 0;
}

# parse first part of requirement string, returning one of the following
# (checked in this order):
# undef:      undefined
# MUST:       "MUST"
# MUST NOT:   "MUST NOT" or "N/A"
# SHOULD:     "SHOULD"
# SHOULD NOT: "SHOULD NOT" or "IN_FUTURE"
# MAY:        "MAY"
# MUST:       true as determined by boolean()
# MUST NOT:   otherwise
sub requirement {
    my ($value) = @_;

    return undef unless defined $value;

    # determine "first part" of requirement string
    $value = white_strip($value);
    $value =~ s/MUST NOT/MUST_NOT/;
    $value =~ s/SHOULD NOT/SHOULD_NOT/;
    $value =~ s/\s.*//;

    return "MUST"       if $value =~ /^MUST$/i;
    return "MUST NOT"   if $value =~ /^(MUST_NOT|N\/A)$/i;
    return "SHOULD"     if $value =~ /^SHOULD$/i;
    return "SHOULD NOT" if $value =~ /^(SHOULD_NOT|IN_FUTURE)$/i;
    return "MAY"        if $value =~ /^MAY$/i;
    return "MUST"       if boolean($value);
    return "MUST NOT";
}

# output multi-line string to stdout, handling indentation
# XXX should take additional indentation from first line and ignore in
#     subsequent lines (would avoid special annotation formatting)
# XXX no, the above is wrong; the right way to do it is to use separate
#     invocations for <annotation>, $annotation and </annotation> (see
#     map.pm)
sub output
{
    my ($indent, $lines) = @_;

    return if $nooutput;

    # ignore initial and final newlines (cosmetic)
    $lines =~ s/^\n?//;
    $lines =~ s/\n?$//;

    foreach my $line (split /\n/, $lines) {
        print '  ' x $indent, $line, "\n";
    }
}

# pre-process in preparation for generating XML
sub preprocess {
    my ($tables) = @_;
 
    # filter tables and check that only one matches
    my @tables = grep {!$table || $_->{name} =~ /$table/i} @$tables;
    my $num_tables = @tables;
    if ($num_tables == 0) {
        print STDERR "no table names match \"$table\"\n";
        return;
    }
    if ($num_tables > 1) {
        print STDERR "$num_tables table names match \"$table\"; ".
            "used \"$tables[0]->{name}\" (the first one)\n";
    }

    # select the first table
    my $table = $tables[0];
    my $tname = $table->{name};
    my $keys = $table->{keys};
    my $Keys = $table->{Keys};
    my $rows = $table->{rows};

    print STDERR "preprocess table $tname\n" if $verbose;

    # if not specified on the command line, determine the DM model name
    if (!$model) {
        $model = $rows->[0]->{name};
        $model =~ s/\..*//;
    }
    if (!$model) {
        print STDERR "couldn't determine DM model name (use --model)\n";
        return;
    }

    print STDERR "preprocess model $model\n" if $verbose;

    # if not specified on the command line, determine the DM version
    if (!$version) {
        my $majmax = -1;
        my $minmax = -1;
        foreach my $row (@$rows) {
            my $version = $row->{version};
            next unless defined($version);
            
            my ($major, $minor) = ($version =~ /(\d+)\.(\d+)/);
            next unless defined($major) && defined($minor);
            
            if ($major > $majmax || ($major == $majmax && $minor > $minmax)) {
                $majmax = $major;
                $minmax = $minor;
            }
        }
        $version = qq{$majmax.$minmax} if $majmax != -1 && $minmax != -1;
    }
    if (!$version) {
        print STDERR "couldn't determine DM version (use --version)\n";
        return;
    }

    print STDERR "preprocess version $version\n" if $verbose;

    # if not specified on the command line, determine TR number
    if (!$trnum) {
        $trnum = '098' if $model eq 'InternetGatewayDevice';
        $trnum = '104' if $model eq 'VoiceService';
        $trnum = '135' if $model eq 'STBService';
        $trnum = '140' if $model eq 'StorageService';
        $trnum = '181' if $model eq 'Device';
        $trnum = '196' if $model eq 'FAPService';
    }
    if (!$trnum) {
        print STDERR "couldn't determine TR number (use --trnum)\n";
        return;
    }

    print STDERR "preprocess trnum $trnum\n" if $verbose;

    # if not specified on the command line, determine TR version
    if (!$trversion) {
        $trversion = $version;
    }

    print STDERR "preprocess trversion $trversion\n" if $verbose;

    # map object/parameter name to row object
    # XXX actually only works for objects; luckily that's all that's needed
    my $row_map = {};
    foreach my $row (@$rows) {
        my $name = $row->{name};
        $row_map->{$name} = $row;
    }

    # populate row objects with "parent" references
    # XXX should also maintain a list of children
    my $trows = [];
    my $object_name;
    foreach my $row (@$rows) {
        my $name = $row->{name};

        my $parent_name;
        if ($name =~ /[^\.]$/) {
            if ($name =~ /\./) {
                ($object_name, $name) = ($name =~ /(.*\.)(.*)/);
                $row->{name} = $name;
            }
            print STDERR "parameter $name with unknown parent\n"
                unless $object_name;
            $parent_name = $object_name;
        } else {
            $parent_name = $object_name = $name;
            $parent_name =~ s/\.\{/\{/g;
            $parent_name =~ s/[^\.]*\.?$//;
            $parent_name =~ s/\{/\.\{/g;
        }

        my $parent;
        if (!$parent_name) {
            $parent = undef;
        } else {
            $parent = $row_map->{$parent_name};
            if (!$parent) {

                # XXX need to deal with multiple levels of non-existent parent
                #my @parent_comps = split /\./, $parent_name;
                #my $sara = \@parent_comps;
                #print STDERR "$parent_name: ", Dumper($sara);

                # XXX have to assume not writable (add some heuristics)
                $parent = {
                    name => $parent_name,
                    type => 'object',
                    write => 0
                };
                push @$trows, $parent;
                $row_map->{$parent_name} = $parent;
            }
        }

        $row->{parent} = $parent;
        push @$trows, $row;
    }

    # replace rows with the new list that includes auto-created object rows
    $table->{rows} = $trows;

    # populate row objects with path fields
    my $paths = {};
    foreach my $row (@$trows) {
        my $name = $row->{name};
        my $type = $row->{type};
        my $parent = $row->{parent};

        my $parent_name = $parent->{name} || '';

        my $path = ($type eq 'object') ? $name : qq{$parent_name$name};

        $row->{path} = $path;

        if ($paths->{$path}) {
            print STDERR "duplicate $path ignored\n";
            $row->{ignored} = 1;
        }
        $paths->{$path} = 1;
    }

    return $table;
}

# check whether to include a row in the DM XML
sub include_dm_row {
    my ($table, $row) = @_;

    # always include vendor extensions
    return 1 if $row->{path} =~ /^X_|\.X_/;

    # need also to check for objects that contain vendor extensions
    # XXX would like to be able to do this without searching
    my $trows = $table->{rows};
    foreach my $trow (@$trows) {
        next unless $trow->{parent};
        return 1 if $trow->{parent} == $row &&
            $trow->{path} =~ /^X_|\.X_/ &&
            $trow->{path} =~ /[^\.]$/;
    }

    return 0;
}

# check whether to include a row in the DT XML
#
# not all rows are labelled, so interpret <Empty> as meaning "include" if
# (and only if) no parent object is excluded
sub include_dt_row {
    my ($row, $requirement_keys) = @_;

    my $include = 1;

    # XXX check for name is a guard against unintended autovivification
    if ($row && $row->{name}) {
        my $name = $row->{name};

        # XXX this is surely more complicated than is necessary...
        my $defined = undef;
        foreach my $key (@$requirement_keys) {
            my $value = $row->{$key};
            if (defined $value) {
                if (requirement($value) =~ /$reqlevel/) {
                    $defined = 1;
                } else {
                    $defined = 0 if !defined($defined);
                }
            }
        }

        if (defined $defined) {
            $include = 0 if !$defined;
        } else {
            $include = 0 if !include_dt_row($row->{parent}, $requirement_keys);
        }
    }

    return $include;
}

# output DM XML
sub output_dm_xml {
    my ($table) = @_;

    my $tname = $table->{name};
    my $keys = $table->{keys};
    my $Keys = $table->{Keys};
    my $rows = $table->{rows};

    # determine names of columns that contain info to be included in
    # description elements
    my @owner_keys =  grep {$_ =~ /$owner/i} @$keys;
    my @comment_keys =  grep {$_ =~ /$comment/i} @$keys;
    my @description_keys = (@owner_keys, @comment_keys);
    print STDERR "output_dm_xml description_keys [".
        join(',',@description_keys)."]\n" if $verbose;

    # determine DM file name and spec for the imported BBF standard data model
    my $tversion = $trversion;
    $tversion =~ s/\./-/;
    my $bbffile = qq{tr-$trnum-$tversion.xml};
    my $bbfspec = qq{urn:broadband-forum-org:tr-$trnum-$tversion};

    # output DM header
    # XXX shouldn't hard-code DM version
    output 0, qq{<?xml version="1.0" encoding="UTF-8"?>};
    output 0, qq{
<dm:document xmlns:dm="urn:broadband-forum-org:cwmp:datamodel-1-5"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="urn:broadband-forum-org:cwmp:datamodel-1-5
                 http://www.broadband-forum.org/cwmp/cwmp-datamodel-1-5.xsd
                              urn:broadband-forum-org:cwmp:datamodel-report-0-1
                 http://www.broadband-forum.org/cwmp/cwmp-datamodel-report.xsd"
             file="$vendorfile" spec="$vendorspec">
  <description>
    $tname table: vendor extensions
  </description>
};

    # output DM import and model elements  
    output 1, qq{
<import file="$bbffile" spec="$bbfspec">
  <model name="$model:$version"/>
</import>
<model name="$vendormodel:$vendorversion" base="$model:$version">
};

    # output rows
    my $object_active = 0;
    foreach my $row (@$rows) {
        my $path = $row->{path};
        my $name = $row->{name};
        my $type = $row->{type};
        my $write = $row->{write};

        # check whether row is being ignored
        next if $row->{ignored};
        
        # check whether to include this row
        my $include = include_dm_row($table, $row);
        next unless $include;

        # determine info to put into the description
        my @defined_keys = grep {defined $row->{$_}} @description_keys;
        my @description = map {
            ($Keys->{$_} ne 'Description' ? qq{$Keys->{$_}: } : qq{}) .
                qq{$row->{$_}}
        } @defined_keys;
        my $description = qq{};
        if (@description) {
            $description = qq{};
            foreach my $line (@description) {
                $description .= qq{\n} if $description;
                $description .= $line;
            }
            $description = xml_escape($description);
        }

        # output object
        my $namebase = ($path=~ /\.X_/) ? 'name' : 'base';
        if ($type eq 'object') {
            my $access = ($write eq 'W') ? qq{readWrite} : qq{readOnly};
            my $multi = ($path =~ /\.\{i\}\.$/);
            my $minEntries = $multi ? qq{0} : qq{1};
            my $maxEntries = $multi ? qq{unbounded} : qq{1};
            output 2, qq{</object>} if $object_active;
            output 2, qq{<object $namebase="$path" access="$access" }.
                qq{minEntries="$minEntries" maxEntries="$maxEntries">};
            output 3, qq{
<description>
  $description
</description>
} if $description;
            $object_active = 1;
        }

        # output parameter
        else {
            my $access = ($write eq 'W') ? qq{readWrite} : qq{readOnly};
            output 3, qq{<parameter name="$name" access="$access">};
            output 4, qq{
<description>
  $description
</description>
} if $description;
            # XXX need to do more with type information; could use some of
            #     the tr2dm.pl logic; for now, heuristic hacks
            my $min;
            my $max;
            my @values;
            if ($type =~ /^string/) {
                ($type, my $rest) = $type =~ /([^\(:]+)(.*)/;
                ($max) = $rest =~ /^\((.*)\)/;
                my ($values) = $rest =~ /^:\s*(.*)/;
                @values = split ',', $values if $values;
            } else {
                ($type, my $range) = $type =~ /([^\[]+)(.*)/;
                ($min, $max) = $range =~ /^\[([^:]*):(.*)\]/;
            }
            output 4, qq{
<syntax>
  <$type>
};
            if ($type eq 'string' && defined $max) {
                output 6, qq{
<size maxLength="$max"/>
};
            }
            if ($type eq 'string' && @values) {
                foreach my $value (@values) {
                    ($value, my $code) = $value =~ /^([^\(]*)\(?([^\)]*)/;
                    $code = defined $code && $code ne '' ?
                        qq{ code="$code"} : qq{};
                    output 6, qq{
<enumeration value="$value"$code/>
};
                }
            }
            if ($type ne 'string' && (defined $min || defined $max)) {
                $min = defined $min && $min ne '' ?
                    qq{ minInclusive="$min"} : qq{};
                $max = defined $max && $max ne '' ?
                    qq{ maxInclusive="$max"} : qq{};
                output 6, qq{
<range$min$max/>
};
            }
            output 4, qq{
  </$type>
</syntax>
};
            output 3, qq{</parameter>};
        }
    }

    # close final object
    output 2, qq{</object>} if $object_active;

    # close model element
    output 1, qq{</model>};

    # close root element
    output 0, qq{</dm:document>};
}

# output DT XML
sub output_dt_xml {
    my ($table) = @_;

    my $tname = $table->{name};
    my $keys = $table->{keys};
    my $Keys = $table->{Keys};
    my $rows = $table->{rows};

    # determine DM file name, spec, model and version; each of these can be
    # overridden by a command-line option
    my $tversion = $trversion;
    $tversion =~ s/\./-/;
    my $dmfile = $vendorfile ? $vendorfile :
        qq{tr-$trnum-$tversion.xml};
    my $dmspec = $vendorspec ? $vendorspec :
        qq{urn:broadband-forum-org:tr-$trnum-$tversion};
    my $dmmodel = $vendormodel ? $vendormodel : $model;
    my $dmversion = $vendorversion ? $vendorversion : $version;

    # determine names of columns that indicate whether object/parameter is
    # required and so should be included in the DT instance
    my @requirement_keys = grep {$_ =~ /$requirement/i} @$keys;
    print STDERR "output_dt_xml requirement_keys [".
        join(',',@requirement_keys)."]\n" if $verbose;

    # determine names of columns that contain info to be included in
    # annotation elements
    my @owner_keys =  grep {$_ =~ /$owner/i} @$keys;
    my @phase_keys =  grep {$_ =~ /$phase/i} @$keys;
    my @comment_keys =  grep {$_ =~ /$comment/i} @$keys;
    my @annotation_keys = (@requirement_keys, @owner_keys, @phase_keys,
                           @comment_keys);
    print STDERR "output_dt_xml annotation_keys [".join(',',@annotation_keys).
        "]\n" if $verbose;

    # output DT header
    # XXX shouldn't hard-code DT version and deviceType
    output 0, qq{<?xml version="1.0" encoding="UTF-8"?>};
    output 0,qq{
<dt:document xmlns:dt="urn:broadband-forum-org:cwmp:devicetype-1-1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="urn:broadband-forum-org:cwmp:devicetype-1-1
                 http://www.broadband-forum.org/cwmp/cwmp-devicetype-1-1.xsd
                              urn:broadband-forum-org:cwmp:datamodel-report-0-1
                 http://www.broadband-forum.org/cwmp/cwmp-datamodel-report.xsd"
             deviceType="urn:cisco-com:tbd-1-0-0">
  <annotation>
    $tname table
  </annotation>
};

    # determine 

    # output DM import and DT model element  
    output 1, qq{
<import file="$dmfile" spec="$dmspec">
  <model name="$dmmodel:$dmversion"/>
</import>
<model ref="$dmmodel:$dmversion">
};

    # output rows
    my $object_active = 0;
    foreach my $row (@$rows) {
        my $path = $row->{path};
        my $name = $row->{name};
        my $type = $row->{type};
        my $write = $row->{write};

        # check whether row is being ignored
        next if $row->{ignored};
        
        # check whether to include this row
        my $include = include_dt_row($row, \@requirement_keys);
        next unless $include;

        # determine info to put into the annotation
        my @defined_keys = grep {defined $row->{$_}} @annotation_keys;
        my @annotation = map {qq{$Keys->{$_}: $row->{$_}}} @defined_keys;
        my $annotation = qq{};
        if (@annotation) {
            $annotation = qq{Additional info:};
            foreach my $line (@annotation) {
                $annotation .= qq{\n  * $line};
            }
            $annotation = xml_escape($annotation);
        }

        # output object
        # XXX where to get minEntries and maxEntries? don't really want to read
        #     DM (although could read the "full" XML)
        if ($type eq 'object') {
            my $access = ($write eq 'W') ? qq{createDelete} : qq{readOnly};
            my $multi = ($path =~ /\.\{i\}\.$/);
            my $minEntries = $multi ? qq{0} : qq{1};
            my $maxEntries = $multi ? qq{unbounded} : qq{1};
            output 2, qq{</object>} if $object_active;
            output 2, qq{<object ref="$path" access="$access" }.
                qq{minEntries="$minEntries" maxEntries="$maxEntries">};
            output 3, qq{
<annotation>
  $annotation
</annotation>
} if $annotation;
            $object_active = 1;
        }

        # output parameter
        else {
            my $slash = $annotation ? qq{} : qq{/};
            my $access = ($write eq 'W') ? qq{readWrite} : qq{readOnly};
            output 3, qq{<parameter ref="$name" access="$access"$slash>};
            output 4, qq{
<annotation>
  $annotation
</annotation>
} if $annotation;
            output 3, qq{</parameter>} unless $slash;
        }
    }

    # close final object
    output 2, qq{</object>} if $object_active;

    # close model element
    output 1, qq{</model>};

    # close root element
    output 0, qq{</dt:document>};
}

# escape characters that are special to XML
sub xml_escape
{
    my ($value, $opts) = @_;

    # XXX probably needing to do this implies a bug elsewhere?
    $value = '' unless $value;

    # XXX this isn't really escaping; it deals with CRs in multiline strings
    $value =~ s/\r/\n/gs;

    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    # only quote quotes in attribute values
    $value =~ s/\"/\&quot;/g if $opts->{attr};

    return $value;
}
