#!/usr/bin/perl -w
#
# Copyright (c) 2010  2Wire,Inc.
# All Rights Reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:	
# - Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# - Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# - Neither the name of 2Wire, Inc. nor the names of its contributors may be
#   used to endorse or promote products derived from this software without
#   specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# Example data model report script.  Parses, validates and reports on TR-069
# DM (data model definition) instance documents.
#
# Please note that this script was developed during the same period that the
# Broadband Forum (BBF) XML standards were evolving.  The script tracked that
# evolution and is not well-structured, easy to understand, or maintainable.
# "XXX" comments throughout the script indicate known restrictions,
# inefficiencies or other issues.  Caveat emptor.
#
# See full usage documentation at the end of the file.

# XXX want better format that can be directly imported into excel (and of
#     course want better export from excel, but that's a separate issue)

# XXX need to process all top-level objects (report needs to be capable of
#     containing ALL information in the input file)

# XXX don't necessarily want to expand components; needs to be controllable;
#     e.g for excel might just want a "header" worksheet with global attributes
#     and imports, then a worksheet for each component, model and
#     profile (format wants to mirror XSD very closely, and to be easily
#     extensible, e.g. first rows can contain attributes)

# XXX need to change style so just puts everything in the node tree (don't want
#     to have to be aware of all attributes and elements, only ones that need
#     special treatment; probably want to start afresh; use proper Perl
#     objects)

# XXX need an "xml" output option that just expands all components and outputs
#     canonical cwmp-datamodel xml (c.f. C pre-processor); note: there is now
#     am "xml" output option but it does something different

# XXX should separate into "expand" and "report" tools (would require keeping
#     things like spec at a much more granular level)

# XXX should check that parameters and objects referenced by the notify and
#     profile tables actually exist (this is now done); also could have a go
#     at checking that object references in descriptions are valid (now that
#     we have {{param}} and {{object}} templates, this could be done)

# XXX 'auto' handling is a mess; wants doing consistently, e.g. auto objects
#     are ignored only for some report types

# XXX name/base/ref handling is incomplete; base/ref requires a copy to be made
#     (actually is sort of working now, but only where model name, excluding
#     version, is the same, not where a copy is needed)

# XXX "hidden" node logic is working well, but need a third value to mean
#     that definitions in command-line files are not hidden by subsequent
#     import (import logic should detect it's already been read?)

# XXX autobase is covering three different things; should be split so one of
#     the usages is the logic for the re-use of models (shouldn't really need
#     it if handle imported and command-line models properly), another is
#     hiding of imported definitions, and the third is what the name implies

# XXX the import of TR-106-Amendment-1.xml is dangerous, because it doesn't
#     import the model, which means that the model is ignored even if there is
#     then an explicit import

# XXX could re-badge autobase as diff, since it's very close to that...

# XXX some report formats are somewhat broken at the moment, with the move to
#     centralised report_node traversal

# XXX need to re-think the report_node concept (the price of simplicity is -
#     in some cases - additional complexity)

# XXX have to parse dataType specifications, so can output them in XML
#     reports (an issue only for TR-106 currently); ditto component
#     definitions

# XXX need once and for all to decide what spec is used for; mostly file is
#     used since it's guaranteed to be unique

# XXX have added some DT hacks, but need better control, e.g. determine whether
#     a given file is DT from its namespace

# XXX should use LWP::mirror to support URLs and cache files locally; also
#     support search path (including base URLs); finding highest corrigendum
#     complicates this (would need to fetch files matching a pattern) unless
#     assume that the HTTP server handles this (which it should do)

# XXX $upnpdm is a hack; need a more clear distinction between path syntax
#     used internally and path syntax used for presentation

# XXX $components is a hack (need full xml2 report support in order to carry
#     over unique keys, references etc)

# XXX why does this happen?
# % report.pl tr-098-1-1-0.xml tr-098-1-2-0.xml
#InternetGatewayDevice.DownloadDiagnostics.: object not found (auto-creating)
#InternetGatewayDevice.DownloadDiagnostics.DownloadURL: parameter not found
#    (auto-creating)
#InternetGatewayDevice.DownloadDiagnostics.DownloadURL: untyped parameter
#InternetGatewayDevice.UploadDiagnostics.: object not found (auto-creating)
#InternetGatewayDevice.UploadDiagnostics.UploadURL: parameter not found
#    (auto-creating)
#InternetGatewayDevice.UploadDiagnostics.UploadURL: untyped parameter
#urn:broadband-forum-org:tr-069-1-0-0: 522
#urn:broadband-forum-org:tr-098-1-0-0: 215
#urn:broadband-forum-org:tr-098-1-1-0: 18
#urn:broadband-forum-org:tr-098-1-2-0: 421
#
# but
#
# % report.pl tr-098-1-2-0.xml 
# urn:broadband-forum-org:tr-069-1-0-0: 522
# urn:broadband-forum-org:tr-098-1-0-0: 215
# urn:broadband-forum-org:tr-098-1-1-0: 18
# urn:broadband-forum-org:tr-098-1-2-0: 417
# urn:broadband-forum-org:tr-143-1-0-1: 49

use strict;
no strict "refs";

# XXX can enable this as an aid to finding auto-vivification problems
#no autovivification qw{fetch exists delete warn};

use Algorithm::Diff;
use Clone qw{clone};
use Data::Compare;
use Data::Dumper;
use File::Spec;
use Getopt::Long;
use Pod::Usage;
use Text::Balanced qw{extract_bracketed};
use URI::Split qw(uri_split);
use XML::LibXML;

my $tool_author = q{$Author: wlupton $};
my $tool_vers_date = q{$Date: 2011/07/05 $};
my $tool_id = q{$Id: //depot/users/wlupton/cwmp-datamodel/report.pl#184 $};

my $tool_url = q{https://tr69xmltool.iol.unh.edu/repos/cwmp-xml-tools/Report_Tool};

my ($tool_vers_date_only) = ($tool_vers_date =~ /([\d\/]+)/);
my ($tool_id_only) = ($tool_id =~ /([^\/ ]+)\s*\$$/);

my $tool_run_date;
my $tool_run_month;
my $tool_run_time;
{
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
        localtime(time);
    my $months = ['January', 'February', 'March', 'April', 'May', 'June',
                  'July', 'August', 'September', 'October', 'November',
                  'December'];
    $tool_run_date = sprintf "%04d/%02d/%02d", 1900+$year, $mon+1, $mday;
    $tool_run_month = sprintf "%s %d", $months->[$mon], 1900+$year;
    $tool_run_time = sprintf "%02d:%02d:%02d", $hour, $min, $sec;
}

my $tool_cmd_line = $0 . ' ' . join(' ', @ARGV);
$tool_cmd_line = util_clean_cmd_line($tool_cmd_line);

# XXX these have to match the current version of the DT schema
my $dtver = qq{1-0};
my $dturn = qq{urn:broadband-forum-org:cwmp:devicetype-${dtver}};
my $dtloc = qq{cwmp-devicetype-${dtver}.xsd};

#print STDERR File::Spec->tmpdir() . "\n";

# XXX this prevents warnings about wide characters, but still not handling
#     them properly (see tr2dm.pl, which now does a better job)
binmode STDOUT, ":utf8";

# XXX this was controllable via --lastonlyusesspec, but is now hard-coded
#     (--compare sets it to 0)
my $modifiedusesspec = 1;

# Command-line options
my $allbibrefs = 0;
my $autobase = 0;
my $autodatatype = 0;
my $bibrefdocfirst = 0;
my $canonical = 0;
my $catalogs = [];
my $compare = 0;
my $components = 0;
my $debugpath = '';
my $deletedeprecated = 0;
my $dtprofiles = [];
my $dtspec = 'urn:example-com:device-1-0-0';
my $help = 0;
my $nohyphenate = 0;
my $ignore = '';
my $importsuffix = '';
my $includes = [];
my $info = 0;
my $lastonly = 0;
my $marktemplates = undef;
my $newparser = 0;
my $noautomodel = 0;
my $nocomments = 0;
my $nolinks = 0;
my $nomodels = 0;
my $noobjects = 0;
my $noparameters = 0;
my $noprofiles = 0;
my $notemplates = 0;
my $nowarnredef = 0;
my $nowarnprofbadref = 0;
my $objpat = '';
my $outfile = undef;
my $pedantic = undef;
my $quiet = 0;
my $report = '';
my $showdiffs = 0;
my $showspec = 0;
my $showreadonly = 0;
my $showsyntax = 0;
my $special = '';
my $thisonly = 0;
my $tr106 = 'TR-106';
my $ugly = 0;
my $upnpdm = 0;
my $verbose = undef;
my $warnbibref = undef;
my $warndupbibref = 0;
my $writonly = 0;
GetOptions('allbibrefs' => \$allbibrefs,
           'autobase' => \$autobase,
           'autodatatype' => \$autodatatype,
           'bibrefdocfirst' => \$bibrefdocfirst,
           'canonical' => \$canonical,
           'catalog:s@' => \$catalogs,
           'compare' => \$compare,
           'components' => \$components,
           'debugpath:s' => \$debugpath,
           'deletedeprecated' => \$deletedeprecated,
           'dtprofile:s@' => \$dtprofiles,
           'dtspec:s' => \$dtspec,
	   'help' => \$help,
           'ignore:s' => \$ignore,
           'importsuffix:s' => \$importsuffix,
           'include:s@' => \$includes,
	   'info' => \$info,
           'lastonly' => \$lastonly,
	   'marktemplates' => \$marktemplates,
           'newparser' => \$newparser,
	   'noautomodel' => \$noautomodel,
	   'nocomments' => \$nocomments,
	   'nohyphenate' => \$nohyphenate,
	   'nolinks' => \$nolinks,
	   'nomodels' => \$nomodels,
	   'noobjects' => \$noobjects,
	   'noparameters' => \$noparameters,
	   'noprofiles' => \$noprofiles,
	   'notemplates' => \$notemplates,
           'nowarnredef' => \$nowarnredef,
           'nowarnprofbadref' => \$nowarnprofbadref,
	   'objpat:s' => \$objpat,
           'outfile:s' => \$outfile,
	   'pedantic:i' => \$pedantic,
	   'quiet' => \$quiet,
	   'report:s' => \$report,
           'showdiffs' => \$showdiffs,
           'showreadonly' => \$showreadonly,
           'showspec' => \$showspec,
           'showsyntax' => \$showsyntax,
           'special:s' => \$special,
	   'thisonly' => \$thisonly,
	   'tr106:s' => \$tr106,
           'upnpdm' => \$upnpdm,
           'ugly' => \$ugly,
	   'verbose:i' => \$verbose,
           'warnbibref:i' => \$warnbibref,
           'warndupbibref' => \$warndupbibref,
	   'writonly' => \$writonly) or pod2usage(2);
pod2usage(2) if $report && $special;
pod2usage(1) if $help;

$report = 'special' if $special;
$report = 'null' unless $report;

unless (defined &{"${report}_node"}) {
    print STDERR "unsupported report format: $report\n";
    pod2usage(2);
}

if ($noparameters) {
    print STDERR "--noparameters not yet implemented\n";
    pod2usage(2);
}

if ($info) {
    print STDERR qq{$tool_author
$tool_vers_date
$tool_id
};
    exit(1);
}

# XXX as part of getting rid of xml2, require the xml report also to specify
#     --lastonly (need to check this doesn't break the xml report)
if ($report eq 'xml2') {
    print STDERR "the xml2 report is deprecated; use the xml report without ".
        "--lastonly to get the same effect\n";
}
if ($report eq 'xml' && !$lastonly) {
    $report = 'xml2';
}

if ($autodatatype) {
    print STDERR "--autodatatype is deprecated because it's set by default\n";
}

if ($ugly) {
    print STDERR "--ugly is deprecated; use --nohyphenate and/or ".
        "--showsyntax\n";
    $nohyphenate = 1;
    $showsyntax = 1;
}

if ($warndupbibref) {
    print STDERR "--warndupbibref is deprecated; use --warnbibref\n";
    $warnbibref = 1;
}

if ($nowarnprofbadref) {
    print STDERR "--nowarnprofbadref is deprecated; it's no longer necessary\n";
}

if ($compare) {
    if (@ARGV != 2) {
        print STDERR "--compare requires exactly two input files\n";
        pod2usage(2);
    }
    $autobase = 1;
    $showdiffs = 1;
    $modifiedusesspec = 0 if $lastonly;
}

if ($outfile) {
    if (!open(STDOUT, ">", $outfile)) {
        die "can't create --outfile $outfile: $!";
    }
} else {
    $tool_cmd_line .= ' ...';
}

*STDERR = *STDOUT if $report eq 'null';

$marktemplates = '&&&&' if defined($marktemplates);

$warnbibref = 1 if defined($warnbibref) and !$warnbibref;
$warnbibref = 0 unless defined($warnbibref);

$pedantic = 1 if defined($pedantic) and !$pedantic;
$pedantic = 0 unless defined($pedantic);

$verbose = 1 if defined($verbose) and !$verbose;
$verbose = 0 unless defined($verbose);

$nocomments = 0 if $verbose;

# XXX upnpdm profiles are broken...
$noprofiles = 1 if $components || $upnpdm || @$dtprofiles;

# XXX load_catalog() works but there is no error checking?
{
    my $parser = XML::LibXML->new();
    foreach my $catalog (@$catalogs) {
        my ($dir, $file) = find_file($catalog);
        if (!$dir) {
            print STDERR "parse_file: XML catalog $file not found\n";
        } else {
            my $tfile = $dir ? File::Spec->catfile($dir, $file) : $file;
            print STDERR "loading XML catalog $tfile\n" if $verbose;
            eval { $parser->load_catalog($tfile) };
            if ($@) {
                warn $@;
            }
        }
    }
}

# Globals.
my $first_comment = undef;
my $allfiles = [];
my $specs = [];
# XXX for DT, lfile and lspec should be last processed DM file
#     (current workaround is to use same spec for DT and this DM)
my $pfile = ''; # last-but-one command-line-specified file
my $pspec = ''; # spec from last-but-one command-line-specified file
my $lfile = ''; # last command-line-specified file
my $lspec = ''; # spec from last command-line-specified file
my $files = {};
my $imports = {}; # XXX not a good name, because it includes main file defns
my $imports_i = 0;
my $bibrefs = {};
# XXX need to change $objects to use util_is_defined()
my $objects = {};
my $parameters = {};
my $profiles = {};
my $anchors = {};
my $root = {file => '', spec => '', lspec => '', path => '', name => '',
            type => '', status => 'current', dynamic => 0};
my $highestMajor = 0;
my $highestMinor = 0;
my $previouspath = '';

# Parse and expand a data model definition file.
# XXX also does minimal expansion of schema files
sub expand_toplevel
{
    my ($file)= @_;

    (my $dir, $file) = find_file($file);

    # parse file
    my $toplevel = parse_file($dir, $file);

    # for XSD files, just track the target namespace then return
    my $spec;
    if ($file =~ /\.xsd$/) {
        my $targetNamespace = $toplevel->findvalue('@targetNamespace');
        push @$allfiles, {name => $file, spec => $targetNamespace,
                          schema => 1};
        return;
    }
    else {
        $spec = $toplevel->findvalue('@spec');
        my @models = $toplevel->findnodes('model');
        push @$allfiles, {name => $file, spec => $spec, models => \@models};
    }

    # XXX this is using file name to check against multiple inclusion, but
    #     would spec be better? maybe, but would require 1-1 correspondence
    #     between spec and file, and would force spec to be used properly
    #     (using file is probably better)
    # XXX might not be quite the right test (will expand_toplevel and
    #     expand_import both have done all that the other needs?)
    $file =~ s/\.xml//;
    return if $files->{$file};
    $files->{$file} = 1;

    $pfile = $lfile;
    $pspec = $lspec;

    $lfile = $file;
    $lspec = $spec;

    $root->{spec} = $spec;
    push @$specs, $spec unless grep {$_ eq $spec} @$specs;

    # pick up description
    # XXX hmm... putting this stuff on root isn't right is it?
    $root->{description} = $toplevel->findvalue('description');
    $root->{descact} = $toplevel->findvalue('description/@action');

    # collect top-level item declarations (treat as though they were imported
    # from an external file; this avoids special cases)
    # XXX need to keep track of context in which the import was performed,
    #     so can reproduce import statements when generating XML
    foreach my $item ($toplevel->findnodes('dataType|component|model')) {
        my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');

        if ($element eq 'model' && $ignore && $name =~ /^$ignore/) {
            print STDERR "ignored model $name\n" if $verbose;
            next;
        }

        update_imports($file, $spec, $file, $spec, $element, $name, $name,
                       $item);
    }

    # expand nested items (context is a stack of nested component context)
    # XXX should be: description, import, dataType, bibliography, component,
    #     model
    my $context = [{file => $file, spec => $spec,
                    lfile => $file, lspec => $spec,
                    path => '', name => ''}];

    #print STDERR "XXXX init in $file; $file\n";

    foreach my $item
	($toplevel->findnodes('import|dataType|bibliography|model')) {
	my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');

        if ($element eq 'model' && $ignore && $name =~ /^$ignore/) {
            print STDERR "ignored model $name\n" if $verbose;
            next;
        }

	"expand_$element"->($context, $root, $item);
    }

    # if saw components but no model, auto-generate a model that references
    # each component once at the top level
    # XXX this duplicates some logic from expand_model_component
    # XXX model name is spec, and so will probably be invalid
    my @comps =
        grep {$_->{element} eq 'component'} @{$imports->{$file}->{imports}};
    my @models =
        grep {$_->{element} eq 'model'} @{$imports->{$file}->{imports}};
    if (!$noautomodel && !@models && @comps) {
        my $mname = $spec;
        print STDERR "auto-generating model: $mname\n" if $verbose;
        my $nnode = add_model($context, $root, $mname);
        foreach my $comp (@comps) {
            my $name = $comp->{name};
            my $component = $comp->{item};

            print STDERR "referencing component: $name\n" if $verbose;
            foreach my $item ($component->findnodes('component|object|'.
                                                    'parameter')) {
                my $element = $item->findvalue('local-name()');
                "expand_model_$element"->($context, $nnode, $nnode, $item);
            }
        }
    }
}

# Expand a top-level import.
# XXX there must be scope for more code share with expand_toplevel
# XXX yes, in both cases should import all top-level items (dataType,
#     component, model) into the "main" namespace, unless there is a
#     conflict; explicitly imported symbols can be renamed locally
sub expand_import
{
    my ($context, $pnode, $import) = @_;

    my $cfile = $context->[0]->{file};
    my $cspec = $context->[0]->{spec};

    my $file = $import->findvalue('@file');
    my $spec = $import->findvalue('@spec');

    (my $dir, $file) = find_file($file);

    print STDERR "expand_import file=$file spec=$spec\n" if $verbose > 1;

    my $tfile = $file;
    $file =~ s/\.xml//;

    # if already read file, add the imports to the current namespace
    if ($files->{$file}) {
        foreach my $item ($import->findnodes('dataType|component|model')) {
            my $element = $item->findvalue('local-name()');
            my $name = $item->findvalue('@name');
            my $ref = $item->findvalue('@ref');
            $ref = $name unless $ref;

            my ($import) = grep {$_->{element} eq $element && $_->{name} eq
                                  $ref} @{$imports->{$file}->{imports}};
            update_imports($cfile, $cspec, $file, $imports->{$file}->{spec},
                           $element, $name, $ref, $import->{item});
        }
        return;
    }
    $files->{$file} = 1;

    return if $thisonly;

    # parse imported file
    my $toplevel = parse_file($dir, $tfile);
    my $fspec = $toplevel->findvalue('@spec');
    push @$specs, $fspec unless grep {$_ eq $fspec} @$specs;

    # check spec (if supplied)
    $spec = $fspec unless $spec;
    print STDERR "import $file: spec is $fspec (expected $spec)\n"
        unless specs_match($spec, $fspec);

    # collect top-level item declarations
    foreach my $item ($toplevel->findnodes('dataType|component|model')) {
        my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');
        my $ref = $item->findvalue('@base');
        # DO NOT default ref to name here; empty ref indicates an initial
        # definition of something!
        
        update_imports($file, $fspec, $file, $fspec, $element, $name, $ref,
                       $item);
    }

    unshift @$context, {file => $file, spec => $fspec,
                        lfile => $file, lspec => $fspec,
                        path => '', name => ''};

    #print STDERR "XXXX impt in $file; $file\n";

    # expand imports in the imported file
    foreach my $item ($toplevel->findnodes('import')) {
	expand_import($context, $root, $item);
    }

    # expand data types in the imported file
    # XXX this is experimental (it's so reports can include data types)
    foreach my $item ($toplevel->findnodes('dataType')) {
        if ($newparser) {
            expand_dataType_new($context, $root, $item);
        } else {
            expand_dataType($context, $root, $item);
        }
    }

    # expand bibliogaphy in the imported file
    my ($bibliography) = $toplevel->findnodes('bibliography');
    expand_bibliography($context, $root, $bibliography) if $bibliography;

    # find imported items in the imported file
    foreach my $item ($import->findnodes('dataType|component|model')) {
        my $element = $item->findvalue('local-name()');
	my $name = $item->findvalue('@name');
	my $ref = $item->findvalue('@ref');
        $ref = $name unless $ref;

        if ($element eq 'model' && $ignore && $name =~ /^$ignore/) {
            print STDERR "ignored model $name\n" if $verbose;
            next;
        }

        # XXX this logic is from expand_model_component
        my ($elem) = grep {$_->{element} eq $element && $_->{name} eq $ref}
        @{$imports->{$file}->{imports}};
        if (!$elem) {
            print STDERR "{$file}$ref: $element not found\n";
            next;
        }
        my $dfile = $elem->{file};

        # find the actual element (first check whether we have already seen it)
        my ($delem) = grep {$_->{element} eq $element && $_->{name} eq $ref}
        @{$imports->{$dfile}->{imports}};
        my $fitem = $delem ? $delem->{item} : undef;
        if ($fitem) {
            print STDERR "{$file}$ref: $element already found in $dfile\n"
                if $verbose;
        } elsif ($dfile eq $file) {
            ($fitem) = $toplevel->findnodes(qq{$element\[\@name="$ref"\]});
        } else {
            (my $ddir, $dfile) = find_file($dfile.'.xml');
            my $dtoplevel = parse_file($ddir, $dfile);
            ($fitem) = $dtoplevel->findnodes(qq{$element\[\@name="$ref"\]});
        }
        print STDERR "{$file}$ref: $element not found in $dfile\n"
            unless $fitem;

        # XXX update regardless; will get another error if try to use it
        update_imports($cfile, $cspec, $file, $fspec, $element, $name, $ref,
                       $fitem);
    }
    shift @$context;
}

# Update the global list of imported items.
sub update_imports
{
    my ($file, $spec, $dfile, $dspec, $element, $name, $ref, $item) = @_;

    $imports->{$file}->{i} = $imports_i++ unless exists $imports->{$file};
    $imports->{$file}->{spec} = $spec;
    push(@{$imports->{$file}->{imports}},
         {file => $dfile, spec => $dspec, element => $element, name => $name,
          ref => $ref, item => $item});

    my $alias = $dfile ne $file ? qq{ = {$dfile}$ref} : qq{};
    print STDERR "update_imports: added $element {$file}$name$alias\n"
        if $verbose;
}

# Expand a dataType definition.
# XXX does the minimum to support TR-106; both it and syntax should use the
#     schema structures to avoid duplication.
sub expand_dataType
{    
    my ($context, $pnode, $dataType) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    my $name = $dataType->findvalue('@name');
    my $base = $dataType->findvalue('@base');
    my $status = $dataType->findvalue('@status');
    my $description = $dataType->findvalue('description');
    my $descact = $dataType->findvalue('description/@action');
    my $descdef = $dataType->findnodes('description')->size();
    my $minLength = $dataType->findvalue('string/size/@minLength');
    my $maxLength = $dataType->findvalue('string/size/@maxLength');
    my $patterns = $dataType->findnodes('string/pattern');

    my $prim;
    foreach my $type (('base64', 'boolean', 'dateTime', 'hexBinary',
                       'int', 'long', 'string', 'unsignedInt',
                       'unsignedLong')) {
        # XXX using prim as loop var didn't work; "last" undefined it?
        if ($dataType->findnodes($type)) {
            $prim = $type;
            last;
        }
    }

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $file, $spec);

    print STDERR "expand_dataType name=$name base=$base\n" if $verbose > 1;

    # XXX for now only replace description if data type is redefined
    my ($node) = grep {$_->{name} eq $name} @{$root->{dataTypes}};
    if ($node) {
        print STDERR "data type $name redefined (description replaced)\n";
        $node->{description} = $description;

    } else {
        $node = {name => $name, base => $base, prim => $prim, spec => $spec,
                 status => $status, description => $description,
                 descact => $descact, descdef => $descdef,
                 minLength => $minLength, maxLength => $maxLength,
                 patterns => [], specs => []};

        foreach my $pattern (@$patterns) {
            my $value = $pattern->findvalue('@value');
            my $description = $pattern->findvalue('description');
            my $descact = $pattern->findvalue('description/@action');
            my $descdef = $pattern->findnodes('description')->size();
            
            update_bibrefs($description, $file, $spec);

            push @{$node->{patterns}}, {value => $value, description =>
                                            $description, descact => $descact,
                                            descdef => $descdef};
        }

        push @{$pnode->{dataTypes}}, $node;
    }
}

# Alternative datatype expansion enabled by --newparser.  Is driven more
# directly by the DM Schema structure.  Will eventually move over to using
# these routines elsewhere.
#
# XXX Would like to make this more data-driven, e.g. pass a description of
#     attributes to fetch, and elements to parse, and how to represent them
#     as a Perl data structure, but such information would just duplicate what
#     is in the schema, so it would be nice to parse the schema itself and use
#     that to drive how the parsed information is represented natively, e.g.
#     $param->{syntax}->{int}->{range}->[0]->{minInclusive} would be the naive
#     representation but might want to skip the {syntax} level and to store the
#     {int} level as an attribute, so would also want some configuration to
#     indicate such things.  Maybe this is too ambitious but it would be nice!
sub expand_dataType_new
{
    my ($context, $pnode, $dataType) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    # attributes
    my $name = $dataType->findvalue('@name');
    my $base = $dataType->findvalue('@base');
    my $status = $dataType->findvalue('@status');

    # description
    my $description = expand_description($dataType);

    # all facets (only permitted if this is a derived type)
    my $facets = expand_facets($dataType);

    # builtin data types
    my $builtin = expand_builtin_data_type($dataType);
}

sub expand_description
{
    my ($context, $node, $dataType) = @_;

}

# Update list of data types that are actually used (the specs attribute is an
# array of the specs that use the data type)
sub update_datatypes
{
    my ($name, $file, $spec) = @_;

    my ($dataType) = grep {$_->{name} eq $name} @{$root->{dataTypes}};
    return unless $dataType;

    print STDERR "#### marking $name used (file=$file, spec=$spec)\n" if
        $verbose > 1;

    push @{$dataType->{specs}}, $spec unless
        grep {$_ eq $spec} @{$dataType->{specs}};
}

# Expand a bibliography definition.
sub expand_bibliography
{
    my ($context, $pnode, $bibliography) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    # will report if $verbose > $vlevel
    my $vlevel = 1;

    my $description = $bibliography->findvalue('description');
    my $descact = $bibliography->findvalue('description/@action');
    my $descdef = $bibliography->findnodes('description')->size();

    update_bibrefs($description, $file, $spec);

    print STDERR "expand_bibliography\n" if $verbose > $vlevel;

    if ($pnode->{bibliography}) {
        # XXX not obvious what should be done with the description here; for
        #     now, just replace it quietly.
        $pnode->{bibliography}->{description} = $description;
        $pnode->{bibliography}->{descact} = $descact;
        $pnode->{bibliography}->{descdef} = $descdef;
    } else {
        $pnode->{bibliography} = {description => $description,
                                  descact => $descact, descdef => $descdef,
                                  references => []};
    }

    # XXX this should really be in a separate routine
    foreach my $reference ($bibliography->findnodes('reference')) {
        my $id = $reference->findvalue('@id');
        my $name = $reference->findvalue('name');

        my ($dupref) =
            grep {$_->{id} eq $id} @{$pnode->{bibliography}->{references}};
        if ($dupref) {
            if ($dupref->{spec} eq $spec) {
                # this isn't necessarily a problem; it can happen if two files
                # with the same spec are processed (which definitely isn't an
                # error if $autobase is set)
                print STDERR "$id: duplicate bibref: {$file}$name\n"
                    if !$autobase && ($verbose || $warnbibref);
            } elsif ($dupref->{name} ne $name) {
                print STDERR "$id: ambiguous bibref: ".
                    "{$dupref->{file}}$dupref->{name}, {$file}$name\n";
            } else {
                print STDERR "$id: duplicate bibref: ".
                    "{$dupref->{file}}$dupref->{name}, {$file}$name\n"
                    if $verbose || $warnbibref;
            }
        }

        print STDERR "expand_bibliography_reference id=$id name=$name\n" if
            $verbose > $vlevel;

        # keep track of the latest available TR-106 reference
        # XXX should be able to use bibid_cmp (or similar)
        $tr106 = $id if $id =~ /^TR-106/ && $id gt $tr106;

        my $hash = {id => $id, name => $name, file => $file};
        foreach my $element (qw{title organization category date hyperlink}) {
            my $value = $reference->findvalue($element);
            $hash->{$element} = $value ? $value : '';
        }

        # XXX check for non-standard organization / category
        my $bbf = 'Broadband Forum';
        my $tr = 'Technical Report';
        if ($hash->{organization} =~ /^(BBF|The\s+Broadband\s+Forum)$/i) {
            print STDERR "$id: $file: replaced organization ".
                "\"$hash->{organization}\" with \"$bbf\"\n"
                if $warnbibref > 1 || $verbose;
            $hash->{organization} = $bbf;
        }
        if ($hash->{category} =~ /^TR$/i) {
            print STDERR "$id: $file: replaced category ".
                "\"$hash->{category}\" with \"$tr\"\n"
                if $warnbibref > 1 || $verbose;
            $hash->{category} = $tr;
        }

        # XXX check for missing category
        if ($id =~ /^TR/i && $name =~ /^TR/i &&
            $hash->{organization} eq $bbf && !$hash->{category}) {
             print STDERR "$id: $file: missing $bbf category (\"$tr\" ".
                 "assumed)\n" if $warnbibref > 1 || $verbose;
            $hash->{category} = $tr;
        }
        if ($id =~ /^RFC/i && $name =~ /^RFC/i &&
            $hash->{organization} eq 'IETF' && !$hash->{category}) {
             print STDERR "$id: $file: missing IETF category (\"RFC\" ".
                 "assumed)\n" if $warnbibref > 1 || $verbose;
            $hash->{category} = 'RFC';
        }

        # XXX could also check for missing date (etc)...

        # for TRs, don't want hyperlink, so can auto-generate the correct
        # hyperlink according to BBF conventions
        if ($hash->{organization} eq $bbf && $hash->{category} eq $tr) {
            if ($hash->{hyperlink}) {
                print STDERR "$id: $file: replaced deprecated $bbf $tr ".
                    "hyperlink\n" if $warnbibref > 1 || $verbose;
            }
            my $h = qq{http://www.broadband-forum.org/technical/download/};
            my $trname = $id;
            $trname =~ s/i(\d+)/_Issue-$1/;
            $trname =~ s/a(\d+)/_Amendment-$1/;
            $trname =~ s/c(\d+)/_Corrigendum-$1/;
            $h .= $trname;
            $h .= qq{.pdf};
            $hash->{hyperlink} = $h;
        }

        # for RFCs, don't want hyperlink, so can auto-generate the correct
        # hyperlink according to IETF conventions
        if ($hash->{organization} eq 'IETF' && $hash->{category} eq 'RFC') {
            if ($hash->{hyperlink}) {
                print STDERR "$id: $file: replaced deprecated IETF RFC ".
                    "hyperlink\n" if $warnbibref > 1 || $verbose;
            }
            my $h = qq{http://tools.ietf.org/html/};
            $h .= lc $id;
            $hash->{hyperlink} = $h;
        }

        # XXX could also replace the hyperlinks for other organisations?

        if ($dupref) {
            my $changed = 0;
            foreach my $key (keys %$hash) {
                # XXX note, only replace if old value is blank and new value
		#     is non-blank (allows entries in tr-069-biblio.xml to
		#     have precedence)
                if (!$dupref->{$key} && $hash->{$key}) {
                    print STDERR "$id: $key -> $hash->{$key}\n" if $verbose;
                    $dupref->{$key} = $hash->{$key};
                    $changed = 1;
                }
            }
            $dupref->{spec} = $spec if $changed;
        } else {
            $hash->{spec} = $spec;
            push @{$pnode->{bibliography}->{references}}, $hash;
        }
    }
    print STDERR Dumper($pnode->{bibliography}) if $verbose > $vlevel;
}

# Expand a data model definition.
sub expand_model
{
    my ($context, $pnode, $model) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    my $name = $model->findvalue('@name');
    my $ref = $model->findvalue('@ref');
    $ref = $model->findvalue('@base') unless $ref;
    my $status = $model->findvalue('@status');
    my $isService = boolean($model->findvalue('@isService'));
    my $description = $model->findvalue('description');
    my $descact = $model->findvalue('description/@action');
    my $descdef = $model->findnodes('description')->size();

    # XXX fudge it if in a DT instance (ref but no name or base)
    $name = $ref if $ref && !$name;

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $file, $spec);

    print STDERR "expand_model name=$name ref=$ref\n" if $verbose > 1;

    # if automatically generating references to existing models, set ref
    if ($autobase  && !$ref) {
        my @match = grep {
            my ($a) = ($name =~ /([^:]*)/);
            my ($b) = ($_->{name} =~ /([^:]*)/);
            $_->{type} eq 'model' && $a eq $b;
        } @{$pnode->{nodes}};
        if (@match) {
            # XXX logic duplicated immediately below (use routine for this)
            my $hmaj = 0;
            my $hmin = 0;
            for my $model (@match) {
                my $name = $model->{name};
                my ($maj, $min) = ($name =~ /:(\d+)\.(\d+)/);
                if (($maj > $hmaj) || ($maj == $hmaj && $min > $hmin)) {
                    $hmaj = $maj;
                    $hmin = $min;
                    $ref = $name;
                }
            }
            # XXX hack for modifying existing models
            $ref = '_' . $ref if $ref eq $name;
            print STDERR "converted to name=$name ref=$ref\n" if $verbose;
        }
    }

    # XXX for now, still handle versions as before
    my ($majorVersion, $minorVersion) = ($name =~ /:(\d+)\.(\d+)/);
    if (($majorVersion > $highestMajor) ||
        ($majorVersion == $highestMajor && $minorVersion > $highestMinor)) {
        $highestMajor = $majorVersion;
        $highestMinor = $minorVersion;
    }

    my $nnode = add_model($context, $pnode, $name, $ref, $isService, $status,
                          $description, $descact, $descdef, $majorVersion,
                          $minorVersion);

    # expand nested components, objects, parameters and profiles
    my $any_profiles = 0;
    foreach my $item ($model->findnodes('component|parameter|object|'.
                                        'profile')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_$element"->($context, $nnode, $nnode, $item);
        $any_profiles = 1 if $element eq 'profile';
    }

    # XXX if there were no profiles, add a fake profile element to avoid
    #     the HTML report problem that post data model parameter tables
    #     are omitted (really the answer here is for the node tree to include
    #     nodes for all nodes in the final report)
    if (!$any_profiles) {
        push @{$nnode->{nodes}}, {type => 'profile', name => '',
                                  spec => $spec, file => $file,
                                  lspec => $Lspec, lfile => $Lfile};
    }
}

# Expand a data model component reference.
sub expand_model_component
{
    my ($context, $mnode, $pnode, $component) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};
    my $Path = $context->[0]->{path};

    my $path = $component->findvalue('@path');
    my $name = $component->findvalue('@ref');

    $Path .= $path;

    # XXX a kludge... will apply to the first items only (really want a way
    #     of passing arguments)
    my $hash = dmr_previous($component, 1);
    $hash->{previousObject} = $path . $hash->{previousObject} if
        $hash->{previousObject};

    print STDERR "expand_model_component path=$path ref=$name\n"
        if $verbose > 1;

    # find component
    my ($comp) = grep {$_->{element} eq 'component' && $_->{name} eq $name}
    @{$imports->{$file}->{imports}};

    # check component is known
    if (!$comp) {
	print STDERR "{$file}$name: component not found\n"
            unless $thisonly;
	return;
    }
    $component = $comp->{item};
    if (!$component) {
	print STDERR "{$file}$name: component not found in $comp->{file}\n"
            unless $thisonly;
	return;
    }

    # from now on, file and spec relate to the component
    # XXX this is ugly (want clean namespace handling)
    $file = $comp->{file};
    $spec = $comp->{spec};

    # check for recursive invocation
    if (grep {$_->{file} eq $file && $_->{name} eq $name} @$context) {
        my $active =
            join ', ', map {qq{{$_->{file}}$_->{name}}} reverse @$context;
        print STDERR "$name: recursive component reference: $active\n";
        return;
    }

    # the path may consist of multiple components; create any intervening
    # objects, returning the new parent and the last component of the name
    # XXX may want control over auto-creation logic; sometimes it's useful, but
    #     it can be error-prone too (one reason to auto-create is to force a
    #     parameter to be the first in an object, so could provide an alter-
    #     native mechanism for this?)
    # XXX this is a problem for profiles, because it creates the profile nodes
    #     as children of the result of add_path; this has been avoided by a
    #     hack in expand_model_profile; an alternative would be to look at the
    #     component contents before expanding it?
    ($pnode, $path) = add_path($context, $mnode, $pnode, $path, 0);

    # pass information from caller to the new component context
    unshift @$context, {file => $file, spec => $spec, 
                        lfile => $Lfile, lspec => $Lspec,
                        path => $Path, name => $name,
                        previousParameter => $hash->{previousParameter},
                        previousObject => $hash->{previousObject},
                        previousProfile => $hash->{previousProfile}};

    #print STDERR "XXXX comp $name in $file; $Lfile\n";

    # expand component's nested components, parameters, objects and profiles
    foreach my $item ($component->findnodes('component|parameter|object|'.
                                            'profile')) {
	my $element = $item->findvalue('local-name()');
        "expand_model_$element"->($context, $mnode, $pnode, $item);
    }

    # pop context from the beginning of the active component list
    shift @$context;
}

# Expand a data model object
sub expand_model_object
{
    my ($context, $mnode, $pnode, $object) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    my $name = $object->findvalue('@name');
    my $ref = $object->findvalue('@ref');
    $ref = $object->findvalue('@base') unless $ref;
    my $access = $object->findvalue('@access');
    my $minEntries = $object->findvalue('@minEntries');
    my $maxEntries = $object->findvalue('@maxEntries');
    my $numEntriesParameter = $object->findvalue('@numEntriesParameter');
    my $enableParameter = $object->findvalue('@enableParameter');
    my $status = $object->findvalue('@status');
    my $description = $object->findvalue('description');
    my $descact = $object->findvalue('description/@action');
    my $descdef = $object->findnodes('description')->size();

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $file, $spec);

    $minEntries = 1 unless defined $minEntries && $minEntries ne '';
    $maxEntries = 1 unless defined $maxEntries && $maxEntries ne '';

    # XXX majorVersion and minorVersion are no longer in the schema
    #my $majorVersion = $object->findvalue('@majorVersion');
    #my $minorVersion = $object->findvalue('@minorVersion');
    my ($majorVersion, $minorVersion) = dmr_version($object);

    my $fixedObject = dmr_fixedObject($object);
    my $noUniqueKeys = dmr_noUniqueKeys($object);

    # XXX this is incomplete name / ref handling
    # XXX WFL2 my $tname = $name ? $name : $ref;
    my $oname = $name;
    my $oref = $ref;
    my $tname = $ref ? $ref : $name;
    my $path = $pnode->{path}.$tname;

    print STDERR "expand_model_object name=$name ref=$ref\n" if $verbose > 1;

    # ignore if doesn't match object name pattern
    if ($objpat ne '' && $path !~ /$objpat/) {
	print STDERR "\tdoesn't match object name pattern\n" if $verbose > 1;
	return;
    }

    # the name may consist of multiple components; create any intervening
    # objects, returning the new parent and the last component of the name
    ($pnode, $name) = add_path($context, $mnode, $pnode, $tname, 1);
    # XXX this is more of the incomplete name / ref handling
    if ($ref) {
        $ref = $name;
        # XXX WFL2 $name = '';
        # XXX this will fail if $oname has multiple components (which it
        #     shouldn't have)
        $name = ($oname && $oref) ? $oname : '';
    }

    # if this is a variable-size table, check that there is a
    # numEntriesParameter attribute and that the referenced parameter exists
    # XXX numEntriesParameter is checked only when object is defined; this
    #     means that no check is made when processing DT instances
    # XXX no longer the case... can we get rid of the check here?
    # XXX I think so
    #if ($name && ($maxEntries eq 'unbounded' || 
    #              ($maxEntries > 1 && $maxEntries > $minEntries))) {
    #	if (!$numEntriesParameter) {
    #         print STDERR "$path: missing numEntriesParameter\n" if $pedantic;
    #   } else {
    #	    unless (grep {$_->{name} =~ /$numEntriesParameter/}
    #		    @{$pnode->{nodes}}) {
    #           if ($pedantic > 2) {
    #               print STDERR "$path: missing NumberOfEntries parameter " .
    #                   "($numEntriesParameter)\n";
    #               print STDERR "\t" .
    #                   join(", ", map {$_->{name}} @{$pnode->{nodes}}) . "\n";
    #           }
    #       }
    #	}
    #}

    # determine name of previous sibling (if any) as a hint for where to
    # create the new node
    # XXX can i assume that there's ALWAYS a text node between each
    #     object node?
    my $previous = dmr_previous($object);
    my $prevnode = $object->previousSibling()->previousSibling();
    if (!defined $previous &&
        $prevnode && $prevnode->findvalue('local-name()') eq 'object') {
        $previous = $prevnode->findvalue('@name');
        $previous = $prevnode->findvalue('@ref') unless $previous;
        $previous = $prevnode->findvalue('@base') unless $previous;
        # previous node could be at a lower level than this node, e.g.
        # it might be A.B.C but we are A.D, so adjust to be the previous
        # node at this level
        $previous = adjust_level($previous,
                                 $pnode->{path} . ($ref ? $ref : $name));
        $previous = undef if $previous eq '';
    }
    # XXX this isn't working in a component (need to prefix component path)
    #print STDERR "$previous\n" if $previous;

    # create the new object
    my $nnode = add_object($context, $mnode, $pnode, $name, $ref, 0, $access,
			   $status, $description, $descact, $descdef,
                           $majorVersion, $minorVersion, $previous);

    # XXX add some other stuff (really should be handled by add_object)
    # XXX should detect attempt to change (need to use routine for this)
    check_and_update($path, $nnode, 'minEntries', $minEntries);
    check_and_update($path, $nnode, 'maxEntries', $maxEntries);
    check_and_update($path, $nnode,
                     'numEntriesParameter', $numEntriesParameter);
    check_and_update($path, $nnode, 'enableParameter', $enableParameter);

    # XXX these are slightly different (just take first definition seen)
    $nnode->{noUniqueKeys} = $noUniqueKeys unless
        $nnode->{noUniqueKeys};
    $nnode->{fixedObject} = $fixedObject unless
        $nnode->{fixedObject};

    # note previous uniqueKeys
    my $uniqueKeys = $nnode->{uniqueKeys};
    $nnode->{uniqueKeys} = [];

    # expand nested components, parameters and objects
    foreach my $item ($object->findnodes('component|uniqueKey|parameter|'.
                                         'object')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_$element"->($context, $mnode, $nnode, $item);
    }

    # XXX for unique keys, add any new ones (this means that there is no way
    #     to remove a unique key, but that's OK?)
    if ($uniqueKeys && @$uniqueKeys) {
        if (!@{$nnode->{uniqueKeys}}) {
            $nnode->{uniqueKeys} = $uniqueKeys;
        } else {
            printf STDERR "$path: uniqueKeys changed (new ones added)\n"
                if $verbose;
            # unshift rather than push because $uniqueKeys is the OLD ones
            unshift @{$nnode->{uniqueKeys}}, @$uniqueKeys;
        }
    }
}

# XXX experimental (should add the full "changed" logic)
sub check_and_update
{
    my ($path, $node, $item, $value) = @_;

    if (defined $node->{$item}) {
        # XXX message is only if new value is non-empty (not the best; should
        #     warn if pedantic > 1 because this means that something has been
        #     specified and then is changed later)
        print STDERR "$path: $item: $node->{$item} -> $value\n"
            if $value ne '' && $value ne $node->{$item} && $verbose;
    }
    $node->{$item} = $value if $value ne '';
}

# Get "fixed object" from @dmr:fixedObject, if present
# XXX there's scope for a more general utility here!
sub dmr_fixedObject
{
    my ($element) = @_;

    my $fixedObject = '';

    my $dmr = $element->lookupNamespaceURI('dmr');
    $fixedObject = $element->findvalue('@dmr:fixedObject') if $dmr;

    return $fixedObject;
}

# Get "no unique keys" from @dmr:noUniqueKeys, if present
sub dmr_noUniqueKeys
{
    my ($element) = @_;

    my $noUniqueKeys = '';

    my $dmr = $element->lookupNamespaceURI('dmr');
    $noUniqueKeys = $element->findvalue('@dmr:noUniqueKeys') if $dmr;

    return $noUniqueKeys;
}

# Get major and minor version from @dmr:version, if present
sub dmr_version
{
    my ($element) = @_;

    my $version = '';

    my $dmr = $element->lookupNamespaceURI('dmr');
    $version = $element->findvalue('@dmr:version') if $dmr;

    return $version =~ /(\d+)\.(\d+)/;
}

# Get previous items from dmr:previous*, if present
sub dmr_previous
{
    my ($element, $wanthash) = @_;

    my $dmr = $element->lookupNamespaceURI('dmr');
    my @previous;
    @previous = $element->findnodes('@dmr:previousParameter|'.
                                    '@dmr:previousObject|'.
                                    '@dmr:previousProfile') if $dmr;
    
    return @previous ? $previous[0]->findvalue('.') : undef unless $wanthash;

    my $hash = {};
    foreach my $attr (@previous) {
        my $name = $attr->findvalue('local-name()');
        $attr = $attr ? $attr->findvalue('.') : undef;
        $hash->{$name} = $attr;
    }
    return $hash;
}

# Adjust and return first node name to be at the same level as the second
sub adjust_level
{
    my ($first, $second) = @_;

    $first =~ s/\.\{/\{/g;
    $second =~ s/\.\{/\{/g;

    my @fcomps = split /\./, $first;
    my @scomps = split /\./, $second;

    $first =~ s/\{/\.\{/g;

    return $first if $#scomps >= $#fcomps;

    my $temp = (join '.', @fcomps[0..$#scomps]) . '.';
    $temp =~ s/\{/\.\{/g;

    return $temp;
}

# Expand a data model object unique key
# XXX this is more like mib2dm.pl; need to handle attempts to change unique
#     keys when modifying data models
sub expand_model_uniqueKey
{
    my ($context, $mnode, $pnode, $uniqueKey) = @_;

    my $functional = boolean($uniqueKey->findvalue('@functional'), 1);

    # expand nested parameter references
    my $keyparams = [];
    foreach my $parameter ($uniqueKey->findnodes('parameter')) {
        my $ref = $parameter->findvalue('@ref');
        push @$keyparams, $ref;
    }
    # XXX would prefer the caller to do this
    push @{$pnode->{uniqueKeys}}, {functional => $functional,
                                   keyparams => $keyparams};
}

# Expand a data model parameter.
sub expand_model_parameter
{
    my ($context, $mnode, $pnode, $parameter) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    my $name = $parameter->findvalue('@name');
    my $ref = $parameter->findvalue('@ref');
    $ref = $parameter->findvalue('@base') unless $ref;
    my $access = $parameter->findvalue('@access');
    my $status = $parameter->findvalue('@status');
    my $activeNotify = $parameter->findvalue('@activeNotify');
    my $forcedInform = $parameter->findvalue('@forcedInform');
    # XXX lots of hackery here...
    my @types = $parameter->findnodes('syntax/*');
    my $type = !@types ? undef : $types[0]->findvalue('local-name()') eq 'list' ? $types[1] : $types[0];
    my $values = $parameter->findnodes('syntax/enumeration/value');
    $values = $parameter->findnodes('syntax/string/enumeration')
        unless $values;
    # XXX should note whether values are enumerations or patterns
    $values = $parameter->findnodes('syntax/string/pattern')
        unless $values;
    my $units = $parameter->findvalue('syntax/*/units/@value');
    my $description = $parameter->findvalue('description');
    my $descact = $parameter->findvalue('description/@action');
    my $descdef = $parameter->findnodes('description')->size();
    my $default = $parameter->findvalue('syntax/default/@type') ?
        $parameter->findvalue('syntax/default/@value') : undef;
    my $deftype = $parameter->findvalue('syntax/default/@type');
    my $defstat = $parameter->findvalue('syntax/default/@status');

    # XXX majorVersion and minorVersion are no longer in the schema
    #my $majorVersion = $parameter->findvalue('@majorVersion');
    #my $minorVersion = $parameter->findvalue('@minorVersion');
    my ($majorVersion, $minorVersion) = dmr_version($parameter);

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $file, $spec);

    # XXX I have a feeling that I need to be more rigorous re the distinction
    #     between nodes being absent and nodes having blank values (see the
    #     descdef handling here)

    my $syntax;
    if (defined($type)) {
	foreach my $attr (('@ref', '@base', '@maxLength',
                           'instanceRef/@refType', 'instanceRef/@targetParent',
                           'instanceRef/@targetParentScope',
                           'pathRef/@refType','pathRef/@targetParent',
                           'pathRef/@targetParentScope', 'pathRef/@targetType',
                           'pathRef/@targetDataType',
                           'enumerationRef/@targetParam',
                           'enumerationRef/@targetParamScope')) {
	    my $val = $type->findvalue($attr);
            my $tattr = $attr;
            $tattr =~ s/.*@//;
            # XXX very limited handling for status="deleted"; can tell by
            #     defined but empty attribute value
            if ($attr =~ /\//) {
                my $sattr = $attr;
                $sattr =~ s/@.*/\@status/;
                my $vst = $type->findvalue($sattr);
                if (defined $vst && $vst eq 'deleted') {
                    $syntax->{$tattr} = '';
                } else {
                    $syntax->{$tattr} = $val if $val ne '';
                }
            } else {
                $syntax->{$tattr} = $val if $val ne '';
            }
	}
        # XXX special case for nullValue; need to distinguish undef and empty
        my $nullValue = ($type->findnodes('enumerationRef/@nullValue'))[0];
        $syntax->{nullValue} = $nullValue->findvalue('.') if $nullValue;

        # handle multiple sizes
        foreach my $size ($type->findnodes('size')) {
            my $minLength = $size->findvalue('@minLength');
            my $maxLength = $size->findvalue('@maxLength');
            my $status = $size->findvalue('@status');

            # XXX this is brain dead handling of status="deleted"; should
            #     check for a matching entry
            if ($status && $status eq 'deleted') {
                $syntax->{sizes} = [];
                next;
            }

            $minLength = undef if $minLength eq '';
            $maxLength = undef if $maxLength eq '';
            if (defined $minLength || defined $maxLength) {
                push @{$syntax->{sizes}}, {minLength => $minLength,
                                           maxLength => $maxLength};
            }
        }

        # handle multiple ranges 
        # XXX no support for status="deleted"
        foreach my $range ($type->findnodes('range')) {
            my $minInclusive = $range->findvalue('@minInclusive');
            my $maxInclusive = $range->findvalue('@maxInclusive');
            my $step = $range->findvalue('@step');
            my $status = $range->findvalue('@status');

            # XXX this is brain dead handling of status="deleted"; should
            #     check for a matching entry
            if ($status && $status eq 'deleted') {
                $syntax->{ranges} = [];
                next;
            }

            $minInclusive = undef if $minInclusive eq '';
            $maxInclusive = undef if $maxInclusive eq '';
            $step = undef if $step eq '';
            if (defined $minInclusive || defined $maxInclusive ||
                defined $step) {
                push @{$syntax->{ranges}}, {minInclusive => $minInclusive,
                                            maxInclusive => $maxInclusive,
                                            step => $step};
            }
        }
    }
    $syntax->{hidden} = defined(($parameter->findnodes('syntax/@hidden'))[0]);
    $syntax->{command} = defined(($parameter->findnodes('syntax/@command'))[0]);
    $syntax->{list} = defined(($parameter->findnodes('syntax/list'))[0]);
    if ($syntax->{list}) {
        my $status = $parameter->findvalue('syntax/list/@status');
        my $minItems = $parameter->findvalue('syntax/list/@minItems');
        my $maxItems = $parameter->findvalue('syntax/list/@maxItems');
        $syntax->{liststatus} = $status;
        $minItems = undef if $minItems eq '';
        $maxItems = undef if $maxItems eq '';
        if (defined $minItems || defined $maxItems) {
            push @{$syntax->{listRanges}}, {minInclusive => $minItems,
                                            maxInclusive => $maxItems};
        }
        my $minLength = $parameter->findvalue('syntax/list/size/@minLength');
        my $maxLength = $parameter->findvalue('syntax/list/size/@maxLength');
        $minLength = undef if $minLength eq '';
        $maxLength = undef if $maxLength eq '';
        if (defined $minLength || defined $maxLength) {
            push @{$syntax->{listSizes}}, {minLength => $minLength,
                                           maxLength => $maxLength};
        }
    }

    if (defined($type)) {
        foreach my $facet (('instanceRef', 'pathRef', 'enumerationRef')) {
            $syntax->{reference} = $facet if $type->findnodes($facet);
        }
    }

    #print STDERR Dumper($syntax) if $syntax->{reference};

    $type = defined($type) ? $type->findvalue('local-name()') : '';

    my $tvalues = {};
    my $i = 0;
    foreach my $value (@$values) {
        my $facet = $value->findvalue('local-name()');
        my $access = $value->findvalue('@access');
        my $status = $value->findvalue('@status');
        my $optional = $value->findvalue('@optional');
        my $description = $value->findvalue('description');
        my $descact = $value->findvalue('description/@action');
        my $descdef = $value->findnodes('description')->size();
        $value = $value->findvalue('@value');
        
        $status = util_maybe_deleted($status);
        update_bibrefs($description, $file, $spec);

        # XXX where should such defaults be applied? here is better
        $access = 'readWrite' unless $access;
        $status = 'current' unless $status;
        # don't default descact, so can tell whether it was specified
        
        $tvalues->{$value} = {access => $access, status => $status,
                              optional => $optional,
                              description => $description,
                              descact => $descact, descdef => $descdef,
                              facet => $facet,
                              i => $i++};
    }
    $values = $tvalues;
    #print STDERR Dumper($values);
    
    print STDERR "expand_model_parameter name=$name ref=$ref\n" if
        $verbose > 1;

    # ignore if doesn't match write-only criterion
    if ($writonly && $access eq 'readOnly') {
	print STDERR "\tdoesn't match write-only criterion\n" if $verbose > 1;
	return;
    }

    # XXX this is incomplete name / ref handling
    # XXX WFL2 my $tname = $name ? $name : $ref;
    my $oname = $name;
    my $oref = $ref;
    my $tname = $ref ? $ref : $name;
    my $path = $pnode->{path}.$tname;

    # the name may consist of multiple components; create any intervening
    # objects, returning the new parent and the last component of the name
    ($pnode, $name) = add_path($context, $mnode, $pnode, $tname, 1);
    # XXX this is more of the incomplete name / ref handling
    if ($ref) {
        $ref = $name;
        # XXX WFL2 $name = '';
        # XXX this will fail if $oname has multiple components (which it
        #     shouldn't have)
        $name = ($oname && $oref) ? $oname : '';
    }

    # determine name of previous sibling (if any) as a hint for where to
    # create the new node
    # XXX can i assume that there's ALWAYS a text node between each
    #     parameter node?
    my $previous = dmr_previous($parameter);
    my $prevnode = $parameter->previousSibling()->previousSibling();
    if (!defined $previous &&
        $prevnode && $prevnode->findvalue('local-name()') eq 'parameter') {
        $previous = $prevnode->findvalue('@name');
        $previous = $prevnode->findvalue('@base') unless $previous;
        $previous = undef if $previous eq '';
    }

    add_parameter($context, $mnode, $pnode, $name, $ref, $type, $syntax,
                  $access, $status, $description, $descact, $descdef, $values,
                  $default, $deftype, $defstat, $majorVersion, $minorVersion,
                  $activeNotify, $forcedInform, $units, $previous);
}

# Expand a data model profile.
sub expand_model_profile
{
    my ($context, $mnode, $pnode, $profile) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    my $name = $profile->findvalue('@name');
    my $base = $profile->findvalue('@base');
    my $extends = $profile->findvalue('@extends');
    # XXX model no longer used
    my $model = $profile->findvalue('@model');
    my $status = $profile->findvalue('@status');
    my $description = $profile->findvalue('description');
    # XXX descact too

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $file, $spec);

    $name = $base unless $name;

    # XXX want to do this consistently; really want to get defaults from
    #     somewhere (not hard-coded)
    $status = 'current' unless $status;

    print STDERR "expand_model_profile name=$name base=$base ".
        "extends=$extends\n" if $verbose > 1;

    # XXX are there any valid circumstances under which would specify both
    #     base and extends?  I don't think it's invalid to do so.

    # determine name of previous sibling (if any) as a hint for where to
    # create the new node
    # XXX can i assume that there's ALWAYS a text node between each
    #     profile node?
    # XXX yes maybe, but it might not be a profile node, so would be best to
    #     avoid previousSibling() and just keep track of previous profile
    my $previous = dmr_previous($profile);
    my $prevnode = $profile->previousSibling()->previousSibling();
    if (!defined $previous &&
        $prevnode && $prevnode->findvalue('local-name()') eq 'profile') {
        $previous = $prevnode->findvalue('@name');
        $previous = undef if $previous eq '';
    }

    # if the context contains "previousProfile", it's from a component
    # reference, and applies only to the first profile
    if ($context->[0]->{previousProfile}) {
        $previous = $context->[0]->{previousProfile};
        undef $context->[0]->{previousProfile};
    }

    # XXX use mnode rather than pnode, because of problems when expanding
    #     profile components with paths (need to explain this!)

    # XXX also, there are problems if mix objects and profiles at the top level
    #     (never a problem in real data models); should ensure that all
    #     profiles come after all objects (or else handle this in the tree
    #     traversal; the latter is better; already do this for parameters)

    # check whether profile already exists
    my ($nnode) = grep {
        $_->{type} eq 'profile' && $_->{name} eq $name} @{$mnode->{nodes}};
    if ($nnode) {
        # XXX don't automatically report this until have sorted out profile
        #     re-definition
        print STDERR "$name: profile already defined\n" if
            $pedantic && !$autobase && $base && $name ne $base;
        # XXX profiles can never change, so just give up; BUT this means that
        #     we won't detect corrections, deprecations etc, so is not good
        #     enough
        #return;
    } else {
        # if base specified, find base profile
        my $baseprof;
        if ($base) {
            ($baseprof) = grep {
                $_->{type} eq 'profile' && $_->{name} eq $base;
            } @{$mnode->{nodes}};
            print STDERR "{$file}$base: profile not found (ignoring)\n" unless
                $baseprof;
        }

        # otherwise check anyway for previous version (this allows later
        # versions to be defined both using base and standalone)
        else {
            # improve this; handle redef of prof / obj / par; add version...
            # make generated xml2 valid (need types)
            # XXX currently only copes with one previous version
            ($baseprof) = grep {
                my ($a) = ($name =~ /([^:]*)/);
                my ($b) = ($_->{name} =~ /([^:]*)/);
                $_->{type} eq 'profile' && $a eq $b;
            } @{$mnode->{nodes}};
            $base = $baseprof->{name} if $baseprof;
        }

        # if extends specified, find profiles that are being extended
        my $extendsprofs;
        if ($extends) {
            foreach my $extend (split /\s+/, $extends) {
                my ($extprof) = grep {
                    $_->{type} eq 'profile' && $_->{name} eq $extend;
                } @{$mnode->{nodes}};
                print STDERR "{$file}$extend: profile not found (ignoring)\n"
                    unless $extprof;
                push @$extendsprofs, $extprof if $extprof;
            }
        }

        my ($mname_only, $mversion_major, $mversion_minor) =
            ($mnode->{name} =~ /([^:]*):(\d+)\.(\d+)/);

        $nnode = {pnode => $mnode, path => $name, name => $name, base => $base,
                  extends => $extends, file => $file, lfile => $Lfile,
                  spec => $spec, lspec => $Lspec, type => 'profile',
                  access => '', status => $status, description => $description,
                  model => $model, nodes => [], baseprof => $baseprof,
                  extendsprofs => $extendsprofs,
                  majorVersion => $mversion_major,
                  minorVersion => $mversion_minor,
                  errors => {}};
        # determine where to insert the new node; after base profile first;
        # then after extends profiles; after previous node otherwise
        my $index = @{$mnode->{nodes}};
        if ($previous) {
            for (0..$index-1) {
                if (@{$mnode->{nodes}}[$_]->{name} eq $previous) {
                    $index = $_+1;
                    last;
                }
            }
       } elsif ($base) {
            for (0..$index-1) {
                if (@{$mnode->{nodes}}[$_]->{name} eq $base) {
                    $index = $_+1;
                    last;
                }
            }
        } elsif ($extends) {
            # XXX this always puts the profile right after the profile that
            #     it extends, so if more than one profile extends another,
            #     they end up in reverse order
            EXTEND: foreach my $extend (split /\s+/, $extends) {
                for (0..$index-1) {
                    if (@{$mnode->{nodes}}[$_]->{name} eq $extend) {
                        $index = $_+1;
                        last EXTEND;
                    }
                }
            }
        } elsif (defined $previous && $previous eq '') {
            $index = 0;
        }
        splice @{$mnode->{nodes}}, $index, 0, $nnode;

        # defmodel is the model in which the profile was first defined
        # (usually this is the current model, but not if this XML was
        # flattened by the xml2 report, in which case it is indicated
        # by dmr:version
        my ($majorVersion, $minorVersion) = dmr_version($profile);
        my $version = defined $majorVersion && defined $minorVersion ?
            qq{$majorVersion.$minorVersion} : undef;
        my $defmodel = $version ? qq{$mname_only:$version} : $mnode->{name};
        $profiles->{$name}->{defmodel} = $defmodel;
    }

    # expand nested parameters and objects
    foreach my $item ($profile->findnodes('parameter|object')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_profile_$element"->($context, $nnode, $nnode, $item);
    }
}

# Expand a data model profile object.
sub expand_model_profile_object
{
    my ($context, $Pnode, $pnode, $object) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};
    # this is the path attribute from component reference
    my $Path = $context->[0]->{path};

    my $name = $object->findvalue('@ref');
    my $access = $object->findvalue('@requirement');
    my $status = $object->findvalue('@status');
    my $description = $object->findvalue('description');
    my $descact = $object->findvalue('description/@action');
    my $descdef = $object->findnodes('description')->size();

    $status = 'current' unless $status;
    $status = util_maybe_deleted($status);
    update_bibrefs($description, $file, $spec);

    print STDERR "expand_model_profile_object path=$Path ref=$name\n" if
        $verbose > 1;

    $name = $Path . $name if $Path;

    # these errors are reported by sanity_node
    unless ($objects->{$name} && %{$objects->{$name}}) {
        if ($noprofiles) {
        } elsif (!defined $Pnode->{errors}->{$name}) {
            $Pnode->{errors}->{$name} = {status => $status};
        } else {
            $Pnode->{errors}->{$name}->{status} = $status;
        }
        delete $Pnode->{errors}->{$name} if $status eq 'deleted';
        return;
    }

    # XXX need bad hyperlink to be visually apparent
    # XXX should check that access matches the referenced object's access

    # if requirement is not greater than that of the base profile or one of
    # the extends profiles, reduce it to 'notSpecified' (but never if descr)
    my $can_ignore = 0;
    my $poa = {notSpecified => 0, present => 1, create => 2, delete => 3,
               createDelete => 4};
    my $baseprof = $Pnode->{baseprof};
    my $baseobj;
    if ($baseprof) {
        ($baseobj) = grep {$_->{name} eq $name} @{$baseprof->{nodes}};
        if ($baseobj && $poa->{$access} <= $poa->{$baseobj->{access}} &&
            $status eq $baseobj->{status} && !$descdef) {
            $can_ignore = 1;
            print STDERR "profile $Pnode->{name} can ignore object $name\n" if
                $verbose;
        }
    }
    # XXX this logic isn't implemented for extends profiles (it is less
    #     necessary but can be added if need be)

    my $push_needed = 1;
    my $push_deferred = 0;
    my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
    my $nnode;
    if (@match) {
	$nnode = $match[0];
        $push_needed = 0;
    } else {
	$nnode = {pnode => $pnode, path => $name, name => $name,
                  type => 'objectRef', access => $access, status => $status,
                  description => $description, descact => $descact,
                  descdef => $descdef, nodes => [], baseobj => $baseobj};
        $push_deferred = 1;
    }

    # expand nested parameters and objects
    # XXX schema doesn't support nested objects
    # XXX this isn't quite right; should use profile equivalent of add_path()
    #     to create intervening nodes; currently top-level parameters are in
    #     the wrong place in the hierarchy
    foreach my $item ($object->findnodes('parameter|object')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_profile_$element"->($context, $Pnode, $nnode, $item);
    }

    # suppress push if possible
    # XXX not supporting previousObject in profiles
    if ($can_ignore && $push_deferred && !@{$nnode->{nodes}}) {
        print STDERR "profile $Pnode->{name} will ignore object $name\n" if
            $verbose;
    } elsif ($push_needed) {
        push(@{$pnode->{nodes}}, $nnode);
        $profiles->{$Pnode->{name}}->{$name} = $access;
    }
}

# Expand a data model profile parameter.
sub expand_model_profile_parameter
{
    my ($context, $Pnode, $pnode, $parameter) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};
    # this is the path attribute from component reference
    my $Path = $context->[0]->{path};

    my $name = $parameter->findvalue('@ref');
    my $access = $parameter->findvalue('@requirement');
    my $status = $parameter->findvalue('@status');
    my $description = $parameter->findvalue('description');
    my $descact = $parameter->findvalue('description/@action');
    my $descdef = $parameter->findnodes('description')->size();

    $status = 'current' unless $status;
    $status = util_maybe_deleted($status);
    update_bibrefs($description, $file, $spec);

    print STDERR "expand_model_profile_parameter path=$Path ref=$name\n" if
        $verbose > 1;

    my $path = $pnode->{type} eq 'profile' ? $name : $pnode->{name}.$name;
    # special case for parameter at top level of a profile
    $path = $Path . $path if $Path && $Pnode == $pnode;

    # these errors are reported by sanity_node
    unless (util_is_defined($parameters, $path)) {
        if ($noprofiles) {
        } elsif (!defined $Pnode->{errors}->{$path}) {
            $Pnode->{errors}->{$path} = {status => $status};
        } else {
            $Pnode->{errors}->{$path}->{status} = $status;
        }
        delete $Pnode->{errors}->{$path} if $status eq 'deleted';
        return;
    } elsif ($access ne 'readOnly' &&
             $parameters->{$path}->{access} eq 'readOnly') {
	print STDERR "profile $Pnode->{name} has invalid requirement ".
            "($access) for $path ($parameters->{$path}->{access})\n";
    }

    # XXX need bad hyperlink to be visually apparent

    # if requirement is not greater than that of the base profile, reduce
    # it to 'notSpecified' (but not if descr)
    my $ppa = {readOnly => 0, readWrite => 1};
    my $baseobj = $pnode->{baseobj};
    if ($baseobj) {
        my ($basepar) = grep {$_->{name} eq $name} @{$baseobj->{nodes}};
        if ($basepar && $ppa->{$access} <= $ppa->{$basepar->{access}} &&
            $status eq $basepar->{status} && !$descdef) {
            print STDERR "profile $Pnode->{name} ignoring parameter $path\n" if
                $verbose;
            return;
        }
    }

    # determine name of previous sibling (if any) as a hint for where to
    # create the new node
    # XXX can i assume that there's ALWAYS a text node between each
    #     parameter node?
    my $previous = dmr_previous($parameter);
    my $prevnode = $parameter->previousSibling()->previousSibling();
    if (!defined $previous &&
        $prevnode && $prevnode->findvalue('local-name()') eq 'parameter') {
        $previous = $prevnode->findvalue('@ref');
        $previous = undef if $previous eq '';
    }

    my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
    my $nnode;
    if (@match) {
        # XXX could / should check for changed requirements here (but
        #     should be used only for errata)
	$nnode = $match[0];
    } else {
        # XXX recently added path; there is code elsewhere that creates it
        #     when needed rather than taking from the node (should tidy up)
        $nnode = {pnode => $pnode, path => $path, name => $name,
                  type => 'parameterRef', access => $access, status => $status,
                  description => $description, descact => $descact,
                  descdef => $descdef, nodes => []};

        # if previous is defined, it's a hint to insert this node after the
        # node of this name, if it exists
        my $index = @{$pnode->{nodes}};
        if (defined $previous && $previous eq '') {
            $index = 0;
        } elsif ($previous) {
            for (0..$index-1) {
                if (@{$pnode->{nodes}}[$_]->{name} eq $previous) {
                    $index = $_+1;
                    last;
                }
            }
        }
        splice @{$pnode->{nodes}}, $index, 0, $nnode;
        $profiles->{$Pnode->{name}}->{$path} = $access;
    }
}

# Helper to add a data model if it doesn't already exist (if it does exist then
# nothing in the new data model can conflict with anything in the old)
sub add_model
{
    my ($context, $pnode, $name, $ref, $isService, $status, $description,
        $descact, $descdef, $majorVersion, $minorVersion) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    $ref = '' unless $ref;
    $isService = 0 unless $isService;
    $status = 'current' unless $status;
    $description = '' unless $description;
    # don't default descact, so can tell whether it was specified
    $majorVersion = 0 unless $majorVersion;
    $minorVersion = 0 unless $minorVersion;

    print STDERR "add_model name=$name ref=$ref isService=$isService\n" if
        $verbose > 1;

    # XXX monumental hack to allow vendor models to be derived from standard
    #     ones; assume that PrefixModel:a.b is derived from Model:c.d
    my ($tname, $tnamever) = $name =~ /([^:]*):(.*)/;
    my ($tref, $trefver) = $ref =~ /([^:]*):(.*)/;
    if ($tref && $tref ne $tname && $tname =~ /$tref$/) {
        print STDERR "hacked so model $name is derived from $ref\n"
            if $verbose;
        $tname = qq{$tref:$tnamever};
    }

    # if ref, find the referenced model
    my $nnode;
    if ($ref) {
        my @match = grep {
            my ($a) = ($tname =~ /([^:]*)/);
            my ($b) = ($_->{name} =~ /([^:]*)/);
            $_->{type} eq 'model' && $a eq $b;
        } @{$root->{nodes}};
        # there can't be more than one match
        if (@match) {
            $nnode = $match[0];
            print STDERR "reusing node $nnode->{name}\n" if $verbose > 1;
        } elsif (load_model($context, $file, $spec, $ref)) {
            @match = grep {
                my ($a) = ($tname =~ /([^:]*)/);
                my ($b) = ($_->{name} =~ /([^:]*)/);
                $_->{type} eq 'model' && $a eq $b;
            } @{$root->{nodes}};
            $nnode = $match[0];
            print STDERR "{$file}$ref: model loaded\n" if $verbose;
        } else {
            # XXX if not found, for now auto-create it
            print STDERR "{$file}$ref: model not found (auto-creating)\n";
        }
    }

    if ($nnode) {
        # cache current node contents
        my $cnode = util_copy($nnode, ['history', 'nodes']);

        # indicate that model was previously known (report might need to
        # use this info)
        $nnode->{history} = [] unless defined $nnode->{history};

        # XXX want similar "changed" logic to objects and parameters?

	$nnode->{name} = $name;

        # XXX this is still how we're handling the version number...
	$nnode->{majorVersion} = $majorVersion;
	$nnode->{minorVersion} = $minorVersion;

	# XXX spec should perhaps be an array and would therefore list all
	#     the specs that contributed to the data model definition
        # XXX unlike objects and parameters, we change it here, because this
        #     is defining a new model version (this is a problem when changing
        #     a model without changing the version, which is why we need a list
        #     of specs, then tools can use the first, last, or all of them
        # XXX the same goes for file
        # XXX also, should support lspec consistently for models?
	$nnode->{file} = $file;
	$nnode->{spec} = $spec;

        # XXX need cleverer comparison
        # XXX need same deferred reporting logic that have for objects and
        #     parameters
        if ($description) {
            if ($description ne $nnode->{description}) {
                print STDERR "$name: description: changed\n" if $verbose;
                $nnode->{description} = $description;
            }
            my $tdescact = util_default($descact);
            print STDERR "$name: invalid description action: $tdescact\n"
                if $pedantic && !$autobase &&
                (!$descact || $descact eq 'create');
        }
        # XXX need cleverer comparison
        if ($descact && $descact ne $nnode->{descact}) {
            print STDERR "$name: descact: $nnode->{descact} -> $descact\n"
                if $verbose > 1;
            $nnode->{descact} = $descact;
        }

        # sub-tree is hidden (i.e. not reported) unless nodes within it are
        # referenced, at which point they and their parents are un-hidden
        # XXX suppress until sort out the fact that models defined in files
        #     specified on the command line should not be hidden
        # XXX this conditional restore is for DT and relies on the fact that
        #     name and ref will be same for DT (owing to hack in the caller)
        hide_subtree($nnode) if $name eq $ref;
        unhide_node($nnode);

        # retain info from previous versions
        unshift @{$nnode->{history}}, $cnode;
    } else {
        print STDERR "unnamed model (after $previouspath)\n" unless $name;
        print STDERR "$name: invalid description action: $descact\n"
            if $pedantic && !$autobase && $descact && $descact ne 'create';
        my $dynamic = $pnode->{dynamic};
        # XXX experimental; may break stuff? YEP!
        #my $path = $isService ? '.' : '';
        my $path = '';
	$nnode = {name => $name, path => $path, file => $file, spec => $spec,
                  type => 'model', access => '',
                  isService => $isService, status => $status,
                  description => $description, descact => $descact,
                  descdef => $descdef, default => undef, dynamic => $dynamic,
                  majorVersion => $majorVersion, minorVersion => $minorVersion,
                  nodes => [], history => undef};
        push @{$pnode->{nodes}}, $nnode;
        $previouspath = $path;
    }

    return $nnode;
}

# Load a deferred model.
sub load_model
{
    my ($context, $file, $spec, $ref) = @_;

    my $models = [];

    while (my ($model) = grep {$_->{element} eq 'model' && $_->{name} eq $ref}
           @{$imports->{$file}->{imports}}) {
        # XXX need better way of distinguishing defining and importing entry
        unshift @$models, $model if
            !@$models || $model->{file} ne $models->[0]->{file};
        last unless $model->{ref};
        $file = $model->{file};
        $ref  = $model->{ref};
    }

    foreach my $model (@$models) {
        my $file = $model->{file};
        my $spec = $model->{spec};
        my $item = $model->{item};
        unshift @$context, {file => $file, spec => $spec,
                            lfile => $file, lspec => $spec,
                            path => '', name => ''};

        #print STDERR "XXXX modl $ref in $file; $file\n";

        expand_model($context, $root, $item);
        shift @$context;
    }

    # XXX need to check proper failure criteria
    return 1;
}

# Hide a sub-tree.
sub hide_subtree
{
    my ($node, $ponly) = @_;

    #print STDERR "hide_subtree: $node->{path}\n" if
    #    $node->{path} =~ /\.$/ && $verbose;

    unless ($node->{hidden}) {
        print STDERR "hiding $node->{type} $node->{name}\n" if $verbose > 1;
        $node->{hidden} = 1;
    }

    foreach my $child (@{$node->{nodes}}) {
        my $type = $child->{type};
        hide_subtree($child) unless $ponly &&
            $type =~ /^(model|object|profile|parameterRef|objectRef)$/;
    }
}

# Un-hide a node and its ancestors.
sub unhide_node
{
    my ($node) = @_;

    if ($node->{hidden}) {
        print STDERR "un-hiding $node->{type} $node->{name}\n" if $verbose > 1;
        $node->{hidden} = 0;
    }

    unhide_node($node->{pnode}) if $node->{pnode};
}

# Helper that, given a path, creates any intervening objects (if $return_last
# is true, doesn't create last component, but instead returns it)
# XXX want an indication that an object was created via add_path, so that all
#     values when it is next encountered will be used, e.g. "access"
sub add_path
{
    my ($context, $mnode, $pnode, $name, $return_last) = @_;

    print STDERR "add_path name=$pnode->{path}$name\n" if $verbose > 1;

    my $tname = $name;
    $tname =~ s/\.\{/\{/g;

    my $object = ($tname =~ /\.$/);
    my @comps = split /\./, $tname;

    my $last = '';
    if (@comps) {
        if ($return_last) {
            $last = pop(@comps);
	    $last =~ s/\{/\.\{/;
	    $last =~ s/$/\./ if $object;
        }
	for (my $i = 0; $i < @comps; $i++) {
	    $comps[$i] =~ s/\{/\.\{/;
	    $comps[$i] =~ s/$/\./;
	    $pnode = add_object($context, $mnode, $pnode, '', $comps[$i], 1);
	}
    }

    return ($pnode, $last);
}

# Helper to add an object if it doesn't already exist (if it does exist then
# nothing in the new object can conflict with anything in the old)
sub add_object
{
    my ($context, $mnode, $pnode, $name, $ref, $auto, $access, $status,
        $description, $descact, $descdef, $majorVersion, $minorVersion,
        $previous) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    # if the context contains "previousObject", it's from a component
    # reference, and applies only to the first object
    if ($context->[0]->{previousObject}) {
        $previous = $context->[0]->{previousObject};
        undef $context->[0]->{previousObject};
    }

    $ref = '' unless $ref;
    $auto = 0 unless $auto;
    $access = 'readOnly' unless $access;
    $status = 'current' unless $status;
    $description = '' unless $description;
    # don't default descact, so can tell whether it was specified
    # don't touch version, since undefined is significant

    my $path = $pnode->{path} . ($ref ? $ref : $name);

    print STDERR "add_object name=$name ref=$ref auto=$auto spec=$spec\n" if
        $verbose > 1 || ($debugpath && $path =~ /$debugpath/);

    # if ref, find the referenced object
    my $nnode;
    if ($ref) {
        my @match = grep {$_->{name} eq $ref} @{$pnode->{nodes}};
        if (@match) {
            $nnode = $match[0];
            unhide_node($nnode);
        } else {
            # XXX if not found, for now auto-create it
            print STDERR "$path: object not found (auto-creating)\n";
            $name = $ref;
            $auto = 1;
        }
    } elsif ($name) {
        my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
        # XXX should this be unconditional?
        # XXX sometimes don't want report (need finer reporting control)
        if (@match && !$autobase) {
            print STDERR "$path: object already defined (new one ignored)\n"
                if $verbose || !$nowarnredef;
            return $match[0];
        }
	$nnode = $match[0];
    }

    if ($nnode) {
	# if auto, nothing more to be done (covers the case where are
        # traversing down the path of an existing object)
        # XXX it's important to do this before setting the history
        # XXX recent change to move before undefine "changed"
	return $nnode if $auto;

        # XXX hack for DT; doing it unconditionally, although there is
        #     probably a reason why this isn't normally done!
        $nnode->{changed} = undef;

        # cache current node contents
        my $cnode = util_copy($nnode, ['history', 'nodes', 'pnode']);

        # indicate that object was previously known (report might need to
        # use this info)
        $nnode->{history} = [] unless defined $nnode->{history};

        # XXX if both name and ref are defined, this is a rename operation
        # XXX what if the new-named object already exists?
        # XXX what are the implications for history?
        # XXX should this be marked as a change? yes
        if ($name && $ref) {
            $objects->{$path} = undef;
            $path = $pnode->{path} . $name;
            $nnode->{path} = $path;
            $nnode->{name} = $name;
            $objects->{$path} = $nnode;
            # XXX this does only half the job; should build the objects and
            #     parameters hashes after the tree has been built
            # XXX should also avoid nodes knowing their path names
            foreach my $tnode (@{$nnode->{nodes}}) {
                if ($tnode->{type} ne 'object') {
                    my $opath = $tnode->{path};
                    my $tpath = $path . $tnode->{name};
                    $tnode->{path} = $tpath;
                    $parameters->{$opath} = undef;
                    $parameters->{$tpath} = $tnode;
                }
            }
            print STDERR "$path: renamed from $ref\n" if $verbose;
        }

        # when an object is modified, its last spec (lspec) and modified spec
        # (mspec) are updated
        my $changed = {};
 
        # XXX should use a utility routine for this change checking
        if ($access ne $nnode->{access}) {
            print STDERR "$path: access: $nnode->{access} -> $access\n"
                if $verbose;
            $nnode->{access} = $access;
            $changed->{access} = 1;
        }
        if ($status ne $nnode->{status}) {
            print STDERR "$path: status: $nnode->{status} -> $status\n"
                if $verbose;
            $nnode->{status} = $status;
            $changed->{status} = 1;
        }
        if ($description) {
            if ($description eq $nnode->{description}) {
                $nnode->{errors}->{samedesc} = $descact if !$autobase;
            } else {
                $nnode->{errors}->{samedesc} = undef;
                # XXX not if descact is append?
                my $diffs = util_diffs($nnode->{description}, $description);
                print STDERR "$path: description: changed\n" if $verbose;
                print STDERR $diffs if $verbose > 1;
                $nnode->{description} = $description;
                $changed->{description} = $diffs;
            }
            $nnode->{errors}->{baddescact} =
                (!$autobase && (!$descact || $descact eq 'create')) ?
                $descact : undef;
        }
        # XXX need cleverer comparison
        if ($descact && $descact ne $nnode->{descact}) {
            print STDERR "$path: descact: $nnode->{descact} -> $descact\n"
                if $verbose > 1;
            $nnode->{descact} = $descact;
        }
        if (($pnode->{dynamic} || $nnode->{access} ne 'readOnly') !=
            $nnode->{dynamic}) {
            print STDERR "$path: dynamic: $nnode->{dynamic} -> ".
                "$pnode->{dynamic}\n" if $verbose;
            $nnode->{dynamic} = $pnode->{dynamic} || $access ne 'readOnly';
            $changed->{dynamic} = 1;
        }        

        # XXX more to copy...

        # if not changed, retain info from previous versions
        # XXX have to be careful about tests in references, e.g. here
        #     if ($changed) doesn't work because it refers to the reference,
        #     not to the hash
        if (keys %$changed) {
            unshift @{$nnode->{history}}, $cnode;
            $nnode->{changed} = $changed;
            $nnode->{lfile} = $Lfile;
            $nnode->{lspec} = $Lspec;
            $nnode->{mspec} = $spec;
            mark_changed($pnode, $Lfile, $Lspec);
            # XXX experimental (absent description is like appending nothing)
            if (!$description) {
                $nnode->{description} = '';
                $nnode->{descact} = 'append';
            }
        }
        # XXX unconditionally keep track of files in which node was seen
        $nnode->{sfile} = $Lfile;
    } else {
        print STDERR "unnamed object (after $previouspath)\n" unless $name;
        print STDERR "$name: invalid description action: $descact\n"
            if $pedantic && !$autobase && $descact && $descact ne 'create';

        # XXX this is still how we're handling the version number...
	$majorVersion = $mnode->{majorVersion} unless defined $majorVersion;
	$minorVersion = $mnode->{minorVersion} unless defined $minorVersion;

        print STDERR "$path: added\n" if
            $verbose && $mnode->{history} && @{$mnode->{history}} && !$auto;

        mark_changed($pnode, $Lfile, $Lspec);
        
        my $dynamic = $pnode->{dynamic} || $access ne 'readOnly';

	$nnode = {pnode => $pnode, name => $name, path => $path, file => $file,
                  lfile => $Lfile, sfile => $Lfile, spec => $spec,
                  lspec => $Lspec, mspec => $spec, type => 'object',
                  auto => $auto, access => $access, status => $status,
                  description => $description, descact => $descact,
                  descdef => $descdef, default => undef, dynamic => $dynamic,
                  majorVersion => $majorVersion, minorVersion => $minorVersion,
                  nodes => [], history => undef, errors => {}};
        $previouspath = $path;
        # XXX ensure minEntries and maxEntries are defined (will be overridden
        #     by the caller if necessary; all this logic should be here)
        # XXX no, bad idea! but yes, all this logic should be here
        #$nnode->{minEntries} = 1;
        #$nnode->{maxEntries} = 1;
        # if previous is defined, it's a hint to insert this node after the
        # node of this name, if it exists
        my $index = @{$pnode->{nodes}};
        if (defined $previous && $previous eq '') {
            $index = 0;
        } elsif ($previous) {
            # XXX special case; if previous is the parent, insert as first
            #     child
            if ($previous eq $pnode->{path}) {
                $index = 0;
            } else {
                for (0..$index-1) {
                    if (@{$pnode->{nodes}}[$_]->{path} eq $previous) {
                        $index = $_+1;
                        last;
                    }
                }
            }
        }
        splice @{$pnode->{nodes}}, $index, 0, $nnode;
	$objects->{$path} = $nnode;
    }

    print STDERR Dumper(util_copy($nnode, ['pnode', 'nodes'])) if
        $debugpath && $path =~ /$debugpath/;

    return $nnode;
}

# Helper to mark a node's ancestors as having been changed
sub mark_changed
{
    my ($node, $Lfile, $Lspec) = @_;

    while ($node && $node->{type} eq 'object') {
        $node->{lfile} = $Lfile;
        $node->{lspec} = $Lspec;
        $node = $node->{pnode};
    }
}

# Helper to add a parameter if it doesn't already exist (if it does exist then
# nothing in the new parameter can conflict with anything in the old)
sub add_parameter
{
    my ($context, $mnode, $pnode, $name, $ref, $type, $syntax, $access,
        $status, $description, $descact, $descdef, $values, $default, $deftype,
        $defstat, $majorVersion, $minorVersion, $activeNotify, $forcedInform,
        $units, $previous)
        = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    # if the context contains "previousParameter", it's from a component
    # reference, and applies only to the first parameter
    if ($context->[0]->{previousParameter}) {
        $previous = $context->[0]->{previousParameter};
        undef $context->[0]->{previousParameter};
    }

    $ref = '' unless $ref;
    # don't default data type
    # assume that syntax defaulting has already been handled
    $access = 'readOnly' unless $access;
    $status = 'current' unless $status;
    $description = '' unless $description;
    # don't default descact, so can tell whether it was specified
    # assume that values defaulting has already been handled
    # don't touch default, since undefined is significant
    $deftype = 'object' unless $deftype;
    $defstat = 'current' unless $defstat;
    # don't touch version, since undefined is significant
    $activeNotify = 'normal' unless $activeNotify;
    # forcedInform is boolean

    my $path = $pnode->{path} . ($ref ? $ref : $name);
    my $auto = 0;

    print STDERR "add_parameter name=$name ref=$ref\n" if
        $verbose > 1 || ($debugpath && $path =~ /$debugpath/);

    # if ref, find the referenced parameter
    my $nnode;
    if ($ref) {
        my @match = grep {$_->{name} eq $ref} @{$pnode->{nodes}};
        if (@match) {
            $nnode = $match[0];
            unhide_node($nnode);
        } else {
            # XXX if not found, for now auto-create it
            print STDERR "$path: parameter not found (auto-creating)\n";
            $name = $ref;
            $auto = 1;
        }
    } elsif ($name) {
        my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
        # XXX should this be unconditional?
        # XXX sometimes don't want report (need finer reporting control)
        if (@match && !$autobase) {
            print STDERR "$path: parameter already defined (new one ignored)\n"
                if $verbose || !$nowarnredef;
            return;
        }
	$nnode = $match[0];
    }

    # XXX should maybe allow name to include an object spec; could call
    #     add_path on it (would like to know if any object in the path didn't
    #     already exist)

    if ($nnode) {
        # XXX hack for DT; doing it unconditionally, although there is
        #     probably a reason why this isn't normally done!
        $nnode->{changed} = undef;

        # cache current node contents
        my $cnode = util_copy($nnode, ['history', 'pnode', 'nodes']);

        # indicate that parameter was previously known (report might need to
        # use this info)
        $nnode->{history} = [] unless defined $nnode->{history};

        # XXX if both name and ref are defined, this is a rename operation
        # XXX what if the new-named parameter already exists?
        # XXX what are the implications for history?
        # XXX should this be marked as a change? yes
        if ($name && $ref) {
            $parameters->{$path} = undef;
            $path = $pnode->{path} . $name;
            $nnode->{path} = $path;
            $nnode->{name} = $name;
            $parameters->{$path} = $nnode;
            print STDERR "$path: renamed from $ref\n" if $verbose;
        }

        # XXX this isn't quite right... there is no inheritance except for
        #     the description (also, it's incomplete)

        # when a parameter is modified, its and its parent's last spec
        # (lspec) is updated (and its mspec is modified)
        my $changed = {};

        if ($access ne $nnode->{access}) {
            print STDERR "$path: access: $nnode->{access} -> $access\n"
                if $verbose;
            $nnode->{access} = $access;
            $changed->{access} = 1;
        }
        if ($status ne $nnode->{status}) {
            print STDERR "$path: status: $nnode->{status} -> $status\n"
                if $verbose;
            $nnode->{status} = $status;
            $changed->{status} = 1;
        }
        my $tactiveNotify = $activeNotify;
        $tactiveNotify =~ s/will/can/;
        if ($tactiveNotify ne $nnode->{activeNotify}) {
            print STDERR "$path: activeNotify: $nnode->{activeNotify} -> " .
                "$activeNotify\n" if $verbose;
            $nnode->{activeNotify} = $activeNotify;
            $changed->{activeNotify} = 1;
        }
        if ($forcedInform &&
            boolean($forcedInform) ne boolean($nnode->{forcedInform})) {
            print STDERR "$path: forcedInform: $nnode->{forcedInform} -> " .
                "$forcedInform\n" if $verbose;
            $nnode->{forcedInform} = $forcedInform;
            $changed->{forcedInform} = 1;
        }
        if ($description) {
            if ($description eq $nnode->{description}) {
                $nnode->{errors}->{samedesc} = $descact if !$autobase;
            } else {
                $nnode->{errors}->{samedesc} = undef;
                # XXX not if descact is append?
                my $diffs = util_diffs($nnode->{description}, $description);
                print STDERR "$path: description: changed\n" if $verbose;
                print STDERR $diffs if $verbose > 1;
                $nnode->{description} = $description;
                $changed->{description} = $diffs;
            }
            $nnode->{errors}->{baddescact} = 
                (!$autobase && (!$descact || $descact eq 'create')) ?
                $descact : undef;
        }
        # XXX need cleverer comparison
        if ($descact && $descact ne $nnode->{descact}) {
            print STDERR "$path: descact: $nnode->{descact} -> $descact\n"
                if $verbose > 1;
            $nnode->{descact} = $descact;
        }
        if ($type && $type ne $nnode->{type}) {
            # XXX changed type is usually an error, but not necessarily if the
            #     new type is 'dataType' (need to check hierarchy)
            print STDERR "$path: type: $nnode->{type} -> $type\n"
                if $verbose && $type ne 'dataType';
            # XXX special case: if type changed to string, discard ranges
            #     (could take this further... but this case arose!)
            if ($type eq 'string' && $nnode->{syntax}->{ranges}) {
                print STDERR "$path: discarding existing ranges\n" if $verbose;
                $nnode->{syntax}->{ranges} = undef;
            }
            # XXX special case: if type changed to dataType, discard sizes and
            #     ranges
            if ($type eq 'dataType' && $nnode->{syntax}->{sizes}) {
                print STDERR "$path: discarding existing sizes\n" if $verbose;
                $nnode->{syntax}->{sizes} = undef;
            }
            if ($type eq 'dataType' && $nnode->{syntax}->{ranges}) {
                print STDERR "$path: discarding existing ranges\n" if $verbose;
                $nnode->{syntax}->{ranges} = undef;
            }
            $nnode->{type} = $type;
            $changed->{type} = 1;
        }
        # XXX need the more sophisticated logic that is used for parameters
        #     here (this comment might no longer apply)
        my $cvalues = $nnode->{values};
        my $visited = {};
        foreach my $value (sort {$values->{$a}->{i} <=>
                                     $values->{$b}->{i}} keys %$values) {
            $visited->{$value} = 1;

            my $cvalue = $cvalues->{$value};
            my $nvalue = $values->{$value};

            if (!defined $cvalue) {
                print STDERR "$path.$value: added\n" if $verbose;
                $changed->{values}->{$value}->{added} = 1;
                next;
            }

            unshift @{$cvalue->{history}}, util_copy($cvalue, ['history']);
            $values->{$value}->{history} = $cvalue->{history};
            
            if ($nvalue->{access} ne $cvalue->{access}) {
                print STDERR "$path.$value: access: $cvalue->{access} -> ".
                    "$nvalue->{access}\n" if $verbose;
                $changed->{values}->{$value}->{access} = 1;
            }
            if ($nvalue->{status} ne $cvalue->{status}) {
                print STDERR "$path.$value: status: $cvalue->{status} -> ".
                    "$nvalue->{status}\n" if $verbose;
                $changed->{values}->{$value}->{status} = 1;
            }
            if (boolean($nvalue->{optional}) ne boolean($cvalue->{optional})) {
                print STDERR "$path.$value: optional: $cvalue->{optional} -> ".
                    "$nvalue->{optional}\n" if $verbose;
                $changed->{values}->{$value}->{optional} = 1;
            }
            if (!$nvalue->{descdef}) {
                $nvalue->{description} = $cvalue->{description};
            } else {
                if ($nvalue->{description} eq $cvalue->{description}) {
                    $nvalue->{errors}->{samedesc} = $nvalue->{descact}
                    if !$autobase;
                } else {
                    $nvalue->{errors}->{samedesc} = undef;
                    # XXX not if descact is append?
                    my $diffs = util_diffs($cvalue->{description},
                                           $nvalue->{description});
                    print STDERR "$path.$value: description: changed\n"
                        if $verbose;
                    print STDERR $diffs if $verbose > 1;
                    $changed->{values}->{$value}->{description} = $diffs;
                }
                $nvalue->{errors}->{baddescact} =
                    (!$autobase &&
                    (!$nvalue->{descact} || $nvalue->{descact} eq 'create')) ?
                    $nvalue->{descact} : undef;
            }
            # XXX need cleverer comparison
            if ($nvalue->{descact} && $nvalue->{descact} ne $cvalue->{descact}){
                print STDERR "$path.$value: descact: $cvalue->{descact} -> ".
                    "$nvalue->{descact}\n" if $verbose > 1;
            }
        }
        if (%$values) {
            foreach my $value (sort {$cvalues->{$a}->{i} <=>
                                         $cvalues->{$b}->{i}} keys %$cvalues) {
                print STDERR "$path.$value: omitted; should instead mark as ".
                    "deprecated/obsoleted/deleted\n"
                    if $pedantic && !$visited->{$value};
            }
            $nnode->{values} = $values;
        }
        #print STDERR Dumper($nnode->{values});
        # XXX this isn't perfect; some things are getting defined as '' when
        #     they should be left undefined? e.g. have seen list = ''
        # XXX for now, don't allow re-definition with empty string...
        # XXX stop press: empty string means "undefine" for some attributes
        #     (have to be careful, e.g. not mentioning <list/> doesn't mean
        #     it isn't a list)
	while (my ($key, $value) = each %$syntax) {
            my $old = defined $nnode->{syntax}->{$key} ?
                $nnode->{syntax}->{$key} : '<none>';
            if (ref $value) {
                if (!defined $nnode->{syntax}->{$key} ||
                               !Compare($value, $nnode->{syntax}->{$key})) {
                    print STDERR "$path: $key: changed\n" if $verbose;
                    $nnode->{syntax}->{$key} = $value;
                    $changed->{syntax}->{$key} = 1;
                }
            } elsif ($value && (!defined $nnode->{syntax}->{$key} ||
                                $value ne $nnode->{syntax}->{$key})) {
                print STDERR "$path: $key: $old -> $value\n" if $verbose;
                $nnode->{syntax}->{$key} = $value;
                $changed->{syntax}->{$key} = 1;
            }
	}
        # XXX the above doesn't catch units, which aren't stored in syntax
        #     (why not? maybe because they are data type specific?)
        # XXX this is exactly the same logic as the above general syntax
        #     syntax logic...
        if ($units && (!defined $nnode->{units} || $units ne $nnode->{units})) {
            my $old = defined $nnode->{units} ? $nnode->{units} : '<none>';
            print STDERR "$path: units: $old -> $units\n"
                if $verbose;
            $nnode->{units} = $units;
            $changed->{units} = 1;
        }
        # XXX this is a special case for deleting list facets
        if ($nnode->{syntax}->{list} && $nnode->{syntax}->{liststatus} &&
            $nnode->{syntax}->{liststatus} eq 'deleted') {
            print STDERR "$path: list: $nnode->{syntax}->{list} -> " .
            "<deleted>\n" if $verbose;
            undef $nnode->{syntax}->{list};
            $changed->{syntax}->{list} = 1;
        }
        if (defined $default &&
            (!defined $nnode->{default} || $default ne $nnode->{default})) {
            my $old = defined $nnode->{default} ? $nnode->{default} : '<none>';
            my $new = defined $default ? $default : '<none>';
            print STDERR "$path: default: $old -> $new\n" if $verbose;
            $nnode->{default} = $default;
            $changed->{default} = 1;
        }
        if (defined $default && $deftype ne $nnode->{deftype}) {
            print STDERR "$path: deftype: $nnode->{deftype} -> $deftype\n"
                if $verbose;
            $nnode->{deftype} = $deftype;
            # note that this marks default, not deftype, as changed
            $changed->{default} = 1;
        }
        # to remove a default, status (defstat) is set to "deleted" (default
        # will always be defined, because the value attribute is mandatory
        if (defined $default && $defstat ne $nnode->{defstat}) {
            print STDERR "$path: defstat: $nnode->{defstat} -> $defstat\n"
                if $verbose;
            $nnode->{defstat} = $defstat;
            # note that this marks default, not defstat, as changed
            $changed->{default} = 1;
        }
        # or, if $autobase (so not $ref), it was present and is no longer
        if (!$ref && defined $nnode->{default} && !defined $default) {
            print STDERR "$path: default: deleted\n" if $verbose;
            $nnode->{defstat} = 'deleted';
            $changed->{default} = 1;
        }
        if ($pnode->{dynamic} != $nnode->{dynamic}) {
            print STDERR "$path: dynamic: $nnode->{dynamic} -> ".
                "$pnode->{dynamic}\n" if $verbose;
            $nnode->{dynamic} = $pnode->{dynamic};
            $changed->{dynamic} = 1;
        }
        
        # if changed, retain info from previous versions
        if (keys %$changed) {
            unshift @{$nnode->{history}}, $cnode;
            $nnode->{changed} = $changed;
            $nnode->{lfile} = $Lfile;
            $nnode->{lspec} = $Lspec;
            $nnode->{mspec} = $spec;
            mark_changed($pnode, $Lfile, $Lspec);
            # XXX experimental (absent description is like appending nothing)
            if (!$description) {
                $nnode->{description} = '';
                $nnode->{descact} = 'append';
            }
        }
        # XXX unconditionally keep track of files in which node was seen
        $nnode->{sfile} = $Lfile;
    } else {
        print STDERR "$path: unnamed parameter\n" unless $name;
        print STDERR "$path: untyped parameter\n" unless $type;
        print STDERR "$path: invalid description action: $descact\n"
            if $pedantic && !$autobase && $descact && $descact ne 'create';

        # XXX this is still how we're handling the version number...
	$majorVersion = $mnode->{majorVersion} unless defined $majorVersion;
	$minorVersion = $mnode->{minorVersion} unless defined $minorVersion;

        print STDERR "$path: added\n" if
            $verbose && $mnode->{history} && @{$mnode->{history}} && !$auto;

        my $dynamic = $pnode->{dynamic};

        mark_changed($pnode, $Lfile, $Lspec);

        # XXX I think this is to with components and auto-removing defaults
        #     from them if they are used in a static environment
        # XXX but it breaks perfectly normal defaults, since it applies not
        #     only to components but to imported models :( (need a more direct
        #     test)
        # XXX why should it break anything; restore with debug message...
        # XXX it breaks detection of inappropriate defaults; disable it again!
        #$default = undef if !$dynamic && @$context > 1;
        #if (defined $default && $deftype eq 'object' && !$dynamic) {
        #    $default = undef;
        #    print STDERR "$path: removing default value\n" if $verbose;
        #}

	$nnode = {pnode => $pnode, name => $name, path => $path, file => $file,
		  lfile => $Lfile, sfile => $Lfile, spec => $spec,
                  lspec => $Lspec, mspec => $spec, type => $type,
                  syntax => $syntax, access => $access, status => $status,
                  description => $description, descact => $descact,
                  descdef => $descdef, values => $values, default => $default,
                  deftype => $deftype, defstat => $defstat,
                  dynamic => $dynamic, majorVersion => $majorVersion,
                  minorVersion => $minorVersion, activeNotify => $activeNotify,
                  forcedInform => $forcedInform, units => $units, nodes => [],
                  history => undef, errors => {}};
        # if previous is defined, it's a hint to insert this node after the
        # node of this name, if it exists
        my $index = @{$pnode->{nodes}};
        if (defined $previous && $previous eq '') {
            $index = 0;
        } elsif ($previous) {
            for (0..$index-1) {
                if (@{$pnode->{nodes}}[$_]->{name} eq $previous) {
                    $index = $_+1;
                    last;
                }
            }
        }
        splice @{$pnode->{nodes}}, $index, 0, $nnode;
        $pnode->{lfile} = $Lfile;
        $pnode->{lspec} = $Lspec;
	$parameters->{$path} = $nnode;
    }

    update_datatypes($syntax->{ref}, $file, $spec) if $type eq 'dataType';

    print STDERR Dumper(util_copy($nnode, ['pnode', 'nodes'])) if
        $debugpath && $path =~ /$debugpath/;
}

# Update list of bibrefs that are actually used (each entry is an array of the
# specs that use the bibref)
sub update_bibrefs
{
    my ($value, $file, $spec) = @_;

    my @ids = ($value =~ /\{\{bibref\|([^\|\}]+)/g);
    foreach my $id (@ids) {
        print STDERR "marking bibref $id used (file=$file, spec=$spec)\n"
            if $verbose > 1;
        push @{$bibrefs->{$id}}, $spec unless
            grep {$_ eq $spec} @{$bibrefs->{$id}};
    }
}

# Determine whether a description contains invalid bibrefs
# XXX or could do during template expansion
sub invalid_bibrefs
{
    my ($value) = @_;

    my @ids = ($value =~ /\{\{bibref\|([^\|\}]+)/g);
    my $bad = [];
    foreach my $id (@ids) {
        push @$bad, $id unless
            grep {$_->{id} eq $id} @{$root->{bibliography}->{references}};
    }
    return $bad;
}

# Determine whether a maximum length is appropriate for this parameter
sub maxlength_appropriate
{
    my ($path, $name, $type) = @_;

    return 0 if $type !~ /string|base64|hexBinary/;

    return 0 if $path =~ /Previous|Current/;

    return 0 if $name =~ /(dest|destination|group|host|ip|mac|max|min|source|src|server|subnet).*(addr|address|ip|mask)$/i;
    return 0 if $name =~ /(bssid|chaddr|chaddrmask|defaultgateway|host|yiaddr)$/i;

    return 1;
}

# Determine whether a parameter is list-valued
sub is_list
{
    my ($syntax) = @_;

    return $syntax->{list};
}

# Determine whether enumerated values are appropriate for this parameter
sub values_appropriate
{
    my ($name, $type) = @_;

    return $type eq 'string';
}

# Determine whether a parameter has enumerated values
sub has_values
{
    my ($values) = @_;

    return (defined $values && %$values) ? 1 : 0;
}

# Determine whether a parameter supports a specific enumerated value
sub has_value
{
    my ($values, $search) = @_;

    return (grep { $_ eq $search } keys %$values) ? 1 : 0;
}

# Determine whether a value is valid for a given parameter
# XXX not complete (see XXX comments below)
sub valid_value
{
    my ($node, $value, $ignore_ranges) = @_;

    my $type = $node->{type};
    my $syntax = $node->{syntax};
    my $values = $node->{values};

    # determine base data type
    my $typeinfo = get_typeinfo($type, $syntax);
    my ($primtype, $dataType) = ($typeinfo->{value}, $typeinfo->{dataType});

    $primtype = base_type($primtype, 1) if $dataType;

    #print STDERR "#### $node->{path} $primtype $value\n";

    # XXX unless suppressed via $ignore_ranges (in which case the range is
    #     the full range for the data type), would also check that numeric
    #     values are within one of the ranges (honoring the step)

    if ($primtype eq 'string') {
        if (!has_values($values)) {
            # XXX no check for plain string; could check length...
            return 1;
        } else {
            # XXX no check for pattern matches
            return has_value($values, $value);
        }

    } elsif ($primtype eq 'boolean') {
        return ($value =~ /^(0|1|false|true)$/);

    } elsif ($primtype eq 'int') {
        # XXX for now no range check
        return ($value =~ /^(-?\d+)$/);

    } elsif ($primtype eq 'long') {
        # XXX for now no range check
        return ($value =~ /^(-?\d+)$/);

    } elsif ($primtype eq 'unsignedInt') {
        # XXX for now no range check (apart from that it's positive)
        return ($value =~ /^(\d+)$/);

    } elsif ($primtype eq 'unsignedLong') {
        # XXX for now no range check (apart from that it's positive)
        return ($value =~ /^(\d+)$/);

    } else {
        # XXX for other types (base64, dateTime, hexBinary) assume valid
        return 1;
    }    
}

# Determine whether a value is valid for a given parameter (value can be a list
# if the parameter is list-valued)
sub valid_values
{
    my ($node, $values) = @_;

    my $syntax = $node->{syntax};

    if (!$syntax->{list}) {
        return valid_value($node, $values);
    } else {
        $values =~ s/^\s*//;
        $values =~ s/\s*$//;
        foreach my $value (split /\s*,\s*/, $values) {
            return 0 unless valid_value($node, $value);
        }
        return 1;
    }
}

# Determine whether ranges are valid
sub valid_ranges
{
    my ($node) = @_;

    my $ranges = $node->{syntax}->{ranges};

    return 1 unless defined $ranges && @$ranges;

    foreach my $range (@$ranges) {
        my $minval = $range->{minInclusive};
        my $maxval = $range->{maxInclusive};

        return 0 if defined($minval) && !valid_value($node, $minval, 1);
        return 0 if defined($maxval) && !valid_value($node, $maxval, 1);
    }

    return 1;
}

# Get formatted enumerated values
# XXX format is currently report-dependent
# XXX no indication of access (didn't we used to show this?)
sub get_values
{
    my ($node, $anchor) = @_;

    my $values = $node->{values};
    return '' unless $values;

    my $list = '';
    foreach my $value (sort {$values->{$a}->{i} <=>
                                 $values->{$b}->{i}} keys %$values) {
        my $cvalue = $values->{$value};

        my $history = $cvalue->{history};
	my $description = $cvalue->{description};
	my $descact = $cvalue->{descact};
        my $readonly = $cvalue->{access} eq 'readOnly';
	my $optional = boolean($cvalue->{optional});
	my $deprecated = $cvalue->{status} eq 'deprecated';
	my $obsoleted = $cvalue->{status} eq 'obsoleted';
	my $deleted = $cvalue->{status} eq 'deleted';

        next if $deleted && !$showdiffs;

        $readonly = 0 unless $showreadonly;

        my $changed = util_node_is_modified($node) &&
            ($node->{changed}->{values}->{$value}->{added} ||
             $node->{changed}->{values}->{$value}->{access} ||
             $node->{changed}->{values}->{$value}->{status});
        my $dchanged = util_node_is_modified($node) &&
            ($changed || $node->{changed}->{values}->{$value}->{description});

        ($description, $descact) = get_description($description, $descact,
                                                   $dchanged, $history, 1);

        # don't mark optional if deprecated or obsoleted
        $optional = 0 if $deprecated || $obsoleted;

	my $quote = $cvalue !~ /^</;

        # XXX this assumes HTML really
        if ($value eq '') {
            $value = '<Empty>';
            $description = '{{empty}}' unless $description;
        }

        # remove any leading or trailing whitespace and replace newlines with
        # spaces
        $description =~ s/^\s*//;
        $description =~ s/\n/ /g;
        $description =~ s/\s*$//;

        # avoid leading upper-case in value description unless an acronym
        # XXX better than it was (it was unconditional) but is it OK?
        #$description = lcfirst $description
        #    if ($description =~ /^[A-Z][a-z]/ &&
        #        $description !~ /^\S+\s+[A-Z]/);
        $description =~ s/\.([\+\-]*)$/$1/;

	my $any = $description || $readonly || $optional ||
            $deprecated || $obsoleted;

	$list .= '* ';
        $list .= ($deleted ? '---' : '+++') if $showdiffs && $changed;
	$list .= "''";
        if (!$anchor) {
            $list .= $value;
        } else {
            # XXX remove backslashes (needs doing properly)
            my $tvalue = $value;
            $tvalue =~ s/\\//g;

            $list .= qq{%%$value%%$tvalue%%};
        }
	$list .= "''";
        $list .= ($deleted ? '---' : '+++') if $showdiffs && $changed;
	$list .= ' (' if $any;
	$list .= $description if $description;
        $list .= ($deleted ? '---' : '+++') if $showdiffs && $changed;
	$list .= ', ' if $description;
	$list .= 'READONLY, ' if $readonly;
	$list .= 'OPTIONAL, ' if $optional;
	$list .= 'DEPRECATED, ' if $deprecated;
	$list .= 'OBSOLETED, ' if $obsoleted;
	chop $list if $any;
	chop $list if $any;
        $list .= ($deleted ? '---' : '+++') if $showdiffs && $changed;
	$list .= ')' if $any;
	$list .= "\n";
    }
    chop $list;
    return $list;
}

# Get description, accounting for the possibility that it hasn't changed from
# the previous version.  History, if supplied, is an array of nodes from
# previous versions, most recent first, so $history->[0]->{description} is
# the description from the previous version.
sub get_description
{
    my ($new, $descact, $changed, $history, $resolve) = @_;

    # XXX there are still problems with "resolve"; can get duplicate
    #     descriptions :(

    # XXX this isn't quite good enough; if description is unaltered in
    #     latest version, this returns the value from the previous version,
    #     whereas it should return an empty string
    # XXX or perhaps this is OK, but need better "changed" logic in the caller?

    # get old description if any
    # XXX this isn't clever enough to detect that "A", "B" (append) and "AB"
    #     in successive versions is not a change
    my $old = get_old_description($history);

    # XXX do this here because the two pieces of description may have different
    #     whitespace conventions (need to rename routine)
    $old = html_whitespace($old);
    $new = html_whitespace($new);

    # if no descact it defaults to replace / create
    $descact = defined $old ? 'replace' : 'create' unless $descact;
    $old = '' unless defined $old;

    # adjust if new description is the old one with text appended (but only if
    # the additional text begins with a newline)
    if ($descact eq 'replace' && length($new) > length($old) && 
        substr($new, 0, length($old)) eq $old &&
        substr($new, length($old), 1) eq "\n") {
        $new = substr($new, length($old));
        $new =~ s/^\s+//;
        $descact = 'append';
    }

    if ($descact eq 'replace') {
        $new = '' if $new eq $old && !$resolve;
    } elsif ($descact eq 'append') {
        # XXX fudge: if new begins with {{enum}} or {{pattern}} template, no
        #     newline (for these, preceding newline is significant)
        my $sep = $new =~ /^[ \t]*\{\{(enum|pattern)/ ? "  " : "\n";
        # XXX I don't trust this logic; need to make more transparently correct
        # XXX need to check whether has changed in latest version; if not, can
        #     end up with appending twice
        $new = $old . (($old ne '' && $new ne '') ? $sep : "") . $new
            if $resolve;
    }

    # if requested, mark insertions and deletions
    $new = util_diffs_markup($old, $new) if $showdiffs && $resolve && $changed;

    return ($new, $descact);
}

# Get old description from history (complicated by the fact that there can be
# several stages of history)
# XXX duplicates some of the logic of get_description
sub get_old_description
{
    my ($history) = @_;

    # XXX old version that doesn't handle more than one stage of history
    #return $history && @$history ? $history->[0]->{description} : undef;

    return undef unless $history && @$history;

    my $old = '';
    foreach my $item (reverse @$history) {
        my $descact = $item->{descact};
        my $new = $item->{description};
        if ($descact eq 'append') {
            # XXX same fudge as in get_description
            my $sep = $new =~ /^[ \t]*\{\{(enum|pattern)/ ? "  " : "\n";
            $old .= (($old ne '' && $new ne '') ? $sep : "") . $new;
        } else {
            $old = $new;
        }
    }

    return $old;
}

# Add formatted enumerated values, if any, to the description
# XXX should be phased out in favor of template expansion
sub add_values
{
    my ($description, $values) = @_;

    if (!$description) {
	;
    } elsif (!$values) {
	$description = remove_values($description);
    } elsif ($description =~ /{{enum}}/) {
	$description =~ s/[ \t]*{{enum}}/$values/;
    } else {
	$description .= "\n" . $values;
    }

    return $description;
}

# Remove "values" indicator, returning the result
# XXX should be phased out in favor of template expansion
sub remove_values
{
    my ($description) = @_;

    $description =~ s/[ \t]*{{enum}}\n?//;

    return $description;
}

# Remove '{{append}}' or '{{replace}}' indicator, returning whether either was
# found, and the result
# XXX should be phased out (currently used only by XLS report?)
sub remove_descact
{
    my ($description, $descact) = @_;

    if ($description =~ /{{(append|replace)}}/) {
	$descact = $1;
	$description =~ s/{{$descact}}\n?//;
    }

    return ($description, $descact);
}

# Form a "type" string (as close as possible to the strings in existing "Type"
# columns)
sub type_string
{
    my ($type, $syntax) = @_;

    my $typeinfo = get_typeinfo($type, $syntax);
    my ($value, $dataType) = ($typeinfo->{value}, $typeinfo->{dataType});

    $value = base_type($value, 1) if $dataType;

    # lists are always strings at the CWMP level
    if ($syntax->{list}) {
        $value = 'string';
        $value .= add_size($syntax, {list => 1});
    } else {
        $value .= add_size($syntax);
        $value .= add_range($syntax);
    }

    return $value;
}

# Determine a named data type's base type
sub base_type
{
    my ($name, $recurse) = @_;

    my ($defn) = grep {$_->{name} eq $name} @{$root->{dataTypes}};
    if (!defined $defn) {
        print STDERR "$name: undefined named data type; invalid XML?\n";
        return $name;
    }

    my $base = $defn->{base};
    my $prim = $defn->{prim};

    print STDERR "$name: no base or primitive data type; invalid XML?\n"
        if !$base  && !$prim;

    return $base ? ($recurse ? base_type($base, 1) : $base) : $prim;
}

# Form a "type", "string(maxLength)" or "int[minInclusive:maxInclusive]" syntax
# string (multiple sizes and ranges are supported)
sub syntax_string
{
    my ($type, $syntax, $human) = @_;

    my $list = $syntax->{list};

    my $typeinfo = get_typeinfo($type, $syntax, {human => $human});
    my ($value, $unsigned) = ($typeinfo->{value}, $typeinfo->{unsigned});

    $value .= add_size($syntax, {human => $human, item => 1});
    $value .= add_range($syntax, {human => $human, unsigned => $unsigned});

    if ($list) {
        $value = 'list' .
            add_size($syntax, {human => $human, list => 1}) .
            add_range($syntax, {human => $human, unsigned => $unsigned,
                                list => 1}) . ' of ' . $value;
    }

    return $value;
}

# Get data type and associated information
sub get_typeinfo
{
    my ($type, $syntax, $opts) = @_;

    my $value = $type;
    my $dataType = ($value eq 'dataType');
    my $unsigned = ($value =~ /^unsigned/);

    if ($syntax->{ref}) {
        $value = $syntax->{ref};
    } elsif ($syntax->{base}) {
        $value = $syntax->{base};
    }

    if ($opts->{human}) {
        $value =~ s/^base64$/BASE64 string/;
        $value =~ s/^hexBinary$/Hex binary string/;
        $value =~ s/^int$/integer/;
        $value =~ s/^unsignedInt$/unsigned integer/;
        $value =~ s/^unsignedLong$/unsigned long/;
        # XXX could try to split multi-word type names, e.g. IPAddress?
        # XXX this is heuristic (it works for IPAddress etc)
        if ($syntax->{list}) {
            $value .= 'e' if $value =~ /s$/;
            $value .= 's';
        }
    }

    return {value => $value, dataType => $dataType, unsigned => $unsigned};
}

# Add size or list size to type / value string
# XXX need better wording for case where a single maximum is specified?
# XXX should check for overlapping sizes
sub add_size
{
    my ($syntax, $opts) = @_;

    my $sizes = $opts->{list} ? 'listSizes' : 'sizes';
    return '' unless defined $syntax->{$sizes} && @{$syntax->{$sizes}};

    my $value = '';

    # all sizes guarantee to have a defined minlen or maxlen (or both)

    # XXX in general, not using "defined"

    $value .= ' ' if $opts->{human};
    $value .= '(';

    # special case where there is only a single size and no minLength (mostly
    # to avoid changing what people are already used to)
    if (@{$syntax->{$sizes}} == 1 &&
        !$syntax->{$sizes}->[0]->{minLength} &&
        $syntax->{$sizes}->[0]->{maxLength}) {
        $value .= 'maximum length ' if $opts->{human};
        $value .= $syntax->{$sizes}->[0]->{maxLength};
        $value .= ')';
        return $value;
    }

    $value .= 'item ' if $opts->{human} && $opts->{item};
    $value .= 'length ' if $opts->{human};

    my $first = 1;
    foreach my $size (@{$syntax->{$sizes}}) {
        my $minlen = $size->{minLength};
        my $maxlen = $size->{maxLength};

        $value .= ', ' unless $first;

        if (!$opts->{human}) {
            $value .= $minlen . ':' if $minlen;
            $value .= $maxlen if $maxlen;
        } elsif ($minlen && !$maxlen) {
            $value .= 'at least ' . $minlen;
        } elsif (!$minlen && $maxlen) {
            $value .= 'up to ' . $maxlen;
        } elsif ($minlen == $maxlen) {
            $value .= $minlen;
        } else {
            $value .= $minlen . ' to ' . $maxlen;
        }

        $first = 0;
    }    

    $value =~ s/(.*,)/$1 or/ if $opts->{human};

    $value .= ')';

    return $value;
}

# Add ranges or list ranges to type / value string
# XXX should check for overlapping ranges
sub add_range
{
    my ($syntax, $opts) = @_;

    my $ranges = $opts->{list} ? 'listRanges' : 'ranges';
    return '' unless defined $syntax->{$ranges} && @{$syntax->{$ranges}};

    my $value = '';

    # all ranges guarantee to have a defined minval or maxval (or both)

    $value .= ' ' if $opts->{human};
    $value .= $opts->{human} ? '(' : '[';
    $value .= 'value ' if $opts->{human} && !$opts->{list};

    my $first = 1;
    foreach my $range (@{$syntax->{$ranges}}) {
        my $minval = $range->{minInclusive};
        my $maxval = $range->{maxInclusive};
        my $step = $range->{step};

        $step = 1 unless defined $step;

        $value .= ', ' unless $first;

        if (!$opts->{human}) {
            if (defined $minval && defined $maxval && $minval == $maxval) {
                $value .= $minval if defined $minval;
            } else {
                $value .= $minval if defined $minval;
                $value .= ':';
                $value .= $maxval if defined $maxval;
                $value .= ' step ' . $step if $step != 1;
            }
        } else {
            my $add_step = 0;
            # XXX default minimum to 0 for unsigned types
            $minval = 0 if $opts->{unsigned} && !defined $minval;
            if (defined $minval && defined $maxval && $minval != $maxval) {
                $value .= $minval . ' to ' . $maxval;
                $add_step = 1;
            } elsif (defined $minval && defined $maxval && $minval == $maxval) {
                $value .= $minval;
            } elsif (defined $minval) {
                $value .= 'at least ' . $minval;
                $add_step = 1;
            } elsif (defined $maxval) {
                $value .= 'up to ' . $maxval;
                $add_step = 1;
            }
            $value .= ' stepping by ' . $step if $add_step && $step != 1;
            $value .= ' items' if $opts->{list};
        }
        $first = 0;
    }

    $value =~ s/(.*,)/$1 or/ if $opts->{human};

    $value .= $opts->{human} ? ')' : ']';

    return $value;
}

# Return 0/1 given string representation of boolean
# XXX shouldn't really allow "t" (is there a reason for this?)
sub boolean
{
    my ($value, $default) = @_;
    $default = 0 unless defined $default;
    return (!$value) ? $default : ($value =~ /1|t|true/i) ? 1 : 0;
}

# Form a "m.n" version string from major and minor versions
sub version
{
    my ($majorVersion, $minorVersion) = @_;

    my $value = "";
    $value .= defined($majorVersion) ? $majorVersion : "";
    $value .= defined($minorVersion) ? ".$minorVersion" : "";
    return $value;
}

# Parse a data model definition file.
sub parse_file
{
    my ($dir, $file)= @_;

    # XXX only use dir if non-blank ('' can be interpreted as '/')
    my $tfile = $dir ? File::Spec->catfile($dir, $file) : $file;

    print STDERR "parse_file: parsing $tfile\n" if $verbose;

    # parse file
    my $parser = XML::LibXML->new();
    my $tree = $parser->parse_file($tfile);
    my $toplevel = $tree->getDocumentElement;

    # for XSD files, pick up target namespace and return
    return $toplevel if $tfile =~ /\.xsd$/;

    # XXX expect these all to be the same if processing multiple documents,
    #     but should check; really should keep separate for each document
    my $tns = 
    my $xsi = 'xsi';
    my @nslist = $toplevel->getNamespaces();
    for my $ns (@nslist) {
        my $declaredURI = $ns->declaredURI();
        my $declaredPrefix = $ns->declaredPrefix();

        if ($declaredURI =~ /cwmp:datamodel-[0-9]/) {
            $root->{dm} = $declaredURI;
        } elsif ($declaredURI =~ /cwmp:datamodel-report-/) {
            $root->{dmr} = $declaredURI;
        } elsif ($declaredURI =~ /XMLSchema-instance/) {
            $root->{xsi} = $declaredURI;
            $xsi = $declaredPrefix;
        }
    }

    # XXX should parse it properly, but for now just check that we keep the
    #     one that defines the dmr location (it will define the dm location
    #     too)
    my $schemaLocation = $toplevel->findvalue("\@$xsi:schemaLocation");
    $root->{schemaLocation} = $schemaLocation unless
        $root->{schemaLocation} &&
        $root->{schemaLocation} =~ /cwmp:datamodel-report-/;
    $root->{schemaLocation} =~ s/\s+/ /g;

    # XXX if no dmr, use default
    $root->{dmr} = "urn:broadband-forum-org:cwmp:datamodel-report-0-1"
        unless $root->{dmr};

    # capture the first comment in the first file
    my $comments = $tree->findnodes('comment()');
    foreach my $comment (@$comments) {
        my $text = $comment->findvalue('.');
        $first_comment = $text unless $first_comment;
    }

    # validate file if requested
    return $toplevel unless $pedantic;

    # use schemaLocation to build schema referencing the same schemas that
    # the file references
    my $schemas =
        qq{<?xml version="1.0" encoding="UTF-8"?>\n} .
        qq{<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">\n};

    my %nsmap = split /\s+/, $schemaLocation;
    foreach my $ns (keys %nsmap) {
        my $path = $nsmap{$ns};

        # if there are no XML catalogs and path is an http(s) URL, retain only
        # the filename part (so can search for it)
        if (!@$catalogs) {
            my ($scheme) = uri_split($path);
            $path =~ s/.*\/// if $scheme && $scheme =~ /^https?$/i;
        }

        # search for file; don't report failure (schema validation will do this)
        my ($dir, $file) = find_file($path);
        $path = File::Spec->catfile($dir, $file) if $dir;
        $schemas .= qq{<xs:import namespace="$ns" schemaLocation="$path"/>\n};
    }

    $schemas .= qq{</xs:schema>\n};

    my $schema;
    eval { $schema = XML::LibXML::Schema->new(string => $schemas) };
    if ($@) {
        print STDERR "invalid auto-generated XML schema for $tfile:\n";
        warn $@;
    } else {
        eval { $schema->validate($tree) };
        if ($@) {
            print STDERR "failed to validate $tfile:\n" if $verbose;
            warn $@;
        } else {
            print STDERR "validated $tfile\n" if $verbose;
        }
    }

    return $toplevel;
}

# Find file by searching for the highest corrigendum number (if omitted)
# XXX should also support proper search path and shouldn't assume ".xml"
# XXX note that it works if supplied file includes directory, but only by
#     chance and not by design
sub find_file
{
    my ($file) = @_;
    
    # search path
    my $dirs = [];

    # if file includes directory, it overrides the search path for this call
    # XXX is it safe to ignore the volume?
    (my $vol, my $dir, $file) = File::Spec->splitpath($file);
    if ($dir) {
        push @$dirs, $dir;
    } else

    # always prepend "." to the list of includes
    {
        push @$dirs, File::Spec->curdir();
        push @$dirs, @$includes;
    }

    my $ffile = $file;
    my $fdir = '';

    # support names of form name-i-a[-c][label].xml where name is of the form
    # "xx-nnn", i, a and c are numeric and label can't begin with a digit
    my ($name, $i, $a, $c, $label) =
        $file =~ /^([^-]+-\d+)-(\d+)-(\d+)(?:-(\d+))?(-\D.*)?\.xml$/;

    # if name, issue (i) and amendment (a) are defined but corrigendum number
    # (c) is undefined, search for the highest corrigendum number
    if (defined $name && defined $i && defined $a && !defined $c) {
        $label = '' unless defined $label;
        foreach my $dir (@$dirs) {
            my @files = glob(File::Spec->catfile($dir,
                                                 qq{$name-$i-$a-*$label.xml}));
            foreach my $file (@files) {
                # remove directory part
                (my $tvol, my $tdir, $file) = File::Spec->splitpath($file);
                # XXX assumes no special RE chars anywhere...
                my ($n) = $file =~ /^$name-$i-$a-(\d+)$label\.xml$/;
                if (defined $n && (!defined $c || $n > $c)) {
                    $c = $n;
                    $fdir = $dir;
                }
            }
        }
        $c = defined($c) ? ('-' . $c) : '';
        $ffile = qq{$name-$i-$a$c$label.xml};
    }

    # otherwise no need to look for highest corrigendum number, either because
    # file name doesn't match pattern, e.g. it's unversioned, or because
    # corrigendum number is defined; still need to search directories though
    else {
        foreach my $dir (@$dirs) {
            if (-r File::Spec->catfile($dir, $ffile)) {
                $fdir = $dir;
                last;
            }
        }
    }

    print STDERR "fdir $fdir ffile $ffile\n" if $verbose;
    return ($fdir, $ffile);
}

# Check whether specs match
sub specs_match
{
    my ($spec, $fspec) = @_;

    # spec is spec from import and fspec is spec from file; if spec omits the
    # corrigendum number it matches all corrigendum numbers

    # support specs that end name-i-a[-c] where name is of the form "xx-nnn",
    # and i, a and c are numeric
    my ($c) = $spec =~ /[^-]+-\d+-\d+-\d+(?:-(\d+))?$/;

    # if corrigendum number is defined, require exact match
    return ($fspec eq $spec) if defined $c;

    # if corrigendum number is undefined in spec, remove it from fspec (if
    # present) before comparing
    ($c) = $fspec =~ /[^-]+-\d+-\d+-\d+(?:-(\d+))?$/;
    $fspec =~ s/-\d+$// if defined $c;
    return ($fspec eq $spec);
}

# Null report of node.
# XXX it's a bit inefficient to do it this way
sub null_node {}

# Text report of node.
sub text_node
{
    my ($node, $indent) = @_;

    if (!$indent) {
        print "$node->{spec}\n";
    } else {
        my $name = $node->{name} ? $node->{name} : '';
        my $base = $node->{history}->[0]->{name};
        my $type = type_string($node->{type}, $node->{syntax});
        print "  "x$indent . "$type $name" .
            ($base && $base ne $name ? ('(' . $base . ')') : '') .
            ($node->{access} && $node->{access} ne 'readOnly' ? ' (W)' : '') .
            ((defined $node->{default}) ? (' [' . $node->{default} . ']'):'') .
            ($node->{model} ? (' ' . $node->{model}) : '') .
            (($node->{status} && $node->{status} ne 'current') ?
             (' ' . $node->{status}) : '') .
            ($node->{changed} ?
             (' #changed: ' . xml_changed($node->{changed})) : '') . "\n";
        print $node->{changed}->{description} if
            $showdiffs && $node->{changed}->{description};
    }
}

# TAB report of node.
sub tab_node
{
    my ($node, $indent) = @_;

    # use indent as a first-time flag
    if (!$indent) {
	print "Name\tType\tWrite\tDescription\tObject Default\tVersion\tSpec\n";
    } else {
	my $attr = $node->{type} eq 'object' ? 'path' : 'name';
	my $name = tab_escape($node->{$attr});
	my $spec = tab_escape($node->{spec});
	my $type = tab_escape($node->{type});
	my $access = tab_escape($node->{access});
	my $description = tab_escape($node->{description});
	my $default = tab_escape($node->{default});
	my $version =
	    tab_escape(version($node->{majorVersion}, $node->{minorVersion}));
	print("$name\t$type\t$access\t$description\t$default\t$version\t$spec\n");
    }
}

# Escape a value suitably for import as tab-separated items into Excel.
sub tab_escape {
    my ($value) = @_;

    $value = util_default($value);

    # just in case...
    $value =~ s/\t/ /g;

    $value =~ s/\n/\&#10;\&#10;/g;

    # escape quotes
    $value =~ s/\"/\"\"/g;

    # quote the result
    $value = '"' . $value . '"';

    return $value;
}

# DM Schema XML report of node.
# XXX does not handle everything (is aimed at processing input documents that
#     have been derived from existing Word tables)

# have to work harder to avoid nesting objects :(
my $xml_objact = 0;

sub xml_node
{
    my ($node, $indent) = @_;

    $indent = 0 unless $indent;

    # generic node properties
    my $changed = $node->{changed};
    my $history = $node->{history};
    my $name = $node->{name};
    my $path = $node->{path};
    my $file = $node->{file};
    my $spec = $node->{spec};
    my $type = $node->{type};
    my $access = $node->{access};
    my $status = $node->{status};
    my $description = $node->{description};
    my $descact = $node->{descact};

    # on creation, history is undef; on re-encounter it's []; on modification,
    # it's non-empty
    my $basename = ref($history) ? 'base' : 'name';

    my $schanged = xml_changed($changed);

    my $dchanged = util_node_is_modified($node) && $changed->{description};
    ($description, $descact) = get_description($description, $descact,
                                               $dchanged, $history);
    $description = xml_escape($description);

    $status = $status ne 'current' ? qq{ status="$status"} : qq{};
    $descact = $descact ne 'create' ? qq{ action="$descact"} : qq{};

    # use node to maintain state (assumes that there will be only a single
    # XML report of a given node)
    $node->{xml} = {action => 'close', element => $type};

    my $i = "  " x $indent;

    # zero indent is root element
    if (!$indent) {
        my $dm = $node->{dm};
        my $xsi = $node->{xsi};
        my $schemaLocation = $node->{schemaLocation};
        my $dataTypes = $node->{dataTypes};
        my $bibliography = $node->{bibliography};

        print qq{$i<?xml version="1.0" encoding="UTF-8"?>
$i<!-- \$Id\$ -->
$i<!-- note: this is an automatically generated XML report -->
$i<dm:document xmlns:dm="$dm"
$i             xmlns:xsi="$xsi"
$i             xsi:schemaLocation="$schemaLocation"
$i             spec="$lspec">
};
        print qq{$i  <description$descact>$description</description>\n} if
            $description;

        # XXX need to be cleverer... this will include both explicit and
        #     implicit imports
        my $imported = {};
        foreach my $file (sort {$imports->{$a}->{i} <=>
                                    $imports->{$b}->{i}} keys %{$imports}) {
            my $spec = $imports->{$file}->{spec};
            
            # don't want to import our own definitions
            # XXX really should use file rather than spec for this, because
            #     nothing guarantees that the spec is unique
            # XXX or perhaps not... if the spec is the same in more than one
            #     file, then those files are associated with the same spec!
            # XXX hack to ensure import types into TR-106 (is exactly this
            #     issue)
            next if $spec eq $lspec && $spec !~ /tr-106$/;

            # XXX special case, don't change "TR-106t.xml"
            my $ifile = $file;
            $ifile = $file . '-' . $importsuffix
                if $importsuffix && $file !~ /TR-106t$/;
            $ifile .= '.xml';
            print qq{$i  <import file="$ifile" spec="$spec">\n};
            foreach my $import (@{$imports->{$file}->{imports}}) {
                my $element = $import->{element};
                my $name = $import->{name};
                my $ref = $import->{ref};
                my $iref = $ref;

                # XXX this mis-fires for imported data types so, rather than
                #     fixing it, avoid the problem
                $name = '_' . $name if $element ne 'dataType' &&
                    grep {$_->{element} eq $element && $_->{name} eq $name}
                @{$imports->{$lfile}->{imports}};

                $ref = $ref ne $name ? qq{ ref="$ref"} : qq{};

                print qq{$i    <$element name="$name"$ref/>\n} unless
                    $imported->{$element}->{$iref};
                $imported->{$element}->{$iref} = 1;
            }
            print qq{$i  </import>\n};
        }

        if ($dataTypes) {
            foreach my $dataType (@$dataTypes) {
                my $name = $dataType->{name};
                my $base = $dataType->{base};
                my $spec = $dataType->{spec};
                # XXX nothing is done with status
                my $status = $dataType->{status};
                my $description = $dataType->{description};
                my $descact = $dataType->{descact} || 'create';
                my $minLength = $dataType->{minLength};
                my $maxLength = $dataType->{maxLength};
                my $patterns = $dataType->{patterns};

                # XXX special case here to avoid re-defining IPAddress (could
                #     be avoided by accounting for file as well as spec)
                if ($spec ne $lspec || $spec =~ /tr-106$/) {
                    print STDERR "dataType $name defined in {$file}\n" if
                        $verbose > 1;
                    next;
                }

                $description = xml_escape($description);

                $base = $base ? qq{ base="$base"} : qq{};
                $descact = $descact ne 'create' ?
                    qq{ action="$descact"} : qq{};
                $minLength = $minLength ? qq{ minLength="$minLength"} : qq{};
                $maxLength = $maxLength ? qq{ maxLength="$maxLength"} : qq{};

                print qq{$i  <dataType name="$name"$base>\n};
                print qq{$i    <description$descact>$description</description>\n} if $description;
                if ($patterns) {
                    print qq{$i    <string>\n};
                    print qq{$i      <size$minLength$maxLength/>\n} if
                        $minLength || $maxLength;
                    foreach my $pattern (@$patterns) {
                        my $value = $pattern->{value};
                        my $description = $pattern->{description};
                        my $descact = $pattern->{descact} || 'create';
                        
                        $description = xml_escape($description);

                        $descact = $descact ne 'create' ?
                            qq{ action="$descact"} : qq{};
                        
                        my $end_element = $description ? '' : '/';
                        
                        print qq{$i      <pattern value="$value"$end_element>\n};
                        print qq{$i        <description$descact>$description</description>\n} if $description;
                        print qq{$i      </pattern>\n} unless $end_element;
                    }
                    print qq{$i    </string>\n};
                }
                print qq{$i  </dataType>\n};
            }
        }

        if ($bibliography && %$bibliography) {
            xml_bibliography($bibliography, $indent, {usespec => $lspec});
        }

        $node->{xml}->{element} = 'dm:document';
    }

    # model (always at level 1)
    # XXX don't output model (or children) if its spec doesn't match of the
    #     last file on the command line
    elsif ($type eq 'model') {
        if ($spec ne $lspec) {
            print STDERR "hiding $type $path $spec $lspec\n" if $verbose > 1;
            hide_subtree($node);
            $node->{xml}->{action} = 'none';
            return;
        }

        my $base = $history && @$history ? $history->[0]->{name} : '';
        my $isService = $node->{isService};

        # XXX hackery
        $base = '_' . $base if defined $base && $base eq $name;

        $base = $base ? qq{ base="$base"} : qq{};
        $isService = $isService ? qq{ isService="true"} : qq{};

        print qq{$i<model name="$name"$base$isService$status>\n};
        print qq{$i  <description$descact>$description</description>\n} if
            $description;
    }

    # model object
    # XXX don't output object (or children) if the spec at which it last
    #     changed doesn't match that of the last file on the command line
    elsif ($type eq 'object') {
        my $ospec = $node->{lspec};
        if ($ospec ne $lspec) {
            print STDERR "hiding $type $path $ospec $lspec\n" if $verbose > 1;
            hide_subtree($node, 1); # only parameter children
            $node->{xml}->{action} = 'none' unless $indent == 2;
            return;
        }

        my $minEntries = $node->{minEntries};
        my $maxEntries = $node->{maxEntries};
        my $numEntriesParameter = $node->{numEntriesParameter};
        my $enableParameter = $node->{enableParameter};
        my $uniqueKeys = $node->{uniqueKeys};

        $numEntriesParameter = $numEntriesParameter ? qq{ numEntriesParameter="$numEntriesParameter"} : qq{};
        $enableParameter = $enableParameter ? qq{ enableParameter="$enableParameter"} : qq{};

        # always at level 2; ignore indent
        $i = '    ';

        # close object if active
        print qq{$i</object>\n} if $xml_objact;

        print qq{$i<object $basename="$path" access="$access" minEntries="$minEntries" maxEntries="$maxEntries"$numEntriesParameter$enableParameter$status>\n};
        unless ($nocomments || $node->{descact} eq 'append') {
            print qq{$i  <!-- changed: $schanged -->\n} if $schanged;
            if ($changed->{description}) {
                print qq{$i  <!--\n};
                foreach my $line (split "\n",
                                  xml_escape($changed->{description})) {
                    print qq{$i  $line\n};
                }
                print qq{$i  -->\n};
            }
        }
        print qq{$i  <description$descact>$description</description>\n} if
            ($basename eq 'name' && $description) || $changed->{description};
        # only output unique keys on first definition
        # XXX should drive this by more general "created" logic
        if ($uniqueKeys && $basename eq 'name') {
            for my $uniqueKey (@$uniqueKeys) {
                my $functional = $uniqueKey->{functional};
                my $keyparams = $uniqueKey->{keyparams};
                $functional = !$functional ? qq{ functional="false"} : qq{};
                print qq{$i  <uniqueKey$functional>\n};
                for my $parameter (@$keyparams) {
                    print qq{$i    <parameter ref="$parameter"/>\n};
                }
                print qq{$i  </uniqueKey>\n};
            }
        }

        $node->{xml}->{action} = 'none' unless $indent == 2;
        $xml_objact = 1;
    }

    # profile
    elsif ($type eq 'profile') {
        if ($spec ne $lspec) {
            print STDERR "hiding $type $path $spec $lspec\n" if $verbose > 1;
            hide_subtree($node);
            $node->{xml}->{action} = 'none';
            return;
        }
        print qq{$i<profile name="$name">\n};
        print qq{$i  <description$descact>$description</description>\n} if
            $description;
    }

    # profile object
    elsif ($type eq 'objectRef') {
        print qq{$i<object ref="$name" requirement="$access">\n};
        print qq{$i  <description$descact>$description</description>\n} if
            $description;
        $node->{xml}->{element} = 'object';
    }

    # profile parameter
    elsif ($type eq 'parameterRef') {
        my $ended = $description ? '' : '/';
        print qq{$i<parameter ref="$name" requirement="$access"$ended>\n};
        print qq{$i  <description$descact>$description</description>\n} unless
            $ended;
        print qq{$i</parameter>\n} unless $ended;
        $node->{xml}->{action} = 'none';
    }

    # model parameter
    else {
        my $ospec = $node->{lspec};
        if ($ospec ne $lspec) {
            print STDERR "ignoring $type $path $ospec $lspec\n" if
                $verbose > 1;
            $node->{xml}->{action} = 'none';
            return;
        }

        my $activeNotify = $node->{activeNotify};
        my $forcedInform = $node->{forcedInform};
        my $syntax = $node->{syntax};

        $activeNotify = $activeNotify ne 'normal' ? qq{ activeNotify="$activeNotify"} : qq{};
        $forcedInform = $forcedInform ? qq{ forcedInform="true"} : qq{};

        # always at level 2 or 3; ignore indent
        $i = $xml_objact ? '      ' : '    ';

        print qq{$i<parameter $basename="$name" access="$access"$status$activeNotify$forcedInform>\n};
        unless ($nocomments || $node->{descact} eq 'append') {
            print qq{$i  <!-- changed: $schanged -->\n} if $schanged;
            if ($changed->{description}) {
                print qq{$i  <!--\n};
                foreach my $line (split "\n",
                                  xml_escape($changed->{description})) {
                    print qq{$i  $line\n};
                }
                print qq{$i  -->\n};
            }
        }
        print qq{$i  <description$descact>$description</description>\n} if
            ($basename eq 'name' && $description) || $changed->{description};
        # XXX need more sophisticated "changed" processing (need it at the
        #     facet level)
        if ($syntax && ($basename eq 'name' || $changed->{syntax} ||
                        $changed->{values} || $changed->{default})) {
            my $hidden = $syntax->{hidden};
            my $command = $syntax->{command};
            my $base = $syntax->{base};
            my $ref = $syntax->{ref};
            my $list = $syntax->{list};
            # XXX notsupport ing multiple sizes
            my $minLength = $syntax->{sizes}->[0]->{minLength};
            my $maxLength = $syntax->{sizes}->[0]->{maxLength};
            # XXX not supporting multiple ranges
            my $minInclusive = $syntax->{ranges}->[0]->{minInclusive};
            my $maxInclusive = $syntax->{ranges}->[0]->{maxInclusive};
            my $step = $syntax->{ranges}->[0]->{step};
            my $values = $node->{values};
            my $default = $node->{default};
            my $deftype = $node->{deftype};
            my $defstat = $node->{defstat};

            $base = $base ? qq{ base="$base"} : qq{};
            $ref = $ref ? qq{ ref="$ref"} : qq{};
            $hidden = $hidden ? qq{ hidden="true"} : qq{};
            $command = $command ? qq{ command="true"} : qq{};
            $minLength = defined $minLength && $minLength ne '' ?
                qq{ minLength="$minLength"} : qq{};
            $maxLength = defined $maxLength && $maxLength ne '' ?
                qq{ maxLength="$maxLength"} : qq{};
            $minInclusive = defined $minInclusive && $minInclusive ne '' ?
                qq{ minInclusive="$minInclusive"} : qq{};
            $maxInclusive = defined $maxInclusive && $maxInclusive ne '' ?
                qq{ maxInclusive="$maxInclusive"} : qq{};
            $step = defined $step && $step ne '' ? qq{ step="$step"} : qq{};
            $defstat = $defstat ne 'current' ? qq{ status="$defstat"} : qq{};

            print qq{$i  <syntax$hidden$command>\n};
            if ($list) {
                my $ended = ($minLength || $maxLength) ? '' : '/';
                print qq{$i    <list$ended>\n};
                print qq{$i      <size$minLength$maxLength/>\n} unless $ended;
                print qq{$i    </list>\n} unless $ended;
                $minLength = $maxLength = undef;
            }
            my $ended = ($minLength || $maxLength || $minInclusive ||
                         $maxInclusive || $step || %$values) ? '' : '/';
            print qq{$i    <$type$ref$base$ended>\n};
            print qq{$i      <size$minLength$maxLength/>\n} if
                $minLength || $maxLength;
            print qq{$i      <range$minInclusive$maxInclusive$step/>\n} if
                $minInclusive || $maxInclusive || $step;
            foreach my $value (sort {$values->{$a}->{i} <=>
                                     $values->{$b}->{i}} keys %$values) {
                my $evalue = xml_escape($value);
                my $cvalue = $values->{$value};

                my $history = $cvalue->{history};
                my $access = $cvalue->{access};
                my $status = $cvalue->{status};
                my $optional = boolean($cvalue->{optional});

                my $description = $cvalue->{description};
                my $descact = $cvalue->{descact};
                my $dchanged = util_node_is_modified($node) &&
                    $changed->{values}->{$value}->{description};
                ($description, $descact) = get_description($description,
                                                           $descact, $dchanged,
                                                           $history);
                $description = xml_escape($description);

                $optional = $optional ? qq{ optional="true"} : qq{};
                $access = $access ne 'readWrite' ? qq{ access="$access"} : qq{};
                $status = $status ne 'current' ? qq{ status="$status"} : qq{};
                $descact = $descact ne 'create' ? qq{ action="$descact"} : qq{};
                my $ended = $description ? '' : '/';

                print qq{$i      <enumeration value="$evalue"$access$status$optional$ended>\n};
                print qq{$i        <description$descact>$description</description>\n} if $description;
                print qq{$i      </enumeration>\n} unless $ended;
            }
            print qq{$i    </$type>\n} unless $ended;
            print qq{$i    <default type="$deftype" value="$default"$defstat/>\n}
            if defined $default && ($basename eq 'name' ||
                                    $changed->{default});
            print qq{$i  </syntax>\n};
        }
        print qq{$i</parameter>\n};
        $node->{xml}->{action} = 'none';
    }
}

sub xml_bibliography
{
    my ($bibliography, $indent, $opts) = @_;

    $indent = 0 unless $indent;
    my $i = "  " x $indent;

    my $usespec = $opts->{usespec};
    my $ignspec = $opts->{ignspec};

    my $description = $bibliography->{description};
    my $descact = $bibliography->{descact} || 'create';
    my $references = $bibliography->{references};
    
    $descact = $descact ne 'create' ? qq{ action="$descact"} : qq{};
    
    print qq{$i  <bibliography>\n};
    print qq{$i    <description$descact>$description</description>\n}
    if $description;
    
    foreach my $reference (sort bibid_cmp @$references) {
        my $id = $reference->{id};
        my $file = $reference->{file};
        my $spec = $reference->{spec};
        
        # ignore if outputting entries from specified spec (usespec) but this
        # comes from another spec
        if ($usespec && $spec ne $usespec) {
            print STDERR "$file: ignoring {$spec}$id\n" if $verbose > 1;
            next;
        }

        # ignore if ignoring entries from specified spec (ignspec) and this
        # comes from that spec
        if ($ignspec && $spec eq $ignspec) {
            print STDERR "$file: ignoring {$spec}$id\n" if $verbose > 1;
            next;
        }
        
        # XXX this can include unused references (I think because these 
        #     are bibrefs for all read data models, not for reported data
        #     models
        if (!$bibrefs->{$id}) {
            # XXX dangerous to omit it since it might be defined here
            #     in order to make it available to later versions
            # XXX for now, have hard-list of things not to omit
            # XXX hack to remove exceptions for xml2 report
            my $omit = ($id !~ /TR-069|TR-106/);
            $omit = 0 if $report eq 'xml2';
            if ($omit) {
                print STDERR "reference $id not used (omitted)\n";
                next;
            }
        }
        
        print qq{$i    <reference id="$id">\n};
        foreach my $element (qw{name title organization category
                                            date hyperlink}) {
            my $value = xml_escape($reference->{$element});
            print qq{$i      <$element>$value</$element>\n} if $value;
        }
        print qq{$i    </reference>\n};
    }
    print qq{$i  </bibliography>\n};
}

# XXX could use postpar as is done for the xml2 report
sub xml_post
{
    my ($node, $indent) = @_;

    my $i = "  " x $indent;

    my $xml = $node->{xml};
    my $action = $xml->{action};
    my $element = $xml->{element};
    
    if ($action eq 'close') {
        print qq{$i</$element>\n};
        $xml_objact = 0 if $element eq 'object';
    }
}

# Escape a value suitably for exporting as XML.
sub xml_escape {
    my ($value) = @_;

    $value = util_default($value, '', '');

    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    return $value;
}

# Form a string indicating what has changed
sub xml_changed
{
    my ($changed) = @_;

    return '' unless $changed;

    my $value = '';
    foreach my $key (sort keys %$changed) {
        $value .= ', ' if $value;
        $value .= $key;
        if (ref $changed->{$key}) {
            $value .= '(' . xml_changed($changed->{$key}) . ')';
        }
    }

    return $value;
}

# XML report of node (alternative form that generates something that should
# be similar to, and can be compared with, XML generated from an old-style
# Word table, e.g. from TR-098 Amendment 2)
#
# XXX doesn't do a complete job
# XXX this COULD be merged with the other XML report... I suppose...
# XXX better now, but: (a) need header comment, (b) need any undefined
#     bibrefs, (c) various other little things showed up by the 181 XML

sub xml2_node
{
    my ($node, $indent) = @_;

    $indent = 0 unless $indent;

    my $type = $node->{type};
    my $element = $type;
    $node->{xml2}->{element} = $element;

    my $i = "  " x $indent;

    # use indent as a first-time flag
    if (!$indent) {
        my $dm = $node->{dm};
        my $dmr = $node->{dmr};
        my $dmspec = $lspec;
        my $xsi = $node->{xsi};
        my $schemaLocation = $node->{schemaLocation};
        my $specattr = 'spec';

        my $changed = $node->{changed};
        my $history = $node->{history};
        my $description = $node->{description};
        my $descact = $node->{descact};
        my $dchanged = util_node_is_modified($node) && $changed->{description};
        ($description, $descact) = get_description($description, $descact,
                                                   $dchanged, $history, 1);
        $description = clean_description($description, $node->{name})
            if $canonical;
        $description = xml_escape($description);        

        # XXX have to hard-code DT stuff (can't get this from input files)
        my $d = @$dtprofiles ? qq{dt} : qq{dm};
        if ($d eq 'dt') {
            $dm = $dturn;
            $dmspec = $dtspec;
            $schemaLocation =~
                s/urn:broadband-forum-org:cwmp:datamodel.*?\.xsd ?//;
            $schemaLocation = qq{$dturn $dtloc $schemaLocation};
            $specattr = 'deviceType';
        }

        $element = qq{$d:document};
        $node->{xml2}->{element} = $element;
        print qq{$i<?xml version="1.0" encoding="UTF-8"?>
$i<!-- \$Id\$ -->
$i<!-- note: this is an automatically generated XML report -->
$i<$d:document xmlns:$d="$dm"
$i             xmlns:dmr="$dmr"
$i             xmlns:xsi="$xsi"
$i             xsi:schemaLocation="$schemaLocation"
$i             $specattr="$dmspec">
};
        # XXX for now hard-code bibliography and data type imports for DM
        if (!@$dtprofiles) {
            print qq{$i  <description>$description</description>\n} if
                $description;
            print qq{$i  <import file="tr-069-biblio.xml" spec="urn:broadband-forum-org:tr-069-biblio"/>
$i  <import file="tr-106-1-0-types.xml" spec="urn:broadband-forum-org:tr-106-1-0">
$i    <dataType name="IPAddress"/>
$i    <dataType name="MACAddress"/>
$i  </import>
};

            my $bibliography = $node->{bibliography};
            if ($bibliography && %$bibliography) {
                xml_bibliography(
                    $bibliography, $indent,
                    {ignspec => 'urn:broadband-forum-org:tr-069-biblio'});
            }
        } else {
            my $temp = util_list($dtprofiles);
            print qq{$i  <annotation>Auto-generated from $temp profiles.</annotation>\n};
            # XXX special case code from xml_node (could generalize)
            my $limports = $imports->{$lfile};
            print qq{$i  <import file="$lfile.xml" spec="$lspec">\n};        
            foreach my $import (@{$limports->{imports}}) {
                my $element = $import->{element};
                my $name = $import->{name};
                my $file = $import->{file};
                
                print qq{$i    <$element name="$name"/>\n} if
                    $file eq $lfile && $element eq 'model' && $name !~ /^_/;
            }
            print qq{$i  </import>\n};
        }
    }

    if ($indent) {
        my $changed = $node->{changed};
        my $history = $node->{history};
        my $path = $node->{path};
        my $name = $type eq 'object' ? $path : $node->{name};
        my $base = $node->{base};
        my $ref = $node->{ref};
        my $access = $node->{access};
        my $numEntriesParameter = $node->{numEntriesParameter};
        my $enableParameter = $node->{enableParameter};
        my $status = $node->{status};
        my $activeNotify = $node->{activeNotify};
        my $forcedInform = $node->{forcedInform};
        my $minEntries = $node->{minEntries};
        my $maxEntries = $node->{maxEntries};
        my $description = $node->{description};
        my $descact = $node->{descact};
        my $uniqueKeys = $node->{uniqueKeys};
        my $syntax = $node->{syntax};
        my $majorVersion = $node->{majorVersion};
        my $minorVersion = $node->{minorVersion};
        my $extends = $node->{extends};

        my $requirement = '';
        my $version = version($majorVersion, $minorVersion);

        my $origelem = $element;

        if ($element eq 'model') {
            $version = '';
            if (@$dtprofiles) {
                $ref = $name;
                $name = '';
            }
            return if $components;
        } elsif ($element eq 'object') {
            $i = '    ';
            if ($components) {
                my $cname = $name;
                $cname =~ s/\{i\}/i/g;
                $cname =~ s/\./_/g;
                $cname =~ s/_$//;
                $cname =~ s/$/_params/ if $noobjects;
                $name =~ s/\.\{i\}/\{i\}/g;
                $name =~ s/.*\.([^\.]+\.)$/$1/;
                $name =~ s/\{i\}/\.\{i\}/g;
                print qq{  <component name="$cname">\n};
            }
            if (@$dtprofiles) {
                $access = object_requirement($dtprofiles, $path);
                # XXX this is risky because it assumes that there will be
                #     no parameters; mark the element empty so it won't be
                #     closed (also see below for parameter check)
                if (!$access) {
                    $node->{xml2}->{element} = '';
                    return;
                }
                $ref = $name;
                $name = '';
                $numEntriesParameter = undef;
                $enableParameter = undef;
                $description = '';
                $descact = 'replace';
            }
        } elsif ($syntax) {
            $i = $node->{pnode}->{type} eq 'object' ? '      ' : '    ';
            $element = 'parameter';
            $node->{xml2}->{element} = $element;
            if (@$dtprofiles) {
                $access = parameter_requirement($dtprofiles, $path);
                # XXX see above for how element can be empty
                if ($node->{pnode}->{xml2}->{element} eq '') {
                    print STDERR "$path: ignoring because parent not in ".
                        "profile\n" if $verbose > 1;
                    return;
                }
                if (!$access) {
                    return;
                }
                $ref = $name;
                $name = '';
                # XXX proposal:
                $activeNotify =
                    $activeNotify eq 'canDeny' ? 'willDeny' : 'normal';
                $status = 'current';
                $forcedInform = 0;
                $description = '';
                $descact = 'replace';
                $syntax = undef;
            }
        } elsif ($element eq 'profile') {
            unless ($name) {
                $node->{xml2}->{element} = '';
                return;
            }
        } elsif ($element =~ /(\w+)Ref/) {
            $ref = $name;
            $name = '';
            $requirement = $access;
            $access = '';
            $element = $1; # parameter or object
            $node->{xml2}->{element} = ($element eq 'object') ? $element : '';
        }

        $name = $name ? qq{ name="$name"} : qq{};
        $base = $base ? qq{ base="$base"} : qq{};
        $ref = $ref ? qq{ ref="$ref"} : qq{};
        $access = $access ? qq{ access="$access"} : qq{};
        $numEntriesParameter = $numEntriesParameter ? qq{ numEntriesParameter="$numEntriesParameter"} : qq{};
        $enableParameter = $enableParameter ? qq{ enableParameter="$enableParameter"} : qq{};
        $status = $status ne 'current' ? qq{ status="$status"} : qq{};
        $activeNotify = (defined $activeNotify && $activeNotify ne 'normal') ?
            qq{ activeNotify="$activeNotify"} : qq{};
        $forcedInform = $forcedInform ? qq{ forcedInform="true"} : qq{};
        $requirement = $requirement ? qq{ requirement="$requirement"} : qq{};
        $minEntries = defined $minEntries ?
            qq{ minEntries="$minEntries"} : qq{};
        $maxEntries = defined $maxEntries ?
            qq{ maxEntries="$maxEntries"} : qq{};
        $base = $extends ? qq{ extends="$extends"} : qq{};

        $version = $version ? qq{ dmr:version="$version"} : qq{};

        my $dchanged = util_node_is_modified($node) && $changed->{description};
        ($description, $descact) = get_description($description, $descact,
                                                   $dchanged, $history, 1);
        $description = clean_description($description, $node->{name})
            if $canonical;
        $description = xml_escape($description);

        my $end_element = (@{$node->{nodes}} || $description || $syntax) ? '' : '/';
        print qq{$i<!--\n} if $element eq 'object' && $noobjects;
        print qq{$i<$element$name$base$ref$access$numEntriesParameter$enableParameter$status$activeNotify$forcedInform$requirement$minEntries$maxEntries$version$end_element>\n};
        $node->{xml2}->{element} = '' if $end_element;
        print qq{$i  <description>$description</description>\n} if
            $description;
        if ($uniqueKeys && !@$dtprofiles) {
            foreach my $uniqueKey (@$uniqueKeys) {
                my $functional = $uniqueKey->{functional};
                my $keyparams = $uniqueKey->{keyparams};
                $functional = !$functional ? qq{ functional="false"} : qq{};
                print qq{$i  <uniqueKey$functional>\n};
                foreach my $parameter (@$keyparams) {
                    print qq{$i    <parameter ref="$parameter"/>\n};
                }
                print qq{$i  </uniqueKey>\n};
            }
        }
        print qq{$i-->\n} if $element eq 'object' && $noobjects;

        # XXX this is almost verbatim from xml_node
        if ($syntax) {
            my $hidden = $syntax->{hidden};
            my $command = $syntax->{command};
            my $base = $syntax->{base};
            my $ref = $syntax->{ref};
            my $list = $syntax->{list};
            # XXX not supporting multiple sizes
            my $minListLength = $syntax->{listSizes}->[0]->{minLength};
            my $maxListLength = $syntax->{listSizes}->[0]->{maxLength};
            my $minLength = $syntax->{sizes}->[0]->{minLength};
            my $maxLength = $syntax->{sizes}->[0]->{maxLength};
            # XXX not supporting multiple ranges
            my $minListItems = $syntax->{listRanges}->[0]->{minInclusive};
            my $maxListItems = $syntax->{listRanges}->[0]->{maxInclusive};
            my $minInclusive = $syntax->{ranges}->[0]->{minInclusive};
            my $maxInclusive = $syntax->{ranges}->[0]->{maxInclusive};
            my $step = $syntax->{ranges}->[0]->{step};
            my $values = $node->{values};
            my $units = $node->{units};
            my $default = $node->{default};
            my $deftype = $node->{deftype};
            my $defstat = $node->{defstat};

            # XXX a bit of a kludge...
            $type = 'dataType' if $ref;

            $base = $base ? qq{ base="$base"} : qq{};
            $ref = $ref ? qq{ ref="$ref"} : qq{};
            $hidden = $hidden ? qq{ hidden="true"} : qq{};
            $command = $command ? qq{ command="true"} : qq{};
            $minListLength = defined $minListLength && $minListLength ne '' ?
                qq{ minLength="$minListLength"} : qq{};
            $maxListLength = defined $maxListLength && $maxListLength ne '' ?
                qq{ maxLength="$maxListLength"} : qq{};
            $minLength = defined $minLength && $minLength ne '' ?
                qq{ minLength="$minLength"} : qq{};
            $maxLength = defined $maxLength && $maxLength ne '' ?
                qq{ maxLength="$maxLength"} : qq{};
            $minListItems = defined $minListItems && $minListItems ne '' ?
                qq{ minItems="$minListItems"} : qq{};
            $maxListItems = defined $maxListItems && $maxListItems ne '' ?
                qq{ maxItems="$maxListItems"} : qq{};
            $minInclusive = defined $minInclusive && $minInclusive ne '' ?
                qq{ minInclusive="$minInclusive"} : qq{};
            $maxInclusive = defined $maxInclusive && $maxInclusive ne '' ?
                qq{ maxInclusive="$maxInclusive"} : qq{};
            $step = defined $step && $step ne '' ? qq{ step="$step"} : qq{};
            $defstat = $defstat ne 'current' ? qq{ status="$defstat"} : qq{};

            my $reference = $syntax->{reference};

            # pathRef and instanceRef
            my $refType = $syntax->{refType};
            my $targetParent = $syntax->{targetParent};
            my $targetParentScope = $syntax->{targetParentScope};

            # instanceRef
            my $targetType = $syntax->{targetType};
            my $targetDataType = $syntax->{targetDataType};

            # enumerationRef
            my $targetParam = $syntax->{targetParam};
            my $targetParamScope = $syntax->{targetParamScope};
            my $nullValue = $syntax->{nullValue};

            $refType = $refType ? qq{ refType="$refType"} : qq{};
            $targetParent = $targetParent ?
                qq{ targetParent="$targetParent"} : qq{};
            $targetParentScope = $targetParentScope ?
                qq{ targetParentScope="$targetParentScope"} : qq{};
            $targetType = $targetType ? qq{ targetType="$targetType"} : qq{};
            $targetDataType = $targetDataType ?
                qq{ targetDataType="$targetDataType"} : qq{};
            $targetParam = $targetParam ?
                qq{ targetParam="$targetParam"} : qq{};
            $targetParamScope = $targetParamScope ?
                qq{ targetParamScope="$targetParamScope"} : qq{};            
            $nullValue = defined $nullValue ?
                qq{ nullValue="$nullValue"} : qq{};

            print qq{$i  <syntax$hidden$command>\n};
            if ($list) {
                my $ended = ($minListLength || $maxListLength ||
                             $minListItems || $maxListItems) ? '' : '/';
                print qq{$i    <list$minListItems$maxListItems$ended>\n};
                print qq{$i      <size$minListLength$maxListLength/>\n} unless
                    $ended;
                print qq{$i    </list>\n} unless $ended;
            }
            my $ended = ($minLength || $maxLength || $minInclusive ||
                         $maxInclusive || $step || $reference || %$values ||
                         $units) ? '' : '/';
            print qq{$i    <$type$ref$base$ended>\n};
            print qq{$i      <size$minLength$maxLength/>\n} if
                $minLength || $maxLength;
            print qq{$i      <range$minInclusive$maxInclusive$step/>\n} if
                $minInclusive || $maxInclusive || $step;
            print qq{$i      <$reference$refType$targetParam$targetParent$targetParamScope$targetParentScope$targetType$targetDataType$nullValue/>\n} if $reference;
            foreach my $value (sort {$values->{$a}->{i} <=>
                                     $values->{$b}->{i}} keys %$values) {
                my $evalue = xml_escape($value);
                my $cvalue = $values->{$value};

                my $facet = $cvalue->{facet};
                my $history = $cvalue->{history};
                my $access = $cvalue->{access};
                my $status = $cvalue->{status};
                my $optional = boolean($cvalue->{optional});
                my $description = $cvalue->{description};
                my $descact = $cvalue->{descact};

                my $dchanged = util_node_is_modified($node) &&
                    $changed->{values}->{$value}->{description};
                ($description, $descact) =
                    get_description($description, $descact, $dchanged, $history,
                                    1);
                $description = clean_description($description, $node->{name})
                    if $canonical;
                $description = xml_escape($description);

                $optional = $optional ? qq{ optional="true"} : qq{};
                $access = $access ne 'readWrite' ? qq{ access="$access"} : qq{};
                $status = $status ne 'current' ? qq{ status="$status"} : qq{};
                my $ended = $description ? '' : '/';

                print qq{$i      <$facet value="$evalue"$access$status$optional$ended>\n};
                print qq{$i        <description>$description</description>\n} if $description;
                print qq{$i      </$facet>\n} unless $ended;
            }
            print qq{$i      <units value="$units"/>\n} if $units;
            print qq{$i    </$type>\n} unless $ended;
            print qq{$i    <default type="$deftype" value="$default"$defstat/>\n}
            if defined $default;
            print qq{$i  </syntax>\n};
            print qq{$i</parameter>\n};
            $node->{xml2}->{element} = '';
        }
        # XXX for profiles, logic doesn't work for parameters that have
        #     descriptions
        if ($origelem eq 'parameterRef' && !$end_element) {
            print qq{$i</parameter>\n};
        }
    }
}

# this is called (for objects and objectRefs only) after all parameters
sub xml2_postpar
{
    my ($node) = @_;

    my $element = $node->{xml2}->{element};
    return if !$element;

    # XXX wrong for profiles?
    my $i = $node->{type} eq 'object' ? '    ' : '      ';;

    print qq{$i<!--\n} if $noobjects;
    print qq{$i</object>\n};
    print qq{$i-->\n} if $noobjects;
    if ($components) {
        print qq{  </component>\n};
    }
}

# this is used only to close elements other than object and objectRef (unless
# already closed)
sub xml2_post
{
    my ($node, $indent) = @_;

    my $element = $node->{xml2}->{element};
    return if !$element || $element eq 'object';

    $indent = 0 unless $indent;
    return if $node->{name} eq 'object';

    # XXX this is a hack (I hate this logic)
    return if @$dtprofiles && $element eq 'parameter';
    
    # XXX this catches model
    return if $components && $indent > 0;

    my $i = "  " x $indent;
    print qq{$i</$element>\n};
}

# Determine maximum requirement for a given object across a set of profiles
sub object_requirement
{
    my ($dtprofiles, $path) = @_;

    my $maxreq = 0;
    foreach my $dtprofile (@$dtprofiles) {
        my $req = $profiles->{$dtprofile}->{$path};
        next unless $req;

        $req = {notSpecified => 1, present => 2, create => 3, delete => 4,
                createDelete => 5}->{$req};
        $maxreq = $req if $req > $maxreq;
    }

    # XXX special case, force "present" for "Device." and
    #     "InternetGatewayDevice."
    $maxreq = 2 if !$maxreq && $path =~ /^(InternetGateway)?Device\.$/;

    # XXX treat "notSpecified" as readOnly, since a profile definition can
    #     say "notSpecified" for an object and then reference its parameters
    $maxreq = {0 => '', 1 => 'readOnly', 2 => 'readOnly', 3 => 'create',
               4 => 'delete', 5 => 'createDelete'}->{$maxreq};

    return $maxreq;
}

# Determine maximum requirement for a given parameter across a set of profiles
sub parameter_requirement
{
    my ($dtprofiles, $path) = @_;

    my $maxreq = 0;
    foreach my $dtprofile (@$dtprofiles) {
        my $req = $profiles->{$dtprofile}->{$path};
        next unless $req;

        $req = {readOnly => 1, readWrite => 2}->{$req};
        $maxreq = $req if $req > $maxreq;
    }

    $maxreq = {0 => '', 1 => 'readOnly', 2 => 'readWrite'}->{$maxreq};

    return $maxreq;
}

# Heuristic changes to description to get rid of formatting etc and increase
# chances that description strings will compare as equal.
# XXX some of these things should be done on initial Word conversion...
sub clean_description
{
    my ($description, $name) = @_;

    return '' unless $description;

    $description =~ s/\{i\}/\[\[i\]\]/g;
    $description =~ s/\s*Comma-separated list of the following enumeration://;
    $description =~ s/\s*Comma separated list of the following enumeration://;
    $description =~ s/\s*Each element of the list is an enumeration of://;
    $description =~ s/\s*Each element in the list is one of://;
    $description =~ s/\s*Each entry in the list is an enumeration of://;
    $description =~ s/\s*Each item in the list is an enumeration of://;
    $description =~ s/\s*Each item is an enumeration of://;
    $description =~ s/\s*Enumeration of://;
    $description =~ s/\s*One of://;
    $description =~ s/\ban empty string\b/\{\{empty\}\}/ig;
    $description =~ s/\ban empty value\b/\{\{empty\}\}/ig;
    $description =~ s/\bnon-empty\b/not \{\{empty\}\}/ig;
    $description =~ s/\bnon empty\b/not \{\{empty\}\}/ig;
    $description =~ s/\bleft empty\b/\{\{empty\}\}/ig;
    $description =~ s/\bempty\b/\{\{empty\}\}/ig;
    $description =~ s/\bfalse\b/\{\{false\}\}/ig;
    $description =~ s/\btrue\b/\{\{true\}\}/ig;
    $description =~ s/\n[:\#\*] /\n/g;
    $description =~ s/\n\d+[:\.] /\n/g;
    $description =~
        s/\{\{(enum|pattern|object|param)\|([^\|\}]*)[^\}]*\}\}/$2/g;
    $description =~ s/\{\{(param|object)\}\}/$name/g;
    $description =~ s/ *\n({{enum|pattern}})/  $1/;
    $description =~ s/[\`\'\"]//g;
    $description =~ s/\{\{\{\{/\{\{/g;
    $description =~ s/\}\}\}\}/\}\}/g;
    $description =~ s/\[\[i\]\]/\{i\}/g;

    return $description;
}

# compare by bibid (designed to be used with sort)
sub bibid_cmp
{
    # try to split into string prefix, numeric middle, and string suffix;
    # sort alphabetically on the prefix, numerically on the middle, and
    # alphabetically on the suffix (gives correct ordering in many common
    # cases, e.g. "RFC1234" -> {RFC, 1234,} and TR-069a2 -> {TR-, 069, a2}
    # (ignore case on the alphabetic sorts)

    my ($ap, $am, $as) = ($a->{id} =~ /(.*?)(\d*)([iac]?\d*)$/);
    my ($bp, $bm, $bs) = ($b->{id} =~ /(.*?)(\d*)([iac]?\d*)$/);

    if ($ap ne $bp) {
        return (lc $ap cmp lc $bp);
    } elsif ($am != $bm) {
        return ($am <=> $bm);
    } else {
        return (lc $as cmp lc $bs);
    }
}

# Create an HTML anchor of a specified type; supported types (with their
# abbreviations) are:
# - heading: section heading
# - datatype: data type
# - bibref: bibliographic reference
# - path: data model object or parameter
# - value: parameter enumeration or pattern
# - profile: data model profile
# - profoot: profile footnote
#
# Anchor names are standardized to the extent that external documents can
# reliably reference resources within HTML files
#
# The general form of an anchor name is:
# - <namespace-prefix><name>
# 
# <namespace> depends on the anchor type and is used to prevent ambiguous
# anchor names; possible values are:
# - H: section Heading
# - T: data Type
# - R: bibliographic Reference
# - P: Profile
# - D: Data model (everything else)
#
# <namespace-prefix> is the namespace followed by a period.
#
# <name> is the name within the namespace and depends on the anchor type:
# - heading (H): the section name
# - datatype (T): the data type (unchanged)
# - bibref (R): the bibref id (unchanged)
# - path (D): the full path name (unchanged)
# - value (D): parameter path name, a period and the value
# - profile (P): the data model name (major version only), a period, and the
#                profile name (including version)
# - profoot (P): the profile anchor name, a period, and the obj/par path name
#
# Note that section names might not be unique (better to use a counter, or
# else derive from the section naming hierarchy, which is more complicated)
#
# Note that these processing rules need to be published

sub html_anchor_namespace_prefix
{
    my ($type) = @_;

    my $sep = '.';

    my $prefix = {heading => 'H', datatype => 'T', bibref => 'R',
                  path => 'D', value => 'D',
                  profile => 'P', profoot => 'P'}->{$type};
    die "html_anchor_namespace_prefix: invalid type: $type\n" unless $prefix;

    $prefix .= $sep;
    
    return $prefix;
}

sub html_anchor_reference_text
{
    my ($name, $label, $dontref) = @_;

    my $text = qq{};
    if ($dontref) {
        $text .= $label;
    } else {
        $text .= qq{<a href="#$name"};
        $text .= qq{>$label</a>} if $label;
        $text .= qq{/>} if !$label;
    }

    return $text;
}

sub html_create_anchor
{
    my ($label, $type, $opts) = @_;

    # label and opts as used as follows:
    # - heading: label is section name
    # - datatype: label is data type name
    # - bibref: label is bibref id
    # - path: label is the obj/par node (NOT the path)
    # - pathref: label is the path
    # - value: label is the value; param node is in $opts->{node}
    # - profile: label is the profile node (NOT the path)
    # - profoot: label is the profile obj/par node (NOT the path)

    my $node = $opts->{node};

    # validate type (any error is a programming error)
    my $types = ['heading', 'datatype', 'bibref', 'path', 'pathref', 'value',
                 'profile', 'profoot'];
    die "html_create_anchor: undefined anchor type\n" unless $type;
    die "html_create_anchor: unsupported anchor type: $type\n"
        unless grep {$type eq $_} @$types;

    # validate label
    die "html_create_anchor: for type '$type', must supply label" unless $label;

    # determine namespace prefix
    my $namespace_prefix = html_anchor_namespace_prefix($type);

    # determine the name as a function of anchor type (for many it is just the
    # supplied label)
    my $name = $label;
    if ($type eq 'bibref') {
        $label = '';
    } elsif ($type eq 'path') {
        die "html_create_anchor: for type '$type', label must be node" if $node;
        $node = $label;
        $name = $node->{path};
        $label = $node->{type} eq 'object' ? $node->{path} : $node->{name};
    } elsif ($type eq 'value') {
        die "html_create_anchor: for type '$type', node must be in opts"
            unless $node;
        $name = qq{$node->{path}.$label};
        $label = '';
    } elsif ($type eq 'profile') {
        die "html_create_anchor: for type '$type', label must be node" if $node;
        $node = $label;
        my $mnode = $node->{pnode};
        my $mname = $mnode->{name};
        $mname =~ s/:(\d+)\.\d+$/:$1/;
        $name = qq{$mname.$node->{name}};
        $label = '';
    } elsif ($type eq 'profoot') {
        die "html_create_anchor: for type '$type', label must be node" if $node;
        $node = $label;
        # XXX this is not nice...
        my $object = ($node->{type} eq 'objectRef');
        my $Pnode = $object ? $node->{pnode} : $node->{pnode}->{pnode};
        my $mnode = $Pnode->{pnode};
        my $mname = $mnode->{name};
        $mname =~ s/:(\d+)\.\d+$/:$1/;
        $name = qq{$mname.$Pnode->{name}.$node->{path}};
        # XXX nor is this
        $label = ++$Pnode->{html_profoot_num};
    }

    # form the anchor name
    my $aname = qq{$namespace_prefix$name};

    # XXX probably better to handle $nolinks logic right here rather than in
    #     the caller (would make things simpler and more consistent over all)
    my $dontdef = $nolinks;

    # form the anchor definition
    # XXX if supporting $dontdef would create html_anchor_definition_text()
    my $adef = qq{};
    $adef .= qq{<a name="$aname"};
    $adef .= qq{>$label</a>} if $label;
    $adef .= qq{/>} if !$label;

    my $dontref = util_is_omitted($node);

    # form the anchor reference (as a service to the caller)
    my $aref = html_anchor_reference_text($aname, $label, $dontref);

    # special case: for anchors of type path, define an additional anchor
    # which (for multi-instance objects) will be the table name, e.g. for
    # A.B.{i}., also define A.B
    # XXX could also define A.B.{i} and A.B. but hasn't seemed necessary
    if ($type eq 'path') {
        my $path = $node->{path};
        my $tpath = $path;
        $tpath =~ s/(\.\{i\})?\.$//;
        if ($tpath ne $path) {
            $adef = qq{<a name="$namespace_prefix$tpath"/>$adef};
        }
    }

    # if already defined, and if the label has changed, warn and update it
    my $hash = $anchors->{$aname};
    if (defined $hash) {
        if ($label ne $hash->{label}) {
            print STDERR "html_create_anchor: warning: $aname label changed\n"
                if $pedantic; 
            $hash->{label} = $label;
            $hash->{def} = $adef;
            $hash->{ref} = $aref;
        }
    } else {
        # XXX will refine this as becomes necessary
        $hash = {name => $aname, label => $label, def => $adef, ref => $aref,
                 dontref => $dontref};
        $anchors->{$aname} = $hash;
    }

    return $hash;
}

# Get the reference text for an anchor of the specified type (the anchor need
# not already be defined
sub html_get_anchor
{
    my ($name, $type, $label) = @_;

    # if not supplied, the label is the name
    $label = $name unless $label;

    # determine namespace prefix
    my $namespace_prefix = html_anchor_namespace_prefix($type);

    # form the anchor name
    my $aname = qq{$namespace_prefix$name};

    # if anchor is defined, get label (if not otherwise specified) and
    # dontref from it
    # XXX this is of limited use, because can reference an anchor before
    #     defining it (should somewhat re-think anchor handling, e.g.
    #     perhaps all anchors should be created as the node tree is created?)
    my $dontref = 0;
    my $hash = $anchors->{$aname};
    if (defined $hash) {
        $label = $hash->{label} unless $label;
        $dontref = $hash->{dontref};
    }

    # XXX this updates dontref for paths, values and profiles, but this
    #     might not be sufficient? (this is all rather heuristic, but the
    #     worst thing that can happen is that there is a link to nowhere)
    if ($type eq 'path') {
        my $node = $objects->{$name};
        $node = $parameters->{$name} if
            !$node && util_is_defined($parameters, $name);
        $dontref = util_is_omitted($node);
    } elsif ($type eq 'value') {
        my $pname = $name;
        $pname =~ s/\.[^\.]*$//;
        my $node = $parameters->{$pname} if
            util_is_defined($parameters, $pname);
        $dontref = util_is_omitted($node);
    } elsif ($type eq 'profile') {
        # XXX this isn't quite right, but no-one will notice!
        $dontref = 1;
    }

    # generate the reference text
    my $aref = html_anchor_reference_text($aname, $label, $dontref);

    return $aref;
}

# HTML report of node.
# XXX using the "here" strings makes this very hard to read, and throws off
#     emacs indentation; best avoided...
# XXX need to ensure that targets are unique within the document, so often
#     need to include the data model name (also need to clean the strings)
my $html_buffer = '';
my $html_parameters = [];
my $html_profile_active = 0;

sub html_node
{
    my ($node, $indent) = @_;

    # table options
    #my $tabopts = qq{border="1" cellpadding="2" cellspacing="2"};
    my $tabopts = qq{border="1" cellpadding="2" cellspacing="0"};

    # styles
    my $table = qq{text-align: left;};
    my $row = qq{vertical-align: top;};
    my $strike = qq{text-decoration: line-through;};
    my $center = qq{text-align: center;};

    # font
    my $h1font = qq{font-family: helvetica,arial,sans-serif; font-size: 14pt;};
    my $h2font = qq{font-family: helvetica,arial,sans-serif; font-size: 12pt;};
    my $h3font = qq{font-family: helvetica,arial,sans-serif; font-size: 10pt;};
    my $font = qq{font-family: helvetica,arial,sans-serif; font-size: 8pt;};
    my $fontnew = qq{color: blue;};
    my $fontdel = qq{color: red;};

    # others
    my $object_bg = qq{background-color: rgb(255, 255, 153);};
    my $theader_bg = qq{background-color: rgb(153, 153, 153);};

    # foo_oc (open comment) and foo_cc (close comment) control generation of
    # optional columns, e.g. the syntax column when generating ugly output
    my $synt_oc =  $showsyntax ? '' : '<!-- ';
    my $synt_cc =  $showsyntax ? '' : ' -->';
    my $vers_oc = !$showspec   ? '' : '<!-- ';
    my $vers_cc = !$showspec   ? '' : ' -->';
    my $spec_oc =  $showspec   ? '' : '<!-- ';
    my $spec_cc =  $showspec   ? '' : ' -->';

    # common processing for all nodes
    my $model = ($node->{type} =~ /model/);
    my $object = ($node->{type} =~ /object/);
    my $profile = ($node->{type} =~ /profile/);
    my $parameter = $node->{syntax}; # pretty safe? not profile params...

    my $changed = $node->{changed};
    my $history = $node->{history};
    my $description = $node->{description};
    my $origdesc = $description;
    my $descact = $node->{descact};
    my $dchanged = util_node_is_modified($node) && $changed->{description};
    ($description, $descact) = get_description($description, $descact,
                                               $dchanged, $history, 1);

    # XXX pass these through html_escape so as get UPnP DM translations
    my $path = html_escape($node->{path}, {empty => ''});
    my $name = html_escape($node->{name}, {empty => ''});
    my $ppath = html_escape($node->{pnode}->{path}, {empty => ''});
    my $pname = html_escape($node->{pnode}->{name}, {empty => ''});
    # XXX don't need to pass hidden, command, list, reference etc (are in
    #     syntax) but does no harm (now passing node too!) :(
    # XXX should work harder to define profile, object and parameter within
    #     profiles (so could use templates in descriptions)
    my $factory = ($node->{deftype} && $node->{deftype} eq 'factory') ?
        html_escape(util_default($node->{default})) : undef;
    $description =
        html_escape($description,
                    {default => '', empty => '',
                     node => $node,
                     path => $path,
                     model => $profile ? $node->{pnode}->{name} : '',
                     param => $parameter ? $name : '',
                     object => $parameter ? $ppath : $object ? $path : undef,
                     table => $node->{table},
                     profile => $profile ? $name : '',
                     access => $node->{access},
                     minEntries => $node->{minEntries},
                     maxEntries => $node->{maxEntries},
                     type => $node->{type},
                     syntax => $node->{syntax},
                     list => $node->{syntax}->{list},
                     hidden => $node->{syntax}->{hidden},
                     command => $node->{syntax}->{command},
                     factory => $factory,
                     reference => $node->{syntax}->{reference},
                     uniqueKeys => $node->{uniqueKeys},
                     enableParameter => $node->{enableParameter},
                     values => $node->{values},
                     units => $node->{units},
                     nbsp => $object || $parameter});

    # use indent as a first-time flag
    if (!$indent) {
        my $bbfhome = qq{http://www.broadband-forum.org/};
        my $doctype = qq{&nbsp;&nbsp;&nbsp;&nbsp;DATA MODEL DEFINITION};
        my $filename1 = $allfiles->[0]->{name};
        my $filename2 = $allfiles->[1]->{name};
        $filename1 =~ s/\.xml$//;
        $filename2 =~ s/\.xml$// if $filename2;
        my $docname1 = util_doc_name($filename1, {verbose => 1});
        my $docname2 = $filename2 ? util_doc_name($filename2, {verbose => 1})
            : qq{};
        my $doclink1 = $docname1 =~ /^TR-/ ?
            ($bbfhome . util_doc_link($docname1)) : qq{};
        my $doclink2 = $docname2 && $docname2 =~ /^TR-/ ?
            ($bbfhome . util_doc_link($docname2)) : qq{};
        $doclink1 = $doclink1 ? qq{<a href="$doclink1">$docname1</a>} :
            $docname1;
        $doclink2 = $doclink2 ? qq{<a href="$doclink2">$docname2</a>} :
            $docname2;
        my $title = qq{%%%%};
        my $any = $objpat || $lastonly || $showdiffs;
        $title .= qq{ (} if $any;
	$title .= qq{$objpat, } if $objpat;
        $title .= qq{changes, } if $lastonly;
        $title .= qq{diffs, } if $showdiffs;
        chop $title if $any;
        chop $title if $any;
        $title.= qq{)} if $any;
        my $sep = $docname2 ? qq{ -> } : qq{};
        my $title_link = $title;
        $title =~ s/%%%%/$docname1$sep$docname2/;
        $title_link =~ s/%%%%/$doclink1$sep$doclink2/;
        my $logo = qq{<a href="${bbfhome}"><img src="${bbfhome}images/logo-broadband-forum.gif" alt="Broadband Forum" style="border:0px;"/></a>};
        my $notice = html_notice($first_comment);
        # XXX in the styles below, should use inheritance to avoid duplication
        # XXX the td.d (delete) styles should use a tr style
        my $hyperlink = $showdiffs ?
            qq{a:link, a:visited, a:hover, a:active { color: inherit; }} : qq{};
	print <<END;
<!-- DO NOT EDIT; generated by Broadband Forum $tool_id_only ($tool_vers_date_only version) on $tool_run_date at $tool_run_time.
     $tool_cmd_line
     See $tool_url. -->
<html>
  <head>
    <meta content="text/html; charset=UTF-8" http-equiv="content-type">
    <title>$title</title>
    <style type="text/css">
      p, li, body { $font }
      h1 { $h1font }
      h2 { $h2font }
      h3 { $h3font }
      span, span.o, div, div.o { $font }
      span.n, div.n { $font $fontnew }
      span.i, div.i { $font $fontnew }
      span.d, div.d { $font $fontdel $strike }
      table { $table }
      th { $row $font }
      th.c { $row $font $center }
      th.g { $row $font $theader_bg }
      th.gc { $row $font $theader_bg $center }
      tr, tr.o { $row $font }
      tr.n { $row $font $fontnew }
      td.o { $row $font $object_bg }
      td, td.p { $row $font }
      td.oc { $row $font $object_bg $center }
      td.pc { $row $font $center }
      td.on { $row $font $object_bg $fontnew }
      td.od { $row $font $object_bg $fontdel $strike }
      td.pn { $row $font $fontnew }
      td.pd { $row $font $fontdel $strike }
      td.onc { $row $font $object_bg $fontnew $center }
      td.odc { $row $font $object_bg $fontdel $strike $center }
      td.pnc { $row $font $fontnew $center }
      td.pdc { $row $font $fontdel $strike $center }
      $hyperlink
    </style>
  </head>
  <body>
  <table width="100%" border="0">
    <tr>
      <td valign="middle">$logo<br><h3>$doctype</h3></td>
      <td align="center" valign="middle"><h1><br>$title_link</h1></td>
      <td width="25%"/>
    </tr>
  </table>
  $notice
END
        if ($description) {
            print <<END;
    <h1>Summary</h1>
    $description
END
        }
        print <<END;
    <h1>Table of Contents</h1>
    <ul> <!-- Table of Contents -->
END
        $html_buffer .= <<END;
    </ul> <!-- Table of Contents -->
END
        my $datatypes = $node->{dataTypes};
        if ($datatypes && @$datatypes) {
            #print STDERR Dumper($datatypes);
            my $anchor = html_create_anchor('Data Types', 'heading');
            print <<END;
      <li>$anchor->{ref}</li>
END
            my $preamble = <<END;
The parameters defined in this specification make use of a limited subset of the default SOAP data types {{bibref|SOAP1.1}}.  The complete set of data types, along with the notation used to represent these types, is listed in {{bibref|$tr106|Section 3.2}}.  The following named data types are used by this specification.
END
            update_bibrefs($preamble, $node->{file}, $node->{spec});
            # XXX sanity_node only detects invalid bibrefs in node and value
            #     descriptions...
            my $ibr = invalid_bibrefs($preamble);
            print STDERR "invalid bibrefs (need to use the --tr106 option?): " .
              join(', ', @$ibr) . "\n" if @$ibr;
            $preamble = html_escape($preamble);
            $html_buffer .= <<END;
    <h1>$anchor->{def}</h1>
    $preamble<p>
    <table $tabopts> <!-- Data Types -->
    <tr>
      <th class="g">Data Type</th>
      <th class="g">Base Type</th>
      <th class="g">Description</th>
    </tr>
END
            # XXX this is still very basic; no ranges, lengths etc;
            foreach my $datatype (sort {$a->{name} cmp $b->{name}}
                                  @$datatypes) {
                next if $lastonly &&
                    !grep {$_ eq $lspec} @{$datatype->{specs}};

                my $name = $datatype->{name};
                my $base = base_type($name, 0);
                my $description = $datatype->{description};
                # XXX not using this yet
                my $descact = $datatype->{descact};

                my $name_anchor = html_create_anchor($name, 'datatype');
                my $base_anchor = html_create_anchor($base, 'datatype');

                # want hyperlinks only for named data types
                my $baseref = ($base =~ /^[A-Z]/ && !$nolinks) ?
                    $base_anchor->{ref} : $base;

                # XXX this needs a generic utility that will escape any
                #     description with full template expansion
                # XXX more generally, a data type report should be quite like
                #     a parameter report (c.f. UPnP relatedStateVariable)
                $description = html_escape($description);

                $html_buffer .= <<END;
      <tr>
        <td>$name_anchor->{def}</td>
        <td>$baseref</td>
        <td>$description</td>
      </tr>
END
            }
            $html_buffer .= <<END;
    </table> <!-- Data Types -->
END
        }
        my $bibliography = $node->{bibliography};
        my $anchor = html_create_anchor('References', 'heading');
        if ($bibliography && %$bibliography) {
            print <<END;
      <li>$anchor->{ref}</li>
END
            $html_buffer .= <<END;
    <h1>$anchor->{def}</h1>
    <table border="0"> <!-- References -->
END
            my $references = $bibliography->{references};
            foreach my $reference (sort bibid_cmp @$references) {
                my $id = $reference->{id};
                next unless $allbibrefs || $bibrefs->{$id};
                # XXX this doesn't work when hiding sub-trees (would like
                #     hide_subtree and unhide_subtree to auto-hide and show
                #     relevant references)
                next if $lastonly &&
                    !grep {$_ eq $lspec} @{$bibrefs->{$id}};
                
                my $name = xml_escape($reference->{name});
                my $title = xml_escape($reference->{title});
                my $organization = xml_escape($reference->{organization});
                my $category = xml_escape($reference->{category});
                my $date = xml_escape($reference->{date});
                my $hyperlink = xml_escape($reference->{hyperlink});

                my $anchor = html_create_anchor($id, 'bibref');

                my $hid = $hyperlink ? qq{<a href="$hyperlink">$id</a>} : $id;
                $id = $anchor->{def} . qq{[$hid]};
                
                $title = $title ? qq{, <em>$title</em>} : qq{};
                $organization = $organization ? qq{, $organization} : qq{};
                # XXX category is no longer used
                $category = $category ? qq{ $category} : qq{};
                $date = $date ? qq{, $date} : qq{};
                $hyperlink = $hyperlink ?
                    qq{, <a href="$hyperlink">$hyperlink</a>} : qq{};
                
                $html_buffer .= <<END;
      <tr>
        <td>$id</td>
        <td>$name$title$organization$date.</td>
      </tr>
END
            }
            $html_buffer .= <<END;
    </table> <!-- References -->
END
        }
    }

    if ($indent) {
        if ($upnpdm && !$object && $node->{pnode}->{type} &&
            $node->{pnode}->{type} eq 'model') {
            print STDERR "$path: ignoring top-level parameter\n" if $verbose;
            return;
        }

        return if !$showdiffs && util_is_deleted($node);

        # XXX there's some double escaping going on here...
	my $name = html_escape($object ? $path : $node->{name},
                               {empty => '', fudge => 1});
        my $base = html_escape($node->{base}, {default => '', empty => ''});
	my $type = html_escape(type_string($node->{type}, $node->{syntax}),
			       {fudge => 1});
	my $syntax = html_escape(syntax_string($node->{type}, $node->{syntax}),
                                 {fudge => 1});
        $syntax = html_get_anchor($syntax, 'datatype') if !$nolinks &&
            grep {$_->{name} eq $syntax} @{$root->{dataTypes}};
        # XXX need to handle access / requirement more generally
        my $access = html_escape($node->{access});
	my $write =
            $access eq 'readWrite' ? 'W' :
            $access eq 'present' ? 'P' :
            $access eq 'create' ? 'A' :
            $access eq 'delete' ? 'D' :
            $access eq 'createDelete' ? 'C' : '-';

        my $default = $node->{default};
        undef $default if defined $node->{deftype} &&
            $node->{deftype} ne 'object';
        undef $default if defined $node->{defstat} &&
            $node->{defstat} eq 'deleted' && !$showdiffs;
	$default = html_escape($default,
                               {quote => scalar($type =~ /^string/),
                                hyphenate => 1});
        # XXX just version isn't sufficient; might need also to show model
        #     name, since "1.0" could be "Device:1.0" or "X_EXAMPLE_Device:1.0"
	my $version =
	    html_escape(version($node->{majorVersion}, $node->{minorVersion}));

        # XXX the above is addressed by $showspec and the use of a cleaned-up
        #     version of the spec
        # XXX doing this for every item is inefficient...
        print STDERR Dumper(util_copy($node, ['pnode', 'nodes'])) if
            $debugpath && $path =~ /$debugpath/;

        my $mspecs = util_history_values($node, 'mspec');
        my $specs = '';
        # XXX specs will be wrong if this XML was generated by the xml2 report
        #     (it will just be the last spec); however, it isn't output by
        #     default, so don't worry about this at the moment
        my $seen = {};
        foreach my $mspec (@$mspecs) {
            next unless defined $mspec;
            $specs .= ' ' if $specs;
            $specs .= util_doc_name($mspec) unless $seen->{$mspec};
            $seen->{$mspec} = 1;
        }

        # XXX $trclass is treated differently from $tdclass only to minimise
        #     diffs with HTML produced by earlier tool versions
        my $trclass = ($showdiffs && util_node_is_new($node)) ? 'n' : '';
        $trclass = $trclass ? qq{ class="$trclass"} : qq{};

	my $tdclass = ($model | $object | $profile) ? 'o' : 'p';
        $tdclass .= 'd' if $showdiffs && util_is_deleted($node);

        my $tdclasstyp = $tdclass;
        if ($showdiffs && util_node_is_modified($node) &&
            ($changed->{type} || $changed->{syntax})) {
            $tdclasstyp .= 'n';
        }

        my $tdclasswrt = $tdclass;
        if ($showdiffs && util_node_is_modified($node) && $changed->{access}) {
            $tdclasswrt .= 'n';
        }

        my $tdclassdef = $tdclass;
        if ($showdiffs && util_node_is_modified($node) && $changed->{default}) {
            if ($node->{defstat} eq 'deleted') {
                $tdclassdef .= 'd' unless $tdclassdef =~ /d/;
            } else {
                $tdclassdef .= 'n';
            }
        }

        if ($model) {
            my $title = qq{$name Data Model};
            $title .= qq{ (changes)} if $lastonly;
            my $anchor = html_create_anchor($title, 'heading');
            print <<END;
      <li>$anchor->{ref}</li>
      <ul> <!-- $title -->
        <li><a href="#$anchor->{name}">Data Model Definition</a></li>
        <ul> <!-- Data Model Definition -->
END
            my $boiler_plate = '';
            $boiler_plate = <<END if $node->{minorVersion};
For a given implementation of this data model, the CPE MUST indicate
support for the highest version number of any object or parameter that
it supports.  For example, even if the CPE supports only a single
parameter that was introduced in version $version, then it will indicate
support for version $version.  The version number associated with each object
and parameter is shown in the <b>Version</b> column.<p>
END
            $html_buffer .= <<END;
    <h1>$anchor->{def}</h1>
    $description<p>$boiler_plate
    <table width="100%" $tabopts> <!-- Data Model Definition -->
      <tbody>
        <tr>
          <th width="10%" class="g">Name</th>
          <th width="10%" class="g">Type</th>
          $synt_oc<th class="g">Syntax</th>$synt_cc
          <th width="10%" class="gc">Write</th>
          <th width="50%" class="g">Description</th>
          <th width="10%" class="gc">Object Default</th>
          $vers_oc<th width="10%" class="gc">Version</th>$vers_cc
          $spec_oc<th class="gc">Spec</th>$spec_cc
	</tr>
END
            $html_parameters = [];
            $html_profile_active = 0;
        }

        if ($parameter) {
            push @$html_parameters, $node;
        }

        # XXX if there are no profiles in the data model, a dummy profile node
        #     is defined, so we know here that we are the end of the data
        #     model definition
        if ($profile) {
            if (!$html_profile_active) {
                my $anchor = html_create_anchor(
                    'Inform and Notification Requirements', 'heading');
                print <<END;
        </ul> <!-- Data Model Definition -->
        <li>$anchor->{ref}</li>
        <ul> <!-- Inform and Notification Requirements -->
END
                $html_buffer .= <<END;
      </tbody>
    </table> <!-- Data Model Definition -->
    <h2>$anchor->{def}</h2>
END
                $html_buffer .=
                html_param_table(qq{Forced Inform Parameters},
                                 {tabopts => $tabopts},
                                 grep {$_->{forcedInform}} @$html_parameters) .
                html_param_table(qq{Forced Active Notification Parameters},
                                 {tabopts => $tabopts},
                                 grep {$_->{activeNotify} eq 'forceEnabled'}
                                 @$html_parameters) .
                html_param_table(qq{Default Active Notification Parameters},
                                 {tabopts => $tabopts},
                                 grep {$_->{activeNotify} eq
                                           'forceDefaultEnabled'}
                                 @$html_parameters) .
                html_param_table(qq{Parameters for which Active Notification }.
                                 qq{MAY be Denied},
                                 {tabopts => $tabopts, sepobj => 1},
                                 grep {$_->{activeNotify} eq 'canDeny'}
                                 @$html_parameters);
                my $panchor = html_create_anchor('Profile Definitions',
                                                 'heading');
                my $nanchor = html_create_anchor('Notation',
                                                 'heading');
                print <<END;
        </ul> <!-- Inform and Notification Requirements -->
        <li>$panchor->{ref}</li>
        <ul> <!-- $panchor->{label} -->
          <li>$nanchor->{ref}</li>
END
                $html_buffer .= <<END;
    <h2>$panchor->{def}</h2>
    <h3>$nanchor->{def}</h3>
    The following abbreviations are used to specify profile requirements:<p>
    <table width="60%" $tabopts>
      <tbody>
        <tr>
          <th class="gc">Abbreviation</th>
          <th class="g">Description</th>
        </tr>
        <tr>
          <td class="pc">R</td>
          <td>Read support is REQUIRED.</td>
        </tr>
        <tr>
          <td class="pc">W</td>
          <td>Both Read and Write support is REQUIRED.  This MUST NOT be specified for a parameter that is defined as read-only.</td>
        </tr>
        <tr>
          <td class="pc">P</td>
          <td>The object is REQUIRED to be present.</td>
        </tr>
        <tr>
          <td class="pc">C</td>
          <td>Creation and deletion of instances of the object via AddObject and DeleteObject is REQUIRED.</td>
        </tr>
        <tr>
          <td class="pc">A</td>
          <td>Creation of instances of the object via AddObject is REQUIRED, but deletion is not REQUIRED.</td>
        </tr>
        <tr>
          <td class="pc">D</td>
          <td>Deletion of instances of the object via DeleteObject is REQUIRED, but creation is not REQUIRED.</td>
        </tr>
      </tbody>
    </table>
END
                $html_profile_active = 1;
            }
            # XXX this avoids trying to report the dummy profile that was
            #     mentioned above (use $node->{name} because $name has been
            #     escaped)
            return unless $node->{name};
            my $anchor = html_create_anchor(qq{$name Profile}, 'heading');
            my $panchor = html_create_anchor($node, 'profile');
            print <<END;
          <li>$anchor->{ref}</li>
END
            my $span1 = $trclass ? qq{<span$trclass>} : qq{};
            my $span2 = $span1 ? qq{</span>} : qq{};
            $html_buffer .= <<END;
    <h3>$span1$panchor->{def}$anchor->{def}$span2</h3>
    $span1$description$span2<p>
    <table width="60%" $tabopts> <!-- $anchor->{label} -->
      <tbody>
        <tr>
          <th width="80%" class="g">Name</th>
          <th width="20%" class="gc">Requirement</th>
        </tr>
END
        }

        if ($model || $profile) {
        } elsif (!$html_profile_active) {
            my $anchor = html_create_anchor($node, 'path');
            $name = $anchor->{def} unless $nolinks;
            # XXX would like syntax to be a link when it's a named data type
            print <<END if $object && !$nolinks;
          <li>$anchor->{ref}</li>
END
            $html_buffer .= <<END;
        <tr$trclass>
          <td class="${tdclass}" title="$path">$name</td>
          <td class="${tdclasstyp}">$type</td>
          $synt_oc<td class="${tdclasstyp}">$syntax</td>$synt_cc
          <td class="${tdclasswrt}c">$write</td>
          <td class="${tdclass}">$description</td>
          <td class="${tdclassdef}c">$default</td>
          $vers_oc<td class="${tdclass}c">$version</td>$vers_cc
          $spec_oc<td class="${tdclass}c">$specs</td>$spec_cc
	</tr>
END
        } else {
            $path = $pname . $name unless $object;
            $name = html_get_anchor($path, 'path', $name) unless $nolinks;
            $write = 'R' if $access eq 'readOnly';
            my $footnote = qq{};
            # XXX need to use origdesc because description has already been
            #     escaped and an originally empty one might no longer be empty
            if ($origdesc) {
                my $anchor = html_create_anchor($node, 'profoot');
                # XXX pretty horrible way to get the profile node
                my $Pnode = $object ?
                    $node->{pnode} : $node->{pnode}->{pnode};
                push @{$Pnode->{html_footnotes}}, {anchor => $anchor,
                                                   description => $description};
                # XXX this isn't honoring $nolinks; I am thinking that this
                #     would be better handled within html_create_anchor()
                $footnote = qq{<sup>$anchor->{ref}</sup>};
            }
            $html_buffer .= <<END;
        <tr>
          <td class="${tdclass}">$name</td>
          <td class="${tdclass}c">$write$footnote</td>
	</tr>
END
        }
    }
}

sub html_post
{
    my ($node, $indent) = @_;

    my $name = $node->{name};
    my $model = ($node->{type} =~ /model/);
    my $profile = ($node->{type} =~ /profile/);

    # XXX horrible hack for nameless profiles
    return if $profile && !$name;

    if (($model && !$html_profile_active) || $profile || !$indent) {
        # XXX this can close too many tables (not a bad problem?)
	$html_buffer .= <<END;
      </tbody>
    </table> <!-- $name -->
END
        # output profile footnotes if any
        if ($profile) {
            $html_buffer .= html_profile_footnotes($node);
        }
        # XXX this is heuristic (but usually correct)
        if (!$indent) {
            print <<END;
        </ul>
      </ul>
END
            $html_buffer .= <<END;
    <p>
    <hr>
    Generated by <a href="http://www.broadband-forum.org">Broadband Forum</a> <a href="$tool_url">$tool_id_only</a> ($tool_vers_date_only version) on $tool_run_date at $tool_run_time.<br>
    $tool_cmd_line<p>
  </body>
</html>
END
            print $html_buffer;
        }
    }
}

# Output an HTML parameter table, optionally with separate object rows
sub html_param_table
{
    my ($title, $hash, @parameters) = @_;

    my $tabopts = $hash->{tabopts};
    my $sepobj = $hash->{sepobj};

    my $anchor = html_create_anchor($title, 'heading');

    my $html_buffer = qq{};

    print <<END;
          <li>$anchor->{ref}</li>
END

    $html_buffer .= <<END;
    <h3>$anchor->{def}</h3>
END

    $html_buffer .= <<END;
    <table width="60%" $tabopts> <!-- $title -->
      <tbody>
        <tr>
          <th class="g">Parameter</th>
        </tr>
END

    my $curobj = '';
    foreach my $parameter (@parameters) {
        # don't html_escape until after have parsed path (assumes dots)
        my $path = $parameter->{path};
        my $param = $path;
        if ($sepobj) {
            (my $object, $param) = $path =~ /^(.*\.)([^\.]*)$/;
            $object = html_escape($object, {empty => ''});
            if ($object && $object ne $curobj) {
                $curobj = $object;
                $object = html_get_anchor($object, 'path') unless $nolinks;
                $html_buffer .= <<END;
        <tr>
          <td class="o">$object</td>
        </tr>
END
            }
        }
        $path = html_escape($path, {empty => ''});
        $param = html_escape($param, {empty => ''});
        $param = html_get_anchor($path, 'path', $param) unless $nolinks;
        $html_buffer .= <<END;
        <tr>
          <td>$param</td>
        </tr>
END
    }

    $html_buffer .= <<END;
      </tbody>
    </table> <!-- $title -->
END
    return $html_buffer;
}

# Output profile footnotes, if any
# XXX this is assumed to be called only on a profile node
sub html_profile_footnotes
{
    my ($node) = @_;

    my $footnotes = $node->{html_footnotes};
    return qq{} unless $footnotes && @$footnotes;

    my $html_buffer = qq{};
    $html_buffer .= <<END;
    <table width="60%" border="0">
      <tbody>
END

    foreach my $footnote (@$footnotes) {
        my $anchor = $footnote->{anchor};
        my $description = $footnote->{description};

        $html_buffer .= <<END;
        <tr>
          <td width="1%"><sup>$anchor->{def}</sup></td>
          <td>$description</td>
        </tr>
END
    }

    $html_buffer .= <<END;
      </tbody>
    </table>
END

    return $html_buffer;
}

# Generate "Notice" from the supplied comment (if any)
sub html_notice
{
    my ($comment) = @_;

    # if undefined, just return empty string
    return '' unless $comment;

    # the comment MUST include a "Notice:" line; text before it is discarded
    # and text is then taken until the next "[\w\s]+:" line
    # (process line by line so can format paragraphs)
    my $text = '';
    my $in_list = 0;
    my $in_list_ever = 0;
    my $seen_notice = 0;
    my $seen_terminator = 0;
    foreach my $line (split /\n/, $comment) {

        # discard leading and trailing space
        $line =~ s/^\s*//;
        $line =~ s/\s*//;

        # look for start of text to be used
        if (!$seen_notice) {
            $seen_notice = ($line =~ /^Notice:$/);
            if ($seen_notice) {
                $text .= qq{<h1>Notice</h1>};
            }
        }

        # look for end of text to be used
        elsif (!$seen_terminator) {
            $seen_terminator = ($line =~ /^[\w\s]+:$/);
            if (!$seen_terminator) {

                # using this text; look for list item
                my ($item) = ($line =~ /^\((\w)\)/);

                # blank line is end of list (if active) and of paragraph
                if ($line eq '') {
                    if ($in_list) {
                        $text .= qq{</ul>};
                        $in_list = 0;
                    }
                    $text .= qq{<p>};
                }

                # if list item, handle list
                # XXX horrible hack; prevent two lists to avoid formatting
                #     errors with (for example) TR-106 notice
                elsif ($item) {
                    if (!$in_list && !$in_list_ever) {
                        $text .= qq{<ul>};
                        $in_list = 1;
                        $in_list_ever = 1;
                    }
                    if ($in_list) {
                        $text .=
                            qq{<li style="list-style-type: upper-alpha;">};
                        $line =~ s/^\(.\)\s*//;
                    }
                }

                # append text (and newline)
                $text .= qq{$line\n};
            }
        }
    }
    if ($in_list) {
        $text .= qq{</ul>};
    }

    return $text;
}

# Escape a value suitably for exporting as HTML.
# XXX is mostly aimed at descriptions, but probably does no harm to anything
#     else
sub html_escape {
    my ($value, $opts) = @_;

    $value = util_default($value, $opts->{default}, $opts->{empty});

    # this is intended for string defaults
    $value = '"' . $value . '"' if $opts->{quote} && $value !~ /^[<-]/;

    # escape special characters
    # XXX do this is part of markup processing?
    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    # apply UPnP DM rules
    # XXX be simple-minded and do this unconditionally to begin with...
    #     (for technical reasons, rules not applied in the same order as
    #     defined in the doc; still some false positives)
    if ($upnpdm) {
        my $before = $value;
        # " .A" -> " A" (also as template arg and at start)
        $value =~ s/^\.([A-Z])/$1/g;
        $value =~ s/([\s\|])\.([A-Z])/$1$2/g;

        # ".{i}" -> ".#"
        $value =~ s/\.\{i\}/\.#/g;

        # "Name.(Name|#)." -> "Name/(Name|#)/"
        $value =~ s/([A-Z]\w*)\.((?:[A-Z]\w*|#))\./$1\/$2\//g;

        # "Name.Name" -> "Name/Name"
        $value =~ s/([A-Z]\w*)\.((?:[A-Z]\w*|#))/$1\/$2/g;

        # "Name(/(Name|#))+." -> ".../"
        $value =~ s/([A-Z]\w*)((?:\/(?:[A-Z]\w*|#))+)\./$1$2\//g;

        # Remove BBF-specific root-ish objects
        $value =~ s/(?:InternetGateway)?Device\/([A-Z])/$1/g;
        $value =~ s/Services\/([A-Z])/$1/g;
        $value =~ s/\w+Service\/#\/([A-Z])/$1/g;

        # Final hack to get rid BBF-specific root-ish objects
        $value = '' if $value =~ /^(?:InternetGateway)?Device\.$/;
        $value = '' if $value =~ /^Services\/$/;

        # XXX this doesn't quite work because leaves empty top-level
        #     Service object and any top-level parameters, e.g. Enable
        $value = '' if $value =~ /^\w+Service\/#\/$/;

        print STDERR "$before -> $value\n" if
                                     $verbose > 1 && $value ne $before;
    }

    # process markup
    # XXX whitespace and template processing is generic; shouldn't be done
    #     here
    unless ($opts->{nomarkup}) {
        $value = html_whitespace($value);
        $value = html_template($value, $opts) unless $notemplates;
        # XXX here is the place to escape HTML-special characters
        $value = html_verbatim($value);
        $value = html_list($value);
        # XXX also (but shouldn't) does "%%" anchor expansion (which will
        #     generate an anchor with the name of the current object or
        #     parameter path, then a dot, then the text between the %%s
        $value = html_font($value, $opts);
        $value = html_paragraph($value);
        $value = html_hyperlink($value);
    }

    # XXX fudge wrap of very long names and types (firefox 3 supports &shy;)
    $value =~ s/([^\d]\.)/$1&shy;/g if $opts->{fudge} && !$nohyphenate;
    $value =~ s/&shy;$// if $opts->{fudge} && !$nohyphenate;
    $value =~ s/\(/&shy;\(/g if $opts->{fudge} && !$nohyphenate;
    $value =~ s/\[/&shy;\[/g if $opts->{fudge} && !$nohyphenate;

    # XXX try to hyphenate long words (firefox 3 supports &shy;)
    $value =~ s/([a-z_])([A-Z])/$1&shy;$2/g if
        $opts->{hyphenate} && !$nohyphenate;

    $value = '&nbsp;' if $opts->{nbsp} && $value eq '';

    return $value;
}

# Process whitespace
sub html_whitespace
{
    my ($inval) = @_;

    return $inval unless $inval;

    # remove any leading whitespace up to and including the first line break
    $inval =~ s/^[ \t]*\n//;

    # remove any trailing whitespace (necessary to avoid polluting the prefix
    # length)
    $inval =~ s/\s*$//;

    # determine longest common whitespace prefix
    my $len = undef;
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {
        my ($pre) = $line =~ /^(\s*)/;
        $len = length($pre) if !defined($len) || length($pre) < $len;
        if ($line =~ /\t/) {
            my $tline = $line;
            $tline =~ s/\t/\\t/g;
            print STDERR "replace tab(s) in \"$tline\" with spaces!\n";
        }
    }
    $len = 0 unless defined $len;

    # remove it
    my $outval = '';
    foreach my $line (@lines) {
        $line = substr($line, $len);
        $outval .= $line . "\n";
    }

    # remove trailing newline
    chomp $outval;
    return $outval;
}

# Process templates
sub html_template
{
    my ($inval, $p) = @_;

    # auto-prefix {{reference}} if the parameter is a reference (put after
    # {{list}} if already there)
    if ($p->{reference} && $inval !~ /\{\{reference/ &&
        $inval !~ /\{\{noreference\}\}/) {
        my $sep = !$inval ? "" : "  ";
        if ($inval =~ /\{\{list\}\}/) {
            $inval =~ s/(\{\{list\}\})/$1$sep\{\{reference\}\}/;
        } else {
            $inval = "{{reference}}" . $sep . $inval;
        }
    }

    # auto-prefix {{list}} if the parameter is list-valued
    if ($p->{list} && $inval !~ /\{\{list/ &&
        $inval !~ /\{\{nolist\}\}/) {
        my $sep = !$inval ? "" : "  ";
        $inval = "{{list}}" . $sep . $inval;
    }

    # auto-prefix {{datatype}} if the parameter has a named data type
    if ($p->{type} && $p->{type} eq 'dataType' &&
        $inval !~ /\{\{datatype/ &&
        $inval !~ /\{\{nodatatype\}\}/) {
        my $sep = !$inval ? "" : "  ";
        $inval = "{{datatype}}" . $sep . $inval;
    }

    # auto-prefix {{profdesc}} if it's a profile
    if ($p->{profile} && $inval !~ /\{\{noprofdesc\}\}/) {
        my $sep = !$inval ? "" : "  ";
        $inval = "{{profdesc}}" . $sep . $inval;
    }

    # auto-append {{enum}} or {{pattern}} if there are values and it's not
    # already there (put it on the same line if the value is empty or ends
    # with a sentence terminator, allowing single quote formatting chars)
    # "{{}}" is an empty template reference that will be removed; it prevents
    # special "after newline" template expansion behavior
    if ($p->{values} && %{$p->{values}}) {
        my ($key) = keys %{$p->{values}};
        my $facet = $p->{values}->{$key}->{facet};
        my $sep = !$inval ? "" : $inval =~ /[\.\?\!]\'*$/ ? "  " : "\n{{}}";
        $inval .= $sep . "{{enum}}" if $facet eq 'enumeration' &&
            $inval !~ /\{\{enum\}\}/ && $inval !~ /\{\{noenum\}\}/;
        $inval .= $sep . "{{pattern}}" if $facet eq 'pattern' &&
            $inval !~ /\{\{pattern\}\}/ && $inval !~ /\{\{nopattern\}\}/;
    }

    # similarly auto-append {{hidden}}, {{command}}, {{factory}}, {{entries}}
    # and {{keys}} if appropriate
    if ($p->{hidden} && $inval !~ /\{\{hidden/ &&
        $inval !~ /\{\{nohidden\}\}/) {
        my $sep = !$inval ? "" : "\n";
        $inval .= $sep . "{{hidden}}";
    }
    if ($p->{command} && $inval !~ /\{\{command/ &&
        $inval !~ /\{\{nocommand\}\}/) {
        my $sep = !$inval ? "" : "\n";
        $inval .= $sep . "{{command}}";
    }
    if ($p->{factory} && $inval !~ /\{\{factory/ &&
        $inval !~ /\{\{nofactory\}\}/) {
        my $sep = !$inval ? "" : "\n";
        $inval .= $sep . "{{factory}}";
    }
    my ($multi) = util_is_multi_instance($p->{minEntries}, $p->{maxEntries});
    if ($multi && $inval !~ /\{\{entries/ && $inval !~ /\{\{noentries\}\}/) {
        my $sep = !$inval ? "" : "\n";
        $inval .= $sep . "{{entries}}";
    }
    if ($p->{uniqueKeys} && @{$p->{uniqueKeys}}&&
        $inval !~ /\{\{keys/ && $inval !~ /\{\{nokeys\}\}/) {
        my $sep = !$inval ? "" : "\n";
        $inval .= $sep . "{{keys}}";
    }

    # in template expansions, the @a array is arguments and the %p hash is
    # parameters (options)
    my $templates =
        [
         {name => 'bibref',
          text1 => \&html_template_bibref,
          text2 => \&html_template_bibref},
         {name => 'section', text => q{}},
         {name => 'param',
          text0 => \&html_template_paramref,
          text1 => \&html_template_paramref,
          text2 => \&html_template_paramref},
         {name => 'object',
          text0 => \&html_template_objectref,
          text1 => \&html_template_objectref,
          text2 => \&html_template_objectref},
         {name => 'profile',
          text0 => \&html_template_profileref,
          text1 => \&html_template_profileref},
         {name => 'keys',
          text0 => \&html_template_keys},
         {name => 'nokeys',
          text0 => q{}},
         {name => 'entries',
          text0 => \&html_template_entries},
         {name => 'noentries',
          text0 => q{}},
         {name => 'list',
          text0 => \&html_template_list,
          text1 => \&html_template_list},
         {name => 'nolist',
          text0 => q{}},
         {name => 'numentries',
          text0 => \&html_template_numentries},
         {name => 'datatype',
          text0 => \&html_template_datatype,
          text1 => \&html_template_datatype},
         {name => 'nodatatype',
          text0 => q{}},
         {name => 'profdesc',
          text0 => \&html_template_profdesc},
         {name => 'noprofdesc',
          text0 => q{}},
         {name => 'hidden',
          text0 => q{{{mark|hidden}}When read, this parameter returns {{null}}, regardless of the actual value.},
          text1 => q{{{mark|hidden}}When read, this parameter returns ''$a[0]'', regardless of the actual value.}},
         {name => 'nohidden',
          text0 => q{}},
         {name => 'command',
          text0 => q{{{mark|command}}The value of this parameter is not part of the device configuration and is always {{null}} when read.}},
         {name => 'nocommand',
          text0 => q{}},
         {name => 'factory',
          text0 => q{{{mark|factory}}The factory default value MUST be ''$p->{factory}''.}},
         {name => 'nofactory',
          text0 => q{}},
         {name => 'null',
          text0 => \&html_template_null,
          text1 => \&html_template_null,
          text2 => \&html_template_null},
         {name => 'enum',
          text0 => \&html_template_enum,
          text1 => \&html_template_valueref,
          text2 => \&html_template_valueref,
          text3 => \&html_template_valueref},
         {name => 'noenum',
          text0 => q{}},
         {name => 'pattern',
          text0 => \&html_template_pattern,
          text1 => \&html_template_valueref,
          text2 => \&html_template_valueref,
          text3 => \&html_template_valueref},
         {name => 'nopattern',
          text0 => q{}},
         {name => 'reference',
          text0 => \&html_template_reference,
          text1 => \&html_template_reference},
         {name => 'noreference',
          text0 => q{}},
         {name => 'units',
          text0 => \&html_template_units},
         {name => 'empty', text0 => q{an empty string}, ucfirst => 1},
         {name => 'false', text0 => q{''false''}},
         {name => 'true', text0 => q{''true''}},
         {name => 'mark',
          text1 => \&html_template_mark},
         {name => 'issue',
          text1 => \&html_template_issue,
          text2 => \&html_template_issue},
         {name => 'ignore',
          text => q{}}
         ];

    # XXX need some protection against infinite loops here...
    # XXX do we want to allow template references to span newlines?
    # XXX insdel works for issues but not in general, e.g. when expanding
    #     references would like to know whether in deleted text so can
    #     suppress warnings (for now made these warnings be output only in
    #     pedantic mode)
    while (my ($newline, $period, $insdel, $temp) =
           $inval =~ /(\n?)[ \t]*([\.\?\!]?)[ \t]*([\-\+]*)[ \t]*(\{\{.*)/) {
        # pattern returns rest of string in temp (owing to difficulty of
        # handling nested braces), so match braces to find end
        my $tref = extract_bracketed($temp, '{}');
        if (!defined($tref)) {
            print STDERR "$p->{path}: invalid template reference: $temp\n";
            $inval =~ s/\{\{/\[\[/;
            next;
        }
        my ($name, $args) = $tref =~ /^\{\{([^\|\}]*)(?:\|(.*))?\}\}$/;
        # XXX atstart is possibly useful for descriptions that consist only of
        #     {{enum}} or {{pattern}}?  I think not...
        if (!defined($name)) {
            print STDERR "$p->{path}: invalid template reference: $tref\n";
            $inval =~ s/\{\{/\[\[/;
            next;
        }
        my $atstart = $inval =~ /^\{\{$name[\|\}]/;
        $p->{atstart} = $atstart;
        $p->{newline} = $newline;
        $p->{period} = $period;
        $p->{insdel} = $insdel;
        #my @a = split /\|/, $args;
        my @a = ();
        if (defined $args) {
            my $a = '';
            my $i = 0;
            foreach my $c (split //, $args) {
                $i++ if $c eq '{';
                $i-- if $c eq '}';
                if (!$i && $c eq '|') {
                    push @a, $a;
                    $a = '';
                } else {
                    $a .= $c;
                }
            }
            push @a, $a;
        }
        my $n = @a;
        my $template = (grep {$_->{name} eq $name} @$templates)[0];
        my $text = $tref;
        $text =~ s/^../\[\[/;
        $text =~ s/..$/\]\]/;
        my $cmd;
        if ($template) {
            $cmd = defined $template->{'text'.$n} ? $template->{'text'.$n} :
                $template->{text};
            if (ref($cmd)) {
                my $ttext = &$cmd($p, @a);
                $text = $ttext if defined $ttext;
            } elsif (defined $cmd) {
                print STDERR "$text: $cmd\n" if $verbose > 2;
                my $ttext = eval "qq{$cmd}";
                if ($@) {
                    warn $@;
                } else {
                    $text = $ttext;
                    $text = ucfirst $text if
                        $template->{ucfirst} && ($newline || $period);
                }
            }
        }
        if ($name && (!defined $text || $text =~ /^\[\[/)) {
            print STDERR "$p->{path}: invalid template reference: $tref\n";
            #print STDERR "$name: n=$n cmd=<$cmd> text=<$text>\n";
            #foreach my $a (@a) {
            #    print STDERR "  $a\n";
            #}
        }
        # process tref to avoid problems with RE special characters
        $tref =~ s/[^\{\}]/\./g;
        $inval =~ s/$tref/$text/;
    }

    # remove null template references (which are used as separators)
    $inval =~ s/\[\[\]\]//g;

    # restore unexpanded templates
    $inval =~ s/\[\[([^\]]*)/\{\{$1/g;
    $inval =~ s/\]\]/\}\}/g;

    return $inval;
}

# insert a mark, e.g. for a template expansion
sub html_template_mark
{
    my ($opts, $arg) = @_;

    return $marktemplates ? qq{$marktemplates$arg: } : qq{};
}

# used by the {{issue}} template
my $issue_counter = {};

# report and track an issue
sub html_template_issue
{
    my ($opts, $arg1, $arg2) = @_;

    # if called with one arg, the prefix is "XXX" and the argument is the
    # comment; if called with two args, they are prefix,status and the
    # comment (prefix,status can be thought of as a list of name=value pairs
    # with a defined positional order, so it is extensible) 
    my ($prefix, $status, $comment);
    if (defined $arg2) {
        ($prefix, $status) = ($arg1 =~ /([^,]*),?([^,]*)/);
        $comment = $arg2;
    } else {
        $prefix = 'XXX';
        $status = '';
        $comment = $arg1;
    }

    # XXX for now any non-blank status means that the issue has been addressed

    # is it already marked as deleted?
    my $deleted = ($opts->{insdel} && $opts->{insdel} eq '---');

    # if preceded by "---" is deleted, so no counter increment
    my $counter = $deleted ? qq{''n''} : $issue_counter->{$prefix}++;

    # if not already deleted and issue has been addressed, mark accordingly
    my $mark = (!$deleted && $status) ? '---' : '';

    return qq{\n'''$mark$prefix $counter: $comment$mark'''};
}

# insert appropriate null value
sub html_template_null
{
    my ($opts, $name, $scope) = @_;

    my $object = $opts->{object};
    my $param = $opts->{param};

    my $this = $name ? 0 : 1;
    $name = $param unless $name;

    (my $path, $name) = relative_path($object, $name, $scope);
    if (!util_is_defined($parameters, $path)) {
        # XXX don't warn if this item has been deleted
        if (!util_is_deleted($opts->{node})) {
            print STDERR "$object$param: reference to invalid parameter ".
                "$path\n";
        }
        return undef;
    }

    my $type = $parameters->{$path}->{type};
    my $syntax = $parameters->{$path}->{syntax};

    my $typeinfo = get_typeinfo($type, $syntax);
    my ($primtype, $dataType) = ($typeinfo->{value}, $typeinfo->{dataType});

    $primtype = base_type($primtype, 1) if $dataType;

    if ($primtype =~ /^(base64|hexBinary|string)$/) {
        return qq{{{empty}}};
    } elsif ($primtype eq 'boolean') {
        return qq{{{false}}};
    } elsif ($primtype eq 'dateTime') {
        return qq{0001-01-01T00:00:00Z};
    } elsif ($primtype =~ /^unsigned(Int|Long)$/) {
        return qq{0};
    } elsif ($primtype =~ /^(int|long)$/) {
        return qq{-1};
    } else {
        die "html_template_null: invalid primitive type: $primtype\n";
    }
}

# insert units string
sub html_template_units
{
    my ($opts) = @_;

    my $path = $opts->{path};
    my $units = $opts->{units};

    if (!$units) {
        print STDERR "$path: empty units string\n";
        return qq{[[units]]};
    } else {
        return qq{''$units''};
    }
}

# XXX want to be able to control level of generated info?
sub html_template_list
{
    my ($opts, $arg) = @_;

    my $type = $opts->{type};
    my $syntax = $opts->{syntax};

    $type = get_typeinfo($type, $syntax)->{value} if $type eq 'dataType';

    my $text = qq{{{mark|list-$type}}Comma-separated };
    $text .= syntax_string($type, $syntax, 1);
    $text .= qq{, $arg} if $arg;
    $text .= '.';

    return $text;
}

# Generate standard NumberOfEntries description.
sub html_template_numentries
{
    my ($opts) = @_;

    my $table = $opts->{table};

    my $text = qq{};
    $text .= qq{{{mark|numentries}}} if $marktemplates;

    if ($table) {
        my $tpath = $table->{path};
        $tpath =~ s/\.(\{i\}\.)?$//;
        $tpath =~ s/.*\.//;
        $text .= qq{The number of entries in the {{object|$tpath}} table.};
    }

    return $text;
}

# XXX want to be able to control level of generated info?
sub html_template_datatype
{
    my ($opts, $arg) = @_;

    my $path = $opts->{path};
    my $type = $opts->{type};
    my $syntax = $opts->{syntax};

    my $typeinfo = get_typeinfo($type, $syntax);
    my $dtname = $typeinfo->{value};

    my ($dtdef) = grep {$_->{name} eq $dtname} @{$root->{dataTypes}};
    if (!$dtdef) {
        print STDERR "$path: invalid use of {{datatype}}; parameter is ".
            "not of a valid named data type\n";
        return qq{};
    }

    # if argument is supplied and is "expand", return the data type description
    my $text;
    if ($arg && $arg eq 'expand') {
        # XXX should check for valid data type? (should always be)
        # XXX not sure why need to call html_whitespace() here...
        $text = html_whitespace($dtdef->{description});
        # XXX we remove any {{issue}} templates so they will occur only in
        # the data type table and not whenever the data type is expanded
        $text = util_ignore_template('issue', $text);
    }

    # otherwise, just return "[datatype] " (as a hyperlink), unless
    # --showsyntax, in which case return nothing because the info will be
    # in the Syntax column
    else {
        $dtname = html_get_anchor($dtname, 'datatype') unless $nolinks;
        $text = $showsyntax ? qq{} : qq{[''$dtname''] };
    }

    return $text;
}

sub html_template_profdesc
{
    my ($opts, $arg) = @_;

    my $node = $opts->{node};
    my $name = $node->{name};
    my $base = $node->{base};
    my $extends = $node->{extends};

    # XXX horrible hack for nameless profiles
    return '' unless $name;

    # model in which profile was first defined
    my $defmodel = $profiles->{$name}->{defmodel};

    # same model but excluding minor version number
    my $defmodelmaj = $defmodel;
    $defmodelmaj =~ s/\.\d+$//;

    my $baseprofs = $base;
    my $plural = '';
    if ($extends) {
        $plural = 's' if $baseprofs || $extends =~ / /;
        $baseprofs .= ' ' if $baseprofs;
        $baseprofs .= $extends;
    }
    if ($baseprofs) {
        $baseprofs =~ s/(\w+:\d+)/{{profile|$1}}/g;
        $baseprofs =~ s/ /, /g;
        $baseprofs =~ s/, ([^,]+$)/ and $1/;
    }

    my $text = $baseprofs ? qq{The} : qq{This table defines the};
    $text .= qq{ {{profile}} profile for the ''$defmodelmaj'' object};
    $text .= qq{ is defined as the union of the $baseprofs profile$plural }.
        qq{and the additional requirements defined in this table} if $baseprofs;
    $text .= qq{.  The minimum REQUIRED version for this profile is }.
        qq{''$defmodel''.};

    return $text;
}

sub html_template_entries
{
    my ($opts) = @_;

    my $min = $opts->{minEntries};
    my $max = $opts->{maxEntries};

    my ($multi, $fixed) = util_is_multi_instance($min, $max);

    return qq{} unless $multi;
    
    return qq{} if $min == 0 && $max eq 'unbounded';

    # XXX should say something here but I don't know what is best
    return qq{} if $min == 0 && $max == 1;

    my $minEntries = ($min > 1) ? 'entries' : 'entry';
    return qq{This table MUST contain exactly $min $minEntries.} if $fixed;

    return qq{This table MUST contain at least $min $minEntries.} if
        $max eq 'unbounded';

    my $maxEntries = ($max > 1) ? 'entries' : 'entry'; 
    return qq{This table MUST contain at least $min and }.
        qq{at most $max $maxEntries.};
}

sub html_template_keys
{
    my ($opts) = @_;

    my $object = $opts->{object};
    my $access = $opts->{access};
    my $uniqueKeys = $opts->{uniqueKeys};
    my $enableParameter = $opts->{enableParameter};

    my $text = qq{{{mark|keys}}};

    # XXX experimental: warn is there is a unique key parameter that's a
    #     strong reference (this is a candidate for additional auto-text)
    my $anystrong = 0;
    foreach my $uniqueKey (@$uniqueKeys) {
        my $keyparams = $uniqueKey->{keyparams};
        foreach my $parameter (@$keyparams) {
            my $path = $object . $parameter;
            my $refType = util_is_defined($parameters, $path) ? 
                $parameters->{$path}->{syntax}->{refType} : undef;
            $anystrong = 1 if defined($refType) && $refType eq 'strong';
        }
    }
    print STDERR "$object: has a unique key parameter that is a strong ".
        "reference ($access)\n" if $anystrong && $verbose;

    # for tables with enable parameters, need to generate separate text for
    # non-functional (not affected by enable) and functional keys (affected
    # by enable)
    my $keys = [[], []];
    foreach my $uniqueKey (@$uniqueKeys) {
        my $functional = $uniqueKey->{functional};
        my $conditional = defined($enableParameter) && $functional;
        push @{$keys->[$conditional]}, $uniqueKey;
    }

    # if have both unconditional and conditional keys, use separate paras
    my $sep_paras = @{$keys->[1]};

    # element 0 of $keys is the keys that are unconditionally unique; element
    # 1 is the keys that are conditionally unique (i.e. only for enabled
    # entries)
    for (my $conditional = 0; $conditional < 2; $conditional++) {
        next unless @{$keys->[$conditional]};

        my $enabled = $conditional ? qq{ enabled} : qq{};
        my $emphasis = (!$conditional && $enableParameter) ?
            qq{ (regardless of whether or not it is enabled)} : qq{};
        $text .= qq{At most one$enabled entry in this table$emphasis } .
            qq{can exist with };

        my $i = 0;
        foreach my $uniqueKey (@{$keys->[$conditional]}) {
            my $keyparams = $uniqueKey->{keyparams};
            
            $text .= qq{, or with } if $i > 0;
            $text .= qq{all } if @$keyparams > 2;
            $text .= @$keyparams > 1 ?
                qq{the same values } : qq{a given value };
            $text .= qq{for };
            $text .= util_list($keyparams, qq{{{param|\$1}}});
            $i++;
        }
        $text .= qq{.};

        # if the unique key is unconditional and includes at least one
        # writable parameter, check whether to output additional text about
        # the CPE needing to choose unique initial values for non-defaulted
        # key parameters
        #
        # XXX the next bit is needed only if one or more of the unique key
        #     parameters is writable; currently we don't have access to this
        #     information here (no longer true?)
        # XXX currently we don't have access to whether or not the key
        #     parameters are writable (no longer true?); it's not quite the
        #     same but this criterion is almost certainly the same as whether
        #     the object is writable
        if (!$conditional && $access ne 'readOnly') {
            # XXX have suppressed this boiler plate (it should be stated once)
            $text .= qq{  If the ACS attempts to set the parameters of an } .
                qq{existing entry such that this requirement would be } .
                qq{violated, the CPE MUST reject the request. In this } .
                qq{case, the SetParameterValues response MUST include a } .
                qq{SetParameterValuesFault element for each parameter in } .
                qq{the corresponding request whose modification would have }.
                qq{resulted in such a violation.} if 0;
            my $i;
            my $params = [];
            foreach my $uniqueKey (@{$keys->[0]}) {
                my $functional = $uniqueKey->{functional};
                my $keyparams = $uniqueKey->{keyparams};
                foreach my $parameter (@$keyparams) {
                    my $path = $object . $parameter;
                    my $defaulted =
                        util_is_defined($parameters, $path, 'default') &&
                        $parameters->{$path}->{deftype} eq 'object' &&
                        $parameters->{$path}->{defstat} ne 'deleted';
                    push @$params, $parameter unless $defaulted;
                    $i++;
                }
            }
            if ($i && !@$params) {
                print STDERR "$object: all unique key parameters are " .
                    "defaulted; need enableParameter\n";
            }
            if (@$params) {
                $text .= qq{  On creation of a new table entry, the CPE } .
                    qq{MUST choose };
                $text .= qq{an } if @$params == 1;
                $text .= qq{initial value};
                $text .= qq{s} if @$params > 1;
                $text .= qq{ for };
                $text .= util_list($params, qq{{{param|\$1}}});
                $text .= qq{ such that the new entry does not conflict with } .
                    qq{any existing entries.};
            }
        }

        $text .= qq{\n} if $sep_paras;
    }

    return $text;
}

sub html_template_enum
{
    my ($opts) = @_;
    # XXX not using atstart (was "atstart or newline")
    my $pref = ($opts->{newline}) ? "" : $opts->{list} ?
        "Each list item is an enumeration of:\n" : "Enumeration of:\n";
    return $pref . xml_escape(get_values($opts->{node}, !$nolinks));
}

sub html_template_pattern
{
    my ($opts) = @_;
    # XXX not using atstart (was "atstart or newline")
    my $pref = ($opts->{newline}) ? "" : $opts->{list} ?
        "Each list item matches one of:\n" :
        "Possible patterns:\n";
    return $pref . xml_escape(get_values($opts->{node}, !$nolinks));
}


# generates reference to bibliographic reference: arguments are bibref name
# and optional section
sub html_template_bibref
{
    my ($opts, $bibref, $section) = @_;

    my $path = $opts->{path};
    $path = '<unknown>' unless $path;

    if ($section) {
        my $origsection = $section;
        $section = qq{Section $section} if $section =~ /^\d/;
        $section = ucfirst $section;
        print STDERR "$path: {{bibref}} section argument was changed: ".
          "\"$origsection\" -> \"$section\"\n"
          if $warnbibref > 1 && $origsection ne $section;
    }

    $bibref = html_get_anchor($bibref, 'bibref') unless $nolinks;
    
    my $text = qq{};
    $text .= qq{[};
    $text .= qq{$section/} if $section && !$bibrefdocfirst;
    $text .= qq{$bibref};
    $text .= qq{ $section} if $section && $bibrefdocfirst;
    $text .= qq{]};

    return $text;
}

# generates reference to parameter: arguments are parameter name and optional
# scope
sub html_template_paramref
{
    my ($opts, $name, $scope) = @_;

    my $object = $opts->{object};
    my $param = $opts->{param};

    # if no param (e.g. in data type description) return literal "parameter"
    unless ($param || $name) {
        return qq{parameter};
    }

    # parameterless case (no "name") is special
    unless ($name) {
        print STDERR "$object: {{param}} is appropriate only within a ".
            "parameter description\n" unless $param;
        return qq{''$param''};
    }

    print STDERR "$object$param: {{param}} argument is unnecessary when ".
        "referring to current parameter\n" if $pedantic && $name eq $param;

    (my $path, $name) = relative_path($object, $name, $scope);
    my $invalid = util_is_defined($parameters, $path) ? '' : '?';
    # XXX don't warn of invalid references for UPnP DM (need to fix!)
    $invalid = '' if $upnpdm;
    # XXX don't warn further if this item has been deleted
    if (!util_is_deleted($opts->{node})) {
        print STDERR "$object$param: reference to invalid parameter $path\n"
            if $invalid;
        # XXX make this nicer (not sure why test of status is needed here but
        #     upnpdm triggers "undefined" errors otherwise
        if (!$invalid && $parameters->{$path}->{status} &&
            $parameters->{$path}->{status} eq 'deleted') {
            print STDERR "$object$param: reference to deleted parameter ".
                "$path\n" if !$showdiffs && $pedantic;
            $invalid = '!';
        }
    }

    $name = qq{''$name$invalid''};
    $name = html_get_anchor($path, 'path', $name) unless $nolinks;

    return $name;
}

# generates reference to object: arguments are object name and optional
# scope
sub html_template_objectref
{
    my ($opts, $name, $scope) = @_;

    my $object = $opts->{object};
    my $param = $opts->{param};

    # parameterless case (no "name") is special; use just the last component
    # of the path (don't generate link from object to itself)
    # XXX this is an experiment
    unless ($name) {
        my $name = $object;
        $name =~ s/\.(\{i\}\.)?$//;
        $name =~ s/.*\.//;
        $name = qq{''$name''};
        $name = html_get_anchor($object, 'path', $name)
            unless $nolinks || !$param;
        return $name;
    }

    # XXX this needs to be cleverer, since "name" can take various forms
    print STDERR "$object$param: {{object}} argument unnecessary when ".
        "referring to current object\n"
        if $pedantic && $name && $name eq $object;

    (my $path, $name) = relative_path($object, $name, $scope);
    my $path1 = $path;
    $path1 .= '.' if $path1 !~ /\.$/;

    # we allow reference to table X via "X" or "X.{i}"...
    my $path2 = $path1;
    $path2 .= '{i}.' if $path2 !~ /\{i\}\.$/;

    # XXX horrible
    $path = $path1 if $objects->{$path1} && %{$objects->{$path1}};
    $path = $path2 if $objects->{$path2} && %{$objects->{$path2}};

    # XXX if path starts ".Services." this is a reference to another data
    #     model, so no checks and no link
    return qq{''$name''} if $path =~ /^\.Services\./;

    my $invalid = ($objects->{$path} && %{$objects->{$path}}) ? '' : '?';
    # XXX don't warn of invalid references for UPnP DM (need to fix!)
    $invalid = '' if $upnpdm;
    # XXX don't warn further if this item has been deleted
    if (!util_is_deleted($opts->{node})) {
        print STDERR "$object$param: reference to invalid object $path\n"
            if $invalid;
        # XXX make this nicer (not sure why test of status is needed here but
        #     upnpdm triggers "undefined" errors otherwise
        if (!$invalid && $objects->{$path}->{status} &&
            $objects->{$path}->{status} eq 'deleted') {
            print STDERR "$object$param: reference to deleted object $path\n"
                if !$showdiffs && $pedantic;
            $invalid = '!';
        }
    }

    $name = qq{''$name$invalid''};
    $name = html_get_anchor($path, 'path', $name) unless $nolinks;

    return $name;
}

# generates reference to enumeration or pattern: arguments are value, optional
# parameter name (if omitted, is this parameter), and optional scope
sub html_template_valueref
{
    my ($opts, $value, $name, $scope) = @_;

    my $object = $opts->{object};
    my $param = $opts->{param};

    my $this = $name ? 0 : 1;
    $name = $param unless $name;

    (my $path, $name) = relative_path($object, $name, $scope);

    my $invalid = '';
    # XXX don't warn of invalid references for UPnP DM (need to fix!)
    if (!util_is_defined($parameters, $path)) {
        $invalid = '?';
        $invalid = '' if $upnpdm;
        # XXX don't warn further if this item has been deleted
        if (!util_is_deleted($opts->{node})) {
            print STDERR "$object$param: reference to invalid parameter ".
                "$path\n" if $invalid;
            # XXX make this nicer (not sure why test of status is needed here
            #     but upnpdm triggers "undefined" errors otherwise
            if (!$invalid && $parameters->{$path}->{status} &&
                $parameters->{$path}->{status} eq 'deleted') {
                print STDERR "$object$param: reference to deleted parameter ".
                    "$path\n" if !$showdiffs && $pedantic;
                $invalid = '!';
            }
        }
    } else {
        my $node = $parameters->{$path};
        # XXX experimental: try to follow enumerationRefs
        my $syntax = $node->{syntax};
        if ($syntax->{reference} && $syntax->{reference} eq 'enumerationRef') {
            my $targetParam = $syntax->{targetParam};
            my $targetParamScope = $syntax->{targetParamScope};
            my ($targetPath) = relative_path($node->{pnode}->{path},
                                             $targetParam, $targetParamScope);
            if (!util_is_defined($parameters, $targetPath)) {
                print STDERR "$path: enumerationRef references non-existent ".
                    "parameter $targetPath: ignored\n";
            } else {
                $path = $targetPath;
                $node = $parameters->{$path};
            }
        }
        my $values = $node->{values};
        $invalid = (has_values($values) && has_value($values, $value)) ?
            '' : '?';
        $invalid = '' if $upnpdm;
        # XXX don't warn further if this item has been deleted
        if (!util_is_deleted($opts->{node})) {
            print STDERR "$object$param: reference to invalid value $value\n"
                if $invalid;
            if (!$invalid && $values->{$value}->{status} eq 'deleted') {
                print STDERR "$object$param: reference to deleted value ".
                    "$value\n" if !$showdiffs && $pedantic;
                $invalid = '!';
            }
        }
    }

    # XXX remove backslashes (such cleanup needs to be done properly)
    # XXX would prefer not to have to know link format
    my $tvalue = $value;
    $tvalue =~ s/\\//g;
    my $sep = $upnpdm ? '/' : '.';

    $value = qq{''$value$invalid''};
    $value = html_get_anchor(qq{$path$sep$tvalue}, 'value', $value)
        unless $this || $nolinks;
   
    return $value;
}

# generates reference to profile: optional argument is the profile name
sub html_template_profileref
{
    my ($opts, $profile) = @_;

    my $node = $opts->{node};

    my $makelink = $profile && !$nolinks;

    $profile = $opts->{profile} unless $profile;

    # XXX logic taken from html_create_anchor
    # XXX would prefer not to have to know link format
    my $mnode = $node->{pnode};
    my $mname = $mnode->{name};
    $mname =~ s/:(\d+)\.\d+$/:$1/;

    my $tprofile = $profile;
    $profile = qq{''$profile''};
    $profile = html_get_anchor(qq{$mname.$tprofile}, 'profile', $profile)
        if $makelink;

    return $profile;
}

sub html_template_reference
{
    my ($opts, $arg) = @_;

    my $object = $opts->{object};
    my $path = $opts->{path};
    my $type = $opts->{type};
    my $list = $opts->{list};
    my $reference = $opts->{reference};
    my $syntax = $opts->{syntax};

    my $text = qq{};

    if (!defined $reference) {
        print STDERR "$path: {{reference}} used on non-reference parameter\n";
        return qq{[[reference]]};
    }

    my $refType = $syntax->{refType} || '';
    $text .= qq{\{\{mark|$reference};
    $text .= qq{-$refType} if $refType;
    $text .= qq{-list} if $list;
    $text .= qq{\}\}};

    # XXX it is assumed that this text will be generated after the {{list}}
    #     expansion (if a list)
    $text .= $list ?
        qq{Each list item } :
        qq{The value };

    if ($reference eq 'pathRef') {
        my $targetParent = $syntax->{targetParent};
        my $targetParentScope = $syntax->{targetParentScope};
        my $targetType = $syntax->{targetType};
        my $targetDataType = $syntax->{targetDataType};

        $targetType = 'any' unless $targetType;

        # XXX this logic currently for pathRef only, but also applies
        #     to instanceRef (for which targetParent cannot be a list, and
        #     targetType is always "row")
        my $targetParentFixed = 0;
        if ($targetParent) {
            $targetParentFixed = 1;
            foreach my $tp (split ' ', $targetParent) {
                my ($tpp) = relative_path($object, $tp, $targetParentScope);

                # check for (and ignore) spurious trailing "{i}." when
                # targetType is "row" (it's a common error)
                if ($targetType eq 'row') {
                    if ($tpp =~ /\{i\}\.$/) {
                        print STDERR "$path: trailing \"{i}.\" ignored in ".
                            "targetParent (targetType \"row\")): $tp\n";
                    } else {
                        $tpp .= '{i}.';
                    }
                    # $tpp is now the table object (including "{i}.")
                }

                my $tpn = $objects->{$tpp};
                print STDERR "$path: targetParent doesn't exist: $tp\n"
                    unless $tpn || $tpp =~ /^\.Services\./;

                $targetParentFixed = 0 if $tpn && !$tpn->{fixedObject};
            }
        }

        $targetParent = object_references($targetParent,
                                          $targetParentScope);

        $text .= qq{MUST be the path name of };

        if ($targetType eq 'row') {
            if ($arg) {
                $text .= $arg;
            } else {
                my $s = $targetParent =~ / / ? 's' : '';
                $text .= $targetParent ?
                    qq{a row in the $targetParent table$s} :
                    qq{a table row};
            }
        } else {
            $targetType =~ s/single/single-instance object/;
            $targetType =~ s/any/parameter or object/;
            if ($arg) {
                $text .= $arg;
            } else {
                if ($targetDataType && $targetDataType ne 'any') {
                    $text .= ($targetDataType =~ /^[aeiou]/ ? qq{an} : qq{a});
                    $text .= qq{ $targetDataType};
                } else {
                    $text .= ($targetType =~ /^[aeiou]/ ? qq{an} : qq{a});
                }
                $text .= qq{ $targetType};
            }
            $text .= $targetParent ?
                qq{, which MUST be a child of $targetParent} :
                qq{};
        }
        if ($refType ne 'strong') {
            $text .= qq{.};
        } else {
            $targetType =~ s/row/object/;
            $targetType =~ s/single.*/object/;
            $targetType =~ s/parameter or object/item/;
            if ($targetParentFixed) {
                $text .= $list ?
                    qq{, or {{empty}}.} :
                    qq{.};
            } else {
                $text .= qq{.};
                $text .= qq{  If the referenced $targetType is deleted, the };
                $text .= $list ?
                    qq{corresponding item MUST be removed from the list.} :
                    qq{parameter value MUST be set to {{empty}}.};
            }
        }

    } elsif ($reference eq 'instanceRef') {
        my $targetParent = $syntax->{targetParent};
        my $targetParentScope = $syntax->{targetParentScope};

        $targetParent = object_references($targetParent,
                                          $targetParentScope);

        my $nullValue =
            (get_typeinfo($type, $syntax)->{value} =~ /^unsigned/) ? 0 : -1;

        my $s = $targetParent =~ / / ? 's' : '';
        $text .= qq{MUST be the instance number of a row in the }.
            qq{$targetParent table$s};
        $text .= qq{, or else be $nullValue if no row is currently } .
            qq{referenced} unless $list;
        $text .= qq{.};
        if ($refType eq 'strong') {
            $text .= qq{  If the referenced row is deleted, the };
            $text .= $list ?
                qq{corresponding item MUST be removed from the list.} :
                qq{parameter value MUST be set to $nullValue.};
        }

    } elsif ($reference eq 'enumerationRef') {
        my $targetParam = $syntax->{targetParam};
        my $targetParamScope = $syntax->{targetParamScope};
        my $nullValue = $syntax->{nullValue};

        $nullValue = ($nullValue ne '' ? qq{''$nullValue''} : qq{{{empty}}}) if
            defined $nullValue;

        # XXX need to use targetParamScope here
        $text .= qq{MUST be a member of the list reported by the } .
            qq{{{param|$targetParam}} parameter};
        $text .= qq{, or else be $nullValue} if defined $nullValue;
        $text .= qq{.};

    } else {
        # XXX should warn about this (can't happen)
        $text = '';
    }

    # this is to avoid problems if there is no whitespace after the template
    # reference
    $text .= qq{  } if $text;

    return $text;
}

# Generate relative path given...
# 
# XXX note that DM instances can't really make use of the proposed "^" syntax
#     because it implies a reference to a different data model, so it is not
#     yet supported (as a partial alternative, a path starting ".Services." is
#     left unchanged)
sub relative_path
{
    my ($parent, $name, $scope) = @_;

    $parent = '' unless $parent;
    $scope = 'normal' unless $scope;

    my $name2 = $name;

    my $path;

    # XXX $parp (parent pattern) won't work for UPnP DM

    my $sep = $upnpdm ? q{#} : q{.};
    my $sepp = $upnpdm ? q{\#} : q{\.};
    my $par = $upnpdm ? q{!} : q{#};
    my $parp = $upnpdm ? q{\!} : q{\#};
    my $instp = $upnpdm ? q{\#} : q{\{};

    if ($scope eq 'normal' && $name =~ /^(Device|InternetGatewayDevice)\./) {
        $path = $name;
    } elsif (($scope eq 'normal' && $name =~ /^$sepp/) || $scope eq 'model') {
        if ($name =~ /^${sepp}Services${sepp}/) {
            $path = $name;
        } else {
            my ($root, $next) = split /$sepp/, $parent;
            $next = ($next =~ /^$instp/) ? ($sep . $next) : '';
            my $sep = ($name =~ /^$sepp/) ? '' : $sep;
            $path = $root . $next . $sep . $name;
        }
    } else {
        if ($scope eq 'normal' && $name =~ /^$parp/) {
            my ($nlev) = ($name =~ /^($parp*)/);
            $nlev = length $nlev;
            # XXX need a utility for this!
            my $tparent = $parent;
            $parent =~ s/\.\{/\{/g;
            #print STDERR "$parent $name $nlev\n" if $nlev;
            my @comps = split /$sepp/, $parent;
            splice @comps, -$nlev;
            $parent = join $sep, @comps;
            $parent =~ s/\{/\.\{/g;
            $parent .= '.' if $parent;
            print STDERR "$tparent: $name has too many $par characters\n"
                unless $parent;
            $name =~ s/^$parp*\.?//;
            # if name is empty, will use final component of parent
            $name2 = $comps[-1];
            $name2 =~ s/\{.*//;
            #print STDERR "$parent $name $name2\n" if $nlev;
        }
        $path = $parent . $name;
        $name = $name2 unless $name;
    }

    # XXX as experiment, remove leading separator in returned name (affects
    #     display only; means that ".DeviceInfo" is displayed as "DeviceInfo")
    $name =~ s/^${sepp}Services//;
    $name =~ s/^${sepp}//;

    return ($path, $name);
}

# Generate appropriate {{object}} references from an XML list
sub object_references
{
    my ($list, $scope) = @_;

    $scope = $scope ? ('|' . $scope) : '';

    my $value = '';

    if ($list) {
        my $i = 0;
        my @refs = split /\s+/, $list;
        foreach my $ref (@refs) {
            $ref =~ s/\.$//;
            $value .= (($i < @refs - 1) ? ', ' : ' or ') if $i > 0;
            $value .= qq{{{object|$ref$scope}}};
            $i++;
        }
    }

    return $value;
}

# Process verbatim sections
sub html_verbatim
{
    my ($inval) = @_;

    my @lines = split /\n/, $inval;
    my $pre;
    my $outval = '';
    foreach my $line (@lines) {
        if (!$pre && $line =~ /^\s/) {
            $outval .= "<pre>\n";
            $pre = 1;
        } elsif ($pre && $line !~ /^\s/) {
            $outval .= "</pre>\n";
            $pre = 0;
        }
        $outval .= $line . "\n";
    }
    if ($pre) {
        $outval .= "</pre>\n";
    }
    chomp $outval;
    return $outval;
}

# Process list markup
sub html_list
{
    my ($inval) = @_;

    my $typemap = {'*' => 'ul', '#' => 'ol', ':' => 'dl'};
    my $itemmap = {'*' => 'li', '#' => 'li', ':' => 'dd'};

    my $outval = '';
    my $depth = 0;
    my $prev = '';
    my $lact = 1;
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {
	my $curr = '';
	my $rest = $line;
	if ($line =~ /^([\*\#:]+)\s*(.*)/) {
	    $curr = $1;
	    $rest = $2;
	}
        # special case for continuation at inner level
        my $cont = 0;
        if (substr($prev, $depth-1, 1) eq ':') {
        } elsif ($depth > 0 && $curr eq ($prev . ':')) {
            $cont = 1;
            $curr = $prev;
            $outval .= '  ' x $depth . "<br>$rest\n";
            next;
        }
        # special case for other continuations, e.g. "**:" -> "*:"
        elsif ($curr =~ /:$/) {
            $curr =~ s/(.*).:/$1:/;
        }
	my $newdepth = length $curr;
        while ($depth > $newdepth || ($depth > 0 && substr($curr, $depth-1, 1)
                                      ne substr($prev, $depth-1, 1))) {
            $depth--;
            my $type = $typemap->{substr($prev, $depth, 1)};
            $outval .= '  ' x $depth . "</$type><p>\n";
        }
	while ($newdepth > $depth) {
            my $type = $typemap->{substr($curr, $depth, 1)};
            $outval .= '  ' x $depth . "<$type>\n";
            $depth++;
        }
        my $item = $depth ? $itemmap->{substr($curr, $depth-1, 1)} : '';
	$outval .= '  ' x $depth . "<$item>" if $depth;
	$outval .= $rest;
        # XXX not currently terminating list items
	#$outval .= "</$item>" if $depth;
	$outval .= "\n";
        $prev = $curr;
    }
    while ($depth > 0) {
        $depth--;
        my $type = $typemap->{substr($prev, $depth, 1)};
	$outval .= '  ' x $depth . "</$type><p>\n";
    }
    chomp $outval;
    return $outval;
}

# Process hyperlinks
sub html_hyperlink
{
    my ($inval) = @_;

    # XXX need a better set of URL characters
    my $last = q{\w\d\:\/\?\&\=\-};
    my $notlast = $last . q{\.};
#   $inval =~ s|([a-z]+://[\w\d\.\:\/\?\&\=-]+)|<a href="$1">$1</a>|g;
    $inval =~ s|([a-z]+://[$notlast]*[$last])|<a href="$1">$1</a>|g;

    return $inval;
}

# Process font markup
sub html_font
{
    my ($inval, $opts) = @_;

    # XXX can't cope with things like '''bold ''bold italics'' bold'''
    #$inval =~ s|'''([^']*)'''|<b>$1</b>|g;
    #$inval =~ s|''([^']*)''|<i>$1</i>|g;

    # XXX experimental alternative; is better but won't cope with things like
    #     '''bold ''bold italics''''' (will mismatch the <b> and <i>... some
    #     browsers accept this... can always use an empty template - {{}} - to
    #     avoid such problems)
    # XXX could be kind and auto-terminate if necessary, e.g. for '''b ''i
    #     convert to '''b ''i''{{}}'''
    $inval =~ s|'''(.*?)'''|<b>$1</b>|g;
    $inval =~ s|''(.*?)''|<i>$1</i>|g;

    # XXX experimental ---text--- to indicate deletion and +++text+++ insertion
    $inval =~ s|\-\-\-([^\n]*?)\-\-\-|<span class="d">$1</span>|gs;
    $inval =~ s|\+\+\+([^\n]*?)\+\+\+|<span class="i">$1</span>|gs;

    $inval =~ s|\-\-\-(.*?)\-\-\-|<div class="d">$1</div>|gs;
    $inval =~ s|\+\+\+(.*?)\+\+\+|<div class="i">$1</div>|gs;

    # XXX "%%" anchor expansion should be elsewhere (hyperlink?)
    # XXX need to escape special characters out of anchors and references
    # XXX would prefer not to have to know link format
    if ($opts->{param}) {
        my $object = $opts->{object} ? $opts->{object} : '';
        my $path = $object . $opts->{param};
        my $prefix = html_anchor_namespace_prefix('value');
        $inval =~ s|%%([^%]*)%%([^%]*)%%|<a name="$prefix$path.$2">$1</a>|g;
    }

    return $inval;
}

# Process paragraph breaks
# XXX this assumes that leading spaces are left on verbatim lines
# XXX it behaves badly with lines that start with <b> or <i> (fudged)
sub html_paragraph
{
    my ($inval) = @_;

    my $outval = '';
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {
        $line =~ s/$/<p>/ if
            $line =~ /^(<b>|<i>|<span)/ || $line !~ /^(\s|\s*<)/;

        $outval .= "$line\n";
    }

    $outval =~ s/(<p>)?\n$//;
    return $outval;
}

# Excel XML report of node.
# XXX is far too hard-coded; want to be able to select which columns are
#     hidden for example
# XXX would also want to create a worksheet for each profile
sub xls_begin
{
    my ($root) = @_;

    # Borders
    my $border_atts = 'ss:LineStyle="Continuous" ss:Weight="1"';
    my $borders = 
	"<Borders>" .
	"<Border ss:Position=\"Bottom\" $border_atts/>" .
	"<Border ss:Position=\"Left\" $border_atts/>" .
	"<Border ss:Position=\"Right\" $border_atts/>" .
	"<Border ss:Position=\"Top\" $border_atts/>" .
	"</Borders>";

    # Alignment
    my $top = 'ss:Vertical="Top"';
    my $center = 'ss:Horizontal="Center"';
    my $wrap =  'ss:WrapText="1"';
    my $align_default = "<Alignment $top $wrap/>";
    my $align_center = "<Alignment $top $center $wrap/>";

    # Font
    my $family = 'x:Family="Swiss"';
    my $bold = 'ss:Bold="1"';
    my $size = 'ss:Size="8"';
    my $font = "<Font $family $size/>";
    my $font_bold = "<Font $family $size $bold/>";

    # Interior (fill)
    my $color_header = 'ss:Color="#D0D0D0"';
    my $color_object = 'ss:Color="#FFFF99"';
    my $pattern = 'ss:Pattern="Solid"';
    my $interior_header = "<Interior $color_header $pattern/>";
    my $interior_object = "<Interior $color_object $pattern/>";

    # root attributes
    my $spec = $root->{spec};

    print <<END;
<?xml version="1.0"?>
<Workbook xsi:schemaLocation="urn:schemas-microsoft-com:office:spreadsheet
 C:\\PROGRA~1\\MI5A53~1\\MICROS~1\\SPREAD~1\\excelss.xsd"
 xmlns="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:x="urn:schemas-microsoft-com:office:excel"
 xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:html="http://www.w3.org/TR/REC-html40"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
 <Styles>
  <Style ss:ID="Default" ss:Name="Normal">$align_default$borders$font</Style>
  <Style ss:ID="DefaultCenter">$align_center$borders$font</Style>
  <Style ss:ID="Header">$align_default$borders$font_bold$interior_header</Style>
  <Style ss:ID="HeaderCenter">$align_center$borders$font_bold$interior_header</Style>
  <Style ss:ID="Object">$align_default$borders$font$interior_object</Style>
  <Style ss:ID="ObjectCenter">$align_center$borders$font$interior_object</Style>
 </Styles>
 <!--
 <Worksheet ss:Name="Introduction">
  <Table>
    <Column ss:Width="120"/>
    <Column ss:Width="120"/>
    <Row>
     <Cell ss:StyleID="Header"><Data ss:Type="String">Spec</Data></Cell>
     <Cell ss:StyleID="Default"><Data ss:Type="String">$spec</Data></Cell>
    </Row>
  </Table>
 </Worksheet>
 -->
END
}

# HTML "BBF" report of node.
#
# Similar output to that on CWMP web page at http://www.broadband-forum.org/
# cwmp.php.  Used to pass requirements to AMS.  Will hopefull evolve to be
# more like the "OD-148" report.

# implementation concepts are similar to those for the "OD-148" report.

# Comments with informal template expansion:
# - {{name}} => model name: name:m.n or "and"-separated list
# - {{type}} => model type: "Root Object" or "Service Object"
# - {{def}} => "definition" or "definitions" (depends on number of models)
# - {{err}} => "errata and clarifications"
# - {{ver}} => "vm.n"
my $htmlbbf_comments = {
    rpcs => 'TR-069 RPCs',
    dm => 'TR-069 Data Model Definition Schema (DM Schema) {{ver}}',
    dmr => 'TR-069 Data Model Report Schema (DMR Schema)',
    dt => 'TR-069 Device Type Schema (DT Schema) {{ver}}',
    dtf => 'TR-069 DT (Device Type) Features Schema (DTF Schema)',
    bibref => 'TR-069 Data Model Bibliographic References',
    types => 'TR-069 Data Model Data Types',
    objdef => 'TR-069 {{name}} {{type}} {{def}}',
    objerr => 'TR-069 {{name}} {{type}} {{err}}',
    compdef => 'Component objects for CWMP: TR-069 {{name}} {{type}} {{def}}',
    comperr => 'Component objects for CWMP: TR-069 {{name}} {{type}} {{err}}'
};

# File info (could read this from a config file) that overrides information
# inferred from the files themselves (shouldn't be needed for DM Instances).
my $htmlbbf_info = {
    'cwmp-1-0.xsd' => {
        comment => 'rpcs', trname => 'tr-069-1-1', date => '2006-12'},
    'cwmp-1-1.xsd' => {
        comment => 'rpcs', trname => 'tr-069-1-2', date => '2007-12'},
    'cwmp-datamodel-1-0.xsd' => {
        comment => 'dm', trname => 'tr-106-1-2', date => '2008-11'},
    'cwmp-datamodel-1-1.xsd' => {
        comment => 'dm', trname => 'tr-106-1-3', date => '2009-09'},
    'cwmp-datamodel-1-2.xsd' => {
        comment => 'dm', trname => 'tr-106-1-4', date => '2010-02'},
    'cwmp-datamodel-report.xsd' => {
        comment => 'dmr', date => '2009-09'},
    'cwmp-devicetype-1-0.xsd' => {
        comment => 'dt', trname => 'tr-106-1-3', date => '2009-09'},
    'cwmp-devicetype-features.xsd' => {
        comment => 'dtf', date => '2009-09'},
    'tr-069-biblio.xml' => {
        comment => 'bibref', support => 1},
    'tr-106-1-0-0-types.xml' => {
        comment => 'types', support => 1}
};

my $htmlbbf = [];

# XXX this is effectively copied from html_node; not all styles are used
sub htmlbbf_begin
{
    # styles
    my $table = qq{text-align: left;};
    my $row = qq{vertical-align: top;};
    my $center = qq{text-align: center;};

    # font
    my $h1font = qq{font-family: helvetica,arial,sans-serif; font-size: 14pt;};
    my $h2font = qq{font-family: helvetica,arial,sans-serif; font-size: 12pt;};
    my $h3font = qq{font-family: helvetica,arial,sans-serif; font-size: 10pt;};
    my $font = qq{font-family: helvetica,arial,sans-serif; font-size: 8pt;};

    # others
    my $theader_bg = qq{background-color: rgb(153, 153, 153);};

    print <<END;
<html>
  <head>
    <meta content="text/html; charset=UTF-8" http-equiv="content-type">
    <title>Broadband Forum - CWMP</title>
    <style type="text/css">
      p, li, body { $font }
      h1 { $h1font }
      h2 { $h2font }
      h3 { $h3font }
      table { $table }
      th { $row $font }
      th.g { $row $font $theader_bg }
      td, td.p { $row $font }
      td.pc { $row $font $center }
    </style>
  </head>
  <body>
    <h1>CPE WAN Management Protocol (CWMP)</h1>

    <h1>XML Schemas and Data Model Definitions</h1>

    <div align="center">
      [<a href="#Schema">Schema Files</a>]
      [<a href="#DMS">DM Support</a>]
      [<a href="#DMD">DM Definitions</a>]
      [<a href="cwmp.zip">Directory Contents</a>]
    </div>

    <p/>
    <p>The available XML Schemas and data model definitions for the TR-069
       suite of documents are listed below.</p>
    <p/>
    <p>Note: all the files below are directly reachable via:
       http://www.broadband-forum.org/cwmp/&lt;filename&gt;.</p>

    <a name="Schema"/>
    <h1>Schema Files</h1>
END
    htmlbbf_file('', {header => 1});
    foreach my $file (@$allfiles) {
        htmlbbf_file($file, {schema => 1});
    }
    htmlbbf_file('', {footer => 1});

    print <<END;
    <a name="DMS"/>
    <h1>Data Model Support Files</h1>
END
    htmlbbf_file('', {header => 1});
    foreach my $file (@$allfiles) {
        htmlbbf_file($file, {support => 1});
    }
    htmlbbf_file('', {footer => 1});

    print <<END;
    <a name="DMD"/>
    <h1>Data Model Definitions</h1>
END
    htmlbbf_file('', {header => 1});
    foreach my $file (@$allfiles) {
        htmlbbf_file($file);
    }
    htmlbbf_file('', {footer => 1});

    print <<END;
    </table>
  </body>
</html>
END
}

# dummy (needed in order to indicate that report type is valid)
sub htmlbbf_node
{
}

my $htmlbbf_mnames = {};

sub htmlbbf_file
{
    my ($file, $opts) = @_;

    # table options
    my $tabopts = qq{border="1" cellpadding="2" cellspacing="0"};

    if ($opts->{header}) {
        print <<END;
    <table width="100%" $tabopts>
      <tr>
        <th width="15%">Filename</th>
        <th width="60%">Comment / HTML</th>
        <th width="12%">Publication Date</th>
        <th width="13%">Technical Report</th>
      </tr>
END
        return;

    } elsif ($opts->{footer}) {
        print <<END;
    </table>
END
        return;
    }

    my $name = $file->{name};
    my $spec = $file->{spec};
    my $schema = $file->{schema};
    my $models = $file->{models};

    return if  $opts->{schema} && !$schema;
    return if !$opts->{schema} &&  $schema;

    my $info = $htmlbbf_info->{$name};
    my $comment = $info->{comment};
    my $support = $info->{support};
    my $trname = $info->{trname};
    my $date = $info->{date};

    return if  $opts->{support} && !$support;
    return if !$opts->{support} &&  $support;

    my $seen = 0;
    my $mult = 0;
    my $type = 'Root Object';
    my $mnames = '';
    # XXX this exposes a logic error here, since the HTML file naming
    #     conventions assume that all data models in a file either define
    #     a new major version or not (actually a reasonable assumption)
    my $newmaj = 1;
    if ($models) {
        foreach my $model (@$models) {
            my $mname = $model->findvalue('@name');
            my $isService = $model->findvalue('@isService');

            $seen = 1 if $htmlbbf_mnames->{$mname};
            $htmlbbf_mnames->{$mname} = 1;

            $mult = 1 if $mnames;

            # XXX assumes that all models in file are Root or Service
            $type = 'Service Object' if $isService;

            $mnames .= ' and ' if $mult;
            $mnames .= $mname;

            my ($mmaj, $mmin) = ($mname =~ /:(\d+)\.(\d+)/);
            $newmaj = 0 if $mmin;
        }   
    }

    my $def = 'definition' . ($mult ? 's' : '');
    my $err = 'errata and clarifications';

    my ($maj, $min) = $name =~ /-(\d+)-(\d+)\.xsd$/;
    $maj = '?' unless defined $maj;
    $min = '?' unless defined $min;
    my $ver = qq{v${maj}.${min}};

    if (!$comment && !$opts->{schema} && !$opts->{support}) {
        $comment .= $mult ? 'comp' : 'obj';
        $comment .= $seen ? 'err'  : 'def';
    }

    $comment = $comment ? $htmlbbf_comments->{$comment} : 'TBD';
    $comment =~ s/{{name}}/$mnames/;
    $comment =~ s/{{type}}/$type/;
    $comment =~ s/{{def}}/$def/;
    $comment =~ s/{{err}}/$err/;
    $comment =~ s/{{ver}}/$ver/;

    # add the HTML hyperlinks
    my $suffices = [];
    if ($schema || $name !~ /\.xml$/) {
        # no HTML for schema files
    } elsif ($name =~ /^tr-(143|157|262)/) {
        push @$suffices, '-dev';
        push @$suffices, '-igd';
    } else {
        push @$suffices, '';
    }
    my $nsuffices = [];
    foreach my $suffix (@$suffices) {
        push @$nsuffices, qq{$suffix-last-diffs} unless $newmaj;
    }
    push @$suffices, @$nsuffices;
    $comment .= qq{<ul>} if @$suffices;
    foreach my $suffix (@$suffices) {
        my $hname = $name;
        $hname =~ s/(\.xml)$/$suffix.html/;
        $comment .= qq{<li><a href="cwmp/$hname">$hname</a></li>};
    }
    $comment .= qq{</ul>} if @$suffices;

    $trname = $spec unless $trname;
    $trname = util_doc_name($trname, {verbose => 1});
    $trname = '&nbsp;' unless $trname;
    
    # XXX not clear where to get the date info from
    if (!$date) {
        $date = 'TBD';
    } else {
        my $months = ['NotAMonth', 'January', 'February', 'March', 'April',
                      'May', 'June', 'July', 'August', 'September', 'October',
                      'November', 'December'];
        my ($year, $month) = $date =~ /(\d+)-(\d+)/;
        $date = qq{$months->[$month] $year};
    }
    
    my $xmllink = qq{cwmp/$name};
    my $trlink = util_doc_link($trname);

    # no TR link for support files or if TR name doesn't begin TR (catches
    # unversioned schemas)
    $trlink = qq{<a href="$trlink">$trname</a>};
    $trlink = '&nbsp;' if $support || $trname !~ /^TR/;

    print <<END;
      <tr>
        <td><a href="$xmllink">$name</a></td>
        <td>$comment</td>
        <td>$date</td>
        <td>$trlink</td>
      </tr>
END
}

# HTML "OD-148" report of node.
#
# Similar output to that of OD-148 sections 2 and 3; pass each data model
# on the command line (duplication doesn't matter because no file is ever
# read more than once).

# array containing all info to be reported, in the form:
#
# [{name => model_name,
#   spec => model_spec,
#   profiles => [{name => profile_name,
#                 spec => profile_spec}, ...], ...]
my $html148 = [];

# XXX this is effectively copied from html_node; not all styles are used
sub html148_begin
{
    # styles
    my $table = qq{text-align: left;};
    my $row = qq{vertical-align: top;};
    my $center = qq{text-align: center;};

    # font
    my $h1font = qq{font-family: helvetica,arial,sans-serif; font-size: 14pt;};
    my $h2font = qq{font-family: helvetica,arial,sans-serif; font-size: 12pt;};
    my $h3font = qq{font-family: helvetica,arial,sans-serif; font-size: 10pt;};
    my $font = qq{font-family: helvetica,arial,sans-serif; font-size: 8pt;};

    # others
    my $theader_bg = qq{background-color: rgb(153, 153, 153);};

    # file header and beginning of TOC
    print <<END;
<html>
  <head>
    <meta content="text/html; charset=UTF-8" http-equiv="content-type">
    <title>TR-069 Data Model and Profile Registry</title>
    <style type="text/css">
      p, li, body { $font }
      h1 { $h1font }
      h2 { $h2font }
      h3 { $h3font }
      table { $table }
      th { $row $font }
      th.g { $row $font $theader_bg }
      td, td.p { $row $font }
      td.pc { $row $font $center }
    </style>
  </head>
  <body>
    <h1>Table of Contents</h1>
    <ul>
END
}

sub html148_node
{
    my ($node) = @_;

    my $model = $node->{type} eq 'model';
    return unless $model;

    my $history = $node->{history};
    if ($history && @$history) {
        foreach my $past (reverse @$history) {
            html148_model($node, $past);
        }
    }
    html148_model($node);
}

sub html148_model
{
    my ($node, $past) = @_;

    # node to use for name and spec is $past if defined, else $node
    my $anode = $past ? $past : $node;
    my $name = $anode->{name};
    my $file = $anode->{file};
    my $spec = $anode->{spec};

    # node to use for other attributes is always $node
    my $isService = $node->{isService};
    my $profs = [];
    foreach my $prof (grep {$_->{type} eq 'profile' && 
                      $_->{spec} eq $spec} @{$node->{nodes}}) {
        my $name = $prof->{name};
        my $spec = $prof->{spec};

        push @$profs, {name => $name, spec => $spec};
    }

    # because of strange way in which model dependencies are handled, this
    # can push things out of order, 
    my $index = @$html148;
    my ($nam, $maj, $min) = ($name =~ /([^:]*):(\d+)\.(\d+)/);
    if (defined $nam && defined $maj && defined $min) {
        for (0..$index-1) {
            my $tname = $html148->[$_]->{name};
            my ($tnam, $tmaj, $tmin) = ($tname =~ /([^:]*):(\d+)\.(\d+)/);
            if (defined $tnam && defined $tmaj && defined $tmin) {
                if ($tnam eq $nam && ($tmaj > $maj ||
                                      ($tmaj == $maj && $tmin > $min))) {
                    $index = $_;
                    last;
                }
            }
        }
    }

    splice @$html148, $index, 0, {name => $name, file => $file, spec => $spec,
                                  isService => $isService, profs => $profs};
}

sub html148_end
{
    # table options
    my $tabopts = qq{border="1" cellpadding="2" cellspacing="0"};

    # TOC is generated directly; all other output is buffered and output
    # at the bottom
    my $text = '';

    # introductory sections and summary table header
    # XXX can you just put the class on <tr>?
    # XXX not filling in dependencies yet; are they useful?
    print <<END;
      <li><a href="#Overview">Overview</a></li>
      <li><a href="#Data Models">Data Models</a></li>
END
    $text .= <<END;
    <h1><a name="Overview">Overview</a></h1>
    <p>This document is a registry of Broadband Forum standardized TR-069 data models and profiles.  This document is intended to catalog all versions of data models and profiles defined in Broadband Forum Technical Reports.</p>
    <h1><a name="Data Models">Data Models</a></h1>
    <p>The following table lists all data model versions defined in Broadband Forum Technical Reports.</p>
    <table width="100%" $tabopts>
      <tbody>
        <tr>
          <th class="g">Object Name</th>
          <th class="g">Object Type</th>
          <th class="g">Version</th>
          <th class="g">Version Update</th>
          <th class="g">Update Type</th>
          <th class="g">Technical Report</th>
          <!-- <th class="g">Dependencies</th> -->
        </tr>
END

    # summary table rows
    my $rows = [];
    my $mrows = {};
    foreach my $model (@$html148) {
        my $name = $model->{name};
        my $file = $model->{file};
        my $spec = $model->{spec};
        my $rootserv = $model->{isService} ? 'Service' : 'Root'; 

        my ($name_only, $major, $minor) = ($name =~ /([^:]*):(\d*)\.(\d*)/);
        my $tr_name = util_doc_name($spec, {verbose => 1});
        my $dependencies = 'dependencies';

        my $nrow = {name => $name_only,
                    name_major => qq{$name_only:$major},
                    file => $file,
                    type => $rootserv,
                    version => qq{$major.$minor},
                    tr_name => $tr_name,
                    dependencies => $dependencies,
                    mrowspan => 0};

        # mrow is the first row for this data model
        my $mrow = $mrows->{$nrow->{name}};
        $mrow = $nrow if !$mrow || $nrow->{name_major} ne $mrow->{name_major};
        $nrow->{mrow} = $mrow;
        $mrow->{mrowspan}++;
        $mrows->{$nrow->{name}} = $mrow;

        push @$rows, $nrow;
    }

    print <<END;
      <ul>
END
    my $first = 1;
    foreach my $row (@$rows) {
        my $mrowspan = $row->{mrowspan};
        my $moc = $mrowspan ? '' : '<!-- ';
        my $mcc = $mrowspan ? '' : ' -->';

        if ($row == $row->{mrow}) {
            print <<END;
        <li><a href="#D:$row->{name_major}">$row->{name_major}</a></li>
END

            # XXX hacked separator row
            if (!$first) {
                $text .= <<END;
        <tr>
          <td colspan="6"></td>
        </tr>
END
            }
            $first = 0;
        }

        # XXX hack: we currently KNOW that 143, 157 and 262 define both root
        #     objects so the HTML includes "-dev" or "-igd"
        my $htmlsuff =
            $row->{file} !~ /^tr-(143|157|262)/ ? '' :
            $row->{name} =~ /^Internet/ ? '-igd' :
            $row->{name} =~ /^Device/ ? '-dev' : '';

        my $version = $row->{version};
        my $version_entry = qq{<a href="cwmp/$row->{file}.xml">$version</a>};

        my $version_update = $version eq '1.0' ? 'Initial' :
            $version =~ /^\d+\.0$/ ? 'Major' : 'Minor';
        # XXX change so never use Major (major versions are all replacements)
        $version_update =$version =~ /^\d+\.0$/ ? 'Initial' : 'Minor';
        my $version_update_entry =
            qq{<a href="cwmp/$row->{file}$htmlsuff.html">$version_update</a>};

        # XXX not quite the same as in OD-148 because ALL XML minor versions
        #     are incremental (not worth keeping this column?)
        my $update_type = $version_update eq 'Initial' ? '-' :
            $version_update eq 'Major' ? 'Replacement' : 'Incremental';
        my $update_type_entry = $update_type eq '-' ? '-' :
            qq{<a href="cwmp/$row->{file}$htmlsuff-last-diffs.html">$update_type</a>};

        $text .= <<END;
        <tr>
          $moc<td rowspan="$mrowspan"><a name="D:$row->{name_major}">$row->{name}</a></td>$mcc
          $moc<td rowspan="$mrowspan">$row->{type}</td>$mcc
          <td>$version_entry</td>
          <td>$version_update_entry</td>
          <td>$update_type_entry</td>
          <td>$row->{tr_name}</td>
          <!-- <td>$row->{dependencies}</td> -->
        </tr>
END
    }
    print <<END;
      </ul>
END

    # end of summary table and profile table header
    print <<END;
      <li><a href="#Profiles">Profiles</a></li>
      <ul>
END
    $text .= <<END;
      </tbody>
    </table>
    <h1><a name="Profiles">Profiles</a></h1>
    <p>The following table lists all data model profiles defined in Broadband Forum Technical Reports.</p>
    <table width="100%" $tabopts>
      <tbody>
        <tr>
          <th class="g">Data Model</th>
          <th class="g">Profile Name</th>
          <th class="g">Profile Version</th>
          <th class="g">Min Data Model Version</th>
          <th class="g">Technical Report(s)</th>
        </tr>
END

    # profile table rows
    $rows = [];
    $mrows = {};
    my $prows = {};
    foreach my $model (@$html148) {
        my $mname = $model->{name};
        my $spec = $model->{spec};
        my $profs = $model->{profs};

        my ($mname_only, $mversion_major, $mversion_minor) =
            ($mname =~ /([^:]*):(\d+)\.(\d+)/);

        foreach my $prof (@$profs) {
            my $name = $prof->{name};
            my $spec = $prof->{spec};

            next unless $name;

            my ($name_only, $version) = ($name =~ /([^:]*):(.*)/);
            my $tr_name = util_doc_name($spec, {verbose => 1});

            my $nrow = {model => qq{$mname_only:$mversion_major},
                        prof => $name_only,
                        prof_version => $version,
                        model_version => qq{$mversion_major.$mversion_minor},
                        tr_name => $tr_name,
                        mrowspan => 0,
                        prow => undef, prowspan => 0};

            # mrow is the first row for this data model
            my $mrow = $mrows->{$nrow->{model}};
            $mrow = $nrow if !$mrow || $nrow->{model} ne $mrow->{model};
            $nrow->{mrow} = $mrow;
            $mrow->{mrowspan}++;
            $mrows->{$nrow->{model}} = $mrow;

            # prow is the first row for this data model and profile
            my $prow = $prows->{$nrow->{model}}->{$nrow->{prof}};
            $prow = $nrow if !$prow || $nrow->{prof} ne $prow->{prof};
            $nrow->{prow} = $prow;
            $prow->{prowspan}++;
            $prows->{$nrow->{model}}->{$nrow->{prof}} = $prow;

            # insert after previous profile for this model, if any, else
            # at the end
            my $index;
            for (0 .. @$rows-1) {
                my $row = @$rows[$_];
                $index = $_ + 1 if $row->{model} eq $nrow->{model} &&
                    $row->{prof} eq $nrow->{prof};
            }
            $index = @$rows unless defined $index;
            splice @$rows, $index, 0, $nrow;
        }
    }

    $first = 1;
    foreach my $row (@$rows) {
        my $mrowspan = $row->{mrowspan};
        my $moc = $mrowspan ? '' : '<!-- ';
        my $mcc = $mrowspan ? '' : ' -->';
        my $prowspan = $row->{prowspan};
        my $poc = $prowspan ? '' : '<!-- ';
        my $pcc = $prowspan ? '' : ' -->';

        if ($row == $row->{mrow}) {
            print <<END;
        <li><a href="#P:$row->{model}">$row->{model}</a></li>
END
            # XXX hacked separator row
            if (!$first) {
                $text .= <<END;
        <tr>
          <td colspan="5"></td>
        </tr>
END
            }
            $first = 0;
        }

# XXX suppress the individual profile entries in the TOC (there are too many
#     of them
#        if ($row == $row->{prow}) {
#            print <<END;
#        <ul><li><a href="#P:$row->{model}.$row->{prof}">$row->{prof}</a></li></ul>
#END
#        }

        $text .= <<END;
        <tr>
          $moc<td rowspan="$mrowspan"><a name="P:$row->{model}">$row->{model}</a></td>$mcc
          $poc<td rowspan="$prowspan"><a name="P:$row->{model}.$row->{prof}">$row->{prof}</a></td>$pcc
          <td>$row->{prof_version}</td>
          <td>$row->{model_version}</td>
          <td>$row->{tr_name}</td>
        </tr>
END
    }
    print <<END;
      </ul>
    </ul>
END

    # end of profile table and document
    $text .= <<END;
      </tbody>
    </table>
  </body>
</html>
END

    # output document body
    print $text;
}

# Excel report of node.
sub xls_node
{
    my ($node, $indent) = @_;

    # use indent as a first-time flag
    # (assume that first line describes the model)
    if (!$indent) {
	my $title = $node->{name};
	$title .= " ($objpat)" if $objpat ne '';
        # XXX worksheet names can't contain ":" (altho' the schema permits it)
        $title =~ s/:/ /g;
	my $lstyle = 'Header';
	my $cstyle = 'HeaderCenter';
	print <<END;
 <Worksheet ss:Name="$title (model)">
  <Table>
   <Column ss:Width="120"/> <!-- Name -->
   <Column ss:Width="60"/>  <!-- Type -->
   <Column ss:Width="30"/>  <!-- Write -->
   <Column ss:Width="300"/> <!-- Description -->
   <!-- <Column ss:Width="120"/> --> <!-- Values -->
   <Column ss:Width="40"/>  <!-- Object Default -->
   <Column ss:Width="40"/>  <!-- Version -->
   <Column ss:Width="50"/>  <!-- Spec -->
   <Row>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">Name</Data></Cell>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">Type</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">Write</Data></Cell>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">Description</Data></Cell>
    <!-- <Cell ss:StyleID="$lstyle"><Data ss:Type="String">Values</Data></Cell> -->
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">Object Default</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">Version</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">Spec</Data></Cell>
   </Row>
END
    }

    my $auto = $node->{auto};
    if ($indent && !$auto) {
	my $object = ($node->{type} eq 'object');
	my $name = xls_escape($object ? $node->{path} : $node->{name});
	my $spec = xls_escape($node->{spec});
	my $type = xls_escape(type_string($node->{type}, $node->{syntax}));
	my $write = xls_escape($node->{access} ne 'readOnly' ? 'W' : '-');
        # is escaped later
	my $description = add_values($node->{description}, get_values($node));
	my $values = ''; #xls_escape(get_values($node));
	my $default =  xls_escape($node->{default});
	my $version =
	    xls_escape(version($node->{majorVersion}, $node->{minorVersion}));
        my $descact = xls_escape($node->{descact});
	($description, $descact) = remove_descact($description, $descact);
        $description = xls_escape($description);

	my $lstyle = $object ? 'Object' : 'Default';
	my $cstyle = $lstyle . 'Center';

	print <<END;
   <Row>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">$name</Data></Cell>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">$type</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">$write</Data></Cell>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">$description</Data></Cell>
    <!-- <Cell ss:StyleID="$lstyle"><Data ss:Type="String">$values</Data></Cell> -->
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">$default</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">$version</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">$spec</Data></Cell>
   </Row>
END
    }
    
    foreach my $child (@{$node->{nodes}}) {
	my $object = ($child->{type} eq 'object');
	xls_node($child, 1) unless $object;
    }
    foreach my $child (@{$node->{nodes}}) {
	my $object = ($child->{type} eq 'object');
	xls_node($child, 1) if $object;
    }
    
    if (!$indent) {
	print <<END;
  </Table>
 </Worksheet>
END
    }
}

sub xls_end
{
    print <<END;
</Workbook>
END
}

# Escape a value suitably for exporting as Excel XML.
sub xls_escape {
    my ($value) = @_;

    $value = util_default($value);

    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    # XXX should do this for all report types; should also use appropriate
    #     string sub-type to get appropriate white space treatment
    $value =~ s/^\n[ \t]*//;
    $value =~ s/\n[ \t]*/\n/g;
    $value =~ s/\n$//;

    $value =~ s/\n/\&#10;\&#10;/g;
    # XXX but not when separating enumerations (very heuristic)
    $value =~ s/\&#10;(\&#10;\* \")/$1/g;

    # XXX poor man's list
    $value =~ s/\&#10;\"/\&#10;    \"/g;

    return $value;
}

# W3C schema report of node.
# XXX makes all sorts of arbitrary assumptions
my $xsd_flag = 0;

sub xsd_begin
{
    print qq{<?xml version="1.0"?>\n};
}

sub xsd_node
{
    my ($node, $indent) = @_;

    my $object = ($node->{type} eq 'object');
    my $name = xsd_escape($node->{name});
    my $description = $node->{description};

    # XXX taken from xls_escape; should do more generically
    $description =~ s/^\n[ \t]*//;
    $description =~ s/\n[ \t]*/\n/g;
    $description =~ s/\n$//;
    my $documentation = xsd_escape(type_string($node->{type}, $node->{syntax}) .
				   ' (' . ($node->{access} ne 'readOnly' ? 'W' : 'R') . ')' .
				   "\n" .
				   add_values($description, get_values($node)));

    # XXX taken from xls_escape; should do more generically
    $documentation =~ s/^\n[ \t]*//;
    $documentation =~ s/\n[ \t]*/\n/g;
    $documentation =~ s/\n$//;

    if ($xsd_flag) {
	print STDERR "ignored second and subsequent data model: " .
	    "$node->{name}\n";

    } elsif (!$indent) {
	print qq{<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"\n};
	print qq{           elementFormDefault="qualified"\n};
	print qq{           attributeFormDefault="unqualified">\n};
	foreach my $child (@{$node->{nodes}}) {
	    xsd_node($child, 1);
	}
	print qq{</xs:schema>\n};
	$xsd_flag = 1;

    } elsif ($object) {
	my $minEntries = $indent > 1 ? qq{ minEntries="0"} : qq{};
	print "  "x$indent . qq{<xs:element name="$name"$minEntries>\n};
        print "  "x$indent . qq{  <xs:annotation>\n};
        print "  "x$indent . qq{    <xs:documentation>$documentation</xs:documentation>\n};
        print "  "x$indent . qq{  </xs:annotation>\n};
	print "  "x$indent . qq{  <xs:complexType>\n};
	# XXX did have maxEntries="unbounded" here (allows order not to be
	#     significant, but also allows duplication)
	print "  "x$indent . qq{    <xs:sequence minEntries="0">\n};
	foreach my $child (@{$node->{nodes}}) {
	    xsd_node($child, $indent + 3);
	}
	print "  "x$indent . qq{    </xs:sequence>\n};
	print "  "x$indent . qq{  </xs:complexType>\n};
	print "  "x$indent . qq{</xs:element>\n};

    } else {
	my $minEntries = $indent > 1 ? qq{ minEntries="0"} : qq{};
	print "  "x$indent . qq{<xs:element name="$name"$minEntries>\n};
        print "  "x$indent . qq{  <xs:annotation>\n};
        print "  "x$indent . qq{    <xs:documentation>$documentation</xs:documentation>\n};
        print "  "x$indent . qq{  </xs:annotation>\n};
	print "  "x$indent . qq{</xs:element>\n};
    }    
}

sub xsd_end {}

# Escape a value suitably for exporting as W3C XSD.
# XXX currently used only for names
sub xsd_escape {
    my ($value) = @_;

    $value = util_default($value);

    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    # XXX should use table syntax
    $value =~ s/\{i\}/i/g;

    # XXX this is for profile names
    $value =~ s/:/_/g;

    # remove trailing dot
    $value =~ s/\.$//;

    $value = util_lines($value);

    return $value;
}

# special report of node.
my $special_object = '';
my $special_profile = '';
my $special_profiles = {};
my $special_newitems = [];
my $special_items = [];

sub special_node
{
    my ($node, $pnode) = @_;

    my $type = $node->{type};
    my $path = $node->{path};
    my $name = $node->{name};
    my $majorVersion = $node->{majorVersion} || 0;
    my $minorVersion = $node->{minorVersion} || 0;

    # check for new profile
    if ($type eq 'profile') {
        $special_profile = $name;
    }

    # collect current profile definition
    elsif ($special_profile) {
        if ($type eq 'objectRef') {
            $special_object = $name;
            $special_profiles->{$special_profile}->{$special_object} = 1;
        } else {
            $special_profiles->{$special_profile}->{$special_object.$name} = 1;
        }
    }

    # make a list of all items added at the highest encountered version
    elsif ($majorVersion == $highestMajor && $minorVersion == $highestMinor) {
        push @$special_newitems, $node;
    }

    # unconditionally collect a list of all items
    # XXX should include values too but these don't currently support the
    #     same interface
    push @$special_items, $node;
}

sub special_end
{
    # deprecated/obsoleted: for each profile item (object, parameter) report
    # if it is deprecated or obsoleted
    if ($special =~ /deprecated|obsoleted/) {
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            next unless $path; # profile items have no path
            if ($item->{status} &&
                $item->{status} =~ /$special/) {
                print STDERR "$path\n" if $verbose;
                my $found = [];
                # XXX could check just new profiles?
                foreach my $profile (keys %$special_profiles) {
                    print STDERR "  checking $profile\n" if $verbose;
                    if ($special_profiles->{$profile}->{$path}) {
                        print STDERR "  found in $profile\n" if $verbose;
                        push @$found, $profile;
                    }
                }
                if (@$found) {
                    print "$path\t" . join(",", @$found) . "\n";
                }            
            }
        }
    }

    # nonascii: for each item (model, object, parameter, value or profile),
    # report use of non-ASCII characters
    # XXX really should simply check all instances of the "description"
    #     element
    elsif ($special eq 'nonascii') {
        # ref. TR-106a2 A.2.2.1: ASCII range 9-10 and 32-126
        my $patt = q{[^\x09-\x0a\x20-\x7e]};
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            #next unless $path; # profile items have no path
            my $description = $item->{description};
            next unless $description; # some parameters and objects omit it
            $description =~ s/\s+/ /g;
            if ($description =~ /$patt/) {
                $description =~ s/($patt)/**$1**/g;
                print "$path\t$description\n";
            }
        }
    }

    # normative: for each item (model, object, parameter, value or profile),
    # report use of lower-case normative language
    # XXX really should simply check all instances of the "description"
    #     element
    elsif ($special eq 'normative') {
        # also check for 'MAY NOT', which should NEVER be used
        my $terms = ['(M|m)ust( not)?', '(R|r)equired', '(S|s)hall( not)?',
                     '(S|s)hould( not)?', '(R|r)ecommended', '(M|m)ay( not)?',
                     '(O|o)ptional', '(D|d)eprecated', '(O|o)obsoleted',
                     'MAY NOT'];
        my $patt = '';
        foreach my $term (@$terms) {
            $patt .= qq{|} if $patt;
            $patt .= qq{\\b$term\\b};
        }
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            #next unless $path; # profile items have no path
            my $description = $item->{description};
            next unless $description; # some parameters and objects omit it
            $description =~ s/\s+/ /g;
            if ($description =~ /$patt/) {
                foreach my $term (@$terms) {
                    $description =~ s/\b($term)\b/**$1**/g;
                }
                print "$path\t$description\n";
            }
        }
    }

    # notify: for each new parameter, check whether it is read-only and in
    # the "can deny active notify" table; report those which aren't
    elsif ($special eq 'notify') {
        foreach my $item (@$special_newitems) {
            my $type = $item->{type};
            next if $type =~ 'model|object|profile';
            my $path = $item->{path};
            my $access = $item->{access};
            my $activeNotify = $item->{activeNotify};
            print STDERR "$path\n" if $verbose;
            print "$path\n"
                if $access eq 'readOnly' && $activeNotify ne 'canDeny';
        }
    }

    # profile: for each new parameter, check whether it is in a profile;
    # report those which aren't
    elsif ($special eq 'profile') {
        foreach my $item (@$special_newitems) {
            my $type = $item->{type};
            next if $type =~ 'model|object|profile';
            my $path = $item->{path};
            print STDERR "$path\n" if $verbose;
            my $found = 0;
            foreach my $profile (keys %$special_profiles) {
                if ($special_profiles->{$profile}->{$path}) {
                    print STDERR "  found in $profile\n" if $verbose;
                    $found = 1;
                    last;
                }
            }
            unless ($found) {
                print "$path\n";
            }
        }
    }

    # rfc: for each item (model, object, parameter, value or profile),
    # report RFCs without references
    # XXX really should simply check all instances of the "description"
    #     element
    elsif ($special eq 'rfc') {
        my $patt = '(RFC\s*[0-9]++)(\s?[^\s\[])';
        my $rfcs = {};
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            next unless $path; # profile items have no path
            my $description = $item->{description};
            next unless $description; # some parameters and objects omit it
            $description =~ s/\s+/ /g;
            if ($description =~ /$patt/) {
                $description =~ s/$patt/**$1**$2/g;
                my $rfc = $1;
                $rfc =~ s/RFC([^ ])/RFC $1/;
                $rfcs->{$rfc} = 1;
                print "$path\t$description\n";
            }
        }
        print join(",", sort(keys %$rfcs)) . "\n";
    }

    # ref: for each reference, report access, refType and path
    elsif ($special eq 'ref') {
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            next unless $path; # profile items have no path
            my $syntax = $item->{syntax};
            next unless $syntax; # only parameters have syntax
            my $refType = $syntax->{refType};
            next unless $refType; # only interested in references
            my $access = $item->{access};
            print "$access\t$refType\t$path\n";
        }
    }

    # key: for each table with a functional key, report access, path and the key
    elsif ($special eq 'key') {
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            next unless $path; # profile items have no path
            my $uniqueKeys = $item->{uniqueKeys};
            next unless $uniqueKeys && @$uniqueKeys; # only tables with keys
            my ($alias) = grep { $_->{name} eq 'Alias' } @{$item->{nodes}};
            next unless $alias; # only tables with aliases
            my $keys = '';
            foreach my $uniqueKey (@$uniqueKeys) {
                next unless $uniqueKey->{functional};
                $keys .= '; ' if $keys;
                $keys .= util_list($uniqueKey->{keyparams});
            }
            next unless $keys; # only interested in functional keys
            my $access = $item->{access};
            print "$access\t$path\t$keys\n";
        }
    }

    # invalid
    else {
        print STDERR "$special: invalid special option\n";
    }
}

# 
sub util_clean_cmd_line
{
    my ($cmd) = @_;

    my @in = split /\s+/, $cmd;
    my @out = ();

    for my $f (@in) {
        my ($a, $b) = split '=', $f;

        # we operate on the value, i.e. "a" if no "=" or "b" otherwise
        my ($n, $v);
        if (defined $b) {
            $n = $a;
            $v = $b;
        } else {
            $n = undef;
            $v = $a;
        }

        # for now there is no context, so just treat the value as a file system
        # path and discard all but the filename part (final component)
        (my $ign1, my $ign2, $v) = File::Spec->splitpath($v);

        $v = qq{''} if $v eq '';

        push @out, defined($n) ? qq{$n=$v} : qq{$v};
    }

    return join ' ', @out;
}

# Heuristic insertion of blank lines
sub util_lines
{
    my ($inval) = @_;

    my $outval = '';
    my @lines = split /\n/, $inval;
    my $last = pop @lines;
    my $prevstar = 0;
    foreach my $line (@lines) {
	my $star = $line =~ /^\*/;
	$outval .= "\n" if $prevstar && !$star;
	$outval .= $line;
	$outval .= "\n" unless $star;
	$outval .= "\n";
	$prevstar = $star;
    }
    $outval .= $last if $last;
    return $outval;
}

# Set value to "-" (or supplied default) if undefined or to "<Empty>" (or
# supplied value) if defined and empty
sub util_default {
    my ($value, $default, $empty) = @_;

    if (!defined $value) {
        $value = defined $default ? $default : '-';
    } elsif ($value eq '') {
        $value = defined $empty ? $empty : '<Empty>';
    }

    return $value;
}

# Convert list to string of the form "a, b and c", optionally supplying
# template containing "$1" to be substituted for each item.
sub util_list
{
    my ($list, $template) = @_;

    $template = qq{\$1} unless $template;

    my $i = 0;
    my $text = qq{};
    foreach my $item (@$list) {
        $text .= (($i < @$list - 1) ? ', ' : ' and ') if $i > 0;
        my $temp = $template;
        $temp =~ s/\$1/$item/g;
        $text .= $temp;
        $i++;
    }

    return $text;
}

# Ignore all instances of the named template in a string
# (relies on the {{ignore}} template, which allows arbitrary arguments and
# expands to an empty string)
sub util_ignore_template
{
    my ($name, $text) = @_;

    $text =~ s/(\{\{)($name)/$1ignore|$2/g;

    return $text;
}

# Return all the historical values of a node's specified attribute
sub util_history_values
{
    my ($node, $attr) = @_;

    my $history = $node->{history};

    my $list = [];

    if ($history) {
        foreach my $item (reverse @$history) {
            push @$list, $item->{$attr};
        }
    }

    push @$list, $node->{$attr};

    return $list;
}

# Copy of all elements of a hash except for those explicitly excluded
sub util_copy
{
    my ($in, $not) = @_;

    my $out = {};
    foreach my $key (keys %$in) {
        $out->{$key} = clone($in->{$key}) unless grep {$_ eq $key} @$not;
    }

    return $out;
}

# Determine differences between two strings
sub util_diffs
{
    my ($old, $new) = @_;
    
    my @old = split "\n", $old;
    my @new = split "\n", $new;
    my $diff = Algorithm::Diff->new(\@old, \@new);
    my $diffs = '';
    while($diff->Next()) {
        next if $diff->Same();
        my $sep = '';
        if (!$diff->Items(2)  ) {
            $diffs .=
                sprintf("%d,%dd%d\n", $diff->Get(qw(Min1 Max1 Max2)));
        } elsif (!$diff->Items(1)) {
            $diffs .=
                sprintf("%da%d,%d\n", $diff->Get(qw(Max1 Min2 Max2)));
        } else {
            # XXX XML comment can't contain "--" (or "---")
            $sep = "===\n";
            $diffs .= sprintf("%d,%dc%d,%d\n",
                              $diff->Get(qw(Min1 Max1 Min2 Max2)));
        }
        # XXX these have to be escaped in the XML (better presentation?)
        $diffs .= "- $_\n" for $diff->Items(1);
        $diffs .= $sep;
        $diffs .= "+ $_\n" for $diff->Items(2);
    }
    return $diffs;
}

# Version of the above that inserts '!' and '!!' markup
# XXX not working tht well; have tried to avoid bad matches by splitting
#     on word boundaries but loses line breaks so need a better solution
#     (and / / doesn't work)
sub util_diffs_markup
{
    my ($old, $new) = @_;

    my $ins = qq{+++};
    my $del = qq{---};

    my $spp = qr{\n};
    my $sep = qq{\n};

    my $pfx = qr{[*#:\s]*};

    my @old = split /$spp/, $old;
    my @new = split /$spp/, $new;
    my $diff = Algorithm::Diff->new(\@old, \@new);

    my $out = qq{};
    while ($diff->Next()) {
        my @same = $diff->Same();
        if (@same) {
            $out .= join $sep, @same;
            $out .= $sep;
            next;
        }

        my @from_old = $diff->Items(1);
        if (@from_old) {
            for my $item (@from_old) {
                my ($pre, $rst) = $item =~ /^($pfx)(.*)$/;
                $out .= qq{$pre$del$rst$del$sep};
            }
            # leave the separator, so as to put deleted and inserted text
            # on separate lines
        }

        my @from_new = $diff->Items(2);
        if (@from_new) {
            for my $item (@from_new) {
                my ($pre, $rst) = $item =~ /^($pfx)(.*)$/;
                $out .= qq{$pre$ins$rst$ins$sep};
            }
            chomp $out if @from_new;
        }

        $out .= $sep;
    }

    chomp $out;
    return $out;
}

# Convert spec to document name
sub util_doc_name
{
    my ($spec, $opts) = @_;

    my $verbose = $opts->{verbose};

    # XXX not sure quite why it's ever blank; something to do with profiles?
    return $spec unless $spec;

    # urn:broadband-forum-org:rest -> rest
    my $text = $spec;
    $text =~ s/.*://;

    # support names of form name-i-a[-c][label] where name is of the form
    # "cat-n", i, a and c are numeric and label can't begin with a digit
    my ($cat, $n, $i, $a, $c, $label) =
        $text =~ /^([^-]+)-(\d+)-(\d+)?-(\d+)(?:-(\d+))?(\D.*)?$/;

    # if doesn't match, return the input unchanged
    if (!$cat) {
        return $text;
    }
    
    $text = '';
    if ($cat =~ /^(dsl|bbf)$/) {
        $text .= qq{$cat};
        $text .= qq{$n}; # year
        $i = 0 unless defined $i;
        $text .= sprintf(".%.3d", $i); # number
        $a = 0 unless defined $a;
        $text .= sprintf(".%.2d", $a); # version
        # $c and $label are ignored
    } elsif ($cat =~ /wt|pd|il|od/i) {
        $cat = uc $cat;
        $text .= qq{$cat-$n};
        $text .= qq{i$i} if defined $i && $i > 1;
        $text .= qq{a$a} if $a;
        $text .= qq{c$c} if $c;
        $text .= qq{$label} if $label;
    } elsif ($cat =~ /tr/i) {
        $cat = uc $cat;
        $text .= qq{$cat-$n};
        $text .= $verbose ? qq{ Issue $i} : qq{i$i} if defined $i && $i > 1;
        $text .= $verbose ? qq{ Amendment $a} : qq{a$a} if $a;
        $text .= $verbose ? qq{ Corrigendum $c} : qq{c$c} if $c;
        # $label is ignored
    } else {
        # XXX it's not clear that this is now the correct logic
        $cat = $cat;
        $text .= qq{$cat-$n};
        $text .= qq{v$i} if defined $i && $i > 1; # version
        $text .= sprintf("_Rev-%.2d", $a) if $a; # revision (major)
        $text .= qq{.$c} if $c; # revision (minor)
        # $label is ignored
    }

    return $text;
}

# Convert BBF document name (as returned by util_doc_name) to a link
# relative to the BBF home page
sub util_doc_link
{
    my ($name) = @_;

    my $link = qq{technical/download/${name}.pdf};
    $link =~ s/ (Issue|Amendment|Corrigendum)/_$1/g;
    $link =~ s/ /-/g;

    return $link;
}

# Delete deprecated or obsoleted items if $deletedeprecated
sub util_maybe_deleted
{
    my ($status) = @_;

    $status = 'deleted'
        if $deletedeprecated && $status =~ /deprecated|obsoleted/;

    return $status;
}

# Determine whether a node has been deleted
sub util_is_deleted
{
    my ($node) = @_;

    for (; $node; $node = $node->{pnode}) {
        if ($node->{status} && $node->{status} eq 'deleted') {
            return 1;
        }
    }

    return 0;
}

# Determine whether an object is multi-instance
sub util_is_multi_instance
{
    my ($min, $max) = @_;

    my $multi = defined($max) && ($max eq 'unbounded' || $max > 1);
    my $fixed = ($multi && $max eq $min);

    return ($multi, $fixed);
}

# from http://www.sysarch.com/Perl/autoviv.txt (where it's called deep_defined)
# XXX would be better to change logic to render this unnecessary
sub util_is_defined {
    my ($ref, @keys) = @_;
    
    unless (@keys) {
        return ref $ref ? 1 : 0;
    }

    foreach my $key (@keys) {
        if (ref $ref eq 'HASH') {
            # fail when the key doesn't exist at this level
            return 0 unless defined($ref->{$key});

            $ref = $ref->{$key};
            next;
        }
        
        if (ref $ref eq 'ARRAY') {
            # fail when the index is out of range or is not defined
            return 0 unless 0 <= $key && $key < @{$ref};
            return 0 unless defined($ref->[$key]);
            
            $ref = $ref->[$key];
            next;
        }
        
        # fail when the current level is not a hash or array ref
        return 0;
    }
    
    return 1;
}

# Indicate whether a node is (to be) omitted from the report
sub util_is_omitted
{
    my ($node) = @_;

    return 1 if $node->{hidden};

    return 0 unless $lastonly;

    my $type = $node->{type};
    # XXX not sure why this is needed
    return 0 unless $type;

    # XXX never omit models (is this correct? it's because models are always
    #     marked changed)
    return 0 if $type eq 'model';

    # never omit parameterRef or objectRef because if the profile is included
    # then its children are always included
    return 0 if $type =~ /Ref$/;

    # XXX this test can give unexpected results if imported definitions
    #     are added to the data model AFTER the local definitions have
    #     been defined, because this can propagate lspec up the tree,
    #     marking lspec on the root object node (this is not believed
    #     to cause problems in real cases)
    return 1 unless util_node_is_modified($node);

    return 0;
}

# Determine if node was modified in the last spec or file
sub util_node_is_modified
{
    my ($node) = @_;

    # spec is used when not comparing files
    if ($modifiedusesspec) {
        return 1 if $node->{lspec} && $node->{lspec} eq $lspec;

    # file is used when comparing files
    } else {
        return 1 if $node->{lfile} && $node->{lfile} eq $lfile;
    }

    return 0;
}

# Determine if a node was new in the last spec or file
sub util_node_is_new
{
    my ($node) = @_;

    # XXX experimental; always use file for this decision
    return $node->{file} && $node->{file} eq $lfile;
}

# Expand all data model definition files.
foreach my $file (@ARGV) {
    expand_toplevel($file);
}

# Perform sanity checks etc, e.g. prune empty objects if --writonly
# XXX should be using the standard report_node framework?
sub sanity_node
{
    my ($node) = @_;

    # XXX this isn't really the place to do this but it's convenient because
    #     the sanity check passes through the entire tree before the report
    #     is generated
    # XXX experimental: treat as deleted if comparing and node was created
    #     in first file but not mentioned in second file (probably lots of
    #     holes in this but it seems to improve things)
    if ($compare) {
        if (defined $node->{file} && $node->{file} eq $pfile) {
            if (defined $node->{sfile} && $node->{sfile} ne $lfile) {
                #print STDERR "$node->{path}: marked deleted!\n";
                # XXX should use a function for this (no need to propagate
                #     to children (although could) because if parent isn't
                #     mentioned, children can't be mentioned)
                $node->{lfile} = $lfile;
                $node->{lspec} = $lspec;
                $node->{status} = 'deleted';
            }
        }
    }

    # no warnings for deleted items
    return if util_is_deleted($node);

    my $path = $node->{path};
    my $name = $node->{name};
    my $type = $node->{type};
    my $hidden = $node->{hidden}; # XXX this is hidden node, not value! 
    my $access = $node->{access};
    my $status = $node->{status};
    my $syntax = $node->{syntax};
    my $values = $node->{values};
    my $default = $node->{default};
    my $deftype = $node->{deftype};
    my $dynamic = $node->{dynamic};
    my $minEntries = $node->{minEntries};
    my $maxEntries = $node->{maxEntries};
    my $numEntriesParameter = $node->{numEntriesParameter};
    my $enableParameter = $node->{enableParameter};
    my $description = $node->{description};

    # XXX not sure that I should have to do this (is needed for auto-created
    #     objects, for which minEntries and maxEntries are undefined)
    $minEntries = '1' unless defined $minEntries;
    $maxEntries = '1' unless defined $maxEntries;

    my $object = ($type && $type eq 'object');
    my $parameter = ($type &&
                     $type !~ /model|object|profile|parameterRef|objectRef/);
    my $profile = ($type && $type eq 'profile');

    $default = undef
        if defined $node->{defstat} && $node->{defstat} eq 'deleted';
    my $udefault = util_default($default);

    # prune empty objects if --writonly
    if ($object && $writonly) {
	# XXX need actually to prune such nodes; for now set type to '',
	#     which isn't clever enough (need to do bottom up or multi pass)
	$node->{type} = '' unless $node->{nodes};
    }

    # object / parameter sanity checks
    if ($object || $parameter) {
        my $objpar = $object ? 'object' : 'parameter';
        print STDERR "$path: $objpar has empty description\n"
            if $pedantic > 1 && defined($description) && $description eq '';
        # XXX should check all descriptions, not just obj / par ones (now
        #     better: checking enumeration descriptions)
        my $ibr = invalid_bibrefs($description);
        print STDERR "$path: invalid bibrefs: " . join(', ', @$ibr) . "\n" if
            @$ibr;
        if (util_is_defined($values)) {
            foreach my $value (keys %$values) {
                my $cvalue = $values->{$value};
                
                my $description = $cvalue->{description};
                my $ibr = invalid_bibrefs($description);
                print STDERR "$path: invalid bibrefs: " . join(', ', @$ibr) .
                    "\n" if @$ibr;
            }
        }

        # errors that were deferred because they might have been cleared by
        # a later version
        print STDERR "$path: description: same as previous\n"
            if $pedantic && defined $node->{errors}->{samedesc} &&
            (!$node->{errors}->{samedesc} || $verbose);
        print STDERR "$path: invalid description action: " .
            util_default($node->{errors}->{baddescact}) . "\n" if
            defined $node->{errors}->{baddescact};
        if (util_is_defined($values)) {
            foreach my $value (keys %$values) {
                my $cvalue = $values->{$value};
                
                print STDERR "$path.$value: description: same as previous\n"
                    if $pedantic && defined $cvalue->{errors}->{samedesc} &&
                    (!$cvalue->{errors}->{samedesc} || $verbose);
                print STDERR "$path.$value: invalid description action: " .
                    util_default($cvalue->{errors}->{baddescact}) . "\n" if
                    defined $cvalue->{errors}->{baddescact};
            }
        }
    }

    # object sanity checks
    # XXX for DT, need to check that things are not only defined but are not
    #     hidden
    if ($object) {
        my $ppath = $node->{pnode}->{path};
        my ($multi, $fixed) = util_is_multi_instance($minEntries, $maxEntries);

        print STDERR "$path: object is optional; was this intended?\n"
            if $minEntries eq '0' && $maxEntries eq '1' && $pedantic > 1;

        print STDERR "$path: object is writable but not a table\n"
            if $access ne 'readOnly' && $maxEntries eq '1';

        print STDERR "$path: object is a table but name doesn't end with ".
            "\"{i}.\"\n" if $multi && $path !~ /\{i\}\.$/;

        print STDERR "$path: object is not a table but name ends with ".
            "\"{i}.\"\n" if !$multi && $path =~ /\{i\}\.$/;

        print STDERR "$path: object is not writable and multi-instance but " .
            "has enableParameter\n"
            if !($access ne 'readOnly' && $multi) && $enableParameter;

        print STDERR "$path: enableParameter ($enableParameter) doesn't ".
            "exist\n"
            if $enableParameter && !$parameters->{$path.$enableParameter};

        # XXX this is questionable use of "hidden" (TR-196?)
        my $temp = $numEntriesParameter || '';
        $numEntriesParameter = $parameters->{$ppath.$numEntriesParameter} if
            $numEntriesParameter;
        if ($multi && !$fixed &&
            (!$numEntriesParameter ||
             (!$hidden && $numEntriesParameter->{hidden}))) {
            print STDERR "$path: missing or invalid numEntriesParameter ".
                "($temp)\n";
            # XXX should filter out only parameters (use grep)
            print STDERR "\t" .
                join(", ", map {$_->{name}} @{$node->{pnode}->{nodes}}) . "\n"
                if $pedantic > 2;
        }

        # add a reference from each #entries parameter to its table (can be
        # used in report generation)
        $numEntriesParameter->{table} = $node if $numEntriesParameter;

        # XXX old test for enableParameter considered "hidden"; why?
        #$enableParameter =
        #    $parameters->{$path.$enableParameter} if $enableParameter;
        #(!$enableParameter || (!$hidden && $enableParameter->{hidden}))

        my $any_functional = 0;
        foreach my $uniqueKey (@{$node->{uniqueKeys}}) {
            $any_functional = 1 if $uniqueKey->{functional};
        }

        print STDERR "$path: writable table but no enableParameter\n"
            if $access ne 'readOnly' && $multi && $any_functional &&
            !$enableParameter;

        print STDERR "$path: writable fixed size table\n"
            if $access ne 'readOnly' && $multi && $fixed;

        # XXX could be cleverer re checking for read-only / writable unique
        #     keys
        print STDERR "$path: no unique keys are defined\n"
            if $pedantic && $multi &&
            !$node->{noUniqueKeys} && !@{$node->{uniqueKeys}};
    }

    # parameter sanity checks
    if ($parameter) {
        # XXX this one is useless
	#print STDERR "$path: parameter is an enumeration but has " .
	#    "no values\n" if $pedantic && values_appropriate($name, $type) &&
	#    !has_values($values);

        # XXX this isn't always an error; depends on whether table entries
        #     correspond to device configuration
        print STDERR "$path: writable parameter in read-only table\n" if
            $pedantic > 1 && $access ne 'readOnly' &&
            defined $node->{pnode}->{access} &&
            $node->{pnode}->{access} eq 'readOnly' &&
            defined $node->{pnode}->{maxEntries} &&
            $node->{pnode}->{maxEntries} eq 'unbounded' &&
            !$node->{pnode}->{fixedObject};

        print STDERR "$path: read-only command parameter\n"
            if $syntax->{command} && $access eq 'readOnly';

        # XXX doesn't complain about defaults in read-only objects or tables;
        #     this is because they are quietly ignored (this is part of
        #     allowing them in components that can be included in multiple
        #     environments)

	print STDERR "$path: default $udefault is invalid for data type $type\n"
            if $pedantic && defined $default && !valid_values($node, $default);

	print STDERR "$path: default $udefault is inappropriate\n"
            if $pedantic && defined($default) && $default =~ /\<Empty\>/i;

        print STDERR "$path: range ".add_range($syntax)." is invalid for ".
            "data type $type\n" if $pedantic && defined $syntax->{ranges} &&
            !valid_ranges($node);

	print STDERR "$path: string parameter has no maximum " .
	    "length specified\n" if $pedantic > 1 &&
	    maxlength_appropriate($path, $name, $type) &&
            !has_values($values) && !$syntax->{maxLength};

	print STDERR "$path: enumeration has unnecessary maximum " .
	    "length specified\n" if $pedantic > 1 &&
	    maxlength_appropriate($path, $name, $type) &&
            has_values($values) && $syntax->{maxLength};

        # XXX why the special case for lists?  suppressed
	print STDERR "$path: parameter within static object has " .
		"a default value\n" if $pedantic && !$dynamic &&
                defined($default) && $deftype eq 'object';
        #&& !($syntax->{list} && $default eq '');

        print STDERR "$path: weak reference parameter is not writable\n" if
            $syntax->{refType} && $syntax->{refType} eq 'weak' && 
            $access eq 'readOnly';

	# XXX other checks to make: profiles reference valid parameters,
	#     reference types, default is valid for type, other facets are
        #     valid for type (valid narrowing checks could be done here too,
        #     but would need to use history)
    }

    # profile sanity checks
    if ($profile) {
        foreach my $path (sort keys %{$node->{errors}}) {
            print STDERR "profile $name references invalid $path\n";
        }
    }

    foreach my $child (@{$node->{nodes}}) {
	sanity_node($child);
    }    
}

if (!$allbibrefs && $root->{bibliography}) {
    foreach my $reference (sort bibid_cmp
                           @{$root->{bibliography}->{references}}) {
        my $id = $reference->{id};
        my $spec = $reference->{spec};
        
        next if ($spec ne $lspec);    
        print STDERR "reference $id not used\n" unless $bibrefs->{$id};
    }
}
            
sanity_node($root);

# Report top-level nodes.
# XXX probably want to output fully expanded XML file of the same format as
#     the input file (i.e. just object and parameter definitions)
# XXX now that report_node is called for the root node too, can dispense with
#     _begin and _end and use _node (indent=0) and _post (indent=0)
# XXX currently doesn't work for all report types (haven't updated them all for
#     the new interface)
# XXX need to re-think "hidden" versus use of "lspec"
"${report}_begin"->($root) if defined &{"${report}_begin"};
report_node($root);
"${report}_end"->($root) if defined &{"${report}_end"};

sub report_node
{    
    my $node = shift;
    return if util_is_omitted($node);

    my $indent = shift;
    $indent = 0 unless $indent;

    unshift @_, $node, $indent;
    "${report}_node"->(@_);
    shift; shift;

    $indent++;

    # always report parameter children before other types of children
    # XXX really shouldn't overload type in this way

    foreach my $child (@{$node->{nodes}}) {
        unshift @_, ($child, $indent);
	report_node(@_) if
            (!$nomodels && $child->{type} !~ /^(model|object|profile|objectRef|parameterRef)$/) ||
            (!$noprofiles && $child->{type} =~ /^parameterRef$/);
        shift; shift;
    }

    # XXX it's convenient to have a hook that is called after the parameter
    #     children and before the object children, e.g. where the report does
    #     not nest objects (need to integrate this properly)
    unshift @_, $node, $indent;
    "${report}_postpar"->(@_) if
        $node->{type} =~ /^object/ && defined &{"${report}_postpar"};
    shift; shift;

    foreach my $child (@{$node->{nodes}}) {
        unshift @_, ($child, $indent);
	report_node(@_) if
            (!$nomodels && $child->{type} =~ /^(model|object)$/) ||
            (!$noprofiles && $child->{type} =~ /^(model|profile|objectRef)$/);
        shift; shift;
    }

    $indent--;

    unshift @_, $node, $indent;
    "${report}_post"->(@_) if defined &{"${report}_post"};
    shift; shift;
}

# Count total number of occurrences of each spec
my $spectotal = {};

sub spec_node
{
    my ($node, $indent) = @_;

    # XXX don't count root node (it confuses people, e.g. me)
    # XXX this gives the wrong answer for "xml2" output
    $spectotal->{$node->{spec}}++ if $indent && $node->{spec};
}

# XXX would be nice to avoid use of the global variable here (just pass
#     the report type as the first argument!)
$report = 'spec';
report_node($root);

foreach my $spec (sort @$specs) {
    print STDERR "$spec: $spectotal->{$spec}\n" if
        defined $spectotal->{$spec} && !$quiet;
}

# documentation
=head1 NAME

report.pl - generate report on TR-069 DM instances (data model definitions)

=head1 SYNOPSIS

B<report.pl> [--allbibrefs] [--autobase] [--autodatatype] [--bibrefdocfirst] [--canonical] [--catalog=c]... [--compare] [--components] [--debugpath=pattern("")] [--deletedeprecated] [--dtprofile=s]... [--dtspec[=s]] [--help] [--ignore=pattern("")] [--importsuffix=string("")] [--include=d]... [--info] [--lastonly] [--marktemplates] [--noautomodel] [--nocomments] [--nohyphenate] [--nolinks] [--nomodels] [--noobjects] [--noparameters] [--noprofiles] [--notemplates] [--nowarnredef] [--nowarnprofbadref] [--objpat=pattern("")] [--outfile=s] [--pedantic[=i(1)]] [--quiet] [--report=html|(null)|tab|text|xls|xml|xml2|xsd] [--showdiffs] [--showreadonly] [--showspec] [--showsyntax] [--special=<option>] [--thisonly] [--tr106=s(TR-106)] [--ugly] [--upnpdm] [--verbose[=i(1)]] [--warnbibref[=i(1)]] [--writonly] DM-instance...

=over

=item * the most common options are --include, --pedantic and --report=html

=item * use --compare to compare files and --showdiffs to show differences

=item * cannot specify both --report and --special

=back

=head1 DESCRIPTION

The files specified on the command line are assumed to be XML TR-069 data model definitions compliant with the I<cwmp:datamodel> (DM) XML schema.

The script parses, validates (ahem) and reports on these files, generating output in various possible formats to I<stdout>.

There are a large number of options but in practice only a few need to be used.  For example:

./report.pl --pedantic --report html tr-098-1-2-0.xml >tr-098-1-2-0.html

=head1 OPTIONS

=over

=item B<--allbibrefs>

usually only bibliographic references that are referenced from within the data model definition are listed in the report; this isn't much help when generating a list of bibliographic references without a data model! that's what this option is for; currently it affects only B<html> reports

=item B<--autobase>

causes automatic addition of B<base> attributes when models, parameters and objects are re-defined, and suppression of redefinition warnings (useful when processing auto-generated data model definitions)

is implied by B<--compare>

=item B<--autodatatype>

causes the B<{{datatype}}> template to be automatically prefixed for parameters with named data types

this is deprecated because it is enabled by default

=item B<--bibrefdocfirst>

causes the B<{{bibref}}> template to be expanded with the document first, i.e. B<[DOC] Section n> rather than the default of B<Section n/[DOC]>

=item B<--canonical>

affects only the B<xml2> report; causes descriptions to be processed into a canonical form that eases comparison with the original Microsoft Word descriptions

=item B<--catalog=s>...

can be specified multiple times; XML catalogs (http://en.wikipedia.org/wiki/XML_Catalog); the current directory and any directories specified via B<--include> are searched when locating XML catalogs

XML catalogs are used only when validating DM instances as described under B<--pedantic>; it is not necessary to use XML catalogs in order to validate DM instances

=item B<--compare>

compares the two files that were specified on the command line, showing the changes made by the second one

note that this is identical to setting B<--autobase> and B<--showdiffs>; it also affects the behavior of B<--lastonly>

=item B<--components>

affects only the B<xml2> report; generates a component for each object; if B<--noobjects> is also specified, the component omits the object definition and consists only of parameter definitions

=item B<--debugpath=pattern("")>

outputs debug information for parameters and objects whose path names match the specified pattern

=item B<--deletedeprecated>

mark all deprecated or obsoleted items as deleted

=item B<--dtprofile=s>...

affects only the B<xml2> report; can be specified multiple times; defines names of profiles to be used to generate an example DT instance

=item B<--dtspec=s>

affects only the B<xml2> report; has an affect only when B<--dtprofile> is also present; specifies the value of the top-level B<spec> attribute in the generated DT instance; if not specified, the spec defaults to B<urn:example-com:device-1-0-0>

=item B<--help>

requests output of usage information

=item B<--ignore>

specifies a pattern; data models whose names begin with the pattern will be ignored

=item B<--importsuffix=string("")>

specifies a suffix which, if specified, will be appended (preceded by a hyphen) to the name part of any imported files in b<xml> reports

=item B<--include=d>...

can be specified multiple times; specifies directories to search for files specified on the command line or included from other files; the current directory is always searched first

no search is performed for files that already include directory names

=item B<--info>

output details of author, date, version etc

=item B<--lastonly>

reports only on items that were defined or last modified in the specification corresponding to the last XML file on the command line (as determined by the last XML file's B<spec> attribute)

if B<--compare> is also specified, the "last only" criterion uses the file name rather than the spec (so the changes shown will always be those from the second file on the command line even if both files have the same spec)

=item B<--marktemplates>

mark selected template expansions with B<&&&&> followed by template-related information, a colon and a space

for example, the B<reference> template is marked by a string such as B<&&&&pathRef-strong:>, B<&&&&pathRef-weak:>, B<&&&&instanceRef-strong:>, B<&&&&instanceRef-strong-list:> or B<enumerationRef:>

and the B<list> template is marked by a string such as B<&&&&list-unsisgnedInt:> or B<&&&&list-IPAddress:>

=item B<--noautomodel>

disables the auto-generation, if no B<model> element was encountered, of a B<Components> model that references each component

=item B<--nocomments>

disables generation of XML comments showing what changed etc (B<--verbose> always switches it off)

=item B<--nohyphenate>

prevents automatic insertion of soft hyphens

=item B<--nolinks>

affects only the B<html> report; disables generation of hyperlinks (which makes it easier to import HTML into Word documents)

=item B<--nomodels>

specifies that model definitions should not be reported

=item B<--noobjects>

affects only the B<xml2> report when B<--components> is specified; omits objects from component definitions

=item B<--noparameters>

affects only the B<xml2> report when B<--components> is specified; omits parameters from component definitions

B<NOT YET IMPLEMENTED>

=item B<--noprofiles>

specifies that profile definitions should not be reported

=item B<--notemplates>

suppresses template expansion (currently affects only B<html> reports

=item B<--nowarnredef>

disables parameter and object redefinition warnings (these warnings are also output if B<--verbose> is specified)

there are some circumstances under which parameter or object redefinition is not worthy of comment

=item B<--nowarnprofbadref>

disables warnings when a profile references an invalid object or parameter

there are some circumstances under which it's useful to use an existing profile definition where some objects or parameters that it references have been (deliberately) deleted

this is deprecated because it is no longer needed (use status="deleted" as appropriate to suppress such errors)

=item B<--objpat=pattern>

specifies an object name pattern (a regular expression); objects that do not match this pattern will be ignored (the default of "" matches all objects)

=item B<--outfile=s>

specifies the output file; if not specified, output will be sent to I<stdout>

if the file already exists, it will be quietly overwritten

the only reason to use this option (rather than using shell output redirection) is that it allows the tool to know the name of the output file and therefore to include it in the report

=item B<--pedantic=[i(1)]>

enables output of warnings to I<stderr> when logical inconsistencies in the XML are detected; if the option is specified without a value, the value defaults to 1

also enables XML schema validation of DM instances; XML schemas are located using the B<schemaLocation> attribute:

=over

=item * if it specifies an absolute path, no search is performed

=item * if it specifies a relative path, the directories specified via B<--include> are searched

=item * URLs are treated specially: if no XML catalogs were supplied via B<--catalog>, the directory part is ignored and the schema is located as for a relative path (above); if XML catalogs were supplied via B<--catalog>, the catalogs govern how (and whether) the URLs are processed

=back

=item B<--quiet>

suppresses informational messages

=item B<--report=html|(null)|tab|text|xls|xml|xml2|xsd>

specifies the report format; one of the following:

=over

=item B<html>

HTML document; see also B<--nolinks> and B<--notemplates>

=item B<null>

no output; errors go to I<stdout> rather than I<stderr> (default)

=item B<tab>

tab-separated list, one object or parameter per line

=item B<text>

indented text

=item B<xls>

Excel XML spreadsheet

=item B<xml>

if B<--lastonly> is specified, DM XML containing only the changes made by the final file on the command line; see also B<--autobase>

if B<--lastonly> is not specified, DM XML with all imports resolved (apart from bibliographic references and data type definitions); use B<--dtprofile>, optionally with B<--dtspec>, to generate DT XML for the specified profiles; use B<--canonical> to generate canonical and more easily compared descriptions; use B<--components> (perhaps with B<--noobjects> or B<--noparameters>) to generate component definitions

=item B<xml2>

same as the B<xml> report with B<--lastonly> not specified; deprecated (use B<xml> instead)

=item B<xsd>

W3C schema

=back

=item B<--showdiffs>

currently affects only the B<text> and B<html> reports; visually indicates the differences resulting from the last XML file on the command line

for the B<html> report, insertions are shown in blue and deletions are shown in red strikeout; in order to enhance readability, hyperlinks are not shown in a special color (but are still underlined); note that this hyperlink behavior uses B<color=inherit>, which apparently isn't supported by Internet Explorer

is implied by B<--compare>

=item B<--showreadonly>

shows read-only enumeration and pattern values as B<READONLY> (experimental)

=item B<--showspec>

currently affects only the B<html> report; generates a B<Spec> rather than a B<Version> column

=item B<--showsyntax>

adds an extra column containing a summary of the parameter syntax; is like the Type column for simple types, but includes additional details for lists

=item B<--special=deprecated|key|nonascii|normative|notify|obsoleted|profile|ref|rfc>

performs special checks, most of which assume that several versions of the same data model have been supplied on the command line, and many of which operate only on the highest version of the data model

=over

=item B<deprecated>, B<obsoleted>

for each profile item (object or parameter) report if it is deprecated or obsoleted

=item B<key>

for each table with a functional key, report access, path and the key

=item B<nonascii>

check which model, object, parameter or profile descriptions contain characters other than ASCII 9-10 or 32-126; the output is the full path names of all such items, together with the offending descriptions with the invalid characters surrounded by pairs of asterisks

=item B<normative>

check which model, object, parameter or profile descriptions contain inappropriate use of normative language, i.e. lower-case normative words, or B<MAY NOT>; the output is the full path names of all such items, together with the offending descriptions with the normative words surrounded by pairs of asterisks

=item B<notify>

check which parameters in the highest version of the data model are not in the "can deny active notify request" table; the output is the full path names of all such parameters, one per line

=item B<profile>

check which parameters defined in the highest version of the data model are not in profiles; the output is the full path names of all such parameters, one per line

=item B<rfc>

check which model, object, parameter or profile descriptions mention RFCs without giving references; the output is the full path names of all such items, together with the offending descriptions with the normative words surrounded by pairs of asterisks

=item B<ref>

for each reference parameter, report access, reference type and path

=back

=item B<--thisonly>

outputs only definitions defined in the files on the command line, not those from imported files

=item B<--tr106=s(TR-106)>

indicates the TR-106 version (i.e. the B<bibref> name) to be referenced in any automatically generated description text

the default value is the latest version of TR-106 that is referenced elsewhere in the data model (or B<TR-106> if it is not referenced elsewhere)

=item B<--upnpdm>

transforms output (currently HTML only) so it looks like a B<UPnP DM> (Device Management) data model definition

=item B<--ugly>

disables some prettifications, e.g. inserting spaces to encourage line breaks

this is deprecated because it has been replaced with the more specific B<--nohyphenate> and B<--showsyntax>

=item B<--verbose[=i(1)]>

enables verbose output; the higher the level the more the output

=item B<--warnbibref[=i(1)]>

enables bibliographic reference warnings (these warnings are also output if B<--verbose> is specified); the higher the level the more warnings

previously known as B<--warndupbibref>, which is now deprecated (and will be removed in a future release) because it covers more than just duplicate bibliographic references

=item B<--writonly>

reports only on writable parameters (should, but does not, suppress reports of read-only objects that contain no writable parameters)

=back

=head1 LIMITATIONS

This script is only for illustration of concepts and has many shortcomings.

=head1 AUTHOR

William Lupton E<lt>wlupton@2wire.comE<gt>

$Date: 2011/07/05 $
$Id: //depot/users/wlupton/cwmp-datamodel/report.pl#184 $

=cut
