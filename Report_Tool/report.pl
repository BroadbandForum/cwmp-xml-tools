#!/usr/bin/env perl
#
# Copyright (C) 2011, 2012  Pace Plc
# Copyright (C) 2012, 2013, 2014  Cisco Systems
# All Rights Reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# - Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# - Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# - Neither the names of the copyright holders nor the names of their
#   contributors may be used to endorse or promote products derived from this
#   software without specific prior written permission.
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

# XXX $showdiffs doesn't do the right thing with components, because the history
#     refers to the component, not the model, so can show component diffs that
#     should not be shown as model diffs

# XXX why does this happen?
# % report.pl tr-098-1-1-0.xml tr-098-1-2-0.xml
#Internetgatewaydevice.DownloadDiagnostics.: object not found (auto-creating)
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
use warnings;

# XXX can enable this as an aid to finding auto-vivification problems
#no autovivification qw{fetch exists delete warn};

# XXX uncomment to enable traceback on warnings and errors
#use Carp::Always;
#sub control_c { die ""; }
#$SIG{INT} = \&control_c;

use Algorithm::Diff;
use Clone qw{clone};
use Data::Compare;
use Data::Dumper;
use File::Spec;
use Getopt::Long;
use Pod::Usage;
use String::Tokenizer;
use Text::Balanced qw{extract_bracketed};
# XXX causes problems, e.g. need aspell (if restore should use "require")
#use Text::SpellChecker;
use URI::Split qw(uri_split);
use XML::LibXML;

# git will not expand these; svn will, so after svn commit should merge
# back into git; also, if further changes are made, should add a "+" sign
# after the version number (this will be removed on the next svn commit); e.g.
# "report.pl 246" -> "report.pl 246+"
my $tool_author = q{$Author$};
my $tool_vers_date = q{$Date$};
my $tool_id = q{$Id$};

my $tool_url = q{https://tr69xmltool.iol.unh.edu/repos/cwmp-xml-tools/Report_Tool};

# extract author from Author keyword (assumes SVN)
my ($tool_author_only) = ($tool_author =~ /\$Author:\s+(\S+)/);
$tool_author_only = q{unknown} unless $tool_author_only;

# extract yyyy/mm/dd date from Date keyword (assumes SVN)
my ($tool_vers_date_only) = ($tool_vers_date =~ /\$Date:\s+(\S+)/);
$tool_vers_date_only =~ s/-/\//g if $tool_vers_date_only;
$tool_vers_date_only = q{unknown} unless $tool_vers_date_only;

# extract report.pl#ver from Id keyword (assumes SVN)
my ($tool_id_only) = ($tool_id =~ /\$Id:\s+(\S+\s+\S+)/);
$tool_id_only =~ s/\s+/\#/ if $tool_id_only;
$tool_id_only = q{report.pl} unless $tool_id_only;

# use the existence of a trailing "+" on the version to determine whether the
# tool is currently checked out, i.e. whether it's changed since the date and
# version were last set
my $tool_checked_out = q{};
if ($tool_id_only =~ /\+$/) {
    $tool_checked_out = q{ (TOOL CURRENTLY CHECKED OUT)};
    $tool_id_only =~ s/\+$//;
}

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

# XXX this loses knowledge of spaces within arguments (eval?)
my $tool_cmd_line = $0 . ' ' . join(' ', @ARGV);
$tool_cmd_line = util_clean_cmd_line($tool_cmd_line);

# XXX this will be used only if the input file is invalid
my $xsiurn = qq{http://www.w3.org/2001/XMLSchema-instance};

# XXX these are defaults that are used only if missing from the DM instance
#     (they should match the current versions of the DM and DMR schemas)
my $dmver = qq{1-5};
my $dmrver = qq{0-1};
my $dmurn = qq{urn:broadband-forum-org:cwmp:datamodel-${dmver}};
my $dmrurn = qq{urn:broadband-forum-org:cwmp:datamodel-report-${dmrver}};

# XXX these have to match the current version of the DT schema
my $dtver = qq{1-3};
my $dturn = qq{urn:broadband-forum-org:cwmp:devicetype-${dtver}};
my $dtloc = qq{http://www.broadband-forum.org/cwmp/}.
    qq{cwmp-devicetype-${dtver}.xsd};

# XXX this prevents warnings about wide characters, but still not handling
#     them properly (see tr2dm.pl, which now does a better job)
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

# XXX this was controllable via --lastonlyusesspec, but is now hard-coded
#     (--compare sets it to 0)
my $modifiedusesspec = 1;

# Command-line options
# XXX don't need --alldatatypes because the last spec is the data type file so
#     all are included; why doesn't this work for bibrefs too?
# XXX needed to change declarations to be "our" in order for variables to be
#     visible to plugins; better to use a single options hash?
our $allbibrefs = 0;
our $autobase = 0;
our $autodatatype = 0;
our $automodel = 0;
our $bibrefdocfirst = 0;
our $canonical = 0;
our $catalogs = [];
our $compare = 0;
our $components = 0;
our $configfile = '';
our $cwmpindex = '../cwmp';
our $cwmppath = 'cwmp';
our $debugpath = '';
our $deletedeprecated = 0;
our $dtprofiles = [];
our $diffs = 0;
our $diffsexts = ['diffs'];
our $dtspec = 'urn:example-com:device-1-0-0';
our $dtuuid = '00000000-0000-0000-0000-000000000000';
our $exitcode = 0;
our $help = 0;
our $nohyphenate = 0;
our $ignore = undef;
our $importsuffix = '';
our $includes = [];
our $info = 0;
our $lastonly = 0;
our $loglevel = 'w';
our $marktemplates = undef;
our $maxchardiffs = 5;
our $maxworddiffs = 10;
our $newparser = 0;
our $noautomodel = 0;
our $nocomments = 0;
our $nolinks = 0;
our $nologprefix = 0;
our $nomodels = 0;
our $noobjects = 0;
our $noparameters = 0;
our $noprofiles = 0;
our $noshowreadonly = 0;
our $notemplates = 0;
our $nowarnbibref = 0;
our $nowarnenableparameter = 0;
our $nowarnnumentries = 0;
our $nowarnredef = 0;
our $nowarnreport = 0;
our $nowarnprofbadref = 0;
our $nowarnuniquekeys = 0;
our $nowarnwtref = 0;
our $objpat = '';
our $options = {};
our $outfile = undef;
our $pedantic = undef;
our $plugins = [];
our $quiet = 0;
our $report = '';
our $showdiffs = 0;
our $showspec = 0;
our $showreadonly = undef;
our $showsyntax = 0;
our $showunion = 0;
our $sortobjects = 0;
our $special = '';
our $thisonly = 0;
our $tr106 = 'TR-106';
our $trpage = 'http://www.broadband-forum.org/technical/download';
our $ucprofiles = [];
our $ugly = 0;
our $upnpdm = 0;
our $verbose = undef;
our $warnbibref = undef;
our $warndupbibref = 0;
our $writonly = 0;
GetOptions('allbibrefs' => \$allbibrefs,
           'autobase' => \$autobase,
           'autodatatype' => \$autodatatype,
           'automodel' => \$automodel,
           'bibrefdocfirst' => \$bibrefdocfirst,
           'canonical' => \$canonical,
           'catalog:s@' => \$catalogs,
           'compare' => \$compare,
           'components' => \$components,
           'configfile:s' => \$configfile,
           'cwmpindex:s' => \$cwmpindex,
           'cwmppath:s' => \$cwmppath,
           'debugpath:s' => \$debugpath,
           'deletedeprecated' => \$deletedeprecated,
           'diffs' => \$diffs,
           'diffsext:s@' => \$diffsexts,
           'dtprofile:s@' => \$dtprofiles,
           'dtspec:s' => \$dtspec,
           'dtuuid:s' => \$dtuuid,
           'exitcode' => \$exitcode,
	   'help' => \$help,
           'ignore:s' => \$ignore,
           'importsuffix:s' => \$importsuffix,
           'include:s@' => \$includes,
	   'info' => \$info,
           'lastonly' => \$lastonly,
           'loglevel:s' => \$loglevel,
	   'marktemplates' => \$marktemplates,
           'maxchardiffs:i' => \$maxchardiffs,
           'maxworddiffs:i' => \$maxworddiffs,
           'newparser' => \$newparser,
	   'noautomodel' => \$noautomodel,
	   'nocomments' => \$nocomments,
	   'nohyphenate' => \$nohyphenate,
	   'nolinks' => \$nolinks,
	   'nologprefix' => \$nologprefix,
	   'nomodels' => \$nomodels,
	   'noobjects' => \$noobjects,
	   'noparameters' => \$noparameters,
	   'noprofiles' => \$noprofiles,
	   'noshowreadonly' => \$noshowreadonly,
	   'notemplates' => \$notemplates,
           'nowarnbibref' => \$nowarnbibref,
           'nowarnenableparameter' => \$nowarnenableparameter,
           'nowarnnumentries' => \$nowarnnumentries,
           'nowarnredef' => \$nowarnredef,
           'nowarnreport' => \$nowarnreport,
           'nowarnprofbadref' => \$nowarnprofbadref,
           'nowarnuniquekeys' => \$nowarnuniquekeys,
           'nowarnwtref' => \$nowarnwtref,
	   'objpat:s' => \$objpat,
           'option:s%' => \$options,
           'outfile:s' => \$outfile,
	   'pedantic:i' => \$pedantic,
           'plugin:s@' => \$plugins,
	   'quiet' => \$quiet,
	   'report:s' => \$report,
           'showdiffs' => \$showdiffs,
           'showreadonly' => \$showreadonly,
           'showspec' => \$showspec,
           'showsyntax' => \$showsyntax,
           'showunion' => \$showunion,
           'sortobjects' => \$sortobjects,
           'special:s' => \$special,
	   'thisonly' => \$thisonly,
	   'tr106:s' => \$tr106,
	   'trpage:s' => \$trpage,
           'ucprofile:s@' => \$ucprofiles,
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

# loglevel constants
my $LOGLEVEL_FATAL   = 00;
my $LOGLEVEL_ERROR   = 10;
my $LOGLEVEL_INFO    = 20;
my $LOGLEVEL_WARNING = 30;
my $LOGLEVEL_DEBUG   = 40;

# msg helpers (use parsed loglevel; see below)
sub msg;
sub tmsg  { msg 'T', @_; } # used for temporary debug output
sub emsg  { msg 'E', @_ if $loglevel >= $LOGLEVEL_ERROR;       }
sub imsg  { msg 'I', @_ if $loglevel >= $LOGLEVEL_INFO;        }
sub w0msg { msg 'W', @_ if $loglevel >= $LOGLEVEL_WARNING;     }
sub w1msg { msg 'W', @_ if $loglevel >= $LOGLEVEL_WARNING + 1; }
sub w2msg { msg 'W', @_ if $loglevel >= $LOGLEVEL_WARNING + 2; }
sub d0msg { msg 'D', @_ if $loglevel >= $LOGLEVEL_DEBUG;       }
sub d1msg { msg 'D', @_ if $loglevel >= $LOGLEVEL_DEBUG + 1;   }
sub d2msg { msg 'D', @_ if $loglevel >= $LOGLEVEL_DEBUG + 2;   }

my $msgs = []; # warnings and errors logged via msg()
my $num_errors = 0;

# parse loglevel (can't use the msg routines until have set it)
# 0x=fatal, 1x=error, 2x=info, 3x=warning, 4x=debug
{
    my $orig_loglevel = $loglevel;
    my ($tname, $tvalue) = ($loglevel =~ /^(\D+)(\d?)$/);
    undef $loglevel; # is set below
    $tvalue = 0 unless $tvalue;
    my @levels = ('fatal', 'error', 'info', 'warning', 'debug');
    if (defined $tname) {
        for (my $i = 0; $i < @levels; $i++) {
            if ($tname eq substr($levels[$i], 0, length $tname)) {
                $loglevel = 10 * $i + $tvalue;
                last;
            }
        }
    }
    if (!defined $loglevel) {
        $loglevel = $LOGLEVEL_ERROR;
        emsg "invalid --loglevel $orig_loglevel";
        pod2usage(2);
    }
}

# this means that plugins can be in included directories
push @INC, @$includes;

# determine all possible report types; a routine called "<rrr>_node" in the
# main module or in a plugin module
# XXX this will give "false positives" if any routines happen to be called
#     "<rrr>_node", e.g. there was an "unhide_node" routine
unshift @$plugins, 'main'; # avoids main being (too much of) a special case
my $reports = {};
foreach my $plugin (@$plugins) {
    if ($plugin ne 'main') {
        require qq{${plugin}.pm};
    }

    my $any = 0;
    foreach my $routine (util_module_routines($plugin)) {
        if ($routine =~ /^(.*?)_node$/ && $1 ne 'report') {
            $reports->{$1} = {
                init => util_module_routine($plugin, "$1\_init"),
                begin => util_module_routine($plugin, "$1\_begin"),
                node => util_module_routine($plugin, "$1\_node"),
                postpar => util_module_routine($plugin, "$1\_postpar"),
                post => util_module_routine($plugin, "$1\_post"),
                end => util_module_routine($plugin, "$1\_end")
            };
            $any = 1;
        }
    }
    if (!$any) {
        emsg "${plugin}.pm: plugin contains no report routines";
    }
}

unless (defined $reports->{$report}) {
    emsg "unsupported report format: $report";
    pod2usage(2);
}

if ($noparameters) {
    emsg "--noparameters not yet implemented";
    pod2usage(2);
}

if (@$ucprofiles && !@$dtprofiles) {
    emsg "--ucprofile requires --dtprofile to be specified";
    pod2usage(2);
}

if ($info) {
    imsg 'Author: ', $tool_author_only;
    imsg 'Date: ', $tool_vers_date_only, $tool_checked_out;
    imsg 'Id: ', $tool_id_only;
    exit(1);
}

# XXX as part of getting rid of xml2, require the xml report also to specify
#     --lastonly (need to check this doesn't break the xml report)
if ($report eq 'xml2') {
    emsg "the xml2 report is deprecated; use the xml report without ".
        "--lastonly to get the same effect";
}
if ($report eq 'xml' && $lastonly) {
    emsg "the xml report with --lastonly is deprecated and might not work";
}
if ($report eq 'xml' && !$lastonly) {
    $report = 'xml2';
}

if ($autodatatype) {
    emsg "--autodatatype is deprecated because it's set by default";
}

if ($noautomodel) {
    emsg "--noautomodel is deprecated; use --automodel instead";
}

if ($showreadonly) {
    emsg "--showreadonly is deprecated because it's enabled by default";
}

if ($ugly) {
    emsg "--ugly is deprecated; use --nohyphenate and/or --showsyntax";
    $nohyphenate = 1;
    $showsyntax = 1;
}

if ($warndupbibref) {
    emsg "--warndupbibref is deprecated; use --warnbibref";
    $warnbibref = 1;
}

if (defined $warnbibref && $nowarnbibref) {
    emsg "--nowarnbibref overrides --warnbibref";
}

if ($nowarnprofbadref) {
    emsg "--nowarnprofbadref is deprecated; it's no longer necessary";
}

if ($diffs) {
    $lastonly = 1;
    $showdiffs = 1;
}

if ($compare) {
    if (@ARGV != 2) {
        emsg "--compare requires exactly two input files";
        pod2usage(2);
    }
    $autobase = 1;
    $showdiffs = 1;
    $modifiedusesspec = 0 if $lastonly;
}

if (@$diffsexts == 0 || @$diffsexts > 2) {
    emsg "--diffsext must be specified either once or twice";
    pod2usage(2);
}

if ($report =~ /html(bbf|148)/) {
    $noautomodel = 1;
}

if ($outfile) {
    if (!open(STDOUT, ">", $outfile)) {
        die "can't create --outfile $outfile: $!";
    }
} else {
    w1msg "--outfile not specified; cannot check for references to ".
        "non-existent files" if $report eq 'htmlbbf';
    $tool_cmd_line .= ' ...';
}

my $samename = 0;
{
    my $seen = {};
    foreach my $path (@ARGV) {
        my ($vol, $dir, $file) = File::Spec->splitpath($path);
        $samename = 1 if $seen->{$file};
        $seen->{$file} = 1;
    }
}

*STDERR = *STDOUT if $report =~ /^(null|special)$/;

$marktemplates = '&&&&' if defined($marktemplates);

$warnbibref = 1 if defined($warnbibref) and !$warnbibref;
$warnbibref = 0 unless defined($warnbibref);
$warnbibref = -1 if $nowarnbibref;

$pedantic = 1 if defined($pedantic) and !$pedantic;
$pedantic = 0 unless defined($pedantic);

$verbose = 1 if defined($verbose) and !$verbose;
$verbose = 0 unless defined($verbose);

# quiet, pedantic and verbose are replaced by loglevel:
# - quiet    sets loglevel to LOGLEVEL_ERROR,  i.e. suppresses info messages
# - pedantic sets loglevel to LOGLEVEL_WARNING + pedantic - 1
# - verbose  sets loglevel to LOGLEVEL_DEBUG   + verbose  - 1
# then the variables are undefined to avoid inadvertent usage
if ($quiet) {
    # XXX this has been changed, because it's undesirable for --quiet to
    #     suppress warnings or file validation
    #$loglevel = $LOGLEVEL_ERROR;
    #undef $quiet;
}
if ($pedantic) {
    $loglevel = $LOGLEVEL_WARNING + $pedantic - 1;
    undef $pedantic;
}
if ($verbose) {
    $loglevel = $LOGLEVEL_DEBUG + $verbose - 1;
    undef $verbose;
}

# this used to be cleared if verbose, so now cleared if debug
$nocomments = 0 if $loglevel >= $LOGLEVEL_DEBUG;

# XXX upnpdm profiles are broken...
$noprofiles = 1 if $components || $upnpdm || @$dtprofiles;

# XXX load_catalog() works but there is no error checking?
{
    my $parser = XML::LibXML->new(line_numbers => 1);
    foreach my $catalog (@$catalogs) {
        my ($dir, $file) = find_file($catalog, '');
        if (!$dir) {
            emsg "XML catalog $file not found";
        } else {
            my $tfile = $dir ? File::Spec->catfile($dir, $file) : $file;
            d0msg "loading XML catalog $tfile";
            eval { $parser->load_catalog($tfile) };
            if ($@) {
                emsg $@;
            }
        }
    }
}

# configfile used to be set via $options->{configfile} but now can be set via
# $configfile; if both are set, the newer $configfile wins, but warn
if ($options->{configfile}) {
    if ($configfile) {
        emsg "both --option configfile and --configfile specified; ".
            "--configfile wins";
    } else {
        $configfile = $options->{configfile};
    }
}
$configfile = qq{$report.ini} unless $configfile;

$cwmppath .= qq{/} if $cwmppath && $cwmppath !~ /\/$/;
$trpage .= qq{/} if $trpage && $trpage !~ /\/$/;

# Globals.
our $first_comment = undef;
our $allfiles = [];
our $files2 = []; # like $files but has the same structure as $allfiles
our $specs = [];
# XXX for DT, lfile and lspec should be last processed DM file
#     (current workaround is to use same spec for DT and this DM)
our $pfile = ''; # last-but-one command-line-specified file
our $pspec = ''; # spec from last-but-one command-line-specified file
our $lfile = ''; # last command-line-specified file
our $lspec = ''; # spec from last command-line-specified file
our $files = {};
our $no_imports = 1;
our $imports = {}; # XXX not a good name, because it includes main file defns
our $imports_i = 0;
our $bibrefs = {};
our $objects = {};
our $parameters = {};
our $profiles = {};
our $anchors = {};
our $root = {file => '', spec => '', lspec => '', path => '', name => '',
            type => '', status => 'current', dynamic => 0};
our $highestMajor = 0;
our $highestMinor = 0;
our $previouspath = '';
our $autogenerated = ''; # is replaced later

our $range_for_type = {
    'int' => {min => -2147483648, max => 2147483647},
    'long' => {min => -9223372036854775808, max => 9223372036854775807},
    'unsignedInt' => {min => 0, max => 4294967295},
    'unsignedLong' => {min => 0, max => 18446744073709551615}
};

# File info from htmlbbf config file (declared here because it's used in some
# template expansions).
our $htmlbbf_info = {};

# Parse and expand a data model definition file.
# XXX also does minimal expansion of schema files
my $firstautomodel = undef;
sub expand_toplevel
{
    my ($file)= @_;

    (my $dir, $file, my $rpath) = find_file($file, '');

    # parse file
    my $toplevel = parse_file($dir, $file);
    return unless $toplevel;

    # for XSD files, just track the target namespace then return
    my $spec;
    my $appdate = util_appdate($toplevel);
    if ($file =~ /\.xsd$/) {
        my $targetNamespace = $toplevel->findvalue('@targetNamespace');
        my $hash = {name => $file, spec => $targetNamespace,
                    appdate => $appdate, schema => 1};
        push @$allfiles, $hash;
        push @$files2, $hash unless grep { $_->{name} eq $file} @$files2;
        return;
    }
    else {
        $spec = $toplevel->findvalue('@spec');
        my $description = $toplevel->findvalue('description');
        $description = undef unless $description;
        my @models = $toplevel->findnodes('model');
        my $hash = {name => $file, spec => $spec, appdate => $appdate,
                    description => $description, models => \@models};
        push @$allfiles, $hash;
        push @$files2, $hash unless grep { $_->{name} eq $file} @$files2;
    }

    # if one or more top-level file has the same name, use the final directory
    # component to differentiate them (this is common when comparing versions
    # of the same data model); this process isn't repeated recursively
    # XXX File::Spec likes to put trailing "/" characters on directory names,
    #     which requires a special case; hopefully this code is portable
    if ($samename && $dir) {
        my @tdirs = File::Spec->splitdir($dir);
        pop @tdirs if $tdirs[$#tdirs] eq '';
        my $tcomp = pop @tdirs;
        my $curdir = File::Spec->curdir();
        $file = File::Spec->catfile(($tcomp), $file) if $tcomp ne $curdir;
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

    # XXX experimentally add annotation (should perhaps use !!!annotation!!!
    #     to cause it to be highlighted); should do this everywhere and use a
    #     utility
    my $annotation = $toplevel->findvalue('annotation');
    $root->{description} .=
        (($root->{description} && $annotation) ? "\n" : "") . $annotation;

    # collect top-level item declarations (treat as though they were imported
    # from an external file; this avoids special cases)
    # XXX need to keep track of context in which the import was performed,
    #     so can reproduce import statements when generating XML
    foreach my $item ($toplevel->findnodes('dataType|component|model')) {
        my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');

        if ($element eq 'model' && !model_matches($name)) {
            d0msg "ignored model $name";
            next;
        }

        update_imports($file, $spec, $file, $spec, $element, $name, $name,
                       $item);
    }

    # expand nested items (context is a stack of nested component context)
    # XXX should be: description, import, dataType, bibliography, component,
    #     model
    my $context = [{dir => $dir, file => $file, spec => $spec,
                    lfile => $file, lspec => $spec,
                    path => '', name => ''}];

    foreach my $item
	($toplevel->findnodes('import|dataType|bibliography|model')) {
	my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');

        if ($element eq 'model' && !model_matches($name)) {
            d0msg "ignored model $name";
            next;
        }

	"expand_$element"->($context, $root, $item);
    }

    # if saw components but no model, auto-generate a model that references
    # each non-internal component once at the top level
    # XXX this duplicates some logic from expand_model_component
    my @comps =
        grep {$_->{element} eq 'component' &&
                  $_->{file} eq $file} @{$imports->{$file}->{imports}};
    my @models =
        grep {$_->{element} eq 'model' &&
                  $_->{file} eq $file} @{$imports->{$file}->{imports}};
    if ($automodel || (!$noautomodel && !@models && @comps)) {
        my $mname = $spec;
        # default automodel is just the last bit of the spec, e.g.
        # tr-262-1-0-0 (this is invalid per the schema)
        $mname =~ s/.*://;
        # if it matches the expected pattern, generate a valid name, e.g.
        # TR-262:1.0
        my ($xxnnn, $i, $a) = ($spec =~ /^.*:([^-]+-\d+)-(\d+)-(\d+)/);
        $xxnnn = uc $xxnnn if $xxnnn;
        $mname = qq{$xxnnn:$i.$a} if $xxnnn && defined $i && defined $a;
        $autogenerated = $mname;
        d0msg "auto-generating model: $mname";
        # XXX is there no way to pass arguments by keyword in perl?
        $i = 1 unless defined $i;
        $a = 0 unless defined $a;
        my $mref = undef;
        if (!defined $firstautomodel) {
            $firstautomodel = $i;
        } else {
            $mref = $mname;
            $mref =~ s/\d+$/$firstautomodel/;
        }
        my $nnode = add_model($context, $root, $mname, $mref, undef, undef,
            '', 'create', undef, $i, $a);
        foreach my $comp (@comps) {
            my $name = $comp->{name};
            my $component = $comp->{item};

            # XXX with the current set of documents, this does a good enough
            #     job (ignore Diffs because the usual pattern is that a new
            #     version of the component (in the same file) will use it
            next if $name =~ /Diffs$/;

            # ignore internal components on the same assumption as above, i.e.
            # that the component will be used below
            next if $name =~ /^_/;

            d0msg "referencing component: $name";
            foreach my $item ($component->findnodes('component|parameter|'.
                                                    'object|profile')) {
                my $element = $item->findvalue('local-name()');
                "expand_model_$element"->($context, $nnode, $nnode, $item);
            }
        }
    }
}

# "allfiles" comparison based on approval date (any files with unknown
# empty approval date will precede any with known approval date; but
# if no files have known approval date, the order will be unchanged)
sub allfiles_appdate_cmp
{
    my $ad = $a->{appdate};
    my $bd = $b->{appdate};

    return ($ad cmp $bd);
}

# Model name doesn't match --ignore
sub model_matches
{
    my ($name) = @_;

    # XXX was going to introduce this but it isn't so simple, e.g. for
    #     Device -> XXXDevice need to match both "Device" and "XXXDevice"
    #return 0 if $model && $name !~ /^$model/;

    return 0 if $ignore && $name =~ /^$ignore/;

    return 1;
}


# Expand a top-level import.
# XXX there must be scope for more code share with expand_toplevel
# XXX yes, in both cases should import all top-level items (dataType,
#     component, model) into the "main" namespace, unless there is a
#     conflict; explicitly imported symbols can be renamed locally
sub expand_import
{
    my ($context, $pnode, $import) = @_;

    $no_imports = 0;

    my $depth = @$context;

    my $cdir  = $context->[0]->{dir};
    my $cfile = $context->[0]->{file};
    my $cspec = $context->[0]->{spec};

    my $file = $import->findvalue('@file');
    my $spec = $import->findvalue('@spec');

    d1msg "expand_import file=$file spec=$spec";

    my $ofile = $file;
    (my $dir, $file, my $corr, my $rpath) = find_file($file, $cdir);

    my $tfile = $file;
    $file =~ s/\.xml//;

    w0msg "$cfile.xml: import $ofile: corrigendum number should " .
        "be omitted" if $corr && $depth == 1;

    # if one or more top-level file has the same name, use the final directory
    # component to differentiate them (this is common when comparing versions
    # of the same data model); this process isn't repeated recursively
    # XXX File::Spec likes to put trailing "/" characters on directory names,
    #     which requires a special case; hopefully this code is portable
    # XXX this code is duplicated from earlier; furthermore, it's a huge hack
    #     because the $samename criterion is based only on the command-line
    #     files; want a combination of this logic and use of $rpath
    if ($samename && $dir) {
        my @tdirs = File::Spec->splitdir($dir);
        pop @tdirs if $tdirs[$#tdirs] eq '';
        my $tcomp = pop @tdirs;
        my $curdir = File::Spec->curdir();
        $file = File::Spec->catfile(($tcomp), $file) if $tcomp ne $curdir;
    }

    # if already read file, just add the imports to the current namespace
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

        # XXX this is a first attempt at list names of components that are
        #     defined in referenced files but not in this file; I am in fact
        #     not convinced that this is worthwhile; note the hack to ignore
        #     XXXDiffs components (which should really be internal); also note
        #     that a given component name (different actual component) can
        #     exist in multiple files
        # XXX XXXDiffs are NOT internal, so the above hack is wrong!!
        my @comps;
        if ($depth == 2) {
            foreach my $comp (@{$imports->{$file}->{imports}}) {
                push(@comps, $comp->{name}) 
                    if $comp->{element} eq 'component' &&
                    $comp->{name} !~ /^_|Diffs$/;
            }
        }
        #emsg join(',', @comps) if @comps;
        return;
    }
    $files->{$file} = 1;

    return if $thisonly;

    # parse imported file
    my $toplevel = parse_file($dir, $tfile);
    return unless $toplevel;
    my $fspec = $toplevel->findvalue('@spec');
    push @$specs, $fspec unless grep {$_ eq $fspec} @$specs;

    # check spec (if supplied)
    $spec = $fspec unless $spec;
    my $trspec = $fspec;
    $trspec =~ s/:wt-/:tr-/;
    my $full_match = specs_match($spec, $fspec);
    my $trwt_mismatch = specs_match($spec, $trspec);
    if ($full_match) {
    } elsif ($trwt_mismatch && $spec =~ /:wt-/) {
        w0msg "$cfile.xml: import $ofile: referencing file's spec indicates ".
            "WT rather than TR (spec=$spec, fspec=$fspec, trspec=$trspec";
    } elsif ($trwt_mismatch) {
        w0msg "$cfile.xml: import $ofile: referenced file's spec indicates ".
            "that it's still a WT" unless $nowarnwtref;
    } else {
        w0msg "$cfile.xml: import $ofile: spec is $fspec (doesn't match $spec)";
    }

    # get description
    my $fdescription = $toplevel->findvalue('description');

    # collect top-level item declarations
    my @models = ();
    foreach my $item ($toplevel->findnodes('dataType|component|model')) {
        my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');
        my $ref = $item->findvalue('@base');
        # DO NOT default ref to name here; empty ref indicates an initial
        # definition of something!

        push @models, $item if $element eq 'model';
        
        update_imports($file, $fspec, $file, $fspec, $element, $name, $ref,
                       $item);
    }

    my $appdate = util_appdate($toplevel);
    push @$files2, {name => $tfile, spec => $fspec, appdate => $appdate,
                    description => $fdescription, models => \@models} unless
                        grep { $_->{name} eq $tfile} @$files2;

    unshift @$context, {dir => $dir, file => $file, spec => $fspec,
                        lfile => $file, lspec => $fspec,
                        path => '', name => ''};

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

        if ($element eq 'model' && !model_matches($name)) {
            d0msg "ignored model $name";
            next;
        }

        emsg "{$file}$ref: invalid import of internal $element"
            if $ref =~ /^_/;

        # XXX this logic is (originally) from expand_model_component
        my ($elem) = grep {$_->{element} eq $element && $_->{name} eq $ref}
        @{$imports->{$file}->{imports}};
        if (!$elem) {
            emsg "{$file}$ref: $element not found";
            next;
        }
        my $ddir  = $elem->{dir};
        my $dfile = $elem->{file};

        # find the actual element (first check whether we have already seen it)
        my ($delem) = grep {$_->{element} eq $element && $_->{name} eq $ref}
        @{$imports->{$dfile}->{imports}};
        my $fitem = $delem ? $delem->{item} : undef;
        if ($fitem) {
            d0msg "{$file}$ref: $element already found in $dfile";
        } elsif ($dfile eq $file) {
            ($fitem) = $toplevel->findnodes(qq{$element\[\@name="$ref"\]});
        } else {
            (my $ddir, $dfile, my $corr) = find_file($dfile.'.xml', $ddir);
            # XXX not sure that we want $depth here; we are already one level
            #     from when we were called
            w0msg "$file.xml: import $dfile.xml: corrigendum number " .
                "should be omitted" if $corr && $depth == 1;
            my $dtoplevel = parse_file($ddir, $dfile);
            next unless $dtoplevel;
            ($fitem) = $dtoplevel->findnodes(qq{$element\[\@name="$ref"\]});
        }
        emsg "{$file}$ref: $element not found in $dfile" unless $fitem;

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
    d1msg "update_imports: added $element {$file}$name$alias";
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
    # XXX this won't handle multiple sizes or ranges
    my $minLength = $dataType->findvalue('.//size/@minLength');
    my $maxLength = $dataType->findvalue('.//size/@maxLength');
    my $minInclusive = $dataType->findvalue('.//range/@minInclusive');
    my $maxInclusive = $dataType->findvalue('.//range/@maxInclusive');
    my $step = $dataType->findvalue('.//range/@step');
    my $values = $dataType->findnodes('string/enumeration');
    my $hasPattern = 0;
    if (!$values) {
        $values = $dataType->findnodes('string/pattern');
        $hasPattern = 1 if $values;
    }

    my $prim;
    foreach my $type (('base64', 'boolean', 'dateTime', 'hexBinary',
                       'int', 'long', 'string', 'unsignedInt',
                       'unsignedLong')) {
        if ($dataType->findnodes($type)) {
            $prim = $type;
            last;
        }
    }

    if (!$base && !$prim) {
        emsg "$name: data type is not derived from anything (string assumed)";
        $prim = 'string';
    }

    emsg "$name: data type derived from $base so cannot derive from $prim"
        if $base && $prim;

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $file, $spec);

    my $tprim = defined $prim ? $prim : "undef";
    d1msg "expand_dataType name=$name base=$base prim=$tprim";

    # XXX for now only replace description if data type is redefined
    my ($node) = grep {$_->{name} eq $name} @{$root->{dataTypes}};
    if ($node) {
        d0msg "$name: data type redefined (description replaced)";
        $node->{description} = $description;

    } else {
        # XXX syntax should really extend the syntax from the base type, and
        #     would check that it only ever narrowed the constraints
        my $syntax;

        $minLength = undef if $minLength eq '';
        $maxLength = undef if $maxLength eq '';
        if (defined $minLength || defined $maxLength) {
            push @{$syntax->{sizes}}, {minLength => $minLength,
                                       maxLength => $maxLength};
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

        # XXX this code is taken from expand_model_parameter()
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

            $access = 'readWrite' unless $access;
            $status = 'current' unless $status;
            $optional = 'false' unless $optional ne '';
            # don't default descact, so can tell whether it was specified

            $tvalues->{$value} = {access => $access, status => $status,
                                  optional => $optional,
                                  description => $description,
                                  descact => $descact, descdef => $descdef,
                                  facet => $facet,
                                  i => $i++};
        }
        $values = $tvalues;

        $node = {name => $name, base => $base, prim => $prim, spec => $spec,
                 status => $status, description => $description,
                 descact => $descact, descdef => $descdef, syntax => $syntax,
                 values => $values, specs => []};

        push @{$pnode->{dataTypes}}, $node;

        # even though it might not be used by a parameter, always regard a data
        # type that is defined in a file as being used by that file
        update_datatypes($name, $file, $spec);
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

    push @{$dataType->{specs}}, $spec unless
        grep {$_ eq $spec} @{$dataType->{specs}};

    # also mark the base type (recursively)
    update_datatypes($dataType->{base}, $file, $spec) if $dataType->{base};
}

# Expand a bibliography definition.
sub expand_bibliography
{
    my ($context, $pnode, $bibliography) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Lfile = $context->[0]->{lfile};
    my $Lspec = $context->[0]->{lspec};

    my $description = $bibliography->findvalue('description');
    my $descact = $bibliography->findvalue('description/@action');
    my $descdef = $bibliography->findnodes('description')->size();

    update_bibrefs($description, $file, $spec);

    d1msg "expand_bibliography";

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
                msg "W", "$id: duplicate bibref: {$file}$name"
                    if !$autobase && ($loglevel >= $LOGLEVEL_DEBUG ||
                                      $warnbibref > 0);
            } elsif ($dupref->{name} ne $name) {
                emsg "$id: ambiguous bibref: ".
                    "{$dupref->{file}}$dupref->{name}, {$file}$name";
            } else {
                msg "W", "$id: duplicate bibref: " .
                    "{$dupref->{file}}$dupref->{name}, {$file}$name"
                    if $loglevel >= $LOGLEVEL_DEBUG || $warnbibref > 0;
            }
        }

        d1msg "expand_bibliography_reference id=$id name=$name";

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
            msg "W", "$id: $file: replaced organization ".
                "\"$hash->{organization}\" with \"$bbf\""
                if $warnbibref > 1 || $loglevel >= $LOGLEVEL_DEBUG;
            $hash->{organization} = $bbf;
        }
        if ($hash->{category} =~ /^TR$/i) {
            msg "W", "$id: $file: replaced category ".
                "\"$hash->{category}\" with \"$tr\""
                if $warnbibref > 1 || $loglevel >= $LOGLEVEL_DEBUG;
            $hash->{category} = $tr;
        }

        # XXX check for missing category
        if ($id =~ /^TR/i && $name =~ /^TR/i &&
            $hash->{organization} eq $bbf && !$hash->{category}) {
            msg "W", "$id: $file: missing $bbf category (\"$tr\" assumed)"
                if $warnbibref > 1 || $loglevel >= $LOGLEVEL_DEBUG;
            $hash->{category} = $tr;
        }
        if ($id =~ /^RFC/i && $name =~ /^RFC/i &&
            $hash->{organization} eq 'IETF' && !$hash->{category}) {
             msg "W", "$id: $file: missing IETF category (\"RFC\" assumed)"
                if $warnbibref > 1 || $loglevel >= $LOGLEVEL_DEBUG;
            $hash->{category} = 'RFC';
        }

        # XXX could also check for missing date (etc)...

        # for TRs, don't want hyperlink, so can auto-generate the correct
        # hyperlink according to BBF conventions
        if ($hash->{organization} eq $bbf && $hash->{category} eq $tr) {
            if ($hash->{hyperlink}) {
                msg "W", "$id: $file: replaced deprecated $bbf $tr hyperlink"
                    if $warnbibref > 1 || $loglevel >= $LOGLEVEL_DEBUG;
            }
            my $h = $trpage;
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
                msg "W", "$id: $file: replaced deprecated IETF RFC hyperlink"
                    if $warnbibref > 1 || $loglevel >= $LOGLEVEL_DEBUG;
            }
            # XXX use id if it starts 'RFC' (case independently); if not, fall
            #     back on name (with whitespace removed)
            my $hname = ($id =~ /rfc/i) ? lc($id) : lc($name);
            $hname =~ s/\s//g;
            my $h = qq{http://tools.ietf.org/html/};
            $h .= $hname;
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
                    d0msg "$id: $key -> $hash->{$key}";
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
    d1msg Dumper($pnode->{bibliography});
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

    d1msg "expand_model name=$name ref=$ref";

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
            d0msg "converted to name=$name ref=$ref";
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
        push @{$nnode->{nodes}}, {mnode => $nnode, pnode => $nnode,
                                  type => 'profile', name => '',
                                  spec => $spec, file => $file,
                                  lspec => $Lspec, lfile => $Lfile};
    }
}

# Expand a data model component reference.
sub expand_model_component
{
    my ($context, $mnode, $pnode, $component) = @_;

    my $dir = $context->[0]->{dir};
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

    d1msg "expand_model_component path=$path ref=$name";

    # find component
    my ($comp) = grep {$_->{element} eq 'component' && $_->{name} eq $name}
    @{$imports->{$file}->{imports}};

    # check component is known
    if (!$comp) {
	emsg "{$file}$name: component not found (ignoring)" unless $thisonly;
	return;
    }
    $component = $comp->{item};
    if (!$component) {
	emsg "{$file}$name: component not found in $comp->{file} (ignoring)"
            unless $thisonly;
	return;
    }

    # find the file that actually defines the component (as opposed to just
    # having it in its namespace)
    while ($comp->{file} ne $file) {
        $dir  = $comp->{dir};
        $file = $comp->{file};
        $spec = $comp->{spec};
        my $ref = $comp->{ref};
        ($comp) = grep {$_->{element} eq 'component' && $_->{name} eq $ref}
        @{$imports->{$file}->{imports}};

        # XXX this should never happen but could if $imports was invalid
        if (!$comp) {
            emsg "internal error in expand_model_component (ignored)";
            last;
        }
    }

    # from now on, file and spec relate to the component
    # XXX this is ugly (want clean namespace handling)

    # check for recursive invocation
    if (grep {$_->{file} eq $file && $_->{name} eq $name} @$context) {
        my $active =
            join ', ', map {qq{{$_->{file}}$_->{name}}} reverse @$context;
        emsg "$name: recursive component reference: $active";
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
    unshift @$context, {dir => $dir, file => $file, spec => $spec, 
                        lfile => $Lfile, lspec => $Lspec,
                        path => $Path, name => $name,
                        previousParameter => $hash->{previousParameter},
                        previousObject => $hash->{previousObject},
                        previousProfile => $hash->{previousProfile}};

    #emsg "#### comp $name in $file; $Lfile";

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
    my $is_dt = ($ref ne '');
    $ref = $object->findvalue('@base') unless $ref;
    my $access = $object->findvalue('@access');
    my $minEntries = $object->findvalue('@minEntries');
    my $maxEntries = $object->findvalue('@maxEntries');
    my $numEntriesParameter = $object->findvalue('@numEntriesParameter');
    my $enableParameter = $object->findvalue('@enableParameter');
    my $status = $object->findvalue('@status');
    my $id = $object->findvalue('@id');
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

    d1msg "expand_model_object name=$name ref=$ref";

    # ignore if doesn't match object name pattern
    if ($objpat ne '' && $path !~ /$objpat/) {
	d1msg "\tdoesn't match object name pattern";
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
    #emsg "$previous" if $previous;

    # determine old name of this object; this is used to allow history tracking
    # across renames during data model development
    my $oldname = dmr_oldname($object);

    # create the new object
    my $nnode = add_object($context, $mnode, $pnode, $is_dt, $name, $ref, 0,
                           $access, $status, $description, $descact, $descdef,
                           $majorVersion, $minorVersion, $previous, $oldname);

    # XXX add some other stuff (really should be handled by add_object)
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

    # XXX hack the id
    $nnode->{id} = $id if $id;

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
    # XXX this logic means that --compare will show duplicates
    if ($uniqueKeys && @$uniqueKeys) {
        if (!@{$nnode->{uniqueKeys}}) {
            $nnode->{uniqueKeys} = $uniqueKeys;
        } else {
            d0msg "$path: uniqueKeys changed (new ones added)";
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
        #     warn at level > 2 because this means that something has been
        #     specified and then is changed later)
        d0msg "$path: $item: $node->{$item} -> $value"
            if $value ne '' && $value ne $node->{$item};
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

# Get old names from dmr:old*, if present
sub dmr_oldname
{
    my ($element) = @_;

    my $dmr = $element->lookupNamespaceURI('dmr');
    my @oldname;
    @oldname = $element->findnodes('@dmr:oldParameter|'.
                                   '@dmr:oldObject|'.
                                   '@dmr:oldProfile') if $dmr;
    
    return @oldname ? $oldname[0]->findvalue('.') : undef;
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
    my $is_dt = ($ref ne '');
    $ref = $parameter->findvalue('@base') unless $ref;
    my $access = $parameter->findvalue('@access');
    my $status = $parameter->findvalue('@status');
    my $activeNotify = $parameter->findvalue('@activeNotify');
    my $forcedInform = $parameter->findvalue('@forcedInform');
    my $id = $parameter->findvalue('@id');
    # XXX lots of hackery here...
    my @types = $parameter->findnodes('syntax/*');
    my $type = !@types ? undef : $types[0]->findvalue('local-name()') eq 'list' ? $types[1] : $types[0];
    # XXX this next line is presumably from the depths of history
    #my $values = $parameter->findnodes('syntax/enumeration/value');
    # we permit enumeration and pattern to match at any depth, because
    # they can be under "string" or "dataType"
    my $values = $parameter->findnodes('syntax//enumeration');
    my $hasPattern = 0;
    if (!$values) {
        $values = $parameter->findnodes('syntax//pattern');
        $hasPattern = 1 if $values;
    }
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

    $syntax->{hidden} = boolean($parameter->findvalue('syntax/@hidden')) if
        $parameter->findvalue('syntax/@hidden');
    $syntax->{command} = boolean($parameter->findvalue('syntax/@command')) if
        $parameter->findvalue('syntax/@command');
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

    #emsg Dumper($syntax) if $syntax->{reference};

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

        # access, status and optional defaults are applied below after checking
        # for derivation from a named data type

        $tvalues->{$value} = {access => $access, status => $status,
                              optional => $optional,
                              description => $description,
                              descact => $descact, descdef => $descdef,
                              facet => $facet,
                              i => $i++};
    }
    $values = $tvalues;

    d1msg "expand_model_parameter name=$name ref=$ref";

    # ignore if doesn't match write-only criterion
    if ($writonly && $access eq 'readOnly') {
	d1msg "\tdoesn't match write-only criterion";
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

    # if the parameter is of a named data type that has values, and there are
    # also local values, then check them
    # XXX this is very similar to the add_parameter() checks when parameter is
    #     modified, so they should both use the same logic (but they don't)
    # XXX the logic is simpler because it doesn't consider history, changes or
    #     --compare
    # XXX this means that it won't honor descact to (for example) append the
    #     a parameter-level enumeration description to a datatype-level
    #     enumeration description
    # XXX should also check other aspects, e.g. ranges, sizes etc
    if ($type eq 'dataType' && $syntax->{base}) {
        my $typeinfo = get_typeinfo($type, $syntax);
        my $dtname = $typeinfo->{value};
        my ($dtdef) = grep {$_->{name} eq $dtname} @{$root->{dataTypes}};
        my $cvalues = $dtdef->{values};
        if ($cvalues && %$cvalues) {
            my $visited = {};
            foreach my $value (sort {$values->{$a}->{i} <=>
                                         $values->{$b}->{i}} keys %$values) {
                $visited->{$value} = 1;

                my $cvalue = $cvalues->{$value};
                my $nvalue = $values->{$value};

                if (!defined $cvalue) {
                    d0msg "$path.$value: added";
                    next;
                }

                if (!$nvalue->{access}) {
                    $nvalue->{access} = $cvalue->{access};
                } elsif ($nvalue->{access} ne $cvalue->{access}) {
                    d0msg "$path.$value: access: $cvalue->{access} -> ".
                        "$nvalue->{access}";
                }
                if (!$nvalue->{status}) {
                    $nvalue->{status} = $cvalue->{status};
                } elsif ($nvalue->{status} ne $cvalue->{status}) {
                    $nvalue->{status} = 'DELETED'
                        if $nvalue->{status} eq 'deleted';
                    d0msg "$path.$value: status: $cvalue->{status} -> ".
                        "$nvalue->{status}";
                }
                if ($nvalue->{optional} eq '') {
                    $nvalue->{optional} = $cvalue->{optional};
                } elsif (boolean($nvalue->{optional}) ne
                    boolean($cvalue->{optional})) {
                    d0msg "$path.$value: optional: $cvalue->{optional} -> ".
                        "$nvalue->{optional}";
                }
                if (!$nvalue->{descdef}) {
                    $nvalue->{description} = $cvalue->{description};
                } else {
                    if ($nvalue->{description} eq $cvalue->{description}) {
                        $nvalue->{errors}->{samedesc} = $nvalue->{descact}
                        if !$autobase;
                    } else {
                        $nvalue->{errors}->{samedesc} = undef;
                        # XXX not if descact is prefix or append?
                        my $diffs = util_diffs($cvalue->{description},
                                               $nvalue->{description});
                        d0msg "$path.$value: description: changed";
                        d1msg $diffs;
                    }
                    $nvalue->{errors}->{baddescact} =
                        (!$autobase && (!$nvalue->{descact} ||
                                        $nvalue->{descact} eq 'create')) ?
                                        $nvalue->{descact} : undef;
                }
                # XXX need cleverer comparison
                if ($nvalue->{descact} && $nvalue->{descact} ne
                    $cvalue->{descact}){
                    d1msg "$path.$value: descact: $cvalue->{descact} -> ".
                        "$nvalue->{descact}";
                }
            }
            if (%$values) {
                my $dvalues = {};
                foreach my $value (
                    sort {$cvalues->{$a}->{i} <=>
                              $cvalues->{$b}->{i}} keys %$cvalues) {
                    if (!$visited->{$value}) {
                        w0msg "$path.$value: omitted; should instead " .
                            "mark as deprecated/obsoleted/deleted";
                    }
                }
            }
        }
    }

    # apply defaults for values' access, status and optional
    # don't default descact, so can tell whether it was specified
    foreach my $value (keys %$values) {
        $values->{$value}->{access} = 'readWrite'
            unless $values->{$value}->{access};
        $values->{$value}->{status} = 'current'
            unless $values->{$value}->{status};
        $values->{$value}->{optional} = 'false'
            unless $values->{$value}->{optional} ne '';
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

    # determine old name of this parameter; this is used to allow history
    # tracking across renames during data model development
    my $oldname = dmr_oldname($parameter);

    my $nnode = add_parameter($context, $mnode, $pnode, $is_dt, $name, $ref,
                              $type, $syntax, $access, $status, $description,
                              $descact, $descdef, $values, $default, $deftype,
                              $defstat, $majorVersion, $minorVersion,
                              $activeNotify, $forcedInform, $units, $previous,
                              $oldname);

    # XXX add some other stuff (really should be handled by add_parameter)
    check_and_update($nnode->{path}, $nnode, 'hasPattern', $hasPattern);

    # XXX hack the id
    $nnode->{id} = $id if $id;
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

    # XXX don't we have a utility for this?
    $extends =~ s/^\s*//g;
    $extends =~ s/\s*$//g;
    $extends =~ s/\s+/ /g;

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $file, $spec);

    $name = $base unless $name;

    # XXX want to do this consistently; really want to get defaults from
    #     somewhere (not hard-coded)
    $status = 'current' unless $status;

    d1msg "expand_model_profile name=$name base=$base extends=$extends";

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

    # XXX the above logic was breaking when generating "flattened" XML, so
    #     disable when base or extends is defined
    $previous = undef if $base || $extends;

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
        w0msg "$name: profile already defined" if
            !$autobase && $base && $name ne $base;
        # XXX profiles can never change, so just give up; BUT this means that
        #     we won't detect corrections, deprecations etc, so is not good
        #     enough
        #return;
    } else {
        # if base specified, find base profile
        my $baseprof;
        my $baseauto = 0;
        if ($base) {
            ($baseprof) = grep {
                $_->{type} eq 'profile' && $_->{name} eq $base;
            } @{$mnode->{nodes}};
            emsg "{$file}$base: profile not found (ignoring)"
                unless $baseprof;
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
            if ($baseprof) {
                $base = $baseprof->{name};
                $baseauto = 1;
            }
        }

        # if extends specified, find profiles that are being extended
        my $extendsprofs;
        if ($extends) {
            foreach my $extend (split /\s+/, $extends) {
                my ($extprof) = grep {
                    $_->{type} eq 'profile' && $_->{name} eq $extend;
                } @{$mnode->{nodes}};
                if (!$extprof) {
                    emsg "{$file}$extend: profile not found (ignoring)";
                } elsif ($base && $extend eq $base) {
                    $baseauto += 2;
                } else {
                    push @$extendsprofs, $extprof;
                }
            }
        }

        # baseauto = 0 if there are no problems with base and extends
        # baseauto = 1 if base was omitted and determined automatically
        # baseauto = 2 if base was specified and extends duplicates it
        # baseauto = 3 if base was specified incorrectly via extends
        if ($baseauto == 1) {
            w1msg "{$file}$name: base profile $base omitted and therefore " .
                "determined automatically";
        } elsif ($baseauto == 2) {
            w0msg "{$file}$name: base profile $base specified incorrectly " .
                "via both \"base\" and \"extends\"";
        } elsif ($baseauto == 3) {
            # XXX maybe this should be w0msg but that would generate warnings
            #     for existing data models that were not previously generated
            w1msg "{$file}$name: base profile $base specified incorrectly " .
                "via \"extends\"";
        }

        my ($mname_only, $mversion_major, $mversion_minor) =
            ($mnode->{name} =~ /([^:]*):(\d+)\.(\d+)/);

        $nnode = {mnode => $mnode, pnode => $mnode, path => $name,
                  name => $name, base => $base, extends => $extends,
                  file => $file, lfile => $Lfile, spec => $spec,
                  lspec => $Lspec, type => 'profile', access => '',
                  status => $status, description => $description,
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

        # XXX the above logic causes problems with "flattened" XML, in which
        #     profiles are already in the correct order so hack to preserve
        #     order in this case
        $index = @{$mnode->{nodes}} if $no_imports;

        splice @{$mnode->{nodes}}, $index, 0, $nnode;

        # defmodel is the model in which the profile was first defined
        # (usually this is the current model, but not if this XML was
        # flattened by the xml2 report, in which case it is indicated
        # by dmr:version
        my ($majorVersion, $minorVersion) = dmr_version($profile);
        my $version = defined $majorVersion && defined $minorVersion ?
            qq{$majorVersion.$minorVersion} : undef;
        my $defmodel = $version ? qq{$mname_only:$version} : $mnode->{name};
        my $fpath = util_full_path($nnode);
        $profiles->{$fpath}->{defmodel} = $defmodel;
    }

    # expand nested parameters and objects
    foreach my $item ($profile->findnodes('parameter|object')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_profile_$element"->($context, $mnode,
                                          $nnode, $nnode, $item);
    }
}

# Expand a data model profile object.
sub expand_model_profile_object
{
    my ($context, $mnode, $Pnode, $pnode, $object) = @_;

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

    d1msg "expand_model_profile_object path=$Path ref=$name";

    $name = $Path . $name if $Path;

    # these errors are reported by sanity_node
    my $fpath = util_full_path($Pnode, 1) . $name;
    unless (util_is_defined($objects, $fpath)) {
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
            d0msg "profile $Pnode->{name} can ignore object $name";
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
	$nnode = {mnode => $mnode, pnode => $pnode, path => $name,
                  name => $name, type => 'objectRef', access => $access,
                  status => $status, description => $description,
                  descact => $descact, descdef => $descdef, nodes => [],
                  baseobj => $baseobj};
        $push_deferred = 1;
    }

    # expand nested parameters and objects
    # XXX schema doesn't support nested objects
    # XXX this isn't quite right; should use profile equivalent of add_path()
    #     to create intervening nodes; currently top-level parameters are in
    #     the wrong place in the hierarchy
    foreach my $item ($object->findnodes('parameter|object')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_profile_$element"->($context, $mnode,
                                          $Pnode, $nnode, $item);
    }

    # suppress push if possible
    # XXX not supporting previousObject in profiles
    if ($can_ignore && $push_deferred && !@{$nnode->{nodes}}) {
        d0msg "profile $Pnode->{name} will ignore object $name";
    } elsif ($push_needed) {
        push(@{$pnode->{nodes}}, $nnode);
        my $fpath = util_full_path($Pnode);
        $profiles->{$fpath}->{$name} = $access;
    }
}

# Expand a data model profile parameter.
sub expand_model_profile_parameter
{
    my ($context, $mnode, $Pnode, $pnode, $parameter) = @_;

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

    d1msg "expand_model_profile_parameter path=$Path ref=$name";

    my $path = $pnode->{type} eq 'profile' ? $name : $pnode->{name}.$name;
    # special case for parameter at top level of a profile
    # XXX this is wrong; see comment in caller; but we live with it...
    $path = $Path . $path if $Path && $Pnode == $pnode;

    # these errors are reported by sanity_node
    my $fpath = util_full_path($Pnode, 1) . $path;
    unless (util_is_defined($parameters, $fpath)) {
        if ($noprofiles) {
        } elsif (!defined $Pnode->{errors}->{$path}) {
            $Pnode->{errors}->{$path} = {status => $status};
        } else {
            $Pnode->{errors}->{$path}->{status} = $status;
        }
        delete $Pnode->{errors}->{$path} if $status eq 'deleted';
        return;
    } elsif ($access ne 'readOnly' &&
             $parameters->{$fpath}->{access} eq 'readOnly') {
	emsg "profile $Pnode->{name} has invalid requirement ".
            "($access) for $path ($parameters->{$fpath}->{access})";
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
            d0msg "profile $Pnode->{name} ignoring parameter $path";
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
        $nnode = {mnode => $mnode, pnode => $pnode, path => $path,
                  name => $name, type => 'parameterRef', access => $access,
                  status => $status, description => $description,
                  descact => $descact, descdef => $descdef, nodes => []};

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
        my $fpath = util_full_path($Pnode);
        $profiles->{$fpath}->{$path} = $access;
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
    $majorVersion = 1 unless $majorVersion;
    $minorVersion = 0 unless $minorVersion;

    d1msg "add_model name=$name ref=$ref isService=$isService";

    # XXX monumental hack to allow vendor models to be derived from standard
    #     ones; assume that PrefixModel:a.b (name) is derived from Model:c.d
    #     (ref)
    my $tname = $name;
    my ($tname1, $tname2) = $name =~ /([^:]*):(.*)/;
    my ($tref1, $tref2) = $ref =~ /([^:]*):(.*)/;
    if ($tref1 && $tref1 ne $tname1 && $tname1 =~ /$tref1$/) {
        d0msg "hacked so model $name is derived from $ref";
        # PrefixModel:a.b -> Model:a.b (for the search below)
        $tname = qq{$tref1:$tname2};
    }

    # XXX extended hack also to assume that Anything_Model:a.b is derived
    #     from AnythingElse_Model:c.d, where the prefixes can themselves
    #     include underscores
    # XXX ignore referenced models whose names begin with underscores; see
    #     expand_model's "hack for modifying existing models" for why
    # XXX probably don't need the first hack if can assume there is always
    #     an underscore separator (which should be guaranteed by the X_VENDOR_
    #     prefix fule) ... but will leave it because it does no harm
    elsif ($ref && $ref !~ /^_/) {
        $tref1 = '' unless $tref1;
        my ($tname1pfx, $tname1sfx) = $tname1 =~ /(.*)_(.*)/;
        my ($tref1pfx, $tref1sfx) = $tref1 =~ /(.*)_(.*)/;
        if ($tname1sfx && $tref1sfx && $tname1sfx eq $tref1sfx) {
            d0msg "hacked so model $name is derived from $ref";
            # Prefix_Model:a.b -> Model:a.b (for the search below)
            $tname = qq{$tref1:$tname2};
        }
    }

    # if ref, find the referenced model
    # XXX minor version doesn't matter because search uses only the major
    #     version; all minor versions will already be sharing the same instance
    my $nnode;
    if ($ref) {
        my @match = grep {
            my ($a) = ($tname =~ /([^:]*:\d+)/);
            my ($b) = ($_->{name} =~ /([^:]*:\d+)/);
            $_->{type} eq 'model' &&
                defined($a) && defined($b) && $a eq $b;
        } @{$root->{nodes}};
        # there can't be more than one match
        if (@match) {
            $nnode = $match[0];
            d1msg "reusing node $nnode->{name}";
        } elsif (load_model($context, $file, $spec, $ref)) {
            @match = grep {
                my ($a) = ($tname =~ /([^:]*:\d+)/);
                my ($b) = ($_->{name} =~ /([^:]*:\d+)/);
                $_->{type} eq 'model' &&
                    defined($a) && defined($b) && $a eq $b;
            } @{$root->{nodes}};
            $nnode = $match[0];
            d0msg "{$file}$ref: model loaded";
        } else {
            # XXX if not found, for now auto-create it
            emsg "{$file}$ref: model not found (auto-creating)";
        }
    }

    if ($nnode) {
        # cache current node contents
        my $cnode = util_copy($nnode, ['history', 'nodes', 'pnode', 'mnode']);

        # indicate that model was previously known (report might need to
        # use this info)
        $nnode->{history} = [] unless defined $nnode->{history};

        # XXX want similar "changed" logic to objects and parameters?

        # XXX note that this always renames the model to the latest version
        #     (past names are stored in the history)
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
                d0msg "$name: description: changed";
                $nnode->{description} = $description;
            }
            my $tdescact = util_default($descact);
            w0msg "$name: invalid description action: $tdescact"
                if !$autobase && (!$descact || $descact eq 'create');
        }
        # XXX need cleverer comparison
        if ($descact && $descact ne $nnode->{descact}) {
            d1msg "$name: descact: $nnode->{descact} -> $descact";
            $nnode->{descact} = $descact;
        }

        # sub-tree is hidden (i.e. not reported) unless nodes within it are
        # referenced, at which point they and their parents are un-hidden
        # XXX suppress until sort out the fact that models defined in files
        #     specified on the command line should not be hidden
        # XXX this conditional restore is for DT and relies on the fact that
        #     name and ref will be same for DT (owing to hack in the caller)
        hide_subtree($nnode) if $name eq $ref;
        unhide_subtree($nnode);

        # retain info from previous versions
        unshift @{$nnode->{history}}, $cnode;
    } else {
        emsg "unnamed model (after $previouspath)" unless $name;
        w0msg "$name: invalid description action: $descact"
            if !$autobase && $descact && $descact ne 'create';
        my $dynamic = $pnode->{dynamic};
        # XXX experimental; may break stuff? YEP!
        #my $path = $isService ? '.' : '';
        my $path = '';
	$nnode = {pnode => $pnode, oname => $name, name => $name,
                  path => $path, file => $file, spec => $spec,
                  type => 'model', access => '', isService => $isService,
                  status => $status, description => $description,
                  descact => $descact, descdef => $descdef, default => undef,
                  dynamic => $dynamic, majorVersion => $majorVersion,
                  minorVersion => $minorVersion, nodes => [],
                  history => undef};
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
        my $dir  = $model->{dir};
        my $file = $model->{file};
        my $spec = $model->{spec};
        my $item = $model->{item};
        unshift @$context, {dir => $dir, file => $file, spec => $spec,
                            lfile => $file, lspec => $spec,
                            path => '', name => ''};

        #emsg "#### modl $ref in $file; $file";

        expand_model($context, $root, $item) if $item;
        shift @$context;
    }

    # XXX need to check proper failure criteria
    return 1;
}

# Hide a sub-tree.
sub hide_subtree
{
    my ($node, $ponly) = @_;

    #d0msg "hide_subtree: $node->{path}" if $node->{path} =~ /\.$/;

    unless ($node->{hidden}) {
        d1msg "hiding $node->{type} $node->{name}";
        $node->{hidden} = 1;
    }

    foreach my $child (@{$node->{nodes}}) {
        my $type = $child->{type};
        hide_subtree($child) unless $ponly &&
            $type =~ /^(model|object|profile|parameterRef|objectRef)$/;
    }
}

# Un-hide a node and its ancestors.
sub unhide_subtree
{
    my ($node) = @_;

    if ($node->{hidden}) {
        d1msg "un-hiding $node->{type} $node->{name}";
        $node->{hidden} = 0;
    }

    unhide_subtree($node->{pnode}) if $node->{pnode};
}

# Helper that, given a path, creates any intervening objects (if $return_last
# is true, doesn't create last component, but instead returns it)
# XXX want an indication that an object was created via add_path, so that all
#     values when it is next encountered will be used, e.g. "access"
sub add_path
{
    my ($context, $mnode, $pnode, $name, $return_last) = @_;

    d1msg "add_path name=$pnode->{path}$name";

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
	    $pnode = add_object($context, $mnode, $pnode, 0, '', $comps[$i],1);
	}
    }

    return ($pnode, $last);
}

# Helper to add an object if it doesn't already exist (if it does exist then
# nothing in the new object can conflict with anything in the old)
sub add_object
{
    my ($context, $mnode, $pnode, $is_dt, $name, $ref, $auto, $access, $status,
        $description, $descact, $descdef, $majorVersion, $minorVersion,
        $previous, $oldname) = @_;

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

    # use oldname as fallback for ref when comparing
    # XXX should this be autobase rather than compare?
    $ref = $oldname if $compare && !$ref && $oldname;

    my $path = $pnode->{path} . ($ref ? $ref : $name);

    msg "D", "add_object is_dt=$is_dt name=$name ref=$ref auto=$auto ".
        "spec=$spec" if $loglevel >= $LOGLEVEL_DEBUG + 1 ||
        ($debugpath && $path =~ /$debugpath/);

    # if ref, find the referenced object
    my $nnode;
    if ($ref) {
        my @match = grep {!util_is_deleted($_) &&
                              $_->{name} eq $ref} @{$pnode->{nodes}};
        if (@match) {
            $nnode = $match[0];
            unhide_subtree($nnode);
        } else {
            # XXX if not found, for now auto-create it
            emsg "$path: object not found (auto-creating)" if !$automodel;
            $name = $ref;
            $auto = 1;
        }
    } elsif ($name) {
        my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
        # XXX should this be unconditional?
        # XXX sometimes don't want report (need finer reporting control)
	$nnode = $match[0];
        if (@match && !$autobase && !$nnode->{hidden}) {
            msg "W", "$path: object already defined (new one ignored)" if
                $loglevel >= $LOGLEVEL_DEBUG || (!$nowarnredef && !$automodel);
            return $nnode;
        }
        # XXX this puts the replacement object in the same place as the orig
        $previous = $nnode->{path} if $nnode && $nnode->{hidden};
    }

    if ($nnode && !$nnode->{hidden}) {
	# if auto, nothing more to be done (covers the case where are
        # traversing down the path of an existing object)
        # XXX it's important to do this before setting the history
        # XXX recent change to move before undefine "changed"
	return $nnode if $auto;

        # XXX hack for DT; doing it unconditionally, although there is
        #     probably a reason why this isn't normally done!
        $nnode->{changed} = undef;

        # cache current node contents
        my $cnode = util_copy($nnode, ['history', 'nodes', 'pnode', 'mnode']);

        # indicate that object was previously known (report might need to
        # use this info)
        $nnode->{history} = [] unless defined $nnode->{history};

        # XXX if both name and ref are defined, this is a rename operation
        # XXX what if the new object has a different parent?
        # XXX what if the new-named object already exists?
        # XXX what are the implications for history?
        # XXX should this be marked as a change? yes
        if ($name && $ref) {
            my $fpath = util_full_path($nnode);
            $objects->{$fpath} = undef;
            $path = $pnode->{path} . $name;
            $nnode->{path} = $path;
            $nnode->{name} = $name;
            $fpath = util_full_path($nnode);
            $objects->{$fpath} = $nnode;
            # XXX this does only half the job; should build the objects and
            #     parameters hashes after the tree has been built
            # XXX should also avoid nodes knowing their path names
            foreach my $tnode (@{$nnode->{nodes}}) {
                if ($tnode->{type} ne 'object') {
                    my $opath = $tnode->{path};
                    my $fopath = util_full_path($tnode);
                    my $tpath = $path . $tnode->{name};
                    $tnode->{path} = $tpath;
                    my $ftpath = util_full_path($tnode);
                    $parameters->{$fopath} = undef;
                    $parameters->{$ftpath} = $tnode;
                }
            }
            d0msg "$path: renamed from $ref";
        }

        # when an object is modified, its last spec (lspec) and modified spec
        # (mspec) are updated
        my $changed = {};
 
        # XXX should use a utility routine for this change checking
        if ($access ne $nnode->{access}) {
            d0msg "$path: access: $nnode->{access} -> $access";
            $nnode->{access} = $access;
            $changed->{access} = 1;
        }
        if ($status ne $nnode->{status}) {
            d0msg "$path: status: $nnode->{status} -> $status";
            $nnode->{status} = $status;
            $changed->{status} = 1;
            hide_subtree($nnode) if !$compare && util_is_deleted($nnode);
        }
        if ($description) {
            if ($description eq $nnode->{description}) {
                $nnode->{errors}->{samedesc} = $descact if !$autobase;
            } else {
                $nnode->{errors}->{samedesc} = undef;
                # XXX not if descact is prefix or append?
                my $diffs = util_diffs($nnode->{description}, $description);
                d0msg "$path: description: changed";
                d1msg $diffs;
                $nnode->{description} = $description;
                $changed->{description} = $diffs;
            }
            $nnode->{errors}->{baddescact} =
                (!$autobase && (!$descact || $descact eq 'create')) ?
                $descact : undef;
        }
        # XXX need cleverer comparison
        if ($descact && $descact ne $nnode->{descact}) {
            d1msg "$path: descact: $nnode->{descact} -> $descact";
            $nnode->{descact} = $descact;
        }
        if (($pnode->{dynamic} || $nnode->{access} ne 'readOnly') !=
            $nnode->{dynamic}) {
            d0msg "$path: dynamic: $nnode->{dynamic} -> $pnode->{dynamic}";
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
        emsg "unnamed object (after $previouspath)" unless $name;
        w0msg "$name: invalid description action: $descact"
            if !$autobase && $descact && $descact ne 'create';

        # XXX this is still how we're handling the version number...
	$majorVersion = $mnode->{majorVersion} unless defined $majorVersion;
	$minorVersion = $mnode->{minorVersion} unless defined $minorVersion;

        d0msg "$path: added"
            if $mnode->{history} && @{$mnode->{history}} && !$auto;

        mark_changed($pnode, $Lfile, $Lspec);
        
        my $dynamic = $pnode->{dynamic} || $access ne 'readOnly';

	$nnode = {mnode => $mnode, pnode => $pnode, name => $name,
                  path => $path, file => $file, lfile => $Lfile,
                  sfile => $Lfile, spec => $spec, lspec => $Lspec,
                  mspec => $spec, type => 'object', auto => $auto,
                  access => $access, status => $status,
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
        my $fpath = util_full_path($nnode);
	$objects->{$fpath} = $nnode;
    }

    $nnode->{is_dt} = $is_dt;

    msg "D", Dumper(util_copy($nnode, ['nodes', 'pnode', 'mnode']))
        if $debugpath && $path =~ /$debugpath/;

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
    my ($context, $mnode, $pnode, $is_dt, $name, $ref, $type, $syntax, $access,
        $status, $description, $descact, $descdef, $values, $default, $deftype,
        $defstat, $majorVersion, $minorVersion, $activeNotify, $forcedInform,
        $units, $previous, $oldname)
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

    # use oldname as fallback for ref when comparing
    # XXX should this be autobase rather than compare?
    $ref = $oldname if $compare && !$ref && $oldname;

    my $path = $pnode->{path} . ($ref ? $ref : $name);
    my $auto = 0;

    msg "D", "add_parameter is_dt=$is_dt, name=$name ref=$ref" if
        $loglevel >= $LOGLEVEL_DEBUG + 1 ||
        ($debugpath && $path =~ /$debugpath/);

    # if ref, find the referenced parameter
    my $nnode;
    if ($ref) {
        my @match = grep {!util_is_deleted($_) &&
                              $_->{name} eq $ref} @{$pnode->{nodes}};
        if (@match) {
            $nnode = $match[0];
            unhide_subtree($nnode);
        } else {
            # XXX if not found, for now auto-create it
            emsg "$path: parameter not found (auto-creating)" if !$automodel;
            $name = $ref;
            $auto = 1;
        }
    } elsif ($name) {
        my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
        # XXX should this be unconditional?
        # XXX sometimes don't want report (need finer reporting control)
	$nnode = $match[0];
        if (@match && !$autobase && !$nnode->{hidden}) {
            msg "W", "$path: parameter already defined (new one ignored)" if
                $loglevel >= $LOGLEVEL_DEBUG || (!$nowarnredef && !$automodel);
            return $nnode;
        }
        # XXX this puts the replacement object in the same place as the orig
        $previous = $nnode->{name} if $nnode && $nnode->{hidden};
    }

    # XXX should maybe allow name to include an object spec; could call
    #     add_path on it (would like to know if any object in the path didn't
    #     already exist)

    if ($nnode && !$nnode->{hidden}) {
        # XXX hack for DT; doing it unconditionally, although there is
        #     probably a reason why this isn't normally done!
        $nnode->{changed} = undef;

        # cache current node contents
        my $cnode = util_copy($nnode, ['history', 'nodes', 'pnode', 'mnode',
                                       'table']);

        # indicate that parameter was previously known (report might need to
        # use this info)
        $nnode->{history} = [] unless defined $nnode->{history};

        # XXX if both name and ref are defined, this is a rename operation
        # XXX what if the new parameter has a different parent?
        # XXX what if the new-named parameter already exists?
        # XXX what are the implications for history?
        # XXX should this be marked as a change? yes
        if ($name && $ref) {
            my $fpath = util_full_path($nnode);
            $parameters->{$fpath} = undef;
            $path = $pnode->{path} . $name;
            $nnode->{path} = $path;
            $nnode->{name} = $name;
            $fpath = util_full_path($nnode);
            $parameters->{$fpath} = $nnode;
            d0msg "$path: renamed from $ref";
        }

        # XXX this isn't quite right... there is no inheritance except for
        #     the description (also, it's incomplete)

        # when a parameter is modified, its and its parent's last spec
        # (lspec) is updated (and its mspec is modified)
        my $changed = {};

        if ($access ne $nnode->{access}) {
            d0msg "$path: access: $nnode->{access} -> $access";
            $nnode->{access} = $access;
            $changed->{access} = 1;
        }
        if ($status ne $nnode->{status}) {
            d0msg "$path: status: $nnode->{status} -> $status";
            $nnode->{status} = $status;
            $changed->{status} = 1;
            hide_subtree($nnode) if !$compare && util_is_deleted($nnode);
        }
        my $tactiveNotify = $activeNotify;
        $tactiveNotify =~ s/will/can/;
        if ($tactiveNotify ne $nnode->{activeNotify}) {
            d0msg "$path: activeNotify: $nnode->{activeNotify} -> " .
                "$activeNotify";
            $nnode->{activeNotify} = $activeNotify;
            $changed->{activeNotify} = 1;
        }
        if ($forcedInform &&
            boolean($forcedInform) ne boolean($nnode->{forcedInform})) {
            d0msg "$path: forcedInform: $nnode->{forcedInform} -> " .
                "$forcedInform";
            $nnode->{forcedInform} = $forcedInform;
            $changed->{forcedInform} = 1;
        }
        if ($description) {
            if ($description eq $nnode->{description}) {
                $nnode->{errors}->{samedesc} = $descact if !$autobase;
            } else {
                $nnode->{errors}->{samedesc} = undef;
                # XXX not if descact is prefix or append?
                my $diffs = util_diffs($nnode->{description}, $description);
                d0msg "$path: description: changed";
                d1msg $diffs;
                $nnode->{description} = $description;
                $changed->{description} = $diffs;
            }
            $nnode->{errors}->{baddescact} = 
                (!$autobase && (!$descact || $descact eq 'create')) ?
                $descact : undef;
        }
        # XXX need cleverer comparison
        if ($descact && $descact ne $nnode->{descact}) {
            d1msg "$path: descact: $nnode->{descact} -> $descact";
            $nnode->{descact} = $descact;
        }
        if ($type && $type ne $nnode->{type}) {
            # XXX changed type is usually an error, but not necessarily if the
            #     new type is 'dataType' (need to check hierarchy)
            d0msg "$path: type: $nnode->{type} -> $type"
                if $type ne 'dataType';
            # XXX special case: if type changed to string, discard ranges
            #     (could take this further... but this case arose!)
            if ($type eq 'string' && $nnode->{syntax}->{ranges}) {
                d0msg "$path: discarding existing ranges";
                $nnode->{syntax}->{ranges} = undef;
            }
            # XXX special case: if type changed to string, discard dataType
            # XXX this should be unconditional warning (unless suppressed)?
            if ($type eq 'string' &&
                ($nnode->{syntax}->{ref} || $nnode->{syntax}->{base})) {
                d0msg "$path: discarding base/ref";
                $nnode->{syntax}->{ref} = $nnode->{syntax}->{base} = undef;
            }
            # XXX special case: if type changed to dataType, discard sizes and
            #     ranges
            if ($type eq 'dataType' && $nnode->{syntax}->{sizes}) {
                d0msg "$path: discarding existing sizes";
                $nnode->{syntax}->{sizes} = undef;
            }
            if ($type eq 'dataType' && $nnode->{syntax}->{ranges}) {
                d0msg "$path: discarding existing ranges";
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
                if (!$is_dt) {
                    d0msg "$path.$value: added";
                    $changed->{values}->{$value}->{added} = 1;
                } else {
                    emsg "$path.$value: can't add enumerated value to DT ".
                        "instance";
                }
                next;
            }

            unshift @{$cvalue->{history}}, util_copy($cvalue, ['history']);
            $values->{$value}->{history} = $cvalue->{history};
            
            # XXX these access, status and optional checks are not as good
            #     as the checks in expand_model_parameter() that compare
            #     values against those from named data types; the trouble
            #     is that they have already been defaulted, so we can't
            #     distinguish "absent" and "default" ("absent" should be
            #     interpreted as "no change")
            if ($nvalue->{access} ne $cvalue->{access}) {
                d0msg "$path.$value: access: $cvalue->{access} -> ".
                    "$nvalue->{access}";
                $changed->{values}->{$value}->{access} = 1;
            }
            if ($nvalue->{status} ne $cvalue->{status}) {
                d0msg "$path.$value: status: $cvalue->{status} -> ".
                    "$nvalue->{status}";
                $changed->{values}->{$value}->{status} = 1;
            }
            if (boolean($nvalue->{optional}) ne boolean($cvalue->{optional})) {
                d0msg "$path.$value: optional: $cvalue->{optional} -> ".
                    "$nvalue->{optional}";
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
                    # XXX not if descact is prefix or append?
                    my $diffs = util_diffs($cvalue->{description},
                                           $nvalue->{description});
                    d0msg "$path.$value: description: changed";
                    d1msg $diffs;
                    $changed->{values}->{$value}->{description} = $diffs;
                }
                $nvalue->{errors}->{baddescact} =
                    (!$autobase &&
                    (!$nvalue->{descact} || $nvalue->{descact} eq 'create')) ?
                    $nvalue->{descact} : undef;
            }
            # XXX need cleverer comparison
            if ($nvalue->{descact} && $nvalue->{descact} ne $cvalue->{descact}){
                d1msg "$path.$value: descact: $cvalue->{descact} -> ".
                    "$nvalue->{descact}";
            }
        }
        if (%$values) {
            my $dvalues = {};
            foreach my $value (sort {$cvalues->{$a}->{i} <=>
                                         $cvalues->{$b}->{i}} keys %$cvalues) {
                if (!$visited->{$value}) {
                    if (!$compare) {
                        w0msg "$path.$value: omitted; should instead mark as ".
                            "deprecated/obsoleted/deleted" if !$is_dt;
                    } else {
                        d0msg "$path.$value: deleted";
                        $changed->{values}->{$value}->{status} = 1;
                        $dvalues->{$value} = $cvalues->{$value};
                        $dvalues->{$value}->{status} = 'deleted';
                    }
                }
            }

            $nnode->{values} = $values;

            # XXX if --compare, rewrite the values with the deleted ones at
            #     the beginning (should have single set of logic here)
            if ($compare) {
                $nnode->{values} = {};
                my $i = 0;
                foreach my $value (
                    sort {$dvalues->{$a}->{i} <=>
                              $dvalues->{$b}->{i}} keys %$dvalues) {
                    $nnode->{values}->{$value} = $dvalues->{$value};
                    $nnode->{values}->{$value}->{i} = $i++
                }
                foreach my $value (
                    sort {$values->{$a}->{i} <=>
                              $values->{$b}->{i}} keys %$values) {
                    $nnode->{values}->{$value} = $values->{$value};
                    $nnode->{values}->{$value}->{i} = $i++
                }                
            }
        }
        #emsg Dumper($nnode->{values});
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
                    d0msg "$path: $key: changed";
                    #d0msg Dumper($value);
                    #d0msg Dumper($nnode->{syntax}->{$key});
                    $nnode->{syntax}->{$key} = $value;
                    $changed->{syntax}->{$key} = 1;
                }
            } elsif ($value ne '' && (!defined $nnode->{syntax}->{$key} ||
                                      $value ne $nnode->{syntax}->{$key})) {
                # XXX special case: if reference changes from undefined to
                #     enumerationRef, discard existing enumerations
                if ($key eq 'reference' && !defined($nnode->{syntax}->{$key})
                    && $value eq 'enumerationRef') {
                    d0msg "$path: discarding existing enumerations";
                    $nnode->{values} = undef;
                }
                d0msg "$path: $key: $old -> $value";
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
            d0msg "$path: units: $old -> $units";
            $nnode->{units} = $units;
            $changed->{units} = 1;
        }
        # XXX this is a special case for deleting list facets
        if ($nnode->{syntax}->{list} && $nnode->{syntax}->{liststatus} &&
            $nnode->{syntax}->{liststatus} eq 'deleted') {
            d0msg "$path: list: $nnode->{syntax}->{list} -> <deleted>";
            undef $nnode->{syntax}->{list};
            $changed->{syntax}->{list} = 1;
        }
        if (defined $default &&
            (!defined $nnode->{default} || $default ne $nnode->{default})) {
            my $old = defined $nnode->{default} ? $nnode->{default} : '<none>';
            my $new = defined $default ? $default : '<none>';
            d0msg "$path: default: $old -> $new";
            $nnode->{default} = $default;
            $changed->{default} = 1;
        }
        if (defined $default && $deftype ne $nnode->{deftype}) {
            d0msg "$path: deftype: $nnode->{deftype} -> $deftype";
            $nnode->{deftype} = $deftype;
            # note that this marks default, not deftype, as changed
            $changed->{default} = 1;
        }
        # to remove a default, status (defstat) is set to "deleted" (default
        # will always be defined, because the value attribute is mandatory
        if (defined $default && $defstat ne $nnode->{defstat}) {
            d0msg "$path: defstat: $nnode->{defstat} -> $defstat";
            $nnode->{defstat} = $defstat;
            # note that this marks default, not defstat, as changed
            $changed->{default} = 1;
        }
        # or, if $autobase (so not $ref), it was present and is no longer
        if (!$ref && defined $nnode->{default} && !defined $default) {
            d0msg "$path: default: deleted";
            $nnode->{defstat} = 'deleted';
            $changed->{default} = 1;
        }
        if ($pnode->{dynamic} != $nnode->{dynamic}) {
            d0msg "$path: dynamic: $nnode->{dynamic} -> $pnode->{dynamic}";
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
        emsg "$path: unnamed parameter" unless $name;
        emsg "$path: untyped parameter" unless $type || $auto;
        w0msg "$path: invalid description action: $descact"
            if !$autobase && $descact && $descact ne 'create';

        # XXX this is still how we're handling the version number...
	$majorVersion = $mnode->{majorVersion} unless defined $majorVersion;
	$minorVersion = $mnode->{minorVersion} unless defined $minorVersion;

        d0msg "$path: added"
            if $mnode->{history} && @{$mnode->{history}} && !$auto;

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
        #    d0msg "$path: removing default value";
        #}

	$nnode = {mnode => $mnode, pnode => $pnode, name => $name,
                  path => $path, file => $file, lfile => $Lfile,
                  sfile => $Lfile, spec => $spec, lspec => $Lspec,
                  mspec => $spec, type => $type, syntax => $syntax,
                  access => $access, status => $status,
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
        my $fpath = util_full_path($nnode);
	$parameters->{$fpath} = $nnode;
    }

    update_datatypes($syntax->{ref}, $file, $spec)
        if $type eq 'dataType' && $syntax->{ref};

    $nnode->{is_dt} = $is_dt;

    msg "D", Dumper(util_copy($nnode, ['nodes', 'pnode', 'mnode', 'table']))
        if $debugpath && $path =~ /$debugpath/;

    return $nnode;
}

# Update list of bibrefs that are actually used (each entry is an array of the
# specs that use the bibref)
# XXX this doesn't cope with the case where a bibref is used and then the
#     parameter description is updated so it is no longer used; this is harder
sub update_bibrefs
{
    my ($value, $file, $spec) = @_;

    my @ids = ($value =~ /\{\{bibref\|([^\|\}]+)/g);
    foreach my $id (@ids) {
        d1msg "marking bibref $id used (file=$file, spec=$spec)";
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

# Determine whether a parameter specifies a maximum length
sub has_maxlength
{
    my ($syntax) = @_;

    foreach my $size (@{$syntax->{listSizes}}) {
        return 1 if $size->{maxLength};
    }

    foreach my $size (@{$syntax->{sizes}}) {
        return 1 if $size->{maxLength};
    }

    return 0;
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
        return 0 if $value !~ /^(-?\d+)$/;
        return 0 if $value < $range_for_type->{int}->{min};
        return 0 if $value > $range_for_type->{int}->{max};
        return 1;

    } elsif ($primtype eq 'long') {
        return 0 if $value !~ /^(-?\d+)$/;
        return 0 if $value < $range_for_type->{long}->{min};
        return 0 if $value > $range_for_type->{long}->{max};
        return 1;

    } elsif ($primtype eq 'unsignedInt') {
        return 0 if $value !~ /^(\d+)$/;
        return 0 if $value < $range_for_type->{unsignedInt}->{min};
        return 0 if $value > $range_for_type->{unsignedInt}->{max};
        return 1;

    } elsif ($primtype eq 'unsignedLong') {
        return 0 if $value !~ /^(\d+)$/;
        return 0 if $value < $range_for_type->{unsignedLong}->{min};
        return 0 if $value > $range_for_type->{unsignedLong}->{max};
        return 1;

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

# Determine whether ranges are valid; return
# * 0 if invalid
# * 1 if valid and sensible
# * 2 if valid but ranges cover the full numeric range (so are unnecessary)
# * 3 if valid but ranges overlap
sub valid_ranges
{
    my ($node) = @_;

    my $type = $node->{type};
    my $syntax = $node->{syntax};
    my $ranges = $syntax->{ranges};

    return 1 unless defined $ranges && @$ranges;

    # determine base data type
    my $typeinfo = get_typeinfo($type, $syntax);
    my ($primtype, $dataType) = ($typeinfo->{value}, $typeinfo->{dataType});

    $primtype = base_type($primtype, 1) if $dataType;

    # XXX if range for type is undefined, something is wrong; most likely,
    #     there is a named data type that is non-numeric but has a range;
    #     quietly ignore such cases
    my $rfort = $range_for_type->{$primtype};
    return 1 unless defined $rfort;

    # ensure that both ends of each range are defined
    my $definedranges = [];
    foreach my $range (@$ranges) {
        my $minval = $range->{minInclusive};
        my $maxval = $range->{maxInclusive};
        my $step = $range->{step};

        return 0 if defined($minval) && !valid_value($node, $minval, 1);
        return 0 if defined($maxval) && !valid_value($node, $maxval, 1);
        return 0 if defined($step)   && !valid_value($node, $step,   1);

        $minval = $range_for_type->{$primtype}->{min} unless defined $minval;
        $maxval = $range_for_type->{$primtype}->{max} unless defined $maxval;
        $step = 1 unless defined $step;

        push @$definedranges, {minInclusive => $minval,
                               maxInclusive => $maxval, step => $step};
    }

    # sort ranges by minInclusive then maxInclusive
    my @sortedranges = sort {
        $a->{minInclusive} != $b->{minInclusive} ?
            $a->{minInclusive} <=> $b->{minInclusive} :
            $a->{maxInclusive} <=> $b->{maxInclusive}
    } @$definedranges;

    #print STDERR $node->{path}, "\n", Dumper(\@sortedranges)
    #    if @sortedranges > 1;

    # go through the ranges checking for overlap
    # XXX step isn't handled properly... in fact it's ignored
    my $overlap = 0;
    my $fullrange = undef;
    my $prevmax = undef;
    foreach my $range (@sortedranges) {
        my $minval = $range->{minInclusive};
        my $maxval = $range->{maxInclusive};
        my $step = $range->{step};

        $overlap++ if defined($prevmax) && $minval <= $prevmax;

        if (!defined $prevmax) {
            $fullrange = ($minval == $range_for_type->{$primtype}->{min});
        } else {
            $fullrange = 0 if $minval > $prevmax + 1;
        }

        $prevmax = $maxval;
    }

    $fullrange = 0
        if defined $prevmax && $prevmax != $range_for_type->{$primtype}->{max};

    #print STDERR $overlap, " ", $fullrange, "\n" if @sortedranges > 1;

    return $overlap ? 3 : $fullrange ? 2 : 1;
}

# Get formatted enumerated values
# XXX format is currently report-dependent
# XXX no indication of access (didn't we used to show this?)
sub get_values
{
    my ($node, $anchor) = @_;

    # XXX this is really horrible, but allow this routine to be called either
    #     with a node or with just the values (in which case there's no node
    #     history); this is intended for getting data type enumerations
    my $values;
    my $is_modified;
    my $changed_values;
    if (defined $node->{type}) {
        $values = $node->{values};
        $is_modified = util_node_is_modified($node);
        $changed_values = $node->{changed}->{values};
    } else {
        $anchor = 0;
        $values = $node;
        $is_modified = 0;
        $changed_values = {};
    }

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
	my $DELETED = $cvalue->{status} eq 'DELETED';

        # DELETED (upper-case) means skip unconditionally
        next if $DELETED || ($deleted && !$showdiffs);

        $readonly = 0 if $noshowreadonly;

        my $changed = $is_modified &&
            ($changed_values->{$value}->{added} ||
             $changed_values->{$value}->{access} ||
             $changed_values->{$value}->{status});
        my $dchanged = $is_modified &&
            ($changed || $changed_values->{$value}->{description});

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

    # XXX there are also problems with --compare when the last change is
    #     append (need to realise this and compare only the last change)

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
    # XXX could/should have similar logic for prefixed text
    if ($descact eq 'replace' && length($new) > length($old) && 
        substr($new, 0, length($old)) eq $old &&
        substr($new, length($old), 1) eq "\n") {
        $new = substr($new, length($old));
        $new =~ s/^\s+//;
        $descact = 'append';
    }

    if ($descact eq 'replace') {
        $new = '' if $new eq $old && !$resolve;
    } elsif ($descact eq 'prefix') {
        # XXX simpler logic than for append because no specific logic for
        #     {{enum}} and {{pattern}}
        $new = $new . (($old ne '' && $new ne '') ? "\n" : "") . $old
            if $resolve;
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

    # XXX check spelling (experimental)
    $new = util_check_spelling($new);

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
        $new = html_whitespace($new);
        if ($descact eq 'prefix') {
            $new = $new . (($old ne '' && $new ne '') ? "\n" : "") . $old;
        } elsif ($descact eq 'append') {
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

# Remove '{{prefix}}', '{{append}}' or '{{replace}}' indicator, returning
# whether any was found, and the result
# XXX should be phased out (currently used only by XLS report?)
sub remove_descact
{
    my ($description, $descact) = @_;

    if ($description =~ /{{(prefix|append|replace)}}/) {
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

    my $psyntax = $syntax;

    my $typeinfo = get_typeinfo($type, $syntax);
    my ($value, $dataType) = ($typeinfo->{value}, $typeinfo->{dataType});

    if ($dataType) {
        # XXX this syntax could be overridden by per-parameter syntax; should
        #     be checking for that...
        $syntax = base_syntax($value, 1);
        $value = base_type($value, 1);
    }

    # lists are always strings at the CWMP level
    if ($psyntax->{list}) {
        $value = 'string';
        $value .= add_size($psyntax, {list => 1});
    } else {
        $value .= add_size($syntax);
        $value .= add_range($syntax);
    }

    return $value;
}

# Determine a named data type's base syntax, i.e. the syntax of the named
# data type prior to any overrides by this parameter
# XXX this is only a partial implementation
sub base_syntax
{
    my ($name) = @_;
    
    my ($defn) = grep {$_->{name} eq $name} @{$root->{dataTypes}};
    if (!defined $defn) {
        emsg "$name: undefined named data type; invalid XML?";
        return $name;
    }

    return $defn->{syntax};
}

# Determine a named data type's base type
sub base_type
{
    my ($name, $recurse) = @_;

    my ($defn) = grep {$_->{name} eq $name} @{$root->{dataTypes}};
    if (!defined $defn) {
        emsg "$name: undefined named data type; invalid XML?";
        return $name;
    }

    my $base = $defn->{base};
    my $prim = $defn->{prim};

    emsg "$name: no base or primitive data type; invalid XML?"
        if !$base && !$prim;

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
    my $thing = $opts->{list} ? 'list' : 'item';
    if (@{$syntax->{$sizes}} == 1 &&
        !$syntax->{$sizes}->[0]->{minLength} &&
        $syntax->{$sizes}->[0]->{maxLength}) {
        $value .= 'maximum ' . $thing . ' length ' if $opts->{human};
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

    d0msg "parse_file: parsing $tfile";

    # parse file
    my $parser = XML::LibXML->new(line_numbers => 1);
    my $tree = eval { $parser->parse_file($tfile) };
    if ($@) {
        emsg $@;
        return undef;
    }
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
            $root->{dm} = $declaredURI unless $root->{dm};
        } elsif ($declaredURI =~ /cwmp:datamodel-report-/) {
            $root->{dmr} = $declaredURI unless $root->{dmr};
        } elsif ($declaredURI =~ /XMLSchema-instance/) {
            $root->{xsi} = $declaredURI;
            $xsi = $declaredPrefix;
        }
    }

    # always use the schemaLocation from the first file parsed, which 
    # determines the schema version in generated "flattened" XML; ensure
    # that it includes a full URL and add the dmr location if it's missing
    my $schemaLocation = $toplevel->findvalue("\@$xsi:schemaLocation");
    if ($schemaLocation && !$root->{schemaLocation}) {
        $schemaLocation =~ s/^\s+//;
        $schemaLocation =~ s/\s+$//;
        $schemaLocation =~ s/\s+/ /g;
        my @comps = split ' ', $schemaLocation;
        for (my $i = 0; $i < @comps; $i += 2) {
            my $nsn = $comps[$i];
            my $loc = $comps[$i+1];
            $loc = qq{http://www.broadband-forum.org/cwmp/$loc} unless
                $loc =~ /^https?:/;

            $root->{schemaLocation} .= qq{$nsn $loc };
        }
        $root->{schemaLocation} .= qq{urn:broadband-forum-org:cwmp:datamodel-report-0-1 http://www.broadband-forum.org/cwmp/cwmp-datamodel-report.xsd } unless
            $root->{schemaLocation} =~ /cwmp:datamodel-report-/;
        chop $root->{schemaLocation};
    }

    # XXX if no dmr, use default
    $root->{dmr} = "urn:broadband-forum-org:cwmp:datamodel-report-0-1"
        unless $root->{dmr};

    # capture the first comment in the first file
    my $comments = $tree->findnodes('comment()');
    foreach my $comment (@$comments) {
        my $text = $comment->findvalue('.');
        next if $text =~ /DO NOT EDIT/i;
        next if $text =~ /edited with XMLSpy/i;
        $first_comment = $text unless defined $first_comment;
    }
    
    # if no comment in first file, don't look in sunbsequent files
    $first_comment = '' if not defined $first_comment;

    # validate file if requested
    return $toplevel unless $loglevel >= $LOGLEVEL_WARNING;

    # use schemaLocation to build schema referencing the same schemas that
    # the file references
    # XXX this isn't perfect because it requires ALL schemas to be referenced
    #     here, even those that are only referenced indirectly by other schemas
    #     (this is most likely to be a problem for DT instances that don't
    #     directly reference the DM schema)
    my $schemas =
        qq{<?xml version="1.0" encoding="UTF-8"?>\n} .
        qq{<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">\n};

    $schemaLocation =~ s/^\s*//;
    $schemaLocation =~ s/\s*$//;
    my %nsmap = split /\s+/, $schemaLocation;
    foreach my $ns (keys %nsmap) {
        my $path = $nsmap{$ns};

        # if there are no XML catalogs and path is an http(s) URL, retain only
        # the filename part (so can search for it)
        if (!@$catalogs) {
            my ($scheme) = uri_split($path);
            $path =~ s/.*\/// if $scheme && $scheme =~ /^https?$/i;
        }

        # search for file; on failure, extract just the file name and try
        # again; don't report failure (schema validation will do this)
        my $fdir = $dir;
        my ($dir, $file) = find_file($path, $fdir);
        if (!$dir) {
            (my $scheme_ignore, my $auth_ignore, $path) = uri_split($path);
            (my $vol_ignore, $dir, $path) = File::Spec->splitpath($path);
            ($dir, $file) = find_file($path, $fdir);
        }
        if ($dir) {
            $path = File::Spec->catfile($dir, $file);
            # XXX drive name causes problems under Windows because it's
            #     interpreted as URL scheme, so prefix with "file:///" if
            #     file starts with a letter followed by a colon
            $path = qq{file:///$path} if $path =~ /^[A-Za-z]:/;
            # XXX backslashes cause problems under Windows because they are
            #     not valid in an xs:anyURI, so change to forward slashes
            $path =~ s/\\/\//g;
            # XXX should really do more, e.g. percent-escape any invalid chars
        }
        $schemas .= qq{<xs:import namespace="$ns" schemaLocation="$path"/>\n};
    }

    $schemas .= qq{</xs:schema>\n};

    my $schema;
    eval { $schema = XML::LibXML::Schema->new(string => $schemas) };
    if ($@) {
        emsg "invalid auto-generated XML schema for $tfile:";
        foreach my $line (split "\n", $@) {
            emsg $line;
        }
    } else {
        eval { $schema->validate($tree) };
        if ($@) {
            d0msg "failed to validate $tfile:";
            foreach my $line (split "\n", $@) {
                emsg $line;
            }
        } else {
            d0msg "validated $tfile";
        }
    }

    return $toplevel;
}

# Find file by searching for the highest corrigendum number (if omitted)
# XXX should also support proper search path and shouldn't assume ".xml"
# XXX note that it works if supplied file includes directory, but only by
#     chance and not by design
# XXX should / could generalise to allow search for issue and amendment (would
#     support planned move to versioned support files, e.g. even with
#     tr-069-i-a-c-biblio.xml would continue to find tr-069-biblio.xml)
sub find_file
{
    my ($file, $predir) = @_;

    # XXX $predir must always be supplied; an empty value means the current
    #     directory; warn if undefined because this indicates that the caller
    #     has made a mistake (still need to add dir to some data structures)
    w0msg "find_file: $file: predir is undefined" unless defined $predir;
    $predir = File::Spec->curdir() unless $predir;
    
    # search path
    my $dirs = [];

    # if file includes directory, it overrides the search path for this call
    # XXX is it safe to ignore the volume?
    (my $vol, my $dir, $file) = File::Spec->splitpath($file);
    if ($dir) {
        push @$dirs, $dir;
    } else

    # always prepend $predir to the list of includes
    {
        push @$dirs, $predir;
        push @$dirs, @$includes;
    }

    my $ffile = $file;
    my $fdir = '';

    # support names of form name-i-a[-c][label].xml where name is of the form
    # "xx-nnn", i, a and c are numeric and label can't begin with a digit
    # XXX as experiment allow label to start with digit as long as it contains
    #     at least one non-digit (have also changed all similar occurrences)
    my ($name, $i, $a, $c, $label) =
        $file =~ /^([^-]+-\d+)-(\d+)-(\d+)(?:-(\d+))?(-\d*\D.*)?\.xml$/;

    # remember whether the corrigendum number was explicitly given
    my $corr = (defined $c);

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

    # form full path and convert to relative path
    # XXX planned on using this in place of "$file" but this is too many
    #     changes for now...
    my $rpath = File::Spec->abs2rel(File::Spec->catfile($fdir, $ffile));

    d0msg "find_file: $file $predir -> $fdir $ffile $corr $rpath";
    return ($fdir, $ffile, $corr, $rpath);
}

# Check whether specs match
sub specs_match
{
    my ($spec, $fspec) = @_;

    # spec is spec from import and fspec is spec from file; if spec omits the
    # corrigendum number it matches all corrigendum numbers

    # support specs that end name-i-a[-c][label] where name is of the form
    # "xx-nnn", i, a and c are numeric, and label is more-or-less arbitrary
    # text (but has to contain at least one non-digit)
    my ($c, $label) = $spec =~ /[^-]+-\d+-\d+-\d+(?:-(\d+))?(\d*\D.*)?$/;
    $label = '' unless $label;

    # if corrigendum number is defined, require exact match
    return ($fspec eq $spec) if defined $c;

    # if corrigendum number is undefined in spec, remove it from fspec (if
    # present) before comparing
    ($c) = $fspec =~ /[^-]+-\d+-\d+-\d+(?:-(\d+))?(?:\d*\D.*)?$/;
    $fspec =~ s/-\d+\Q$label\E$/$label/ if defined $c;
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
        print "=+=+=+=+=\n" . $node->{changed}->{description} . "\n=-=-=-=-=\n"
            if $showdiffs && $node->{changed}->{description};
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

# XXX can probably just be deleted, because it doesn't really work; first step
#     can be to rename as the xml0 report and rename xml2 as xml; then check
#     that the new xml (old xml2) report works with and without --lastonly;
#     then delete this

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

    # XXX why can status be undefined... but seemingly nothing else?
    $status = $status && $status ne 'current' ? qq{ status="$status"} : qq{};
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

        if ($dataTypes && @$dataTypes) {
            xml_datatypes($dataTypes, $indent, {});
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
            d1msg "hiding $type $path $spec $lspec";
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
            d1msg "hiding $type $path $ospec $lspec";
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
        unless ($nocomments || $node->{descact} =~ /prefix|append/) {
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
            d1msg "hiding $type $path $spec $lspec";
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
            d1msg "ignoring $type $path $ospec $lspec";
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
        unless ($nocomments || $node->{descact} =~ /prefix|append/) {
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

                my $facet = $cvalue->{facet};
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

                print qq{$i      <$facet value="$evalue"$access$status$optional$ended>\n};
                print qq{$i        <description$descact>$description</description>\n} if $description;
                print qq{$i      </$facet>\n} unless $ended;
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

sub xml_datatypes
{
    my ($dataTypes, $indent, $opts) = @_;

    $indent = 0 unless $indent;
    my $i = "  " x $indent;

    # XXX status and descact are ignored

    foreach my $dataType (@$dataTypes) {
        my $name = $dataType->{name};
        my $base = $dataType->{base};
        my $prim = $dataType->{prim};
        my $spec = $dataType->{spec};
        my $description = $dataType->{description};
        # XXX not handling multiple sizes or ranges
        my $minLength = $dataType->{syntax}->{sizes}->[0]->{minLength};
        my $maxLength = $dataType->{syntax}->{sizes}->[0]->{maxLength};
        my $minInclusive = $dataType->{syntax}->{ranges}->[0]->{minInclusive};
        my $maxInclusive = $dataType->{syntax}->{ranges}->[0]->{maxInclusive};
        my $values = $dataType->{values};
        
        $description = xml_escape($description);
        
        $base = $base ? qq{ base="$base"} : qq{};
        $minLength = defined $minLength ? qq{ minLength="$minLength"} : qq{};
        $maxLength = defined $maxLength ? qq{ maxLength="$maxLength"} : qq{};
        $minInclusive = defined $minInclusive ? qq{ minInclusive="$minInclusive"} : qq{};
        $maxInclusive = defined $maxInclusive ? qq{ maxInclusive="$maxInclusive"} : qq{};
        
        print qq{$i  <dataType name="$name"$base>\n};
        print qq{$i    <description>$description</description>\n} if $description;
        my $j = $i . ($prim ? '  ' : '');
        print qq{$i    <$prim>\n} if $prim;

        print qq{$j    <size$minLength$maxLength/>\n} if
            $minLength || $maxLength;
        print qq{$j    <range$minInclusive$maxInclusive/>\n} if
            $minInclusive || $maxInclusive;

        # XXX logic is similar to that in xml_node() but here there is no
        #     support for history or descact
        if ($values && %$values) {
            foreach my $value (sort {$values->{$a}->{i} <=>
                                         $values->{$b}->{i}} keys %$values) {
                my $evalue = xml_escape($value);
                my $cvalue = $values->{$value};

                my $facet = $cvalue->{facet};
                my $access = $cvalue->{access};
                my $status = $cvalue->{status};
                my $optional = boolean($cvalue->{optional});

                my $description = $cvalue->{description};
                $description = xml_escape($description);
                
                $optional = $optional ? qq{ optional="true"} : qq{};
                $access = $access ne 'readWrite'? qq{ access="$access"} : qq{};
                $status = $status ne 'current' ? qq{ status="$status"} : qq{};
                my $ended = $description ? '' : '/';

                print qq{$j    <$facet value="$evalue"$access$status$optional$ended>\n};
                print qq{$j      <description>$description</description>\n} if $description;
                print qq{$j    </$facet>\n} unless $ended;
            }
        }
        print qq{$i    </$prim>\n} if $prim;
        print qq{$i  </dataType>\n};
    }
}

sub xml_bibliography
{
    my ($bibliography, $indent, $opts) = @_;

    # XXX descact is ignored

    $indent = 0 unless $indent;
    my $i = "  " x $indent;

    my $usespec = $opts->{usespec};
    my $ignspec = $opts->{ignspec};

    my $description = $bibliography->{description};
    my $references = $bibliography->{references};
    
    print qq{$i  <bibliography>\n};
    print qq{$i    <description>$description</description>\n} if $description;
    
    foreach my $reference (sort bibid_cmp @$references) {
        my $id = $reference->{id};
        my $file = $reference->{file};
        my $spec = $reference->{spec};
        
        # ignore if outputting entries from specified spec (usespec) but this
        # comes from another spec
        if ($usespec && $spec ne $usespec) {
            d1msg "$file: ignoring {$spec}$id";
            next;
        }

        # ignore if ignoring entries from specified spec (ignspec) and this
        # comes from that spec
        if ($ignspec && $spec eq $ignspec) {
            d1msg "$file: ignoring {$spec}$id";
            next;
        }
        
        # XXX this can include unused references (I think because these 
        #     are bibrefs for all read data models, not for reported data
        #     models
        if (!$bibrefs->{$id}) {
            # XXX for now, have hard-list of things not to omit
            my $omit = ($id !~ /SOAP1.1|$tr106/);
            if ($omit) {
                d1msg "reference $id not used (omitted)";
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

my $xml2_dtprofiles = [];
my $xml2_ucprofiles = [];

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
        my $comment = $first_comment || '';
        my $dm = $node->{dm} || $dmurn;
        my $dmr = $node->{dmr} || $dmrurn;
        my $dmspec = $lspec;
        my $dmfile = $lfile;
        my $xsi = $node->{xsi} || $xsiurn;
        my $schemaLocation = $node->{schemaLocation} || '';
        my $specattr = 'spec';

        $comment = qq{<!--$comment-->} if $comment;

        # will use in XML comment, so quietly change "--" to "-"
        my $tool_cmd_line_mod = $tool_cmd_line;
        $tool_cmd_line_mod =~ s/--/-/g;

        # generate file attribute (use output file if specified)
        my $tfile;
        if ($outfile) {
            $tfile = $outfile;
        } else {
            $tfile = $dmfile;
            $tfile =~ s/\.xml/-full.xml/;
        }
        my $fileattr = qq{ file="$tfile"};

        # file attribute was introduced in cwmp-datamodel-1-4
        my ($dmmaj, $dmmin) = $dm =~ /.*-(\d+)-(\d+)$/;
        $fileattr = '' if $dmmaj == 1 && $dmmin < 4;

        my $changed = $node->{changed};
        my $history = $node->{history};
        my $description = $node->{description};
        my $descact = $node->{descact};
        my $dchanged = util_node_is_modified($node) && $changed->{description};
        ($description, $descact) = get_description($description, $descact,
                                                   $dchanged, $history, 1);
        #$description = clean_description($description, $node->{name})
        #    if $canonical;
        $description = xml_escape($description);     

        # XXX have to hard-code DT stuff (can't get this from input files)
        my $d = @$dtprofiles ? qq{dt} : qq{dm};
        my $uuidattr = qq{};
        if ($d eq 'dt') {
            $dm = $dturn;
            $dmspec = $dtspec;
            $uuidattr = qq{ uuid="$dtuuid"};
            $schemaLocation =~
                s/urn:broadband-forum-org:cwmp:datamodel.*?\.xsd ?//;
            $schemaLocation = qq{$dturn $dtloc $schemaLocation};
            $specattr = 'deviceType';
            $fileattr = '';
        }

        $element = qq{$d:document};
        $node->{xml2}->{element} = $element;
        print qq{$i<?xml version="1.0" encoding="UTF-8"?>
$i<!-- DO NOT EDIT; generated by Broadband Forum $tool_id_only ($tool_vers_date_only version) on $tool_run_date at $tool_run_time$tool_checked_out.
$i     $tool_cmd_line_mod
$i     See $tool_url. -->
$i$comment
$i<$d:document xmlns:$d="$dm"
$i             xmlns:dmr="$dmr"
$i             xmlns:xsi="$xsi"
$i             xsi:schemaLocation="$schemaLocation"
$i             $specattr="$dmspec"$fileattr$uuidattr>
};
        if (!@$dtprofiles) {
            my $dataTypes = $node->{dataTypes};
            my $bibliography = $node->{bibliography};
            print qq{$i  <description>$description</description>\n} if
                $description;
            if ($dataTypes && @$dataTypes) {
                xml_datatypes($dataTypes, $indent, {});
            }
            if ($bibliography && %$bibliography) {
                xml_bibliography($bibliography, $indent, {});
            }
        } else {
            my $temp = util_list($dtprofiles, qq{''\$1''});
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
        my $isService = $node->{isService};
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
        my $noUniqueKeys = $node->{noUniqueKeys};
        my $fixedObject = $node->{fixedObject};
        my $syntax = $node->{syntax};
        my $majorVersion = $node->{majorVersion};
        my $minorVersion = $node->{minorVersion};
        my $extends = $node->{extends};

        my $mpref = util_full_path($node, 1);

        my $requirement = '';
        my $version = version($majorVersion, $minorVersion);

        my $origelem = $element;

        if ($element eq 'model') {
            $version = '';
            if (@$dtprofiles) {
                $xml2_dtprofiles = expand_dtprofiles($node, $dtprofiles);
                $xml2_ucprofiles = expand_dtprofiles($node, $ucprofiles,
                                                     'ucprofile');
                $isService = '';
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
                ($access, my $dtcode, my $dtmatches) =
                    object_requirement($mpref, $xml2_dtprofiles, $path);
                my ($ucaccess, $uccode, $ucmatches) =
                    object_requirement($mpref, $xml2_ucprofiles, $path);
                if ($uccode > $dtcode) {
                    $dtmatches = util_list($dtmatches);
                    $ucmatches = util_list($ucmatches);
                    if ($dtmatches) {
                        w0msg "$path: in $ucmatches but requirement ".
                            "($ucaccess) > $dtmatches ($access)";
                    } else {
                        w0msg "$path: in $ucmatches but not in --dtprofile";
                    }
                }
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
                ($access, my $dtcode, my $dtmatches) =
                    parameter_requirement($mpref, $xml2_dtprofiles, $path);
                my ($ucaccess, $uccode, $ucmatches) =
                    parameter_requirement($mpref, $xml2_ucprofiles, $path);
                if ($uccode > $dtcode) {
                    $dtmatches = util_list($dtmatches);
                    $ucmatches = util_list($ucmatches);
                    if ($dtmatches) {
                        w0msg "$path: in $ucmatches but requirement ".
                            "($ucaccess) > $dtmatches ($access)";
                    } else {
                        w0msg "$path: in $ucmatches but not in --dtprofile";
                    }
                }
                # XXX see above for how element can be empty
                if ($node->{pnode}->{xml2}->{element} eq '') {
                    d1msg "$path: ignoring because parent not in profile";
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
        $isService = $isService ? qq{ isService="true"} : qq{};
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
        $extends = $extends ? qq{ extends="$extends"} : qq{};

        $version = $version ? qq{ dmr:version="$version"} : qq{};
        $noUniqueKeys = $noUniqueKeys ? qq{ dmr:noUniqueKeys="$noUniqueKeys"} : qq{};
        $fixedObject = $fixedObject ? qq{ dmr:fixedObject="$fixedObject"} : qq{};

        my $dchanged = util_node_is_modified($node) && $changed->{description};
        ($description, $descact) = get_description($description, $descact,
                                                   $dchanged, $history, 1);
        #$description = clean_description($description, $node->{name})
        #    if $canonical;
        $description = xml_escape($description);
        my $descname = !@$dtprofiles ? qq{description} : qq{annotation};

        my $end_element = (@{$node->{nodes}} || $description || $syntax) ? '' : '/';
        print qq{$i<!--\n} if $element eq 'object' && $noobjects;
        # XXX horrible hack for top-level parameters in profiles (which
        #     probably only happens when the profile was defined in a
        #     component?); have to create an entry for the parent object
        #     but not if it's at the top level of a Service object!
        my $tlpp = ($node->{pnode}->{type} &&
                    $node->{pnode}->{type} eq 'profile' &&
                    $element eq 'parameter' && $path =~ /\./);
        my $isave = $i;
        if ($tlpp) {
            my $tpath = $path;
            $tpath =~ s/[^\.]+$//;
            print qq{$i<object ref="$tpath" requirement="present">\n};
            $i .= '  ';
        }
        print qq{$i<$element$name$base$ref$isService$extends$access$numEntriesParameter$enableParameter$status$activeNotify$forcedInform$requirement$minEntries$maxEntries$version$noUniqueKeys$fixedObject$end_element>\n};
        if ($tlpp) {
            $i = $isave;
            print qq{$i</object>\n};
        }
        $node->{xml2}->{element} = '' if $end_element;
        print qq{$i  <$descname>$description</$descname>\n} if $description;
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

        # XXX this was almost verbatim from xml_node but is now better,
        #     because it handles multiple ranges and sizes
        if ($syntax) {
            my $hidden = $syntax->{hidden};
            my $command = $syntax->{command};
            my $base = $syntax->{base};
            my $ref = $syntax->{ref};
            my $list = $syntax->{list};
            # XXX not supporting multiple list sizes or ranges
            my $minListLength = $syntax->{listSizes}->[0]->{minLength};
            my $maxListLength = $syntax->{listSizes}->[0]->{maxLength};
            my $minListItems = $syntax->{listRanges}->[0]->{minInclusive};
            my $maxListItems = $syntax->{listRanges}->[0]->{maxInclusive};
            my $sizes = $syntax->{sizes};
            my $ranges = $syntax->{ranges};
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
            $minListItems = defined $minListItems && $minListItems ne '' ?
                qq{ minItems="$minListItems"} : qq{};
            $maxListItems = defined $maxListItems && $maxListItems ne '' ?
                qq{ maxItems="$maxListItems"} : qq{};
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
            my $ended = (($sizes && @$sizes) || ($ranges && @$ranges) ||
                         $reference || %$values || $units) ? '' : '/';
            print qq{$i    <$type$ref$base$ended>\n};

            foreach my $size (@{$syntax->{sizes}}) {
                my $minLength = $size->{minLength};
                my $maxLength = $size->{maxLength};

                $minLength = defined $minLength && $minLength ne '' ?
                    qq{ minLength="$minLength"} : qq{};
                $maxLength = defined $maxLength && $maxLength ne '' ?
                    qq{ maxLength="$maxLength"} : qq{};

                print qq{$i      <size$minLength$maxLength/>\n} if
                    $minLength || $maxLength;
            }

            foreach my $range (@{$syntax->{ranges}}) {
                my $minInclusive = $range->{minInclusive};
                my $maxInclusive = $range->{maxInclusive};
                my $step = $range->{step};

                $minInclusive = defined $minInclusive && $minInclusive ne '' ?
                    qq{ minInclusive="$minInclusive"} : qq{};
                $maxInclusive = defined $maxInclusive && $maxInclusive ne '' ?
                    qq{ maxInclusive="$maxInclusive"} : qq{};
                $step = defined $step && $step ne '' ? qq{ step="$step"} : qq{};
                
                print qq{$i      <range$minInclusive$maxInclusive$step/>\n} if
                    $minInclusive || $maxInclusive || $step;
            }

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
                #$description = clean_description($description, $node->{name})
                #    if $canonical;
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

# expand_dtprofiles() helper
sub add_profile_subtree
{
    my ($mprofs, $p, $profs) = @_;

    my $b = $p->{base};
    if ($b) {
        ($b) = grep {$_->{name} eq $b} @$mprofs;
        add_profile_subtree($mprofs, $b, $profs) if $b;
    }

    foreach my $e (split /\s+/, $p->{extends}) {
        ($e) = grep {$_->{name} eq $e} @$mprofs;
        add_profile_subtree($mprofs, $e, $profs) if $e;
    }

    push @$profs, $p->{name} unless grep {$_ eq $p->{name}} @$profs;
}

# For each model, generate expanded profiles, accounting for omitted versions,
# dependencies and non-existent profiles
sub expand_dtprofiles
{
    my ($model, $dtprofiles, $optname) = @_;

    $optname = 'dtprofile' unless $optname;

    # collect all the model's profiles
    my @mprofs = grep {$_->{type} eq 'profile'} @{$model->{nodes}};

    my $profiles = [];

    # cycle through the supplied profile name prefixes
    foreach my $dtprofile (@$dtprofiles) {
        # temporarily append ':' if not already there (so "Digital" doesn't
        # match "DigitalOutput" for example)
        my $tdt = $dtprofile;
        $tdt .= ':' if $tdt !~ /:/;

        # collect all the model's profiles that match this one
        my @profs = grep {$_->{name} =~ /^$tdt/} @mprofs;

        # error if no match
        w0msg "$model->{name}: --$optname $dtprofile matches no profiles"
            unless @profs;

        # for each matching profile, add the profiles that it depends on or
        # extends (including itself)
        foreach my $p (@profs) {
            add_profile_subtree(\@mprofs, $p, $profiles);
        }
    }

    return $profiles;
}

# Determine maximum requirement for a given object across a set of profiles
sub object_requirement
{
    my ($mpref, $profs, $path) = @_;

    my $maxreq = 0;
    my $matches = [];
    foreach my $prof (@$profs) {
        my $fpath = $mpref . $prof;
        my $req = $profiles->{$fpath}->{$path};
        next unless $req;

        $req = {notSpecified => 1, present => 2, create => 3, delete => 4,
                createDelete => 5}->{$req};
        if ($req > $maxreq) {
            $maxreq = $req;
            push @$matches, $prof;
        }
    }

    # XXX special case, force "present" for "Device.", "InternetGatewayDevice."
    #     and their "Services." child
    $maxreq = 2 if !$maxreq &&
        $path =~ /^(InternetGateway)?Device\.(Services\.)?$/;

    # XXX treat "notSpecified" as readOnly, since a profile definition can
    #     say "notSpecified" for an object and then reference its parameters
    my $access = {0 => '', 1 => 'readOnly', 2 => 'readOnly', 3 => 'create',
                  4 => 'delete', 5 => 'createDelete'}->{$maxreq};

    return ($access, $maxreq, $matches);
}

# Determine maximum requirement for a given parameter across a set of profiles
sub parameter_requirement
{
    my ($mpref, $profs, $path) = @_;

    my $maxreq = 0;
    my $matches = [];
    foreach my $prof (@$profs) {
        my $fpath = $mpref . $prof;
        my $req = $profiles->{$fpath}->{$path};
        next unless $req;

        $req = {readOnly => 1, readWrite => 2}->{$req};
        if (defined($req) && $req > $maxreq) {
            $maxreq = $req;
            push @$matches, $prof;
        }
    }

    my $access = {0 => '', 1 => 'readOnly', 2 => 'readWrite'}->{$maxreq};

    return ($access, $maxreq, $matches);
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
    } elsif ($am ne $bm) {
        return (($am ne '' ? $am : 0) <=> ($bm ne '' ? $bm : 0));
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
    die "html_anchor_namespace_prefix: invalid type: $type" unless $prefix;

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
        $text .= qq{<a href="#$name">$label</a>};
    }

    return $text;
}

sub html_create_anchor
{
    my ($label, $type, $opts) = @_;

    # label and opts as used as follows:
    # - heading: label is section name; prefix with $opts->{node} pfx if there
    # - datatype: label is data type name
    # - bibref: label is bibref id
    # - path: label is the obj/par node (NOT the path)
    # - value: label is the value; param node is in $opts->{node}
    # - profile: label is the profile node (NOT the path)
    # - profoot: label is the profile obj/par node (NOT the path)
    #
    # label is prefixed with model prefix from $opts->{node} (if present) for
    # model-specific anchors, i.e. heading, path, value, profile and profoot

    my $node = $opts->{node};

    # validate type (any error is a programming error)
    my $types = ['heading', 'datatype', 'bibref', 'path', 'value',
                 'profile', 'profoot'];
    die "html_create_anchor: undefined anchor type" unless $type;
    die "html_create_anchor: unsupported anchor type: $type"
        unless grep {$type eq $_} @$types;

    # validate label
    die "html_create_anchor: for type '$type', must supply label"
        unless $label;

    # determine namespace prefix
    my $namespace_prefix = html_anchor_namespace_prefix($type);

    # determine the name as a function of anchor type (for many it is just the
    # supplied label)
    my $name = $label;
    if ($type eq 'heading') {
        my $mpref = util_full_path($node, 1);
        $name = $mpref . $name;
    } elsif ($type eq 'bibref') {
        $label = '';
    } elsif ($type eq 'path') {
        die "html_create_anchor: for type '$type', label must be node"
            if $node;
        $node = $label;
        $name = util_full_path($node);
        $label = $node->{type} eq 'object' ? $node->{path} : $node->{name};
    } elsif ($type eq 'value') {
        die "html_create_anchor: for type '$type', node must be in opts"
            unless $node;
        $name = util_full_path($node) . '.' . $label;
        $label = '';
    } elsif ($type eq 'profile') {
        die "html_create_anchor: for type '$type', label must be node"
            if $node;
        $node = $label;
        $name = util_full_path($node);
        $label = '';
    } elsif ($type eq 'profoot') {
        die "html_create_anchor: for type '$type', label must be node"
            if $node;
        $node = $label;
        # XXX this is not nice...
        my $object = ($node->{type} eq 'objectRef');
        my $Pnode = $object ? $node->{pnode} : $node->{pnode}->{pnode};
        $name = util_full_path($Pnode) . '.' . $node->{path};
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
    my $adef = qq{<a name="$aname">$label</a>};

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
            my $fpath = util_full_path($node);
            $fpath =~ s/(\.\{i\})?\.$//;
            $adef = qq{<a name="$namespace_prefix$fpath"></a>$adef};
        }
    }

    # if already defined, and if the label has changed, warn and update it
    my $hash = $anchors->{$aname};
    if (defined $hash) {
        if ($label ne $hash->{label}) {
            w0msg "html_create_anchor: warning: $aname label changed"; 
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
# not already be defined)
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
        # XXX this assumes that name is the key to the $objects and $parameters
        #     globals (so the caller has to ensure that this is the case)
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
# XXX using the "here" strings makes this VERY hard to read, and throws off
#     emacs indentation; best avoided... need to restructure...
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
    my $sup_valign = qq{vertical-align: super;};
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
                     param => $parameter ? $name : '',
                     object => $parameter ? $ppath : $object ? $path : undef,
                     table => $node->{table},
                     profile => $profile ? $name : '',
                     access => $node->{access},
                     id => $node->{id},
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
        my $filename1 = $allfiles->[0]->{name} ? $allfiles->[0]->{name} : qq{};
        my $filename2 = $allfiles->[1]->{name} ? $allfiles->[1]->{name} : qq{};
        my $filelink1 = qq{<a href="$cwmpindex#$filename1">$filename1</a>};
        my $filelink2 = $filename2 ?
            qq{<a href="../cwmp#$filename2">$filename2</a>} : qq{};
        my $title = qq{%%%%};
        my $any = $objpat || $lastonly || $showdiffs || $canonical;
        $title .= qq{ (} if $any;
	$title .= qq{$objpat, } if $objpat;
        $title .= qq{changes, } if $lastonly;
        $title .= qq{differences, } if $showdiffs;
        $title .= qq{canonical, } if $canonical;
        chop $title if $any;
        chop $title if $any;
        $title.= qq{)} if $any;
        my $sep = $filename2 ? qq{ -> } : qq{};
        my $title_link = $title;
        $title =~ s/%%%%/$filename1$sep$filename2/;
        $title_link =~ s/%%%%/$filelink1$sep$filelink2/;
        my $logo = qq{<a href="${bbfhome}"><img src="${bbfhome}images/logo-broadband-forum.gif" alt="Broadband Forum" style="border:0px;"/></a>};
        my ($preamble, $notice) = html_notice($first_comment);
        $preamble .= qq{<br>} if $preamble;
        # XXX should use a routine for this
        my $errors = qq{};
        if (!$nowarnreport && @$msgs) {
            $errors .= qq{<h1>Messages</h1><ol>};
            foreach my $error (@$msgs) {
                $error = html_escape(qq{$error}, {nomarkup => 1});
                $errors .= qq{<li>$error</li>};
            }
            $errors .= qq{</ol>};
        }
        # XXX in the styles below, should use inheritance to avoid duplication
        # XXX the td.d (delete) styles should use a tr style
        # will use in HTML comment, so quietly change "--" to "-"
        my $tool_cmd_line_mod = $tool_cmd_line;
        $tool_cmd_line_mod =~ s/--/-/g;
        my $hyperlink = $showdiffs ?
            qq{a:link, a:visited, a:hover, a:active { color: inherit; }} : qq{};
        my $do_not_edit = qq{<!-- DO NOT EDIT; generated by Broadband Forum $tool_id_only ($tool_vers_date_only version)};
        $do_not_edit .= qq{ on $tool_run_date at $tool_run_time$tool_checked_out.
     $tool_cmd_line_mod
     See $tool_url} if !$canonical;
        $do_not_edit .= qq{. -->};
	print <<END;
$do_not_edit
<html>
  <head>
    <meta content="text/html; charset=UTF-8" http-equiv="content-type">
    <title>$title</title>
    <style type="text/css">
      p, li, body { $font }
      h1 { $h1font }
      h2 { $h2font }
      h3 { $h3font }
      sup { $sup_valign }
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
        <td align="center" valign="middle"><h1><br>$preamble$title_link</h1></td>
        <td width="25%"/>
      </tr>
    </table>
  $notice
  $errors
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
            #emsg Dumper($datatypes);
            my $anchor = html_create_anchor('Data Types', 'heading');
            print <<END;
      <li>$anchor->{ref}</li>
END
            my $tr106section = $tr106 lt 'TR-106a6' ?
                                      'Section 3.2' : 'Appendix I.4';
            my $preamble = <<END;
The parameters defined in this specification make use of a limited subset of the default SOAP data types {{bibref|SOAP1.1}}.  The complete set of data types, along with the notation used to represent these types, is listed in {{bibref|$tr106|$tr106section}}.  The following named data types are used by this specification.
END
            update_bibrefs($preamble, $node->{file}, $node->{spec});
            # XXX sanity_node only detects invalid bibrefs in node and value
            #     descriptions...
            my $ibr = invalid_bibrefs($preamble);
            emsg "invalid bibrefs (need to use the --tr106 option?): " .
              join(', ', @$ibr) if $warnbibref >= 0 && @$ibr;
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
                # XXX this is the wrong criterion; the test should be whether
                #     any of the parameters in the report use the data type
                next if $lastonly &&
                    !grep {$_ eq $lspec} @{$datatype->{specs}};

                my $name = $datatype->{name};
                my $base = base_type($name, 0);
                my $description = $datatype->{description};
                # XXX not using this yet
                my $descact = $datatype->{descact};
                my $values = $datatype->{values};

                my $name_anchor = html_create_anchor($name, 'datatype');
                my $base_anchor = html_create_anchor($base, 'datatype');

                # want hyperlinks only for named data types
                my $baseref = ($base =~ /^[A-Z]/ && !$nolinks) ?
                    $base_anchor->{ref} : $base;

                my $sizerange = '';
                $sizerange .= add_size(base_syntax($name));
                $sizerange .= add_range(base_syntax($name));

                # XXX this needs a generic utility that will escape any
                #     description with full template expansion
                # XXX more generally, a data type report should be quite like
                #     a parameter report (c.f. UPnP relatedStateVariable)
                $description = html_escape($description, {values => $values});

                $html_buffer .= <<END;
      <tr>
        <td>$name_anchor->{def}</td>
        <td>$baseref$sizerange</td>
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
            d0msg "$path: ignoring top-level parameter";
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
        my $typetitle = $showsyntax ? qq{} : qq{ title="$syntax"};
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
        # XXX although there is a proposal to permit "tiny" versions in this
        #     case, in which case there would be no conflict
	my $version =
	    html_escape(version($node->{majorVersion}, $node->{minorVersion}));

        # XXX the above is addressed by $showspec and the use of a cleaned-up
        #     version of the spec
        # XXX doing this for every item is inefficient...
        msg "D", Dumper(util_copy($node, ['nodes', 'pnode', 'mnode', 'table']))
            if $debugpath && $path =~ /$debugpath/;

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
        $specs = '' if $canonical;
        my $versiontitle = $showspec ? qq{} : qq{ title="$specs"};

        # XXX $trclass is treated differently from $tdclass only to minimise
        #     diffs with HTML produced by earlier tool versions
        my $trclass = ($showdiffs && util_node_is_new($node)) ? 'n' : '';
        # XXX never show diffs if the model is new, i.e. has no history
        $trclass = '' if !defined $node->{mnode}->{history};
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
            if ($html_profile_active) {
                print <<END;
        </ul> <!-- Profile Definitions -->
      </ul> <!-- Data Model -->
END
            }
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
          $spec_oc<th width="10%" class="gc">Spec</th>$spec_cc
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
                my $infreq = 'Inform and Notification Requirements';
                my $anchor = html_create_anchor($infreq, 'heading',
                                                {node => $node});
                print <<END;
        </ul> <!-- Data Model Definition -->
        <li>$anchor->{ref}</li>
        <ul> <!-- $infreq -->
END
                $html_buffer .= <<END;
      </tbody>
    </table> <!-- Data Model Definition -->
    <h2>$anchor->{def}</h2>
END
                $html_buffer .=
                html_param_table(qq{Forced Inform Parameters},
                                 {tabopts => $tabopts, node => $node},
                                 grep {$_->{forcedInform}} @$html_parameters) .
                html_param_table(qq{Forced Active Notification Parameters},
                                 {tabopts => $tabopts, node => $node},
                                 grep {$_->{activeNotify} eq 'forceEnabled'}
                                 @$html_parameters) .
                html_param_table(qq{Default Active Notification Parameters},
                                 {tabopts => $tabopts, node => $node},
                                 grep {$_->{activeNotify} eq
                                           'forceDefaultEnabled'}
                                 @$html_parameters) .
                html_param_table(qq{Parameters for which Active Notification }.
                                 qq{MAY be Denied},
                                 {tabopts => $tabopts, sepobj => 1,
                                  node => $node},
                                 grep {$_->{activeNotify} eq 'canDeny'}
                                 @$html_parameters);
                my $panchor = html_create_anchor('Profile Definitions',
                                                 'heading', {node => $node});
                my $nanchor = html_create_anchor('Notation',
                                                 'heading', {node => $node});
                print <<END;
        </ul> <!-- $infreq -->
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
            my $anchor = html_create_anchor(qq{$name Profile}, 'heading', 
                                            {node => $node});
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
            my $tspecs = $specs;
            $tspecs =~ s/ /<br>/g;
            $html_buffer .= <<END;
        <tr$trclass>
          <td class="${tdclass}" title="$path">$name</td>
          <td class="${tdclasstyp}"$typetitle>$type</td>
          $synt_oc<td class="${tdclasstyp}">$syntax</td>$synt_cc
          <td class="${tdclasswrt}c">$write</td>
          <td class="${tdclass}">$description</td>
          <td class="${tdclassdef}c">$default</td>
          $vers_oc<td class="${tdclass}c"$versiontitle>$version</td>$vers_cc
          $spec_oc<td class="${tdclass}c">$tspecs</td>$spec_cc
	</tr>
END
        } else {
            my $fpath = util_full_path($node);
            $name = html_get_anchor($fpath, 'path', $name) unless $nolinks;
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
        # XXX this can close too many tables (not a bad problem?); fixed?
        if ($indent) {
            $html_buffer .= <<END;
      </tbody>
    </table> <!-- $name -->
END
        }

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
            my $generated_by = qq{Generated by <a href="http://www.broadband-forum.org">Broadband Forum</a> <a href="$tool_url">$tool_id_only</a> ($tool_vers_date_only version)};
            $generated_by .= $canonical ? qq{.} : qq{ on $tool_run_date at $tool_run_time$tool_checked_out.<br>$tool_cmd_line};
            $generated_by .= qq{<p>};
            $html_buffer .= <<END;
    <p>
    <hr>
    $generated_by
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
    my $node = $hash->{node};

    my $anchor = html_create_anchor($title, 'heading', {node => $node});

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
        # this is the model prefix (it's the same for all the parameters)
        my $mpref = util_full_path($parameter, 1);

        # don't html_escape until after have parsed path (assumes dots)
        my $path = $parameter->{path};
        my $param = $path;
        if ($sepobj) {
            (my $object, $param) = $path =~ /^(.*\.)([^\.]*)$/;
            $object = html_escape($object, {empty => ''});
            if ($object && $object ne $curobj) {
                $curobj = $object;
                $object = html_get_anchor($mpref.$object, 'path', $object)
                    unless $nolinks;
                $html_buffer .= <<END;
        <tr>
          <td class="o">$object</td>
        </tr>
END
            }
        }
        $path = html_escape($path, {empty => ''});
        $param = html_escape($param, {empty => ''});
        $param = html_get_anchor($mpref.$path, 'path', $param) unless $nolinks;
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

# Generate "Notice" from the supplied comment (if any), returning preamble
# and notice (both as HTML)
sub html_notice
{
    my ($comment) = @_;

    my $preamble = '';
    my $text = '';

    # if undefined, just return empty strings
    return ($preamble, $text) unless $comment;

    # the comment MUST include a "Notice:" line (preamble text before it is
    # returned to the caller); text following the notice is taken until the
    # next "[\w\s]+:" line
    # (process line by line so can format paragraphs)
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
            if (!$seen_notice) {
                my $sep = $preamble ? qq{<br>} : qq{};
                $preamble .= qq{$sep$line} if $line;
            } else {
                $text .= qq{<h1>Notice</h1>\n};
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

    return ($preamble, $text);
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
    # XXX do this as part of markup processing?
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

        d1msg "$before -> $value" if $value ne $before;
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
        # ignore lines consisting only of whitespace (they never make any
        # difference)
        next if $line =~ /^\s*$/;
        my ($pre) = $line =~ /^(\s*)/;
        $len = length($pre) if !defined($len) || length($pre) < $len;
        if ($line =~ /\t/) {
            my $tline = $line;
            $tline =~ s/\t/\\t/g;
            w0msg "replace tab(s) in \"$tline\" with spaces!";
        }
    }
    $len = 0 unless defined $len;

    # remove it
    my $outval = '';
    foreach my $line (@lines) {
        next if $line =~ /^\s*$/;
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

    # path for use in error messages
    my $path = $p->{path};
    $path = '<unknown>' unless $path;

    # XXX hack to ignore ---deleted--- text when deciding whether to auto-
    #     include template references
    my $tinval = $inval;
    $tinval =~ s|\-\-\-(.*?)\-\-\-||gs;

    # auto-prefix {{reference}} if the parameter is a reference (put after
    # {{list}} if already there)
    if ($p->{reference} && $tinval !~ /\{\{reference/ &&
        $tinval !~ /\{\{noreference\}\}/) {
        my $sep = !$tinval ? "" : "  ";
        if ($tinval =~ /\{\{list\}\}/) {
            $inval =~ s/(\{\{list\}\})/$1$sep\{\{reference\}\}/;
        } else {
            $inval = "{{reference}}" . $sep . $inval;
        }
    }

    # auto-prefix {{list}} if the parameter is list-valued
    if ($p->{list} && $tinval !~ /\{\{list/ &&
        $tinval !~ /\{\{nolist\}\}/) {
        my $sep = !$tinval ? "" : "  ";
        $inval = "{{list}}" . $sep . $inval;
    }

    # auto-prefix {{datatype}} if the parameter has a named data type
    if ($p->{type} && $p->{type} eq 'dataType' &&
        $tinval !~ /\{\{datatype/ &&
        $tinval !~ /\{\{nodatatype\}\}/) {
        my $sep = !$tinval ? "" : "  ";
        $inval = "{{datatype}}" . $sep . $inval;
    }

    # auto-prefix {{showid}} if the item has an id
    if ($p->{id} &&
        $tinval !~ /\{\{showid/ &&
        $tinval !~ /\{\{noshowid\}\}/) {
        my $sep = !$tinval ? "" : "  ";
        $inval = "{{showid}}" . $sep . $inval;
    }

    # auto-prefix {{profdesc}} if it's a profile
    if ($p->{profile} && $tinval !~ /\{\{noprofdesc\}\}/) {
        my $sep = !$tinval ? "" : "\n";
        $inval = "{{profdesc}}" . $sep . $inval;
    }

    # auto-append {{enum}} or {{pattern}} if there are values and it's not
    # already there (apply rather complex logic to decide whether to put it
    # on the same line); "{{}}" is an empty template reference that will be
    # removed; it prevents special "after newline" template expansion behavior
    # XXX actually it's more complicated than this; also don't auto-add them if
    #     the description includes "{{datatype|expand}}" because it's assumed
    #     that such an expansion will include "{{enum}}" or "{{pattern}}"
    if ($p->{values} && %{$p->{values}} &&
        $tinval !~ /\Q{{datatype|expand}}\E/) {
        my ($key) = keys %{$p->{values}};
        my $facet = $p->{values}->{$key}->{facet};
        my $sep =
            !$tinval ? "" :
            $tinval =~ /(^|\n)\s*[\*\#\:][^\n]*$/s ? "\n{{}}" :
            $tinval =~ /[\.\?\!]\'*$/ ? "  " : "\n{{}}";
        $inval .= $sep . "{{enum}}" if $facet eq 'enumeration' &&
            $tinval !~ /\{\{enum\}\}/ && $tinval !~ /\{\{noenum\}\}/;
        $inval .= $sep . "{{pattern}}" if $facet eq 'pattern' &&
            $tinval !~ /\{\{pattern\}\}/ && $tinval !~ /\{\{nopattern\}\}/;
    }

    # similarly auto-append {{hidden}}, {{command}}, {{factory}}, {{entries}}
    # and {{keys}} if appropriate
    if ($p->{hidden} && $tinval !~ /\{\{hidden/ &&
        $tinval !~ /\{\{nohidden\}\}/) {
        my $sep = !$tinval ? "" : "\n";
        $inval .= $sep . "{{hidden}}";
    }
    if ($p->{command} && $tinval !~ /\{\{command/ &&
        $tinval !~ /\{\{nocommand\}\}/) {
        my $sep = !$tinval ? "" : "\n";
        $inval .= $sep . "{{command}}";
    }
    if (defined($p->{factory}) && $tinval !~ /\{\{factory/ &&
        $tinval !~ /\{\{nofactory\}\}/) {
        my $sep = !$tinval ? "" : "\n";
        $inval .= $sep . "{{factory}}";
    }
    my ($multi, $fixed_ignore, $union) = 
        util_is_multi_instance($p->{minEntries}, $p->{maxEntries});
    if (($multi || $union) &&
        $tinval !~ /\{\{entries/ && $tinval !~ /\{\{noentries\}\}/) {
        my $sep = !$tinval ? "" : "\n";
        $inval .= $sep . "{{entries}}";
    }
    if ($p->{uniqueKeys} && @{$p->{uniqueKeys}}&&
        $tinval !~ /\{\{keys/ && $tinval !~ /\{\{nokeys\}\}/) {
        my $sep = !$tinval ? "" : "\n";
        $inval .= $sep . "{{keys}}";
    }

    # in template expansions, the @a array is arguments and the %p hash is
    # parameters (options)
    my $templates =
        [
         {name => 'appdate', text1 => \&html_template_appdate},
         {name => 'docname', text1 => \&html_template_docname},
         {name => 'trname', text1 => \&html_template_trname},
         {name => 'trref', text1 => \&html_template_trref},
         {name => 'xmlref',
          text1 => \&html_template_xmlref,
          text2 => \&html_template_xmlref},
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
         {name => 'keys', text0 => \&html_template_keys},
         {name => 'nokeys', text0 => q{}},
         {name => 'entries', text0 => \&html_template_entries},
         {name => 'noentries', text0 => q{}},
         {name => 'list',
          text0 => \&html_template_list,
          text1 => \&html_template_list},
         {name => 'nolist',
          text0 => q{}},
         {name => 'numentries', text0 => \&html_template_numentries},
         {name => 'datatype',
          text0 => \&html_template_datatype,
          text1 => \&html_template_datatype},
         {name => 'nodatatype', text0 => q{}},
         {name => 'profdesc', text0 => \&html_template_profdesc},
         {name => 'noprofdesc', text0 => q{}},
         {name => 'hidden',
          text0 => q{{{marktemplate|hidden}}}.
              q{When read, this parameter returns {{null}}, }.
              q{regardless of the actual value.},
          text1 => q{{{marktemplate|hidden}}}.
              q{When read, this parameter returns ''$a[0]'', }.
              q{regardless of the actual value.}},
         {name => 'nohidden',
          text0 => q{}},
         {name => 'command',
          text0 => q{{{marktemplate|command}}}.
              q{The value of this parameter is not part of the device }.
              q{configuration and is always {{null}} when read.}},
         {name => 'nocommand', text0 => q{}},
         {name => 'factory',
          text0 => q{{{marktemplate|factory}}}.
              q{The factory default value MUST be ''$p->{factory}''.}},
         {name => 'nofactory', text0 => q{}},
         {name => 'null',
          text0 => \&html_template_null,
          text1 => \&html_template_null,
          text2 => \&html_template_null},
         {name => 'enum',
          text0 => \&html_template_enum,
          text1 => \&html_template_valueref,
          text2 => \&html_template_valueref,
          text3 => \&html_template_valueref},
         {name => 'noenum', text0 => q{}},
         {name => 'pattern',
          text0 => \&html_template_pattern,
          text1 => \&html_template_valueref,
          text2 => \&html_template_valueref,
          text3 => \&html_template_valueref},
         {name => 'nopattern', text0 => q{}},
         {name => 'reference',
          text0 => \&html_template_reference,
          text1 => \&html_template_reference,
          text2 => \&html_template_reference},
         {name => 'noreference', text0 => q{}},
         {name => 'units', text0 => \&html_template_units},
         {name => 'empty', text0 => q{an empty string}, ucfirst => 1},
         {name => 'false', text0 => q{''false''}},
         {name => 'true', text0 => q{''true''}},
         {name => 'marktemplate', text1 => \&html_template_marktemplate},
         {name => 'issue',
          text1 => \&html_template_issue,
          text2 => \&html_template_issue},
         {name => 'showid', text0 => \&html_template_showid},
         {name => 'br', text0 => q{<br/>}},
         {name => 'mark', text1 => q{<mark>$a[0]</mark>}},
         {name => 'sub', text1 => q{<sub>$a[0]</sub>}},
         {name => 'sup', text1 => q{<sup>$a[0]</sup>}},
         {name => 'ignore', text => q{}}
         ];

    # XXX need some protection against infinite loops here...
    # XXX do we want to allow template references to span newlines?
    # XXX insdel works for issues but not in general, e.g. when expanding
    #     references would like to know whether in deleted text so can
    #     suppress warnings
    while (my ($newline, $period, $insdel, $temp) =
           $inval =~ /(\n?)[ \t]*([\.\?\!]?)[ \t]*([\-\+]*)[ \t]*(\{\{.*)/) {
        # pattern returns rest of string in temp (owing to difficulty of
        # handling nested braces), so match braces to find end
        my $tref = extract_bracketed($temp, '{}');
        if (!defined($tref)) {
            emsg "$path: invalid template reference: $temp" unless 
                ($warnbibref < 0 && $temp =~ /^\{\{bibref/);
            $inval =~ s/\{\{/\[\[/;
            next;
        }
        my ($name, $args) = $tref =~ /^\{\{([^\|\}]*)(?:\|(.*))?\}\}$/;
        # XXX atstart is possibly useful for descriptions that consist only of
        #     {{enum}} or {{pattern}}?  I think not...
        if (!defined($name)) {
            emsg "$path: invalid template reference: $tref" unless
                ($warnbibref < 0 && $name eq 'bibref');
            $inval =~ s/\{\{/\[\[/;
            next;
        }
        my $atstart = $inval =~ /^\{\{\Q$name\E[\|\}]/;
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
                d2msg "$text: $cmd";
                my $ttext = eval "qq{$cmd}";
                if ($@) {
                    emsg $@;
                } else {
                    $text = $ttext;
                    $text = ucfirst $text if
                        $template->{ucfirst} && ($newline || $period);
                }
            }
        }
        if ($name && (!defined $text || $text =~ /^\[\[/)) {
            emsg "$path: invalid template reference: $tref"
                unless $compare || ($warnbibref < 0 && $name eq 'bibref');
            #emsg "$name: n=$n cmd=<$cmd> text=<$text>";
            #foreach my $a (@a) {
            #    emsg "  $a";
            #}
        }
        # process tref to avoid problems with RE special characters
        # XXX could/should use \Q and \E here (but won't change it now)
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
sub html_template_marktemplate
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
    my $counter = $deleted ? qq{''n''} : ++$issue_counter->{$prefix};

    # if not already deleted and issue has been addressed, mark accordingly
    my $mark = (!$deleted && $status) ? '---' : '';

    # if there is a status, include it
    $status = $status ? qq{ ($status)} : qq{};

    return qq{\n'''$mark$prefix $counter$status: $comment$mark'''};
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
    my $mpref = util_full_path($opts->{node}, 1);
    my $fpath = $mpref . $path;
    if (!util_is_defined($parameters, $fpath)) {
        # XXX don't warn if this item has been deleted
        if (!util_is_deleted($opts->{node})) {
            emsg "$object$param: reference to invalid parameter $path"
                unless $automodel;
        }
        return undef;
    }

    my $type = $parameters->{$fpath}->{type};
    my $syntax = $parameters->{$fpath}->{syntax};

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
        die "html_template_null: invalid primitive type: $primtype";
    }
}

# insert units string
sub html_template_units
{
    my ($opts) = @_;

    my $path = $opts->{path};
    my $units = $opts->{units};

    if (!$units) {
        emsg "$path: empty units string";
        return undef;
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

    my $text = qq{{{marktemplate|list-$type}}Comma-separated };
    $text .= syntax_string($type, $syntax, 1);
    $text .= qq{, $arg} if $arg;
    $text .= '.';

    return $text;
}

# Generate standard NumberOfEntries description.
sub html_template_numentries
{
    my ($opts) = @_;

    my $node = $opts->{node};
    my $path = $opts->{path};
    my $table = $opts->{table};

    my $text = qq{};
    $text .= qq{{{marktemplate|numentries}}} if $marktemplates;

    if (!$table) {
        emsg "$path: invalid use of {{numentries}}; parameter is " .
            "not associated with a table" unless util_is_deleted($node);
        return undef;
    } else {
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
        emsg "$path: invalid use of {{datatype}}; parameter is ".
            "not of a valid named data type";
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
    my $baseprof = $node->{baseprof};
    my $extendsprofs = $node->{extendsprofs};

    # XXX horrible hack for nameless profiles
    return '' unless $name;

    # model in which profile was first defined
    my $mpref = util_full_path($opts->{node}, 1);
    my $defmodel = $profiles->{$mpref.$name}->{defmodel};

    # same model but excluding minor version number
    my $defmodelmaj = $defmodel;
    $defmodelmaj =~ s/\.\d+$//;

    my $profs = [];
    push @$profs, $baseprof if $baseprof;
    push @$profs, @$extendsprofs if $extendsprofs && @$extendsprofs;
    my $plural = @$profs > 1 ? 's' : '';
    my $profnames = join ' ', map { $_->{name} } @$profs;

    if ($profnames) {
        $profnames =~ s/(\w+:\d+)/{{profile|$1}}/g;
        $profnames =~ s/ /, /g;
        $profnames =~ s/, ([^,]+$)/ and $1/;
    }

    my $text = $profnames ? qq{The} : qq{This table defines the};
    $text .= qq{ {{profile}} profile for the ''$defmodelmaj'' data model};
    $text .= qq{ is defined as the union of the $profnames profile$plural }.
        qq{and the additional requirements defined in this table} if $profnames;
    $text .= qq{.  The minimum REQUIRED version for this profile is }.
        qq{''$defmodel''.};

    return $text;
}

sub html_template_entries
{
    my ($opts) = @_;

    my $min = $opts->{minEntries};
    my $max = $opts->{maxEntries};

    my ($multi, $fixed, $union) = util_is_multi_instance($min, $max);

    # XXX note that (min,max) = (0,1) is NOT regarded as "multi"; it's too
    #     hard to generate sensible text in this case so we don't try
    return ($showunion ? qq{This object is a member of a union, i.e. } .
            qq{it is a member of a group of objects of which only one } .
            qq{can exist at a given time.} : qq{}) if $union;

    # don't say anything in the common (0,unbounded) case
    return qq{} if $min == 0 && $max eq 'unbounded';

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

    my $node = $opts->{node};
    my $object = $opts->{object};
    my $access = $opts->{access};
    my $uniqueKeys = $opts->{uniqueKeys};
    my $enableParameter = $opts->{enableParameter};

    my $text = qq{{{marktemplate|keys}}};

    # XXX various errors and warnings are suppressed if the object has been
    #     deleted; this case should be handled generally and not piecemeal
    my $is_deleted = util_is_deleted($node);

    # warn if there is a unique key parameter that's a list (this has been
    # banned since TR-106a7)
    # XXX experimental: warn is there is a unique key parameter that's a
    #     strong reference (this is a candidate for additional auto-text)
    my $anystrong = 0;
    my $anylist = 0;
    my $mpref = util_full_path($opts->{node}, 1);
    foreach my $uniqueKey (@$uniqueKeys) {
        my $keyparams = $uniqueKey->{keyparams};
        foreach my $parameter (@$keyparams) {
            my $fpath = $mpref . $object . $parameter;

            my $refType = util_is_defined($parameters, $fpath) ? 
                $parameters->{$fpath}->{syntax}->{refType} : undef;
            $anystrong = 1 if defined($refType) && $refType eq 'strong';

            my $list = util_is_defined($parameters, $fpath) ?
                $parameters->{$fpath}->{syntax}->{list} : undef;
            $anylist = 1 if $list;
        }
    }
    d0msg "$object: unique key parameter is a strong reference ($access)"
        if $anystrong && !$is_deleted;
    w1msg "$object: unique key parameter is list-valued"
        if $anylist && !$is_deleted;

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
                    my $fpath = $mpref . $object . $parameter;
                    my $defaulted =
                        util_is_defined($parameters, $fpath, 'default') &&
                        $parameters->{$fpath}->{deftype} eq 'object' &&
                        $parameters->{$fpath}->{defstat} ne 'deleted';
                    push @$params, $parameter unless $defaulted;
                    $i++;
                }
            }
            if ($i && !@$params) {
                emsg "$object: all unique key parameters are " .
                    "defaulted; need enableParameter";
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

    # pass node if supplied; otherwise values
    my $node_or_values = $opts->{node} ? $opts->{node} : $opts->{values};

    # XXX not using atstart (was "atstart or newline")
    my $pref = ($opts->{newline}) ? "" : $opts->{list} ?
        "Each list item is an enumeration of:\n" : "Enumeration of:\n";
    return $pref . xml_escape(get_values($node_or_values, !$nolinks));
}

sub html_template_pattern
{
    my ($opts) = @_;

    # pass node if supplied; otherwise values
    my $node_or_values = $opts->{node} ? $opts->{node} : $opts->{values};

    # XXX not using atstart (was "atstart or newline")
    my $pref = ($opts->{newline}) ? "" : $opts->{list} ?
        "Each list item matches one of:\n" :
        "Possible patterns:\n";
    return $pref . xml_escape(get_values($node_or_values, !$nolinks));
}

# report an object or parameter id
sub html_template_showid
{
    my ($opts) = @_;

    my $node = $opts->{node};
    my $id = $node->{id};

    # XXX would like to generate a link, but this fights with the auto-link
    #     logic; need to support a more mediawiki-like link syntax
    #my $text = qq{'''[http://oid-info.com/get/$id]'''};
    my $text = qq{'''[$id]'''};

    return $text;
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
        emsg "$path: {{bibref}} section argument was changed: ".
          "\"$origsection\" -> \"$section\""
          if $warnbibref > 1 && $origsection ne $section;
    }

    # when showing diffs, "name" can include deleted and inserted text
    $bibref =~ s|\-\-\-(.*?)\-\-\-||g;
    $bibref =~ s|\+\+\+(.*?)\+\+\+|$1|g;

    $bibref = html_get_anchor($bibref, 'bibref') unless $nolinks;
    
    my $text = qq{};
    $text .= qq{[};
    $text .= qq{$section/} if $section && !$bibrefdocfirst;
    $text .= qq{$bibref};
    $text .= qq{ $section} if $section && $bibrefdocfirst;
    $text .= qq{]};

    return $text;
}

# document name (expands to empty string)
sub html_template_docname
{
    my ($opts, $name) = @_;

    my $file = $opts->{file};
    $htmlbbf_info->{$file}->{document} = $name if
        $file && !defined $htmlbbf_info->{$file}->{document};

    return qq{};
}

# TR name (expands to empty string)
sub html_template_trname
{
    my ($opts, $name) = @_;

    # convert the TR-nnniiaacc form to tr-nnn-i-a-c (because it's documented)
    my ($tr, $nnn, $i, $a, $c) =
        ($name =~ /^(TR)-(\d+)(?:i(\d+))?(?:a(\d+))?(?:c(\d+))?$/);
    if (defined $tr  && defined $nnn) {
        $i = 1 unless defined $i;
        $a = 0 unless defined $a;
        $c = 0 unless defined $c;
        $name = qq{tr-$nnn-$i-$a-$c};
    }

    my $file = $opts->{file};
    $htmlbbf_info->{$file}->{trname} = $name if
        $file && !defined $htmlbbf_info->{$file}->{trname};

    return qq{};
}

# TR reference
# XXX expects spec or full TR name; should allow it to take names of the
#     form TR-069a5; should also allow optional link text?
sub html_template_trref
{
    my ($opts, $trname) = @_;

    my $trlink = util_doc_link($trname);
    return qq{[$trlink $trname]};
}

# approval date (expands to empty string)
sub html_template_appdate
{
    my ($opts, $date) = @_;

    my $file = $opts->{file};
    $htmlbbf_info->{$file}->{appdate} = $date if
        $file && !defined $htmlbbf_info->{$file}->{appdate};

    return qq{};
}

# generates reference to XML document: arguments are document name (.xml
# extension optional) and optional display text (defaults to document name)
sub html_template_xmlref
{
    my ($opts, $docname, $text) = @_;

    my $xmlrefmap = $opts->{xmlrefmap};
    my $file = $opts->{file};
    my $latest = $opts->{latest};
    my $outdated = $opts->{outdated};

    $outdated = 0 unless defined $outdated;

    $text = $docname unless $text;
    $docname .= '.xml' unless $docname =~ /\.xml$/;

    # docname might omit the corrigendum; if so, replace with latest
    # XXX there are too many places where file names are parsed like this
    # XXX this logic is not perfect, because "latest" and "docname" could
    #     refer to different TRs, in which case the latest corrigendum of
    #     docname is not known; in this case, the link will omit the
    #     corrigendum number and the file will probably appear as though it's
    #     an outdated corrigendum :(
    my ($cat1, $n1, $i1, $a1, $c1, $label1) =
        $latest =~ /^([^-]+)-(\d+)-(\d+)?-(\d+)(?:-(\d+))?(\d*\D.*)?\.xml$/
        if $latest;
    my ($cat2, $n2, $i2, $a2, $c2, $label2) =
        $docname =~ /^([^-]+)-(\d+)-(\d+)?-(\d+)(?:-(\d+))?(\d*\D.*)?\.xml$/;
    my $samedoc = defined $cat1 && defined $cat2 &&
        defined $n1 && defined $n2 && defined $i1 && defined $i2 &&
        defined $a1 && defined $a2 &&
        $cat1 eq $cat2 && $n1 == $n2 && $i1 == $i2 && $a1 == $a2;
    $docname = $latest if $samedoc && !defined $c2;

    # determine whether to generate a link
    my $link = !$samedoc ||
        (!$outdated && $docname ne $latest) ||
        ( $outdated && $docname eq $latest);

    $text = qq{<a href="#$docname">$text</a>} if $link;

    # only add if not already there
    push @{$xmlrefmap->{$file}}, $docname if
        $xmlrefmap && $file && !grep {$_ eq $docname} @{$xmlrefmap->{$file}};

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
        emsg "$object: {{param}} is appropriate only within a ".
            "parameter description" unless $param;
        return qq{''$param''};
    }

    # when showing diffs, "name" can include deleted and inserted text
    $name =~ s|\-\-\-(.*?)\-\-\-||g;
    $name =~ s|\+\+\+(.*?)\+\+\+|$1|g;

    w0msg "$object$param: {{param}} argument is unnecessary when ".
        "referring to current parameter" if $name eq $param;

    (my $path, $name) = relative_path($object, $name, $scope);
    my $mpref = util_full_path($opts->{node}, 1);
    my $fpath = $mpref . $path;
    my $invalid = util_is_defined($parameters, $fpath) ? '' : '?';
    # XXX don't warn of invalid references for UPnP DM (need to fix!)
    $invalid = '' if $upnpdm;
    # XXX don't warn further if this item has been deleted
    if (!util_is_deleted($opts->{node})) {
        emsg "$object$param: reference to invalid parameter $path"
            if $invalid && !$automodel;
        # XXX make this nicer (not sure why test of status is needed here but
        #     upnpdm triggers "undefined" errors otherwise
        if (!$invalid && $parameters->{$fpath}->{status} &&
            $parameters->{$fpath}->{status} eq 'deleted') {
            w0msg "$object$param: reference to deleted parameter ".
                "$path" if !$showdiffs;
            $invalid = '!';
        }
    }

    $name = qq{''$name$invalid''};
    $name = html_get_anchor($fpath, 'path', $name) unless $nolinks;

    return $name;
}

# generates reference to object: arguments are object name and optional
# scope
sub html_template_objectref
{
    my ($opts, $name, $scope) = @_;

    my $object = $opts->{object};
    my $param = $opts->{param};

    my $mpref = util_full_path($opts->{node}, 1);

    # parameterless case (no "name") is special; use just the last component
    # of the path (don't generate link from object to itself)
    # XXX this is an experiment
    unless ($name) {
        my $name = $object;
        $name =~ s/\.(\{i\}\.)?$//;
        $name =~ s/.*\.//;
        $name = qq{''$name''};
        $name = html_get_anchor($mpref.$object, 'path', $name)
            unless $nolinks || !$param;
        return $name;
    }

    # when showing diffs, "name" can include deleted and inserted text
    $name =~ s|\-\-\-(.*?)\-\-\-||g;
    $name =~ s|\+\+\+(.*?)\+\+\+|$1|g;

    # XXX this needs to be cleverer, since "name" can take various forms
    w0msg "$object$param: {{object}} argument unnecessary when ".
        "referring to current object" if $name && $name eq $object;

    (my $path, $name) = relative_path($object, $name, $scope);
    my $path1 = $path;
    $path1 .= '.' if $path1 !~ /\.$/;

    # we allow reference to table X via "X" or "X.{i}"...
    my $path2 = $path1;
    $path2 .= '{i}.' if $path2 !~ /\{i\}\.$/;

    # XXX horrible
    $path = $path1 if util_is_defined($objects, $mpref.$path1);
    $path = $path2 if util_is_defined($objects, $mpref.$path2);
    my $fpath = $mpref . $path;

    # XXX if path starts ".Services." this is a reference to another data
    #     model, so no checks and no link
    return qq{''$name''} if $path =~ /^\.Services\./;

    my $invalid = util_is_defined($objects, $fpath) ? '' : '?';
    # XXX don't warn of invalid references for UPnP DM (need to fix!)
    $invalid = '' if $upnpdm;
    # XXX don't warn further if this item has been deleted
    if (!util_is_deleted($opts->{node})) {
        emsg "$object$param: reference to invalid object $path"
            if $invalid && !$automodel;
        # XXX make this nicer (not sure why test of status is needed here but
        #     upnpdm triggers "undefined" errors otherwise
        if (!$invalid && $objects->{$fpath}->{status} &&
            $objects->{$fpath}->{status} eq 'deleted') {
            w0msg "$object$param: reference to deleted object $path"
                if !$showdiffs;
            $invalid = '!';
        }
    }

    $name = qq{''$name$invalid''};
    $name = html_get_anchor($fpath, 'path', $name) unless $nolinks;

    return $name;
}

# generates reference to enumeration or pattern: arguments are value, optional
# parameter name (if omitted, is this parameter), and optional scope
sub html_template_valueref
{
    my ($opts, $value, $name, $scope) = @_;

    my $object = $opts->{object};
    my $param = $opts->{param};

    # if object or param not defined, we are probably in a data type definition
    # so just return the italicised value
    return qq{''$value''} unless defined($object) && defined($param);

    my $this = $name ? 0 : 1;
    $name = $param unless $name;

    # when showing diffs, "value" and "name" can include deleted and inserted
    # text
    $value =~ s|\-\-\-(.*?)\-\-\-||g;
    $value =~ s|\+\+\+(.*?)\+\+\+|$1|g;

    $name =~ s|\-\-\-(.*?)\-\-\-||g;
    $name =~ s|\+\+\+(.*?)\+\+\+|$1|g;

    (my $path, $name) = relative_path($object, $name, $scope);

    my $invalid = '';
    # XXX don't warn of invalid references for UPnP DM (need to fix!)
    my $mpref = util_full_path($opts->{node}, 1);
    my $fpath = $mpref . $path;
    if (!util_is_defined($parameters, $fpath)) {
        $invalid = '?';
        $invalid = '' if $upnpdm;
        # XXX don't warn further if this item has been deleted
        if (!util_is_deleted($opts->{node})) {
            emsg "$object$param: reference to invalid parameter ".
                "$path" if $invalid && !$automodel;
            # XXX make this nicer (not sure why test of status is needed here
            #     but upnpdm triggers "undefined" errors otherwise
            if (!$invalid && $parameters->{$fpath}->{status} &&
                $parameters->{$fpath}->{status} eq 'deleted') {
                w0msg "$object$param: reference to deleted parameter ".
                    "$path" if !$showdiffs;
                $invalid = '!';
            }
        }
    } else {
        my $node = $parameters->{$fpath};
        # XXX experimental: try to follow enumerationRefs
        my $syntax = $node->{syntax};
        if ($syntax->{reference} && $syntax->{reference} eq 'enumerationRef') {
            my $targetParam = $syntax->{targetParam};
            my $targetParamScope = $syntax->{targetParamScope};
            my ($targetPath) = relative_path($node->{pnode}->{path},
                                             $targetParam, $targetParamScope);
            if (!util_is_defined($parameters, $mpref.$targetPath)) {
                emsg "$path: enumerationRef references non-existent ".
                    "parameter $targetPath: ignored";
            } else {
                $path = $targetPath;
                $fpath = $mpref . $path;
                $node = $parameters->{$fpath};
            }
        }
        my $values = $node->{values};
        $invalid = (has_values($values) && has_value($values, $value)) ?
            '' : '?';
        $invalid = '' if $upnpdm;
        # XXX don't warn further if this item has been deleted
        if (!util_is_deleted($opts->{node})) {
            emsg "$object$param: reference to invalid value $value"
                if $invalid && !$automodel;
            if (!$invalid && $values->{$value}->{status} eq 'deleted') {
                w0msg "$object$param: reference to deleted value ".
                    "$value" if !$showdiffs;
                $invalid = '!';
            }
        }
    }

    # XXX edit backslashes and dots (such cleanup needs to be done properly)
    # XXX would prefer not to have to know link format
    my $tvalue = $value;
    $tvalue =~ s/\\//g;
    $tvalue =~ s/\./_/g;
    my $sep = $upnpdm ? '/' : '.';

    $value = qq{''$value$invalid''};
    $value = html_get_anchor(qq{$fpath$sep$tvalue}, 'value', $value)
        unless $this || $nolinks;
   
    return $value;
}

# generates reference to profile: optional argument is the profile name
sub html_template_profileref
{
    my ($opts, $profile) = @_;

    my $mpref = util_full_path($opts->{node}, 1);

    my $makelink = $profile && !$nolinks;

    $profile = $opts->{profile} unless $profile;

    my $tprofile = $profile;
    $profile = qq{''$profile''};
    $profile = html_get_anchor($mpref.$tprofile, 'profile', $profile)
        if $makelink;

    return $profile;
}

sub html_template_reference
{
    my ($opts, $arg1, $arg2) = @_;

    my $object = $opts->{object};
    my $path = $opts->{path};
    my $type = $opts->{type};
    my $list = $opts->{list};
    my $reference = $opts->{reference};
    my $syntax = $opts->{syntax};

    # if the second arg is supplied, it is a comma-separated list of keywords;
    # currently supported keywords are:
    # - delete : (delete if null) this reference can never be NULL, i.e. the
    #            referencing object and the referenced object have the same
    #            lifetime
    # - ignore : (ignore if non-existent) ignore any targetParents that do not
    #            exist (this allows a reference parameter to list targets that
    #            exist in only some of the data models in which it is to be
    #            used (e.g. to reference the Host table, which doesn't exist in
    #            Device:1)
    my ($delete, $ignore) = (0, 0);
    if (defined $arg2) {
        my @keys = split(/,/, $arg2);
        foreach my $key (@keys) {
            if ($key eq 'delete') {
                $delete = 1;
            } elsif ($key eq 'ignore') {
                $ignore = 1;
            } else {
                emsg "$path: {{reference}} has invalid argument: $arg2";
            }
        }
    }

    my $text = qq{};

    if (!defined $reference) {
        emsg "$path: {{reference}} used on non-reference parameter";
        return qq{[[reference]]};
    }

    my $refType = $syntax->{refType} || '';
    $text .= qq{\{\{marktemplate|$reference};
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
        my $targetParentTemp = '';
        my $targetParentFixed = 0;
        if ($targetParent) {
            $targetParentFixed = 1;
            foreach my $tp (split ' ', $targetParent) {
                my ($tpp) = relative_path($object, $tp, $targetParentScope);

                # check for (and ignore) spurious trailing "{i}." when
                # targetType is "row" (it's a common error)
                if ($targetType eq 'row') {
                    if ($tpp =~ /\{i\}\.$/) {
                        w0msg "$path: trailing \"{i}.\" ignored in ".
                            "targetParent (targetType \"row\"): $tp";
                    } else {
                        $tpp .= '{i}.';
                    }
                    # $tpp is now the table object (including "{i}.")
                }

                my $mpref = util_full_path($opts->{node}, 1);
                my $tpn = $objects->{$mpref.$tpp};

                # maintain a list consisting only of those targetParent items
                # that exist
                if ($tpn) {
                    $targetParentTemp .= ' ' if $targetParentTemp;
                    $targetParentTemp .= $tp;
                }

                # if targetParent item doesn't exist, but ignoring non-existent
                # ones, quietly proceed to the next item
                elsif ($ignore) {
                    next;
                }

                # XXX heuristically suppress error message in some cases
                elsif ($tpp !~ /^\.Services\./ && !$automodel) {
                    emsg "$path: targetParent doesn't exist: $tp";
                }

                $targetParentFixed = 0 if $tpn && !$tpn->{fixedObject};
            }
        }

        # if ignoring non-existent targetParent items, replace targetParent
        # with those that do exist
        my $empty = 0;
        if ($ignore) {
            $empty = $targetParent && !$targetParentTemp;
            $targetParent = $targetParentTemp;
            $targetParentFixed = 0 if !$targetParent;
        }

        # if some targetParent items were specified but none exist, this is
        # a special case and the parameter value always has to be empty
        if ($empty) {
            $text = qq{None of the possible target objects exist in } .
                qq{this data model, so the parameter value MUST be {{empty}}.};
            return $text;
        }

        $targetParent = object_references($targetParent,
                                          $targetParentScope);

        $text .= qq{MUST be the path name of };

        if ($targetType eq 'row') {
            if ($arg1) {
                $text .= $arg1;
            } else {
                my $s = $targetParent =~ / / ? 's' : '';
                $text .= $targetParent ?
                    qq{a row in the $targetParent table$s} :
                    qq{a table row};
            }
        } else {
            $targetType =~ s/single/single-instance object/;
            $targetType =~ s/any/parameter or object/;
            if ($arg1) {
                $text .= $arg1;
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
                $text .= qq{  If the referenced $targetType is deleted, };
                if ($delete) {
                    $text .= qq{this instance MUST also be deleted (so the } .
                        qq{parameter value will never be {{empty}}).};
                } else {
                    $text .= qq{the };
                    $text .= $list ?
                        qq{corresponding item MUST be removed from the list.} :
                        qq{parameter value MUST be set to {{empty}}.};
                }
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
        # XXX pathRef has no equivalent of the following text
        $text .= qq{, or else be $nullValue if no row is currently } .
            qq{referenced} unless $delete || $list;
        $text .= qq{.};
        if ($refType eq 'strong') {
            $text .= qq{  If the referenced row is deleted, };
            if ($delete) {
                $text .= qq{this instance MUST also be deleted (so the } .
                    qq{parameter value will never be $nullValue).};
            } else {
                $text .= qq{the };
                $text .= $list ?
                    qq{corresponding item MUST be removed from the list.} :
                    qq{parameter value MUST be set to $nullValue.};
            }
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
            #emsg "$parent $name $nlev" if $nlev;
            my @comps = split /$sepp/, $parent;
            splice @comps, -$nlev;
            $parent = join $sep, @comps;
            $parent =~ s/\{/\.\{/g;
            $parent .= '.' if $parent;
            emsg "$tparent: $name has too many $par characters"
                unless $parent;
            $name =~ s/^$parp*\.?//;
            # if name is empty, will use final component of parent
            $name2 = $comps[-1] || '';
            $name2 =~ s/\{.*//;
            #emsg "$parent $name $name2" if $nlev;
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
# hyperlinks can be either bare URLs, in which case the URL appears literally,
# or else of the form [URL TEXT] in which case the TEXT appears in the HTML
# and links to URL (any punctuation or whitespace in URL has to be percent
# escaped)
sub html_hyperlink
{
    my ($inval) = @_;

    # XXX need a better set of URL characters
    my $last = q{\w\d\:\~\/\?\&\=\-\%\#};
    my $notlast = $last . q{\.};

    # URL => <a href=URL">URL</a>
    $inval =~ s|([a-z]+://[$notlast]*[$last])|<a href="$1">$1</a>|g;

    # [<a href="URL">URL</a> TEXT] => <a href="URL">TEXT</a>
    #  |-----$1-----|$2||$3| |$4|
    $inval =~ s|\[(\<[^\>]+\>)([^\<]+)(\<[^\>]+\>)\s+([^\]]+)\]|$1$4$3|g;

    # XXX allow file://#ANCHOR but this is an invalid URL, so remove the
    #     file:// bit; it would be better instead to support the mediawiki-
    #     like [[#fragment]] syntax
    $inval =~ s|file://\#|\#|g;

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

    # XXX experimental four or more hyphens on their own line -> horiz rule
    $inval =~ s|^-{4,}\n|<hr>|g;
    $inval =~ s|\n-{4,}\n|<hr>|g;
    $inval =~ s|\n-{4,}$|<hr>|g;

    # XXX experimental ---text--- to indicate deletion and +++text+++ insertion
    $inval =~ s|\-\-\-([^\n]*?)\-\-\-|<span class="d">$1</span>|gs;
    $inval =~ s|\+\+\+([^\n]*?)\+\+\+|<span class="i">$1</span>|gs;

    $inval =~ s|\-\-\-(.*?)\-\-\-|<div class="d">$1</div>|gs;
    $inval =~ s|\+\+\+(.*?)\+\+\+|<div class="i">$1</div>|gs;

    # XXX experimental -- -> en-dash (not --- -> em-dash for now because that
    #     conflicts with deleted text; change char sequence for deleted text?)
    #$inval =~ s|---|&#8212;|g;
    $inval =~ s|--|&#8211;|g;

    # XXX "%%" anchor expansion should be elsewhere (hyperlink?)
    # XXX need to escape special characters out of anchors and references
    # XXX would prefer not to have to know link format
    if ($opts->{param}) {
        #my $object = $opts->{object} ? $opts->{object} : '';
        #my $path = $object . $opts->{param};
        my $prefix = html_anchor_namespace_prefix('value');
        my $fpath = util_full_path($opts->{node});
        $inval =~ s|%%([^%]*)%%([^%]*)%%|<a name="$prefix$fpath.$2">$1</a>|g;
    }

    return $inval;
}

# Process paragraph breaks
# XXX this assumes that leading spaces are left on verbatim lines
# XXX lines that start with character formatting tags are treated specially
sub html_paragraph
{
    my ($inval) = @_;

    my $outval = '';
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {

        # XXX if add a character formatting tag here, need to add it below too;
        #     should use a pattern variable but I am not 100% confident here...
        $line =~ s/$/<p>/ if
            $line =~ /^(<b>|<i>|<sub>|<sup>|<mark>|<span)/ ||
            $line !~ /^(\s|\s*<)/;

        $outval .= "$line\n";
    }

    # removing trailing <p> (see note below); the idea is that text that
    # doesn't contain multiple paragraphs will not contain any <p> tags
    $outval =~ s/(<p>)?\n$//;

    # XXX need to fix use of <p> properly (i.e. <p>para</p>) but currently
    #     it's used as a paragraph separator; as a partial workaround, and
    #     using the same criterion as that used above, it puts a <p> at the
    #     start if there is least one there already
    $outval =~ s/^/<p>/ if 
        $outval =~ /<p>/ &&
        ($outval =~ /^(<b>|<i>|<sub>|<sup>|<mark>|<span)/ ||
         $outval !~ /^(\s|\s*<)/);

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
# Similar output to that proposed for the CWMP web page at
# http://www.broadband-forum.org/cwmp.php.
#
# implementation concepts are similar to those for the bbf148 ("OD-148")
# report.

# pattern matching filenames of support files (hopefully this pattern will
# never need to change; note that it's agnostic to presence or absence of
# version number)
# XXX should put this info in the config file
my $htmlbbf_supportpatt = q{^tr-(069|106).*-(types|biblio)\.xml$};

# pattern matching filenames or specs that define both the IGD and Dev root
# data models (this list will never need to change)
# XXX should put this info in the config file
my $htmlbbf_igddevpatt = q{^tr-(143-1-0|157-1-[0123])-};

# pattern matching filenames that currently use "file-last.html" for "diffs"
# HTML on the BBF web site CWMP page (note that these all include corrigendum
# numbers)
# XXX should put this info in the config file
my $htmlbbf_lastpatt = q{^tr-(098-1-[023]-0|104-1-1-0|106-[12]-0|135-1-[12]-0|140-1-[12]-0|143-1-0-1|157-[123]-0|181-1-[01]-0|181-2-[123]-0|196-1-1-0)\.xml$};

# Global settings from config file (htmlbbf_info is declared earlier because
# it's used in some template expansions).
my $htmlbbf_global = {};

# this maps full filenames to a list of other filenames that they reference
# via the {{xmlref}} template; this is used in deciding which files to list
# in the "Outdated" section
my $htmlbbf_xmlrefmap = {};

sub htmlbbf_init
{
    # parse config file (http://en.wikipedia.org/wiki/INI_file)
    #
    # the config structure is a two-level hash; the top-level is the section
    # and the second-level is the properties
    #
    # XXX see OD-148.txt for the details
    return unless $configfile;

    my $known_props = q{document|description|descr_model|trname|appdate};

    require Config::IniFiles;

    my ($dir, $file) = main::find_file($configfile, '');
    $configfile = File::Spec->catfile($dir, $file) if $dir;

    my %config;
    tie %config, 'Config::IniFiles', ( -file => $configfile,
                                       -allowcontinue => 1 );
    my $config = \%config;
    if (@Config::IniFiles::errors) {
        foreach my $error (@Config::IniFiles::errors) {
            emsg "$configfile: $error";
        }
    } elsif (%$config) {
        foreach my $section (sort keys %$config) {

            # global
            if ($section eq 'global') {
                my $values = $config->{$section};
                foreach my $prop (sort keys %$values) {
                    my $value = $values->{$prop};
                    $value = join "\n", @$value if ref $value eq 'ARRAY';
                    $htmlbbf_global->{$prop} = $value;
                }
            }

            # file name
            else {
                my $file = $section;
                my $values = $config->{$file};
                foreach my $prop (sort keys %$values) {
                    my $value = $values->{$prop};
                    $value = join "\n", @$value if ref $value eq 'ARRAY';
                    if ($prop !~ /$known_props/) {
                        emsg "$configfile: $file unexpected: " .
                            "$prop = \"$value\"";
                    }
                    $htmlbbf_info->{$file}->{$prop} = $value;
                }
            }
        }
    }
}

# XXX this is effectively copied from html_node; not all styles are used
# XXX note use of hard-coded vertical alignment "middle", which isn't good
#     for very large cells (it should be set on a per-column basis)
# XXX there are other things like that, e.g. could center the version column
sub htmlbbf_begin
{
    # styles
    my $table = qq{text-align: left;};
    my $row = qq{vertical-align: middle;};
    my $center = qq{text-align: center;};

    # font
    my $h1font = qq{font-family: helvetica,arial,sans-serif; font-size: 14pt;};
    my $h2font = qq{font-family: helvetica,arial,sans-serif; font-size: 12pt;};
    my $h3font = qq{font-family: helvetica,arial,sans-serif; font-size: 10pt;};
    my $font = qq{font-family: helvetica,arial,sans-serif; font-size: 8pt;};

    # others
    my $sup_valign = qq{vertical-align: super;};
    my $theader_bg = qq{background-color: rgb(153, 153, 153);};

    # introductory text
    my $intro = $htmlbbf_global->{intro};
    $intro = <<END unless $intro;
    [${trpage}TR-181i2%20Overview.pdf Overview of the Device:2 Root Data Model in TR-069 Family of Specifications]
    The available data model definitions and XML Schemas for the TR-069 suite of documents are listed below.

END

    # handle any footnotes within the introductory text
    # XXX footnotes are currently handled locally but general footnote support
    #     might be added later
    my $footnotes = [];
    my $footpatt = q{(\{\{footnote\|.*)};
    my $footcount = 0;
    while ($intro =~ /$footpatt/) {
        $footcount++;
        my ($footref) = $intro =~ /$footpatt/;
        $footref = extract_bracketed($footref, '{}');
        my ($footnote) = $footref =~ /{{footnote\|(.*)}}/;
        $intro =~ s/\Q$footref\E/{{sup|$footcount}}/;
        push @$footnotes, $footnote;
    }
    $intro .= qq{{{footnotes}}} if @$footnotes && $intro !~ /{{footnotes}}/;
    my $foottext = qq{};
    $footcount = 0;
    foreach my $footnote (@$footnotes) {
        $footcount++;
        $foottext .= qq{{{sup|$footcount}} $footnote\n};
    }
    $intro =~ s/{{footnotes}}\s*/$foottext/;

    # escape the introductory text
    $intro = html_escape($intro);

    # header
    # XXX should put standard header and footer info, as for the HTML report
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
      sup { $sup_valign }
      table { $table }
      th { $row $font }
      th.g { $row $font $theader_bg }
      td, td.p { $row $font }
      td.pc { $row $font $center }
    </style>
  </head>
  <body>
    <h1>CPE WAN Management Protocol (CWMP)</h1>
    $intro

END

    # XXX temporary until are sure that it works
    my $allfiles = $files2;

    # first determine heuristically which ones are support files and components
    # (schema files are already identified in $allfiles)
    # XXX this modifies the $allfiles element, but should do no harm
    foreach my $file (@$allfiles) {
        my $name = $file->{name};
        my $models = $file->{models};
        if ($file->{schema}) {
        } elsif ($name =~ /$htmlbbf_supportpatt/) {
            $file->{support} = 1;
        } elsif ($name =~ /$htmlbbf_igddevpatt/ ||
                 !defined $models || !@$models) {
            $file->{component} = 1;
        }
    }

    # data models (use version of $allfiles with one model per entry)
    my $modelfiles = [];
    foreach my $file (@$allfiles) {
        my $models = $file->{models};
        foreach my $model (@$models) {
            my $tmpfile = util_copy($file, ['models']);
            $tmpfile->{model} = $model;
            push @$modelfiles, $tmpfile;
        }
    }

    # open the table of contents
    print <<END;
    <ul>
END

    # latest versions of root and service data models
    my $latestcontext = htmlbbf_file(undef, {
        model => 1, root => 1, service => 1, title => 'Latest Data Models',
        header => 1, latestcolumn => 'version', noanchors => 1,
        noseparator => 1, reverserows => 1});
    foreach my $file (sort htmlbbf_model_cmp @$modelfiles) {
        htmlbbf_file($file, {context => $latestcontext});
    }
    htmlbbf_file(undef, {context => $latestcontext, contents => 1});

    # root data models
    my $rootcontext = htmlbbf_file(undef, {
        model => 1, root => 1, title => 'Root Data Models', header => 1,
        reverserows => 1});
    foreach my $file (sort htmlbbf_model_cmp @$modelfiles) {
        htmlbbf_file($file, {context => $rootcontext});
    }
    htmlbbf_file(undef, {context => $rootcontext, contents => 1});

    # service data models
    my $servicecontext = htmlbbf_file(undef, {
        model => 1, service => 1, title => 'Service Data Models',
        header => 1, reverserows => 1});
    foreach my $file (sort htmlbbf_model_cmp @$modelfiles) {
        htmlbbf_file($file, {context => $servicecontext});
    }
    htmlbbf_file(undef, {context => $servicecontext, contents => 1});

    # components
    my $componentcontext = htmlbbf_file(undef, {
        component => 1, title => 'Component Definitions', header => 1,
        reverserows => 1});
    foreach my $file (sort htmlbbf_component_cmp @$allfiles) {
        htmlbbf_file($file, {context => $componentcontext});
    }
    htmlbbf_file(undef, {context => $componentcontext, contents => 1});

    # schemas
    my $schemacontext = htmlbbf_file(undef, {
        schema => 1, title => 'Schema Files', header => 1, reverserows => 1});
    foreach my $file (sort htmlbbf_schema_cmp @$allfiles) {
        htmlbbf_file($file, {context => $schemacontext});
    }
    htmlbbf_file(undef, {context => $schemacontext, contents => 1});

    # support files
    my $supportcontext = htmlbbf_file(undef, {
        support => 1, title => 'Support Files', header => 1, reverserows => 1});
    foreach my $file (sort htmlbbf_support_cmp @$allfiles) {
        htmlbbf_file($file, {context => $supportcontext});
    }
    htmlbbf_file(undef, {context => $supportcontext, contents => 1});

    # outdated corrigenda; identified via {{xmlref}}) templates in the other
    # files; populate the list (it's like a pared-down $allfiles)
    my $outdatedfiles = [];
    foreach my $name (keys %$htmlbbf_xmlrefmap) {
        my $rfiles = $htmlbbf_xmlrefmap->{$name};
        foreach my $rfile (@$rfiles) {

            # this test ignores files that are not outdated
            next if grep {$_->{name} eq $rfile} @$allfiles;

            # this test ignores files that are already in the list of outdated
            # files (this should never happen, but it could, e.g. if there were
            # multiple {{xmlref}} references to the same outdated file)
            next if grep {$_->{name} eq $rfile} @$outdatedfiles;

            # take the description, TR name and approval date from the latest
            # file
            my ($file) = grep {$_->{name} eq $name} @$allfiles;
            my $description = $file->{description};
            my $trname = $file->{trname};
            my $appdate = $file->{appdate};

            # override with latest file info from the config file if defined
            # explicitly
            my $info = $htmlbbf_info->{$name};
            $description = $info->{description} if $info->{description};
            $trname = $info->{trname} if $info->{trname};
            $appdate = $info->{appdate} if $info->{appdate};

            # note the name of the file that references the outdated file
            # (this is used when deciding whether to create links)
            push @$outdatedfiles, {name => $rfile, latest => $name,
                                   description => $description,
                                   trname => $trname, appdate => $appdate,
                                   outdated => 1};
        }
    }

    my $outdatedcontext = htmlbbf_file(undef, {
        outdated => 1, title => 'Outdated Corrigenda', header => 1,
        reverserows => 1});
    foreach my $file (sort htmlbbf_component_cmp @$outdatedfiles) {
        htmlbbf_file($file, {context => $outdatedcontext});
    }
    htmlbbf_file(undef, {context => $outdatedcontext, contents => 1});

    # downloads (table of contents)
    print <<END;
      <b><a href="#Downloads">Downloads</a></b>
END

    # close the table of contents
    print <<END;
    </ul>

END

    # output the tables
    foreach my $context (($latestcontext, $rootcontext, $servicecontext,
                          $componentcontext, $schemacontext, $supportcontext,
                          $outdatedcontext)) {
        htmlbbf_file(undef, {context => $context, footer => 1});
    }

    # downloads (content)
    print <<END;
    <a name="Downloads"><h1>Downloads</h1></a>
    <a href="cwmp.zip">cwmp.zip</a>: directory contents<br>
END

    # footer
    print <<END;
  </body>
</html>
END
}

# compare schema files; $allfiles elements are passed and the comparison is
# based on file name, with the following order:
#
#   cwmp-devicetype-<non-number>
#   cwmp-devicetype-<rest>
#   cwmp-datamodel-<non-number>
#   cwmp-datamodel-<rest>
#   <rest>
#   cwmp-<number>
#
# within the above categories, the order is alphabetical
sub htmlbbf_schema_cmp
{
    my @n = ($a->{name}, $b->{name});
    my @c = (undef, undef); 

    for (my $i = 0; $i < 2; $i++) {
        $c[$i] =
            ($n[$i] =~ /^cwmp-\d/)            ? 6 :
            ($n[$i] =~ /^cwmp-datamodel-\D/)  ? 3 :
            ($n[$i] =~ /^cwmp-datamodel-/)    ? 4 :
            ($n[$i] =~ /^cwmp-devicetype-\D/) ? 1 :
            ($n[$i] =~ /^cwmp-devicetype-/)   ? 2 : 5;
    }

    return ($c[0] == $c[1]) ? (lc($n[0]) cmp lc($n[1])) : ($c[0] <=> $c[1]);
}

# compare support files; $allfiles elements are passed and the comparison is
# based on file name
sub htmlbbf_support_cmp
{
    return ($a->{name} cmp $b->{name});
}

# compare component files; $allfiles elements are passed and the comparison is
# based on file name
sub htmlbbf_component_cmp
{
    return (lc($a->{name}) cmp lc($b->{name}));
}

# compare model files; $allfiles-like elements are passed and the
# comparison is based on model name, major version, minor version
#
# the actual elements are not $allfiles, because some files define multiple
# models; so $allfiles element {models => [m1, m2], ...} is replicated into
# {model => m1, ...}, {model => m2, ...} before sorting
sub htmlbbf_model_cmp
{
    my @f = ($a->{name}, $b->{name});
    my @m = ($a->{model}, $b->{model});

    # if both don't contain models (this can't happen), return 0 (no change)
    return 0 unless $m[0] && $m[1];

    my @n = (undef, undef);
    my @s = (undef, undef);
    my @x = (undef, undef);
    my @y = (undef, undef);
    my @z = (undef, undef);
    for (my $i = 0; $i < 2; $i++) {
        my $name = $m[$i]->findvalue('@name');
        ($n[$i], $x[$i], $y[$i]) = ($name =~ /([^:]+):(\d+)\.(\d+)/); 
        $s[$i] = boolean($m[$i]->findvalue('@isService'));
        # XXX this is a hack to place TR-143 before TR-106a2
        $z[$i] = ($f[$i] =~ /^tr-143-1-0/) ? 0 : 1;
   }

    return
        ($n[0] ne $n[1]) ? (htmlbbf_model_name_cmp(@f, @n, @s)) :
        ($x[0] != $x[1]) ? ($x[0] <=> $x[1]) : 
        ($y[0] != $y[1]) ? ($y[0] <=> $y[1]) : ($z[0] <=> $z[1]);
}

# helper for the above; is passed file names, model names (no version) and
# whether they are services, e.g. ("tr-181-2-1-0.xml", "tr-104-1-2-0.xml",
# "Device", "VoiceService", 0, 1)
#
# is called only when model names are different
#
# Service Objects ordered by file name (TR number) followed by Root Objects
# ordered by file name (TR number) but with IGD last
#
# note: IGD exception avoids intermingling triggered by past use of 143 and 157
# for root objects
#
# note: reporting in reverse order eventually puts Device:2 first
sub htmlbbf_model_name_cmp
{
    my ($f1, $f2, $n1, $n2, $s1, $s2) = @_;

    # one is root and the other is service; service object comes first
    if ($s1 != $s2) {
        return ($s2 <=> $s1);
    }

    # both are root or service objects (note IGD exception)
    else {
        return
            ($n1 eq 'InternetGatewayDevice') ? -1 :
            ($n2 eq 'InternetGatewayDevice') ?  1 : (lc($f1) cmp lc($f2));
    }

    # can't get here
    return 0;
}

# dummy (needed in order to indicate that report type is valid)
sub htmlbbf_node
{
}

# there are four file categories (schema, support, component, model); the file
# category is passed in the opts argument
#
# for models, additional root and/or service booleans are passed in the 
# opts argument
#
# an outdated boolean (actually in both the file and the opts argument)
# indicates that the file is outdated; such files have no HTML column and
# always have a Description column
#
# the routine is assumed to be called in the correct presentation order for
# the files; consecutive rows with the same content are spanned
sub htmlbbf_file
{
    my ($file, $opts) = @_;

    my $context = $opts->{context};

    # header (c.f. constructor)
    if ($opts->{header}) {
        # create context (note that it contains all opts)
        $context = $opts;

        # conditional column rules are as follows:
        #
        # column         present for    comment
        # ------         -----------    -------
        # Document/Model all            "Data Model" for model, else "Document"
        # Version        model
        # Filename/XML   all            "Filename" for schema, else "XML"
        # HTML           all but schema or outdated
        # Description    all
        # Publicn Date   all
        # PDF            all
        my $document_suppress = $opts->{model};
        my $model_suppress = !$opts->{model};
        my $version_suppress = $model_suppress;
        my $html_suppress = $opts->{schema} || $opts->{outdated};
        my $filename = $opts->{schema} ? 'Filename' : 'XML';

        # title is clunky (it's placed on the first field)
        my $title = $opts->{title};

        # open table of contents entry
        $context->{contents} = {title => $title, keys => []};

        # row is an array of columns (first row is header; don't need suppress
        # or percent values in subsequent rows)
        # XXX it would be better to omit rather than suppress?
        # XXX title is clunky (it's on the first field)
        push @{$context->{rows}},
        [
         { name => 'document', value => 'Document', percent => 15,
           suppress => $document_suppress, title => $title },
         { name => 'model', value => 'Data Model', percent => 15,
           suppress => $model_suppress },
         { name => 'version', value => 'Version', percent => 4,
           suppress => $version_suppress },
         { name => 'file', value => $filename, percent => 12, suppress => 0 },
         { name => 'html', value => 'HTML', percent => 3,
           suppress => $html_suppress },
         { name => 'description', value => 'Description', percent => 40,
           suppress => 0 },
         { name => 'appdate', value => 'Approval Date', percent => 10,
           suppress => 0 },
         { name => 'pdflink', value => 'PDF', percent => 15, suppress => 0 }
        ];

        return $context;
    }

    # contents (output table of contents)
    elsif ($opts->{contents}) {
        my $contents = $context->{contents};
        my $title = $contents->{title};
        my @keys = $context->{reverserows} ? 
            reverse(@{$contents->{keys}}) : @{$contents->{keys}};
        print <<END;
      <b><a href="#$title">$title</a></b>
      <ul>
END
        foreach my $key (@keys) {
            print <<END;
        <a href="#$key">$key</a><br>
END
        }
        print <<END;
      </ul>
END
        return;
    }

    # footer (c.f. destructor)
    elsif ($opts->{footer}) {
        htmlbbf_output_table(
            qq{class="stdtable" width="100%" bordercolor="#005c27" } .
            qq{border="1" cellpadding="2" cellspacing="0"}, $context->{rows},
            {latestcolumn => $context->{latestcolumn},
             noanchors => $context->{noanchors},
             noseparator => $context->{noseparator},
             reverserows => $context->{reverserows}});
        return;
    }

    # not header or footer

    # information from $allfiles
    my $name = $file->{name};
    my $spec = $file->{spec};
    my $schema = $file->{schema};
    my $support = $file->{support};
    my $component = $file->{component};
    my $outdated = $file->{outdated};

    # this is defined only for outdated files; it's the file name of the latest
    # version; for non-outdated files just set it to the file name
    my $latest = $outdated ? $file->{latest} : $name;

    # $allfiles has "models", but the objects passed to this routine have only
    # "model" (if multiple models, this routine is called for each model);
    # context is checked because, for a file with components and models, this
    # routine is called for both the components and for each model
    my $model = $context->{model} ? $file->{model} : undef;

    # return if file isn't of the requested type
    # XXX would be better to put this logic in the caller really
    return if  $context->{schema} && !$schema;
    return if !$context->{schema} &&  $schema;

    return if  $context->{support} && !$support;
    return if !$context->{support} &&  $support;

    return if  $context->{component} && !$component;
    return if !$context->{component} && !$context->{model} && $component;

    # determine model name and version (used below)
    my $mname = '';
    my $mname_name = '';
    my $mname_major = '';
    my $mname_minor = '';
    my $mdesc = '';
    if ($model) {
        $mname = $model->findvalue('@name');

        ($mname_name, my $version) = ($mname =~ /([^:]+):(.*)/);
        ($mname_major, $mname_minor) = ($version =~ /(\d+)\.(\d+)/);

        # alternative name for model description (necessary because some
        # files can contain both components and models)
        $mdesc = 'descr_model';
    }

    # for model, check latest / root / service
    if ($model) {
        my $service = $model->findvalue('@isService');

        return if !$context->{root}    && !$service;
        return if !$context->{service} &&  $service;
    }

    # name used for looking up config info is filename first, then filename
    # with successive version numbers omitted (only the first encountered value
    # is used)
    my @names = ();

    # also (for models and components) note the "no corrigendum" file name
    my $name_nc = undef;

    # for non "tr" schemas, support names of form prefix-m-n.xsd where prefix
    # contains no digits and m and n are numeric (the same for outdated XSD
    # files)
    # XXX tr-232-1-0-0-serviceSpec.xsd forces distinction of "tr" schemas
    if ($name !~ /^tr-/ && ($schema || ($outdated && $name =~ /\.xsd$/))) {
        # the rather complicated pattern allows it to match names with no
        # numeric characters at all, e.g. cwmp-datamodel-report.xsd
        my ($prefix, $m, $n) = $name =~
            /^([^\d\.]+)(?:-(\d+))?(?:-(\d+))?\.xsd$/;
        push @names, qq{$prefix-$m-$n.xsd} if defined $n;
        push @names, qq{$prefix-$m.xsd} if defined $m;
        push @names, qq{$prefix.xsd};
    }

    # for "tr" schemas, models, components and support files, allow names of
    # form xxnnn-i-a[-c][label].xml where xxnnn is of the form "xx-nnn", i, a
    # and c are numeric and label can't begin with a digit (the same for
    # outdated XSD and XML files)
    elsif ($schema || $model || $component || $support ||
           ($outdated && $name =~ /\.(xsd|xml)/)) {
        my ($xxnnn, $i, $a, $c, $label, $ext) =
            $name =~ /^([^-]+-\d+)(?:-(\d+))?(?:-(\d+))?(?:-(\d+))?(-\D.*)?\.(xsd|xml)$/;
        $label = '' unless defined $label;
        push @names, qq{$xxnnn-$i-$a-$c$label.$ext} if defined $c && $label;
        push @names, qq{$xxnnn-$i-$a$label.$ext} if defined $a && $label;
        push @names, qq{$xxnnn-$i$label.$ext} if defined $i && $label;
        push @names, qq{$xxnnn$label.$ext} if defined $xxnnn && $label;
        push @names, qq{$xxnnn-$i-$a-$c.$ext} if defined $c;
        push @names, qq{$xxnnn-$i-$a.$ext} if defined $a;
        push @names, qq{$xxnnn-$i.$ext} if defined $i;
        push @names, qq{$xxnnn.$ext} if defined $xxnnn;

        $name_nc = qq{$xxnnn-$i-$a$label.$ext} if defined $i && defined $a;
    }

    # other files aren't versioned so just push the full name
    else {
        push @names, $name;
    }

    # look up and escape description first because {{docname}} etc templates
    # might provide some of the other info.
    my $description = undef;
    my $namedesc = undef;
    foreach my $n (@names) {
        my $info = $htmlbbf_info->{$n};

        # use $mdesc if it's defined, otherwise "description"
        my $descname = defined($info->{$mdesc}) ? $mdesc : 'description';

        # use most specific (first) description
        if (defined($info->{$descname})) {
            ($description, $namedesc) = ($info->{$descname}, $n);
            last;
        }
    }    

    # use description from XML file if defined and not specifically overridden
    # in config file
    $description = $file->{description} if
        $file->{description} && (!$namedesc || $namedesc ne $name);

    # if description undefined, set to "TBD"
    $description = q{'''TBD'''} unless $description;

    # escape the description
    $description = html_escape($description, {
        xmlrefmap => $htmlbbf_xmlrefmap, file => $name, latest => $latest,
        outdated => $outdated});

    # look up config info (from config file or from templates in the
    # description)
    my $document = $file->{document};
    my $trname = $file->{trname};
    my $appdate = $file->{appdate};
    foreach my $n (@names) {
        my $info = $htmlbbf_info->{$n};
        $document = $info->{document} unless $document;
        $trname = $info->{trname} unless $trname;
        $appdate = $info->{appdate} unless $appdate;
    }

    # if document unspecified, set to "TBD"
    $document = q{<b>TBD</b>} unless $document;

    # determine the file rows, which involves deciding whether to add the
    # "full" XML link (not the HTML link because the "full" HTML should be the
    # same)
    my @filerows = ();
    if ($model && $name =~ /\.xml$/) {
        my $aname = $name;
        $aname =~ s/\.xml$/-full.xml/;
        push @filerows, qq{$aname};
    }
    push @filerows, qq{$name};

    # determine the HTML rows (first collect the file suffices)
    my $suffices = [];
    if ($context->{schema} || $name !~ /\.xml$/) {
        # no HTML for schema files
    } elsif (!$context->{component} && $name =~ /$htmlbbf_igddevpatt/) {
        push @$suffices, '-dev' if $mname_name eq "Device";
        push @$suffices, '-igd' if $mname_name eq "InternetGatewayDevice";
    } else {
        push @$suffices, '';
    }
    my $diffsext = ($name =~ /$htmlbbf_lastpatt/) ?
             $diffsexts->[0] : $diffsexts->[-1];
    my $nsuffices = [];
    foreach my $suffix (@$suffices) {
        push @$nsuffices, qq{$suffix-$diffsext} if $mname_minor;
    }
    push @$suffices, @$nsuffices;
    my @htmlrows = ();
    foreach my $suffix (@$suffices) {
        my $hname = $name;
        $hname =~ s/(\.xml)$/$suffix.html/;
        push @htmlrows, qq{$hname};
    }

    # convert the approval date from "yyyy-mm" to "Month yyyy"; if it
    # doesn't match the pattern, quietly leave it alone (perhaps it's OK!)
    if ($appdate) {
        my $months = ['NotAMonth', 'January', 'February', 'March', 'April',
                      'May', 'June', 'July', 'August', 'September', 'October',
                      'November', 'December'];
        my ($year, $month) = $appdate =~ /(\d+)-(\d+)/;
        $appdate = qq{$months->[$month] $year} if
            defined($month) && defined($year);
    }

    # if approval date unspecified, set to "TBD"
    $appdate = q{<b>TBD</b>} unless $appdate;

    # generate the TR document name and PDF link
    my $shortname;
    if ($trname) {
        $shortname = util_doc_name($trname);
        $trname = util_doc_name($trname, {verbose => 1});
        $trname = undef unless $trname;
    }

    # no TR link if TR name doesn't begin "TR" or for support files
    # XXX should verify that we still want this logic
    my $pdfval = undef;
    if ($trname && $trname =~ /^TR/ && !$support) {
        # use short name with no corrigendum, e.g. TR-181i2a5, as the anchor
        $shortname =~ s/c\d+$//;
        $pdfval = {text => $trname, names => [$shortname],
                   link => util_doc_link($trname)};
    }

    # convenience variables
    my $mnam = qq{$mname_name:$mname_major};
    my $mver = qq{$mname_major.$mname_minor};

    # generate the table rows for this file; number of rows is the maximum of
    # the number of file and HTML rows
    my $numrows = (@filerows > @htmlrows) ? @filerows : @htmlrows;
    for (my $i = 0; $i < $numrows; $i++) {

        # determine file and HTML row values
        my $filerow = ($i < @filerows) ? $filerows[$i] : undef;
        my $htmlrow = ($i < @htmlrows) ? $htmlrows[$i] : undef;

        # XXX key is a bit klunky; the row should be a hash rather than an
        #     array; by convention the key is on the first column (regardless
        #     of which columns contribute to it)
        my $key = !$context->{model} ? $document : $mnam;

        # output table of contents entry (not for outdated files because
        # the link would go to the latest file)
        # XXX hmm... can we simplify this logic? it's not clear...
        if (!$outdated) {
            my $changed = !$context->{prevkey} || $key ne $context->{prevkey}; 
            if ($changed) {
                push @{$context->{contents}->{keys}}, $key
                    unless $context->{noanchors};
            }
        }
        $context->{prevkey} = $key;

        my $docval = {text => $document, names => [$document]};

        # link model to its anchor if not defining anchors, i.e. if the link
        # won't be self-referential
        my $modval = {text => $mnam,
                      link => ($context->{noanchors} ? qq{#$mnam} : qq{})};

        my $verval = {text => $mver};

        # put model anchor on file to avoid jump to the middle of a large cell;
        # don't define anchors for "full" XML
        my $fileval = undef;
        if ($filerow) {
            my $fileval_names = [];
            push @$fileval_names, $mnam if $context->{model};
            push @$fileval_names, $name_nc if $name_nc;
            push @$fileval_names, $filerow if $filerow !~ /-full.xml/;
            $fileval = {text => $filerow,
                        names => $fileval_names,
                        link => qq{$cwmppath$filerow}};
        }

        my $htmlval = undef;
        if ($htmlrow) {
            my $diffs = grep {$htmlrow =~ /-$_/} @$diffsexts;
            # XXX this did have text => qq{HTML} and bold => !$diffs, but in
            #     Denver agreed to use qq{Diffs} and qq{Full}; actually using
            #     qq{Diff} (which some people preferred; and still using bold
            $htmlval = {text => $diffs ? qq{Diff} : qq{Full},
                        link => qq{$cwmppath$htmlrow},
                        bold => !$diffs};
        }

        my $descval = {text => $description};
        my $appval = {text => $appdate};

        # row is an array of columns
        push @{$context->{rows}},
        [
         { name => 'document',    value => $docval, key => $key },
         { name => 'model',       value => $modval },
         { name => 'version',     value => $verval },
         { name => 'file',        value => $fileval },
         { name => 'html',        value => $htmlval },
         { name => 'description', value => $descval },
         { name => 'appdate',     value => $appval },
         { name => 'pdflink',     value => $pdfval }
        ];
    }
}

# output table, using rowspan to span consecutive rows that have the same
# value or are undefined; put a double line after any row where the key (first)
# column changes value
#
# options:
# - latestcolumn: only output rows with the latest value for the specified
#   column (specified by name)
# - noanchors: don't define anchors
# - noseparator: don't output separator line when the key (first) column
#   changes value
# - reverserows: output the rows in reverse order
# 
# XXX shouldn't pass HTML options directly in $tabopts (pass a hash instead;
#     combine with other options?)
my $htmlbbf_anchors = {}; # keeps track of which anchors have been defined
sub htmlbbf_output_table
{
    my ($tabopts, $rows, $opts) = @_;

    # options
    my $latestcolumn = $opts->{latestcolumn};
    my $noanchors = $opts->{noanchors};
    my $noseparator = $opts->{noseparator};
    my $reverserows = $opts->{reverserows};

    # first row is the header
    # XXX is this modifying the argument in the caller; can one get warnings
    #     for such things?
    my $header = shift @$rows;

    # title is on first header field
    my $title = $header->[0]->{title};
    if ($title) {
        print <<END;
    <a name="$title"><h1>$title</h1></a>
END
    }

    # output header row
    print <<END;
    <table $tabopts>
      <thead>
        <tr>
END

    # need to remember which columns are suppressed (this information is given
    # only on the header row) and number of unsuppressed columns
    my $suppressed = [];
    my $actcols = 0;

    # header columns have name, value, percent and suppress attributes
    my $perctot = 0;
    foreach my $col (@$header) {
        $perctot += $col->{percent} unless $col->{suppress};
    }
    foreach my $col (@$header) {
        my $value = $col->{value};
        my $percent = $col->{percent};
        my $suppress = $col->{suppress};

        $percent = sprintf("%.2f", ($percent * 100) / $perctot);

        push @$suppressed, $suppress;
        $actcols++ unless $suppress;

        my $oc = $suppress ? '<!-- ' : '';
        my $cc = $suppress ? ' -->' : '';

        print <<END;
          $oc<th width="$percent%">$value</th>$cc
END
    }

    print <<END;
        </tr>
      </thead>
      <tbody>
END

    # perform initial pass to collect info on the latest values (for each row
    # key) for each column
    my $latestvalues = {};
    for (my $i = 0; $i < @$rows; $i++) {
        my $row = $rows->[$i];
        my $prow = ($i == 0) ? undef : $rows->[$i-1];

        my $rkey = $row->[0]->{key};
        for (my $j = 0; $j < @$row; $j++) {
            my $col = $row->[$j];
            my $name = $col->{name};
            my $value = $col->{value};
            $latestvalues->{$rkey}->{$name} = $value if defined($value);
        }
    }

    # create a copy of the rows with the same information but additionally
    # tracking where values change down columns
    my $nrows = [];
    ROW: for (my ($i, $ii) = (0, 0); $i < @$rows; $i++) {
        my $row = $rows->[$i];
        my $prow = ($ii == 0) ? undef : $nrows->[$ii-1];

        # row key is by convention held on the first column
        my $rkey = $row->[0]->{key};
        my $prkey = $prow->[0]->{key};
        my $newkey = ($i == 0) ||
            (defined $rkey && !defined $prkey) ||
            (defined $rkey && $rkey ne $prkey);

        my $tprkey = defined($prkey) ? $prkey : '';

        my $ncols = [];
        for (my $j = 0; $j < @$row; $j++) {
            my $col = $row->[$j];
            my $key = $col->{key};
            my $name = $col->{name};
            my $value = $col->{value};

            my $pcol = (!defined $prow) ? undef : $prow->[$j];
            my $pvalue = $pcol->{value};

            # name and value come from the old row
            # key comes from old row; newkey indicates that it has changed
            # block (reference to field that starts block) is set below;
            # bsize (number of rows in block) is set (via block) in subsequent
            # rows
            my $ncol = { name => $name, value => $value,
                         key => $key, newkey => $newkey,
                         block => undef, bsize => undef };

            # this is the same as the "newkey" criterion; a new key forces
            # all column values to be regarded as new
            my $text = $value->{text};
            my $link = $value->{link} || qq{};
            my $ptext = $pvalue->{text};
            my $plink = $pvalue->{link} || qq{};
            my $newval = $newkey || ($i == 0) ||
                (defined $text && !defined $ptext) ||
                (defined $text && ($text ne $ptext || $link ne $plink));

            # block is this column in the row that started the block
            my $block = $newval ? $ncol : $pcol->{block};
            $ncol->{block} = $block;

            # bsize is defined only in start-of-block rows
            $block->{bsize} =
                !defined($block->{bsize}) ? 1 : $block->{bsize} + 1;

            # possibly discard row if selecting only rows with the latest value
            # for a specified column
            if ($latestcolumn && $name eq $latestcolumn &&
                $value->{text} ne $latestvalues->{$rkey}->{$name}->{text}) {
                next ROW;
            }

            # if selecting only rows with the latest value for a specific
            # ensure that the column value is defined (it might not be if
            # it is unchanged from a previous version
            $ncol->{value} = $latestvalues->{$rkey}->{$name} if
                $latestcolumn && !defined($ncol->{value});

            push @$ncols, $ncol;
        }

        push @$nrows, $ncols;
        $ii++;
    }

    # if outputting rows in reverse order, shift newkey to the next row so it
    # will be correct when the rows have been reversed, then reverse them
    if ($reverserows) {
        for (my $i = 0; $i < @$nrows; $i++) {
            my $row = $nrows->[$i];
            my $nrow = ($i < @$nrows-1) ? $nrows->[$i+1] : undef;
            $row->[0]->{newkey} = $nrow ? $nrow->[0]->{newkey} : 1;
        }
        my @trows = reverse(@$nrows);
        $nrows = \@trows;
    }

    # output body rows
    for (my $i = 0; $i < @$nrows; $i++) {
        my $row = $nrows->[$i];
        my $prow = ($i == 0) ? undef : $nrows->[$i-1];

        # if not suppressed, if key has changed, and if this isn't the first
        # row, output a separator row
        my $newkey = $row->[0]->{newkey};
        if (!$noseparator && $newkey && $i > 0) {
            print <<END;
        <tr>
          <td colspan="$actcols"></td>
        </tr>
END
        }

        print <<END;
        <tr>
END
        for (my $j = 0; $j < @$row; $j++) {
            my $col = $row->[$j];
            my $pcol = (!defined $prow) ? undef : $prow->[$j];

            # start-of-block row for this row and for previous row
            my $block = $col->{block};
            my $pblock = $pcol ? $pcol->{block} : undef;

            # new block? i.e. are this and previous row in different blocks?
            my $nblock = !$pblock || $block != $pblock;

            # take value and bsize from the block row; bsize isn't defined on
            # non block rows
            my $value = $block->{value};
            my $bsize = $block->{bsize};

            # check whether cell (column or row) is suppressed
            my $suppress = $suppressed->[$j] || !$nblock;

            # process value
            my $text = undef;
            if ($value) {
                $text = $value->{text} || qq{};

                my $names = $value->{names};
                my $link = $value->{link};
                my $bold = $value->{bold};

                # generate anchors unless anchors or cell are suppressed
                my $anchors = qq{};
                unless ($noanchors || $suppress) {
                    foreach my $name (@$names) {
                        $anchors .= qq{<a name="$name"></a>} if
                            $name && !$htmlbbf_anchors->{$name}++;
                    }
                }

                # generate hyperlink
                $text = qq{<a href="$link">$text</a>} if $link;

                # prefix anchors
                $text = qq{$anchors$text} if $anchors;

                # embolden if requested
                $text = qq{<b>$text</b>} if $bold && $text;

                # if the cell isn't suppressed, and if possible, check whether
                # the referenced file exists
                if (!$suppress && $outfile &&
                    $link && $link !~ /^\#/ && $link !~ /^http/) {
                    my ($ovol, $odir, $ofile) = File::Spec->splitpath($outfile);
                    if (defined $odir) {
                        my ($dir) = find_file($link, $odir);
                        emsg "hyperlink to non-existent $link" unless $dir;
                    }
                }
            }
            
            # quietly replace undefined or empty text with non-breaking space
            $text = '&nbsp;' unless $text;
            my $oc = $suppress ? '<!-- ' : '';
            my $cc = $suppress ? ' -->' : '';

            print <<END;
          $oc<td rowspan="$bsize">$text</td>$cc
END

        }
        print <<END;
        </tr>
END
    }

    print <<END;
      </tbody>
    </table>

END
}

# HTML "OD-148" report of node.
#
# Similar output to that of OD-148 sections 2 and 3; pass each data model
# on the command line (duplication doesn't matter because no file is ever
# read more than once).
#
# This will be replaced by the new "htmlbbf" report, which merges the
# existing CWMP web page structure with some OD-148 layout ideas.

# XXX until then, could / should use the new generic htmlbbf table output
#     routine (makes all the row spanning etc much easier)

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
    my $sup_valign = qq{vertical-align: super;};
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
      sup { $sup_valign }
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

        my $htmlsuff =
            $row->{file} !~ /$htmlbbf_igddevpatt/ ? '' :
            $row->{name} =~ /^Internet/ ? '-igd' :
            $row->{name} =~ /^Device/ ? '-dev' : '';

        my $version = $row->{version};
        my $version_entry = qq{<a href="$cwmppath$row->{file}.xml">$version</a>};

        my $filefull = $row->{file} . '-full.xml';
        if (-r $filefull) {
            $version_entry .= qq{ <a href="$cwmppath$filefull">[full]</a>};
        }

        my $version_update = $version eq '1.0' ? 'Initial' :
            $version =~ /^\d+\.0$/ ? 'Major' : 'Minor';
        # XXX change so never use Major (major versions are all replacements)
        $version_update =$version =~ /^\d+\.0$/ ? 'Initial' : 'Minor';
        my $version_update_entry =
            qq{<a href="$cwmppath$row->{file}$htmlsuff.html">$version_update</a>};

        # XXX not quite the same as in OD-148 because ALL XML minor versions
        #     are incremental (not worth keeping this column?)
        # XXX always use the last diffsext value (we don't support multiple ones)
        my $diffsext = $diffsexts->[-1];
        my $update_type = $version_update eq 'Initial' ? '-' :
            $version_update eq 'Major' ? 'Replacement' : 'Incremental';
        my $update_type_entry = $update_type eq '-' ? '-' :
            qq{<a href="$cwmppath$row->{file}$htmlsuff-$diffsext.html">$update_type</a>};

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
    
    #foreach my $child (@{$node->{nodes}}) {
    #	my $object = ($child->{type} eq 'object');
    #	xls_node($child, 1) unless $object;
    #}
    #foreach my $child (@{$node->{nodes}}) {
    #	my $object = ($child->{type} eq 'object');
    #	xls_node($child, 1) if $object;
    #}
}    

sub xls_post
{
    my ($node, $indent) = @_;

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
sub xsd_begin
{
    print qq{<?xml version="1.0"?>\n};
    print qq{<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"\n};
    print qq{           elementFormDefault="qualified"\n};
    print qq{           attributeFormDefault="unqualified">\n};
}

sub xsd_node
{
    my ($node, $indent) = @_;

    my $name = $node->{name};
    my $access = $node->{access};
    my $description = $node->{description};
    my $type = $node->{type};
    my $syntax = $node->{syntax};

    $name = xsd_escape($name, 1);

    my $model = ($type eq 'model');
    my $object = ($type eq 'object');

    return unless $model || $object || $syntax;

    # XXX taken from xls_escape; should do more generically
    $description =~ s/^\n[ \t]*//;
    $description =~ s/\n[ \t]*/\n/g;
    $description =~ s/\n$//;
    my $documentation =
        xsd_escape(type_string($type, $syntax) . ' (' .
                   ($access ne 'readOnly' ? 'W' : 'R') . ')' . "\n" .
                   add_values($description, get_values($node)));

    # XXX taken from xls_escape; should do more generically
    $documentation =~ s/^\n[ \t]*//;
    $documentation =~ s/\n[ \t]*/\n/g;
    $documentation =~ s/\n$//;

    if ($model || $object) {
	my $minOccurs = $indent > 1 ? qq{ minOccurs="0"} : qq{};
	print "  "x$indent . qq{<xs:element name="$name"$minOccurs>\n};
        print "  "x$indent . qq{  <xs:annotation>\n};
        print "  "x$indent . qq{    <xs:documentation>$documentation</xs:documentation>\n};
        print "  "x$indent . qq{  </xs:annotation>\n};
	# XXX did have maxEntries="unbounded" here (allows order not to be
	#     significant, but also allows duplication)
	print "  "x$indent . qq{  <xs:complexType><xs:sequence minOccurs="0">\n};

    } else {
	my $minOccurs = $indent > 1 ? qq{ minOccurs="0"} : qq{};
	print "  "x$indent . qq{<xs:element name="$name"$minOccurs>\n};
        print "  "x$indent . qq{  <xs:annotation>\n};
        print "  "x$indent . qq{    <xs:documentation>$documentation</xs:documentation>\n};
        print "  "x$indent . qq{  </xs:annotation>\n};
	print "  "x$indent . qq{</xs:element>\n};
    }    
}

sub xsd_post {
    my ($node, $indent) = @_;

    my $type = $node->{type};

    my $model = ($type eq 'model');
    my $object = ($type eq 'object');

    return unless $model || $object;

    print "  "x$indent . qq{  </xs:sequence></xs:complexType>\n};
    print "  "x$indent . qq{</xs:element>\n};
}

sub xsd_end {
    print qq{</xs:schema>\n};
}

# Escape a value suitably for exporting as W3C XSD.
# XXX currently used only for names
sub xsd_escape {
    my ($value, $is_name) = @_;

    $value = util_default($value);

    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    # XXX should use table syntax
    $value =~ s/\{i\}/i/g;

    $value =~ s/:/_/g if $is_name;

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
    my ($node) = @_;

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
                d0msg $path;
                my $found = [];
                # XXX could check just new profiles?
                foreach my $profile (keys %$special_profiles) {
                    d0msg "  checking $profile";
                    if ($special_profiles->{$profile}->{$path}) {
                        d0msg "  found in $profile";
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
        my $ascii = q{\x09-\x0a\x20-\x7e};
        my $count = {};
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            my $description = $item->{description};
            next unless $description; # some parameters and objects omit it
            $description =~ s/\s+/ /g;
            my $any = 0;
            undef pos($description);
            while ($description =~ /\G[$ascii]*([^$ascii])/g) {
                push @{$count->{$1}}, $path;
                $any = 1;
            }
            if ($any) {
                $description =~ s/([^$ascii])/**$1**/g;
                print "$path\t$description\n";
            }
        }
        foreach my $char (sort {$a cmp $b} keys %$count) {
            my $n = @{$count->{$char}};
            print "$char : $n occurrences\n"
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
            d0msg $path;
            print "$path\n"
                if $access eq 'readOnly' && $activeNotify ne 'canDeny';
        }
    }

    # pathref: somewhat similar to ref but specifically pathref, and
    # reports references from and to "CPE-managed non-fixed" objects
    elsif ($special eq 'pathref') {
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            next unless $path; # profile items have no path
            my $syntax = $item->{syntax};
            next unless $syntax; # only parameters have syntax
            my $refType = $syntax->{refType};
            next unless $refType; # only interested in references

            # source (referencing) object; we are interested only if it's
            # CPE-managed (read-only) and non-fixed
            my $srcobj = $item->{pnode};
            my $srcaccess = $srcobj->{access};
            my $srcfixed = $srcobj->{fixedObject};
            next unless $srcaccess eq 'readOnly' && !$srcfixed;
            my $list = $syntax->{list};

            # target (referenced) object(s); we are interested only if the
            # targets are specified, are rows, and all are CPE-managed
            #(read-only) and non-fixed
            my $targetParent = $syntax->{targetParent};
            my $targetType = $syntax->{targetType};
            next unless $targetParent && $targetType eq 'row';
            my $targetParentScope = $syntax->{targetParentScope};
            my $mpref = util_full_path($item, 1);
            my $tgtobjs = '';
            foreach my $tp (split ' ', $targetParent) {
                my ($tpp) = relative_path($srcobj->{path}, $tp,
                                          $targetParentScope);
                $tpp .= '{i}.' unless $tpp =~ /\{i\}\.$/;
                my $tgtobj = $objects->{$mpref.$tpp};
                next unless $tgtobj; # quietly ignore if doesn't exist
                $tgtobjs .= qq{$tgtobj->{path} }
                if $tgtobj->{access} eq 'readOnly' && !$tgtobj->{fixedObject};
            }
            $list = $list ? qq{ (list)} : qq{};
            print "$item->{path}$list\t$tgtobjs\n" if $tgtobjs;
        }
    }

    # profile: for each new parameter, check whether it is in a profile;
    # report those which aren't
    elsif ($special eq 'profile') {
        foreach my $item (@$special_newitems) {
            my $type = $item->{type};
            next if $type =~ 'model|object|profile';
            my $path = $item->{path};
            d0msg $path;
            my $found = 0;
            foreach my $profile (keys %$special_profiles) {
                if ($special_profiles->{$profile}->{$path}) {
                    d0msg "  found in $profile";
                    $found = 1;
                    last;
                }
            }
            unless ($found) {
                print "$path\n";
            }
        }
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

    # rfc: for each item (model, object, parameter, value or profile),
    # report RFCs without references
    # XXX really should simply check all instances of the "description"
    #     element
    # XXX not very useful
    elsif ($special eq 'rfc') {
        #my $patt = '(RFC\s*[0-9]++)(\s?[^\s\[])';
        my $patt = '(RFC\s*[0-9]++)(\s?)([^\|\})|\{\{[^b])';
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

    # key: for each table with a functional key, report access, path and key
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

    # imports: report the imports structure in a human-readable way
    # XXX inefficient because doesn't require a pass through the node tree
    elsif ($special =~ /^imports/) {
        my $colon = ':'; # XXX otherwise confuses Emacs syntax highlighting
        my ($ignore, $ielem, $iname) = split /$colon/, $special, 3;
        # XXX it gets autovivified somewhere...
        foreach my $file (sort keys %$imports) {
            $imports->{$file}->{i} = -1 unless defined $imports->{$file}->{i};
        }
        foreach my $file (sort {$imports->{$a}->{i} <=>
                                    $imports->{$b}->{i}} keys %$imports) {
            my $impfile = $imports->{$file};
            foreach my $imp (@{$impfile->{imports}}) {
                next if $ielem && $imp->{element} !~ /^$ielem/;
                next if $iname && $imp->{name} !~ /^_?$iname/;
                my $dfile = $imp->{file};
                my $element = $imp->{element};
                my $name = $imp->{name};
                my $ref = $imp->{ref};
                my $alias = $dfile ne $file ? qq{ = {$dfile}$ref} : qq{};
                my $uri = $imp->{item}->ownerDocument()->URI();
                $uri =~ s/^.*\///;
                $uri =~ s/\..*$//;
                $uri = $uri ne $dfile ? qq{ {$uri}} : qq{};
                print "$element {$file}$name$alias$uri\n"
            }
        }
    }

    # vendorvalues: explicit clarifications that vendors can add enums or
    # patterns
    elsif ($special eq 'vendorvalues') {
        my $total = 0;
        my $match = 0;
        foreach my $node (@$special_items) {
            next unless $node->{syntax};

            my $path = $node->{path};
            my $changed = $node->{changed};
            my $history = $node->{history};
            my $description = $node->{description};
            my $origdesc = $description;
            my $descact = $node->{descact};
            my $dchanged = util_node_is_modified($node) &&
                $changed->{description};
            ($description, $descact) = get_description($description, $descact,
                                                       $dchanged, $history, 1);

            if (has_values($node->{values})) {
                if ($description =~ /vendor[ -]specific.*3\.3/) {
                    print "$path:\n";
                    foreach my $line (split /\n/, $description) {
                        print "* $line\n";
                    }
                    print "\n";
                    $match++;
                }
                $total++;
            }
        }
        print "total = $total, match = $match\n";
    }

    # invalid
    else {
        emsg "$special: invalid special option";
    }
}

# Output message to STDERR (add newline if not present)
sub msg
{
    my $cat = shift;
    my $nl = (@_ == 0) ? 0 : $_[-1] =~ /\n$/;
    my $pfx = $nologprefix ? qq{} : qq{($cat) };
    my $text = join '', @_;
    $text = $pfx . $text;
    push @$msgs, $text if $cat =~ /E|W/;
    print STDERR $text, $nl ? qq{} : qq{\n};
    $num_errors++ if $cat eq 'E';
}

# Clean the command line by discarding all but the final component from path
# names
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

# List routines defined (or imported into) a module
#
# ref http://stackoverflow.com/questions/607282/whats-the-best-way-to-
#            discover-all-subroutines-a-perl-module-has
#
# this includes routines that have been imported into the module (the same
# reference indicates how to avoid that)
sub util_module_routines {
    my ($module) = @_;
    no strict 'refs';
    return grep { defined &{"$module\::$_"} } keys %{"$module\::"}
}

# Helper for the above
sub util_module_routine
{
    my ($module, $routine) = @_;
    return defined &{"$module\::$routine"} ? \&{"$module\::$routine"} : undef;
}

# Given a node, form the (model name, model major version, dot) prefix, e.g.
# "Device:2." and optionally append the path name (note that a profile path is
# just its name).
#
# This routine never fails, but will not try to append things that don't exist.
sub util_full_path
{
    my ($node, $prefix_only) = @_;

    my $text = '';

    # determine model node, either this node if type 'model' or else mnode
    my $mnode = $node->{type} && $node->{type} eq 'model' ? $node :
        $node->{mnode};

    # form (model name, major version, dot) prefix, e.g. "Device:2."
    # (this always uses "oname", the original name, which will in most cases
    # be minor version 0)
    if ($mnode) {
        $text .= $mnode->{oname};
        $text  =~ s/\.\d+$//;
        $text .= '.';
    }

    # if requested append the path
    my $path = $node->{path};
    if ($path && !$prefix_only) {
        $text .= $node->{path};
    }

    return $text;
}

# Heuristic determination of approval date of an XML file; the date is
# returned as numeric 'yyyy-mm-dd' (i.e. will sort correctly) or as '' if
# unknown
sub util_appdate
{
    my ($toplevel) = @_;

    return '';
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
        unless (grep {$_ eq $key} @$not) {
            $out->{$key} = clone($in->{$key});
        }
    }

    return $out;
}

# Scan a string counting +1 for "{" and -1 for "}"
sub util_brace_count
{
    my ($string) = @_;

    my $count = 0;
    foreach my $char (split '', $string) {
        $count++ if $char eq '{';
        $count-- if $char eq '}';
    }

    return $count;
}

# Tokenize a string
# XXX not getting much benefit from String::Tokenizer
sub util_tokenize
{
    my ($string, $delimiters) = @_;

    my $tokens;

    # empty and newline-only delimiters are special
    if ($delimiters eq qq{} || $delimiters eq qq{\n}) {
        my @temp_tokens = split $delimiters, $string;
        $tokens = \@temp_tokens;

    } else {
        my $tokenizer = String::Tokenizer->new(
            $string, $delimiters, String::Tokenizer->RETAIN_WHITESPACE);
        my $temp_tokens = $tokenizer->getTokens();
        
        # replace whitespace with a token character; allows (for example)
        # " " -> "  " to be detected as an addition of a space rather than
        # a replacement
        $tokens = [];
        foreach my $token (@$temp_tokens) {
            if ($token !~ /^\s*$/) {
                push @$tokens, $token;
            } else {
                push @$tokens, split '', $token;
            }
        }

    }

    return $tokens;
}

# util_diffs() helper; add items surrounded by markers
sub util_diffs_helper
{
    my $marker = shift;
    my @items = @_;

    my $out = '';
    if (@items) {
        $out .= $marker . ' ';
        foreach my $item (@items) {
            $out .= ($item eq "\n") ? '\n' : $item;
        }
        $out .= "\n";
    }

    return $out;
}

# Determine differences between two strings
# XXX the old logic is still there but for now just invoke util_diffs_markup()
#     plus minor whitespace tidy-up
sub util_diffs
{
    my ($old, $new) = @_;

    my $text = util_diffs_markup($old, $new);
    $text =~ s/^\s*//;
    $text =~ s/\s*$//;
    return $text;

    my $old_tokens = util_tokenize($old);
    my $new_tokens = util_tokenize($new);

    my $diff = Algorithm::Diff->new($old_tokens, $new_tokens);
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
        $diffs .= util_diffs_helper("-", $diff->Items(1));
        $diffs .= $sep;
        $diffs .= util_diffs_helper("+", $diff->Items(2));
    }
    return $diffs;
}

# util_diffs_markup() helper; add items surrounded by markers
sub util_diffs_markup_helper
{
    my ($items, $marker) = @_;
    $marker = '' unless $marker;

    my $out = '';
    my $num = 0;
    my $brc = 0;

    if (@$items) {
        $out .= $marker;
        foreach my $item (@$items) {
            $out .= $marker if $item eq "\n";
            $out .= $item;
            $out .= $marker if $item eq "\n";

            # force $num to be huge if item contains template argument
            # separator
            # XXX "|" should be a token separator so how is this happening?
            #     ah, because a hunk can be multiple tokens of course...
            # XXX a hack and not a nice interface...
            $num += 1000 if $marker && $item =~ /\|/;
        }
        $out .= $marker;
    }

    # if the marker is non-empty, i.e. these are insertions or deletions...
    if ($marker) {

        # empty lines can have unnecessary double markers; these won't do any
        # harm but get rid of them anyway
        $out =~ s/\Q$marker$marker\E//g;

        # force $num to be huge if braces aren't balanced
        # XXX a hack and not a nice interface...
        $brc = util_brace_count($out);
        $num += 1000 if $brc != 0;

        # maintain a count of the number of insertions or deletions
        $num++ if @$items;
    }

    return ($out, $num, $brc);
}

# util_diffs_markup() helper; look for diffs with a given set of delimiters
# XXX there is duplication of logic between this routine and the main
#     util_diffs_markup() routine; ideally only one routine would interface
#     with Algorithm::Diff
sub util_diffs_markup_inner_try
{
    my ($old, $new, $delimiters) = @_;

    # these tags indicate inserted and deleted text, e.g. "+++new+++" indicates
    # that "abc" is inserted and "---old---" indicates that "old" is deleted,
    # so "---old---+++new+++" indicates that "old" is replaced with "new"
    my $ins = qq{+++};
    my $del = qq{---};

    my $old_tokens = util_tokenize($old, $delimiters);
    my $new_tokens = util_tokenize($new, $delimiters);

    my $diff = Algorithm::Diff->new($old_tokens, $new_tokens);

    my $out = qq{};
    my $num = 0;
    while ($diff->Next()) {
        my $a;
        my $b;

        my @same = $diff->Same();
        ($a, $b) = util_diffs_markup_helper(\@same);
        $out .= $a;
        $num += $b;
        next if @same;

        my @from_old = $diff->Items(1);
        my @from_new = $diff->Items(2);

        ($a, $b) = util_diffs_markup_helper(\@from_old, $del);
        $out .= $a;
        $num += $b;

        # special case; add newline if both deletions and insertions and
        # newline delimiter
        $out .= "\n" if @from_old && @from_new && $delimiters eq "\n";

        ($a, $b) = util_diffs_markup_helper(\@from_new, $ins);
        $out .= $a;
        $num += $b;
    }

    # XXX $num is incremented for each deleted OR inserted section
    return ($out, $num);
}

# util_diffs_markup helper(); looks for diffs at the character, word and
# paragraph level
sub util_diffs_markup_inner
{
    my ($old, $new) = @_;

    my $out;
    my $num;

    # first try at the character level
    ($out, $num) = util_diffs_markup_inner_try($old, $new, qq{});
    return qq{{{marktemplate|diffs-0:$num}}} . $out if $num <= $maxchardiffs;

    # next try at (more-or-less) the word level
    ($out, $num) = util_diffs_markup_inner_try($old, $new,
                                               qq{,:;\.\!\?\{\|\}});
    return qq{{{marktemplate|diffs-1:$num}}} . $out if $num <= $maxworddiffs;

    # fall back to the paragraph level
    # XXX we are never called with more than one paragraph so this is
    #     over-complex
    ($out, $num) = util_diffs_markup_inner_try($old, $new, qq{\n});
    return qq{{{marktemplate|diffs-2:$num}}} . $out;
}

# Version of util_diffs() that inserts '+++' and '---' markup
sub util_diffs_markup
{
    my ($old, $new) = @_;

    # these tags indicate inserted and deleted text, e.g. "+++new+++" indicates
    # that "abc" is inserted and "---old---" indicates that "old" is deleted,
    # so "---old---+++new+++" indicates that "old" is replaced with "new"
    my $ins = qq{+++};
    my $del = qq{---};

    # paragraph separator pattern and replacement string
    my $spp = qr{\n};
    my $sep = qq{\n};

    # prefix pattern matching list item indicators and whitespace
    my $pfx = qr{[*#:\s]*};

    # split old and new strings into paragraphs
    my @old = split /$spp/, $old;
    my @new = split /$spp/, $new;

    # analyze to determine "hunks" (sets of paragraphs)
    my $diff = Algorithm::Diff->new(\@old, \@new);

    # iterate through the hunks
    my $out = qq{};
    while ($diff->Next()) {

        # this hunk is the same in old and new
        my @same = $diff->Same();
        if (@same) {
            $out .= join $sep, @same;
            $out .= $sep;
            next;
        }

        # this old hunk...
        my @from_old = $diff->Items(1);

        # is replaced by this new hunk
        my @from_new = $diff->Items(2);

        # if both hunks have the same number of paragraphs, there is a good
        # chance that there is a 1:1 mapping between the old and new ones, and
        # that the changes are minor
        if (@from_old && @from_new && @from_old == @from_new) {
            for (my $i = 0; $i < @from_old; $i++) {
                my $a = $from_old[$i];
                my $b = $from_new[$i];

                # separate out the prefixes, which are never marked as
                # deletions or insertions
                my ($ap, $ar) = $a =~ /^($pfx)(.*)$/;
                my ($bp, $br) = $b =~ /^($pfx)(.*)$/;

                # if prefixes don't match, 
                $out .= $bp;
                $out .= util_diffs_markup_inner($ar, $br);
                $out .= $sep;
            }
            next;
        }

        my $temp1 = @from_old;
        my $temp2 = @from_new;
        $out .= "{{marktemplate|diffs-$temp1&$temp2}}";

        # otherwise just show changes paragraph by paragraph
        if (@from_old) {
            for my $item (@from_old) {
                my ($pre, $rst) = $item =~ /^($pfx)(.*)$/;
                $out .= qq{$pre$del$rst$del$sep};
            }
            # leave the separator, so as to put deleted and inserted text
            # on separate lines
        }
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

# Check spelling
#
# XXX not ready for prime time; need to be able to pass language (default to
#     en_US), to require installation only if requested via --spellcheck or
#     --standard (say), to ignore template references, to allow user
#     dictionaries etc
# XXX should check in add_parameter() etc, and add to a list of pending errors,
#     then process before reporting (e.g. for a given mistake list where it's
#     used, reported in alphabetical order); also indicate visually in the
#     output (with links)
sub util_check_spelling
{
    my ($text) = @_;

    # XXX for now...
    return $text;

    #my $checker = Text::SpellChecker->new(text => $text, lang => 'en_US');

    # XXX see http://search.cpan.org/~bduggan/Text-SpellChecker-0.11/
    #     lib/Text/SpellChecker.pm
    #while (my $word = $checker->next_word) {
    #    emsg "spelling mistake?: $word";
    #}
    
    #return $text;
}

# Convert spec or TR name to document name
sub util_doc_name
{
    my ($spec, $opts) = @_;

    my $verbose = $opts->{verbose};

    # XXX not sure quite why it's ever blank; something to do with profiles?
    return $spec unless $spec;

    # return input if it's a URN but not a BBF one
    return $spec if $spec =~ /^urn:/i && $spec !~ /^urn:broadband-forum-org/i;

    # return input if it's a URL
    return $spec if $spec =~ /^https?:\/\//i;

    # if a URN, urn:broadband-forum-org:rest -> rest
    my $text = $spec;
    $text =~ s/.*://;

    # support names of form name-i-a[-c][label] where name is of the form
    # "cat-n", i, a and c are numeric and label can't begin with a digit
    my ($cat, $n, $i, $a, $c, $label) =
        $text =~ /^([^-]+)-(\d+)-(\d+)?-(\d+)(?:-(\d+))?(\d*\D.*)?$/;

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
        # XXX it's not clear that this is now the correct logic; probably best
        #     just to return the input in this case?
        $cat = $cat;
        $text .= qq{$cat-$n};
        $text .= qq{-$i} if defined $i; # version
        $text .= qq{-$a} if defined $a; # revision (major)
        $text .= qq{-$c} if defined $c; # revision (minor)
        $text .= qq{-$label} if defined $label;
    }

    return $text;
}

# Convert BBF document name (as returned by util_doc_name) to a link
# relative to the BBF home page
sub util_doc_link
{
    my ($name) = @_;

    my $link = qq{${trpage}${name}.pdf};
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
    my $union = (!$multi && defined($min) && $min == 0);

    return ($multi, $fixed, $union);
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

    # XXX experimental; always use spec for this decision (this works when
    #     comparing corrigenda and is better than the more complex version
    #     below? ... but I must have missed something); added on 06-Aug-12
    # XXX no; this is wrong because it doesn't regard items newly added via
    #     components as being new (but it works well when comparing corrigenda
    #     ... but lastonly ain't so great when comparing corrigenda)
    # XXX desperation; change this logic to use file rather than spec
    #return $node->{spec} && $node->{spec} eq $lspec if $compare;
    return $node->{file} && $node->{file} eq $lfile if $compare;

    # XXX experimental; always use file for this decision (what was wrong
    #     with this?); was already disabled on 06-Aug-12 and it was using the
    #     version below
    #return $node->{file} && $node->{file} eq $lfile;
    
    # assume not new if there is no model node or it's a parameterRef or
    # objectRef
    my $mnode = $node->{mnode};
    return 0 if !$mnode || $node->{type} =~ /Ref$/;

    # the node should now be an object parameter or profile node

    # unnamed nodes are always regarded as new
    # XXX this is really here just for the fake unnamed profile node
    return 1 unless $node->{name};

    # otherwise new if the node version is the model version
    # XXX there probably a more direct way of doing this but this method has
    #     the advantage of being easy to understand!
    return ($node->{majorVersion} == $mnode->{majorVersion} &&
            $node->{minorVersion} == $mnode->{minorVersion});
}

# Perform sanity checks etc, e.g. prune empty objects if --writonly
# XXX some warnings are suppressed if is_dt is true; should check all; very
#     klunky
sub sanity_node
{
    my ($node) = @_;

    # XXX this isn't really the place to do this but it's convenient because
    #     the sanity check passes through the entire tree before the report
    #     is generated
    # XXX experimental: treat as deleted if comparing and node was created
    #     in first file but not mentioned in second file (probably lots of
    #     holes in this but it seems to improve things)
    # XXX one thing it DOES NOT improve is if the node was auto-created, so
    #     auto-created nodes are excluded
    if ($compare) {
        if (defined $node->{file} && $node->{file} eq $pfile) {
            if (defined $node->{sfile} && $node->{sfile} ne $lfile &&
                !$node->{auto}) {
                #emsg "$node->{path}: marked deleted!";
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

    my $is_dt = $node->{is_dt};
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

    my $mpref = util_full_path($node, 1);
    my $fpath = util_full_path($node);

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
        # XXX should check all descriptions, not just obj / par ones (now
        #     better: checking enumeration descriptions)
        my $ibr = invalid_bibrefs($description);
        emsg "$path: invalid bibrefs: " . join(', ', @$ibr) if
            $warnbibref >= 0 && @$ibr;
        if (util_is_defined($values)) {
            foreach my $value (keys %$values) {
                my $cvalue = $values->{$value};
                
                my $description = $cvalue->{description};
                my $ibr = invalid_bibrefs($description);
                emsg "$path: invalid bibrefs: " . join(', ', @$ibr) if
                    $warnbibref >= 0 && @$ibr;
            }
        }

        # errors that were deferred because they might have been cleared by
        # a later version
        w0msg "$path: description: same as previous" if
            defined $node->{errors}->{samedesc} &&
            !$node->{errors}->{samedesc};
        w0msg "$path: invalid description action: " .
            util_default($node->{errors}->{baddescact})
            if defined $node->{errors}->{baddescact};
        if (util_is_defined($values)) {
            foreach my $value (keys %$values) {
                my $cvalue = $values->{$value};
                
                w0msg "$path.$value: description: same as previous" if
                    defined $cvalue->{errors}->{samedesc} &&
                    !$cvalue->{errors}->{samedesc};
                w0msg "$path.$value: invalid description action: " .
                    util_default($cvalue->{errors}->{baddescact})
                    if defined $cvalue->{errors}->{baddescact};
            }
        }
    }

    # object sanity checks
    # XXX for DT, need to check that things are not only defined but are not
    #     hidden
    if ($object) {
        my $fppath = util_full_path($node->{pnode});
        my ($multi, $fixed) = util_is_multi_instance($minEntries, $maxEntries);

        w1msg "$path: object is optional; was this intended?"
            if $minEntries eq '0' && $maxEntries eq '1';

        emsg "$path: object is writable but not a table"
            if $access ne 'readOnly' && $maxEntries eq '1';

        emsg "$path: object is a table but name doesn't end with \"{i}.\""
            if $multi && $path !~ /\{i\}\.$/;

        emsg "$path: object is not a table but name ends with \"{i}.\""
            if !$is_dt && !$multi && $path =~ /\{i\}\.$/;

        emsg "$path: object is not a table but has a unique key"
            if !$multi && $node->{uniqueKeys} && @{$node->{uniqueKeys}};

        emsg "$path: object is not writable and multi-instance but " .
            "has enableParameter" if
            !$is_dt && !($access ne 'readOnly' && $multi) && $enableParameter;

        emsg "$path: enableParameter ($enableParameter) doesn't exist"
            if $enableParameter && !$parameters->{$fpath.$enableParameter};

        # XXX this is questionable use of "hidden" (TR-196?)
        my $temp = $numEntriesParameter || '';
        $numEntriesParameter = $parameters->{$fppath.$numEntriesParameter} if
            $numEntriesParameter;
        if (!$is_dt && $multi && !$fixed && !$nowarnnumentries &&
            (!$numEntriesParameter ||
             (!$hidden && $numEntriesParameter->{hidden}))) {
            emsg "$path: missing or invalid numEntriesParameter ($temp)";
            # XXX should filter out only parameters (use grep)
            w2msg "\t" .
                join(", ", map {$_->{name}} @{$node->{pnode}->{nodes}}) . "\n";
        }

        if ($numEntriesParameter) {
            emsg "$path: numEntriesParameter " .
                "($numEntriesParameter->{name}) is writable" if
                $numEntriesParameter->{access} eq 'readWrite';

            # add a reference from each #entries parameter to its table (can
            # be used in report generation)
            if ($numEntriesParameter->{table}) {
                emsg "$path: numEntriesParameter " .
                    "($numEntriesParameter->{name}) already used by " .
                    "$numEntriesParameter->{table}->{path}";
            } else {
                $numEntriesParameter->{table} = $node;
            }
        }

        # XXX old test for enableParameter considered "hidden"; why?
        #$enableParameter =
        #    $parameters->{$fpath.$enableParameter} if $enableParameter;
        #(!$enableParameter || (!$hidden && $enableParameter->{hidden}))

        my $any_functional = 0;
        my $any_writable = 0;
        foreach my $uniqueKey (@{$node->{uniqueKeys}}) {
            $any_functional = 1 if $uniqueKey->{functional};
            my $keyparams = $uniqueKey->{keyparams};
            foreach my $parameter (@$keyparams) {
                my $ppath = $path . $parameter;
                my $paccess = util_is_defined($parameters, $mpref.$ppath) ?
                    $parameters->{$mpref.$ppath}->{access} : undef;
                $any_writable = 1 if $paccess && $paccess ne 'readOnly';
            }
        }

        emsg "$path: writable table but no enableParameter"
            if $access ne 'readOnly' && $multi && $any_functional &&
            !$nowarnenableparameter && $any_writable && !$enableParameter;

        emsg "$path: writable fixed size table"
            if $access ne 'readOnly' && $multi && $fixed;

        # XXX could be cleverer re checking for read-only / writable unique
        #     keys
        w0msg "$path: no unique keys are defined"
            if $multi && !$nowarnuniquekeys &&
            !$node->{noUniqueKeys} && !@{$node->{uniqueKeys}};
    }

    # parameter sanity checks
    if ($parameter) {
        # XXX this isn't always an error; depends on whether table entries
        #     correspond to device configuration
        w2msg "$path: writable parameter in read-only table" if
            $access ne 'readOnly' &&
            defined $node->{pnode}->{access} &&
            $node->{pnode}->{access} eq 'readOnly' &&
            defined $node->{pnode}->{maxEntries} &&
            $node->{pnode}->{maxEntries} eq 'unbounded' &&
            !$node->{pnode}->{fixedObject};

        emsg "$path: read-only command parameter"
            if $syntax->{command} && $access eq 'readOnly';

        emsg "$path: useless <Empty> value for list-valued parameter"
            if $syntax->{list} && has_values($values) &&
            has_value($values, '');

        emsg "$path: $syntax->{reference} has enumerated values"
            if $syntax->{reference} && has_values($values);

        # XXX doesn't complain about defaults in read-only objects or tables;
        #     this is because they are quietly ignored (this is part of
        #     allowing them in components that can be included in multiple
        #     environments)

	w0msg "$path: default $udefault is invalid for data type $type"
            if defined $default && !valid_values($node, $default);

	w0msg "$path: default $udefault is inappropriate"
            if defined($default) && $default =~ /\<Empty\>/i;

        my $valid = valid_ranges($node);
        w0msg "$path: range ".add_range($syntax)." is invalid for ".
            "data type $type" if !$valid;
        w0msg "$path: ranges ".add_range($syntax)." overlap" if $valid == 3;

	w2msg "$path: string parameter has no maximum length specified" if
            maxlength_appropriate($path, $name, $type) &&
            !has_values($values) && !has_maxlength($syntax);

	w1msg "$path: enumeration has unnecessary maximum length specified" if
            maxlength_appropriate($path, $name, $type) &&
            !$node->{hasPattern} && has_values($values) &&
            has_maxlength($syntax);

        # XXX why the special case for lists?  suppressed
	w0msg "$path: parameter within static object has a default value" if
            !$is_dt && !$dynamic && defined($default) && $deftype eq 'object';
        #&& !($syntax->{list} && $default eq '');

        emsg "$path: weak reference parameter is not writable" if
            $syntax->{refType} && $syntax->{refType} eq 'weak' && 
            $access eq 'readOnly';

	# XXX other checks to make: profiles reference valid parameters,
	#     reference types, default is valid for type, other facets are
        #     valid for type (valid narrowing checks could be done here too,
        #     but would need to use history)
    }

    # profile sanity checks
    if ($profile && !$automodel) {
        foreach my $path (sort keys %{$node->{errors}}) {
            emsg "profile $name references invalid $path";
        }
    }
}

sub report_node
{
    my $node = shift;

    my $indent = shift;
    $indent = 0 unless $indent;

    my $opts = shift;
    my $treport = $opts ? $opts->{report} : $report;

    # the sanity report needs to visit ALL nodes
    return if $treport ne 'sanity' && util_is_omitted($node);

    my $beginfunc = $reports->{$treport}->{begin};
    my $nodefunc = $reports->{$treport}->{node};
    my $postparfunc = $reports->{$treport}->{postpar};
    my $postfunc = $reports->{$treport}->{post};
    my $endfunc = $reports->{$treport}->{end};

    if (!$indent) {
        unshift @_, $node, $indent, $opts;
        $beginfunc->(@_) if defined $beginfunc;
        shift; shift; shift;
    }

    unshift @_, $node, $indent, $opts;
    $nodefunc->(@_);
    shift; shift; shift;

    $indent++;

    # always report children in the following order:
    # 1. model
    # 2. parameter (and parameterRef)
    # 3. object (and objectRef)
    # 4. profile
    my $sorted = {};
    foreach my $child (@{$node->{nodes}}) {
        my $type = $child->{type};
        if ($type eq 'model') {
            push @{$sorted->{model}}, $child if !$nomodels ||
                ($autogenerated && $child->{name} =~ /^$autogenerated/);
        } elsif ($type =~ /^object/) {
            push @{$sorted->{object}}, $child;
        } elsif ($type eq 'profile') {
            push @{$sorted->{profile}}, $child unless $noprofiles;
        } else {
            push @{$sorted->{parameter}}, $child;
        }
    }

    if ($report eq 'html' && $sortobjects) {
        foreach my $type (('object', 'profile')) {
            if (defined $sorted->{$type}) {
                my @tmp = sort {$a->{name} cmp $b->{name}} @{$sorted->{$type}};
                $sorted->{$type} = \@tmp;
            }
        }
    }

    foreach my $type (('model', 'parameter', 'object', 'profile')) {
        foreach my $child (@{$sorted->{$type}}) {
            unshift @_, $child, $indent, $opts;
            report_node(@_);
            shift; shift; shift;
        }

        # XXX it's convenient to have a hook that is called after the parameter
        #     children and before the object children, e.g. where the report
        #     does not nest objects (need to integrate this properly)
        if ($node->{type} =~ /^object/ && $type eq 'parameter') {
            unshift @_, $node, $indent-1, $opts;
            $postparfunc->(@_) if defined $postparfunc;
            shift; shift; shift;
        }
    }

    $indent--;

    unshift @_, $node, $indent, $opts;
    $postfunc->(@_) if defined $postfunc;
    shift; shift; shift;

    if (!$indent) {
        unshift @_, $node, $indent, $opts;
        $endfunc->(@_) if defined $endfunc;
        shift; shift; shift;
    }
}

# Count total number of occurrences of each spec
my $spectotal = {};
sub spec_node
{
    my ($node, $indent) = @_;

    # XXX don't count root or profile nodes (it confuses people, e.g. me)
    # XXX this gives the wrong answer for "xml2" output
    if ($indent && $node->{spec} &&
        $node->{type} !~ /model|profile|parameterRef|objectRef/) {
        d1msg "$node->{type}: $node->{path}: $node->{spec}";
        $spectotal->{$node->{spec}}++;
    }
}

# Main program

# Invoke report init routine (if defined)
my $initfunc = $reports->{$report}->{init};
$initfunc->() if defined $initfunc;

# Expand all data model definition files.
foreach my $file (@ARGV) {
    expand_toplevel($file);
}

report_node($root, 0, {report => 'sanity'});

# Report top-level nodes.
# XXX probably want to output fully expanded XML file of the same format as
#     the input file (i.e. just object and parameter definitions)
# XXX currently doesn't work for all report types (haven't updated them all for
#     the new interface)
# XXX need to re-think "hidden" versus use of "lspec"
report_node($root);

# Warn of unused bibrefs (note do this after generating the report because
# report generation can use additional bibrefs)
if (!$allbibrefs && $root->{bibliography}) {
    foreach my $reference (sort bibid_cmp
                           @{$root->{bibliography}->{references}}) {
        my $id = $reference->{id};
        my $spec = $reference->{spec};
        
        next if ($spec ne $lspec);    
        # XXX suppress if there are no imports at all, which means that this
        #     is almost certainly "flattened" XML generated by the xml2
        #     report; in this case warnings are spurious and will be because
        #     a bibref was used in a previous version of a description and
        #     is no longer used
        w0msg "reference $id not used" unless $bibrefs->{$id} || $no_imports;
    }
}
            
report_node($root, 0, {report => 'spec'});

foreach my $spec (sort @$specs) {
    imsg "$spec: $spectotal->{$spec}"
        if !$quiet && defined $spectotal->{$spec};
}

# The exit code is the negative of the number of reported errors, which will
# probably be masked to 8 bits, e.g. -2 will probably be reported as 254
exit -$num_errors if $exitcode;

# this allows the file to be included as a module
1;

# documentation
=head1 NAME

report.pl - generate report on TR-069 DM instances (data model definitions)

=head1 SYNOPSIS

B<report.pl>
[--allbibrefs]
[--autobase]
[--autodatatype]
[--automodel]
[--bibrefdocfirst]
[--canonical]
[--catalog=c]...
[--compare]
[--components]
[--configfile=s("")]
[--cwmpindex=s(..)]
[--cwmppath=s(cwmp)]
[--debugpath=p("")]
[--deletedeprecated]
[--diffs]
[--diffsext=s(diffs)]...
[--dtprofile=s]...
[--dtspec[=s]]
[--dtuuid[=s]]
[--exitcode]
[--help]
[--ignore=p("")]
[--importsuffix=s("")]
[--include=d]...
[--info]
[--lastonly]
[--loglevel=tn(i)]
[--marktemplates]
[--maxchardiffs=i(5)]
[--maxworddiffs=i(10)]
[--noautomodel]
[--nocomments]
[--nohyphenate]
[--nolinks]
[--nologprefix]
[--nomodels]
[--noobjects]
[--noparameters]
[--noprofiles]
[--noshowreadonly]
[--notemplates]
[--nowarnredef]
[--nowarnbibref]
[--nowarnenableparameter]
[--nowarnnumentries]
[--nowarnreport]
[--nowarnprofbadref]
[--nowarnuniquekeys]
[--nowarnwtref]
[--objpat=p("")]
[--option=n=v]...
[--outfile=s]
[--pedantic[=i(1)]]
[--plugin=s]...
[--quiet]
[--report=html|htmlbbf|(null)|tab|text|xls|xml|xsd|other...]
[--showdiffs]
[--showreadonly]
[--showspec]
[--showsyntax]
[--showunion]
[--sortobjects]
[--special=s]
[--thisonly]
[--tr106=s(TR-106)]
[--trpage=s(http://www.broadband-forum.org/technical/download)]
[--ucprofile=s]...
[--ugly]
[--upnpdm]
[--verbose[=i(1)]]
[--warnbibref[=i(1)]]
[--writonly]
DM-instance...

=over

=item * the most common options are --include, --loglevel and --report=html

=item * use --compare to compare files and --showdiffs to show differences

=item * cannot specify both --report and --special

=back

=head1 DESCRIPTION

The files specified on the command line are assumed to be XML TR-069 data model definitions compliant with the I<cwmp:datamodel> (DM) XML schema.

The script parses, validates and reports on these files, generating output in various possible formats to I<stdout>.

There are a large number of options but in practice only a few need to be used.  For example:

./report.pl --report html tr-098-1-2-0.xml >tr-098-1-2-0.html

=head1 OPTIONS

=over

=item B<--allbibrefs>

usually only bibliographic references that are referenced from within the data model definition are listed in the report; this isn't much help when generating a list of bibliographic references without a data model! that's what this option is for; currently it affects only B<html> reports

=item B<--autobase>

causes automatic addition of B<base> attributes when models, parameters and objects are re-defined, and suppression of redefinition warnings (useful when processing auto-generated data model definitions)

is implied by B<--compare>

=item B<--automodel>

enables the auto-generation, if no B<model> element was encountered, of an auto-generated model that references each non-internal component, i.e. each component whose name doesn't begin with an underscore

this is preferable to the (deprecated) B<--noautomodel> because it allows various error messages to be suppressed

=item B<--autodatatype>

causes the B<{{datatype}}> template to be automatically prefixed for parameters with named data types

this is deprecated because it is enabled by default

=item B<--bibrefdocfirst>

causes the B<{{bibref}}> template to be expanded with the document first, i.e. B<[DOC] Section n> rather than the default of B<Section n/[DOC]>

=item B<--canonical>

new behavior: omits text that would cause lots of differences between nominally similar reports; is particularly aimed at allowing direct comparison of HTML generated from normative XML and from the "flattened" XML of the B<xml> report

old behavior: affected only the B<xml> report; caused descriptions to be processed into a canonical form that eased comparison with the original Microsoft Word descriptions

=item B<--catalog=s>...

can be specified multiple times; XML catalogs (http://en.wikipedia.org/wiki/XML_Catalog); the current directory and any directories specified via B<--include> are searched when locating XML catalogs

XML catalogs are used only when processing URL-valued B<schemaLocation> attributes during DM instance validation; it is not necessary to use XML catalogs in order to validate DM instances; see B<--loglevel>

=item B<--compare>

compares the two files that were specified on the command line, showing the changes made by the second one

note that this is identical to setting B<--autobase> and B<--showdiffs>; it also affects the behavior of B<--lastonly>

=item B<--components>

affects only the B<xml> report; generates a component for each object; if B<--noobjects> is also specified, the component omits the object definition and consists only of parameter definitions

=item B<--configfile=s("")>

the name of the configuration file; the configuration file format and usage are specific to the report type; not all report types use configuration files

the configuration file name can also be specified via B<--option configfile=s> but this usage is deprecated

defaults to B<report.ini> where B<report> is the report type, e.g. B<htmlbbf.ini> for the B<htmlbbf> report

=item B<--cwmpindex=s(..)>

affects only the B<html> report; specifies the location of the BBF CWMP index page, i.e. the page generated using the B<htmlbbf> report; is used to generate a link back to the appropriate location within the index page

defaults to B<../cwmp> (parent directory), which will work for the BBF web site but will not necessarily work in other locations; the generated link will be B<cwmpindex#xmlfile>, e.g. B<../cwmp#tr-069-1-0-0.xml>

=item B<--cwmppath=s(cwmp)>

affects only the B<htmlbbf> report; specifies the location of the XML and HTML files relative to the BBF CWMP index page

defaults to B<cwmp> (sub-directory), which will work for the BBF web site; can be set to B<http://www.broadband-forum.org/cwmp> to generate a local BBF CWMP index page that references published content

=item B<--debugpath=p("")>

outputs debug information for parameters and objects whose path names match the specified pattern

=item B<--deletedeprecated>

mark all deprecated or obsoleted items as deleted

=item B<--diffs>

has the same affect as specifying both B<--lastonly> (reports only items that were defined or last modified in the last XML file on the command line) and B<--showdiffs> (visually indicates the differences)

=item B<--diffsext=s(diffs)>

how diffs files referenced by the B<htmlbbf> report are named; for DM Instance B<foo.xml>, the diffs file name is B<foo-diffsext.html>; the default is B<diffs>, i.e. the default file name is B<foo-diffs.html>

note: as an advanced feature, if this option is specified twice, the first value should be B<last> and will be used for files known to be named B<foo-last.html> on the BBF CWMP page, and the second value (typically B<diffs>) will be used for all other files

=item B<--dtprofile=s>...

affects only the B<xml> report; can be specified multiple times; defines profiles to be used to generate an example DT instance

for example, specify B<Baseline> to select the latest version of the B<Baseline> pofile, or B<Baseline:1> to select the B<Baseline:1> profile

B<base> and B<extends> attributes are honored, so (for example), B<Baseline:2> will automatically include B<Baseline:1> requirements

=item B<--dtspec=s>

affects only the B<xml> report; has an affect only when B<--dtprofile> is also present; specifies the value of the top-level B<spec> attribute in the generated DT instance; if not specified, the spec defaults to B<urn:example-com:device-1-0-0>

=item B<--dtuuid=s>

affects only the B<xml> report; has an affect only when B<--dtprofile> is also present; specifies the value of the top-level B<uuid> attribute in the generated DT instance (there is no "uuid:" prefix); if not specified, the UUID defaults to B<00000000-0000-0000-0000-000000000000>

=item B<--exitcode>

if specified, the exit code is minus the number of reported errors, which will typically be masked to 8 bits, e.g. 2 errors would result in an exit code of -2, which might become 254

if not specified, the exit code is zero regardless of the number of errors

=item B<--help>

requests output of usage information

=item B<--ignore>

specifies a pattern; data models whose names begin with the pattern will be ignored

=item B<--importsuffix=s("")>

specifies a suffix which, if specified, will be appended (preceded by a hyphen) to the name part of any imported files in b<xml> reports

=item B<--include=d>...

can be specified multiple times; specifies directories to search for files specified on the command line or imported by other files

=over

=item * for files specified on the command line, the current directory is always searched first

=item * for files imported by other files, the directory containing the first file is always searched first; B<this behavior has changed; previously the current directory was always searched>

=item * no search is performed for files that already include directory names

=back

=item B<--info>

output details of author, date, version etc

=item B<--lastonly>

reports only on items that were defined or last modified in the specification corresponding to the last XML file on the command line (as determined by the last XML file's B<spec> attribute)

if B<--compare> is also specified, the "last only" criterion uses the file name rather than the spec (so the changes shown will always be those from the second file on the command line even if both files have the same spec)

=item B<--loglevel=tn(i)>

sets the log level; this consists of a B<type> and a B<sublevel> (0-9); all messages up and including this sublevel will be output to B<stderr>; the default type and sublevel are B<warning> and B<0>, which means that by default only error, informational and sublevel 0 warning messages will be output

by default, messages are output with a prefix consisting of the upper-case first letter of the log level type in parentheses, followed by a space; for example, "(E) " indicates an error message; the message prefix can be suppressed using B<--nologprefix>

the possible log level types, which can be abbreviated to a single character, are:

=over

=item B<fatal>

only fatal messages will be output; the sublevel is ignored

=item B<error>

only fatal and error messages will be output; the sublevel is ignored

=item B<info>

only fatal, error and informational messages will be output; the sublevel is ignored

=item B<warning>

only fatal, error, informational and warning messages will be output; the sublevel distinguishes different levels of warning messages

currently only warning messages with sublevels 0, 1 and 2 are distinguished, but all values in the range 0-9 are valid

=item B<debug>

fatal, error, informational, warning and debug messages will be output; the sublevel distinguishes different levels of debug messages

currently only debug messages with sublevels 0, 1 and 2 are distinguished, but all values in the range 0-9 are valid

=back

for example, a value of B<d1> will cause fatal, error, informational, all warning, and sublevel 0 and 1 debug messages to be output

the log level feature is used to implement the functionality of B<--quiet>, B<--pedantic> and B<--verbose> (all of which are still supported); these options are processed in the order (B<loglevel>, B<quiet>, B<pedantic>, B<verbose>), so (for example) B<--loglevel=d --pedantic> is the same as B<--loglevel=w>

a log level of warning or debug also enables XML schema validation of DM instances; XML schemas are located using the B<schemaLocation> attribute:

=over

=item * if it specifies an absolute path, no search is performed

=item * if it specifies a relative path, the directories specified via B<--include> are searched

=item * URLs are treated specially; if XML catalogs were supplied (see B<--catalog>) then they govern the behavior; otherwise, the directory part is ignored and the schema is located as for a relative path (above)

=back

=item B<--marktemplates>

mark selected template expansions with B<&&&&> followed by template-related information, a colon and a space

for example, the B<reference> template is marked by a string such as B<&&&&pathRef-strong:>, B<&&&&pathRef-weak:>, B<&&&&instanceRef-strong:>, B<&&&&instanceRef-strong-list:> or B<enumerationRef:>

and the B<list> template is marked by a string such as B<&&&&list-unsignedInt:> or B<&&&&list-IPAddress:>

=item B<--maxchardiffs=i(5)>, B<--maxworddiffs=i(10)>

these control how differences are shown in descriptions; each paragraph is handled separately

=over

=item * if the number of inserted and/or deleted characters in the paragraph is less than or equal to B<maxchardiffs>, changes are shown at the character level

=item * otherwise, if the number of inserted and/or deleted words in the paragraph is less than or equal to B<maxworddiffs>, changes are shown at the word level

=item * otherwise, the entire paragraph is shown as a single change

=back

=item B<--noautomodel>

disables the auto-generation, if no B<model> element was encountered, of an auto-generated model that references each non-internal component, i.e. each component whose name doesn't begin with an underscore

this is deprecated in favor of B<--automodel> and will be removed in a future version (at which point the default behavior will be changed so an automatic model is not created)

it is better to use B<--automodel> because it allows various error messages to be suppressed

=item B<--nocomments>

disables generation of XML comments showing what changed etc (B<--verbose> always switches it off)

=item B<--nohyphenate>

prevents automatic insertion of soft hyphens

=item B<--nolinks>

affects only the B<html> report; disables generation of hyperlinks (which makes it easier to import HTML into Word documents)

=item B<--nologprefix>

suppresses log message prefixes, i.e. the strings such as "E: " or "W: " that indicate errors, warnings etc

=item B<--nomodels>

specifies that model definitions should not be reported

=item B<--noobjects>

affects only the B<xml> report when B<--components> is specified; omits objects from component definitions

=item B<--noparameters>

affects only the B<xml> report when B<--components> is specified; omits parameters from component definitions

B<NOT YET IMPLEMENTED>

=item B<--noprofiles>

specifies that profile definitions should not be reported

=item B<--noshowreadonly>

disables showing read-only enumeration and pattern values as B<READONLY>

=item B<--notemplates>

suppresses template expansion (currently affects only B<html> reports

=item B<--nowarnbibref>

disables bibliographic reference warnings

see also B<--warnbibref>

=item B<--nowarnnableparameter>

disables warnings when a writable table has no enable parameter

=item B<--nowarnnumentries>

disables warnings (and/or errors) when a multi-instance object has no associated NumberOfEntries parameter

this is always an error so disabling these warnings isn't such a good idea

=item B<--nowarnredef>

disables parameter and object redefinition warnings (these warnings are also output if B<--verbose> is specified)

there are some circumstances under which parameter or object redefinition is not worthy of comment

=item B<--nowarnreport>

disables the inclusion of error and warning messages in reports (currently only in B<HTML> reports)

=item B<--nowarnprofbadref>

disables warnings when a profile references an invalid object or parameter

there are some circumstances under which it's useful to use an existing profile definition where some objects or parameters that it references have been (deliberately) deleted

this is deprecated because it is no longer needed (use status="deleted" as appropriate to suppress such errors)

=item B<--nowarnuniquekeys>

disables warnings when a multi-instance object has no unique keys

=item B<--nowarnwtref>

disables "referenced file's spec indicates that it's still a WT" warnings

=item B<--objpat=p>

specifies an object name pattern (a regular expression); objects that do not match this pattern will be ignored (the default of "" matches all objects)

=item B<--option=n=v>...

can be specified multiple times; defines options that can be accessed and used when generating the report; useful when used with reports implemented in plugins

=item B<--outfile=s>

specifies the output file; if not specified, output will be sent to I<stdout>

if the file already exists, it will be quietly overwritten

the only reason to use this option (rather than using shell output redirection) is that it allows the tool to know the name of the output file and therefore to include it in the generated XML, HTML report etc

=item B<--pedantic=[i(1)]>

enables output of warnings to I<stderr> when logical inconsistencies in the XML are detected; if the option is specified without a value, the value defaults to 1

this has the same effect as setting B<--loglevel> to "w" (warning) followed by the pedantic value minus one, e.g. "w1" for B<--pedantic=2>

=item B<--plugin=s>...

can be specified multiple times; defines external plugins that can define additional report types

=over

=item * currently each plugin must correspond to a file of the same name but with a B<.pm> (Perl Module) extension; for example, B<--plugin=foo> must correspond to a file called B<foo.pm>; the directories specified via the Perl include path (including the current directory) and via B<--include> are searched

=item * each plugin must define a package of the same name and can define one of more routines with names of the form B<rrr_node>; B<rrr> becomes an additional report type; if only one such routine is defined then by convention B<rrr> should be the same as the plugin name; for example, B<foo.pm> will always define the B<foo> package and will usually define a B<foo_node> routine

=item * the file can optionally also define routines with names of the form B<rrr_init>, B<rrr_begin>, B<rrr_postpar>, B<rrr_post> and B<rrr_end>

=item * B<rrr_init> is called after processing command line arguments but before reading any of the DM files; it can be used for initializing the plugin, e.g. parsing configuration files

=item * each of the other routines is called with three arguments; the first is the node on which it is to report; the second is the indentation level (0 means the initial call, for which the node is the root node, i.e. the parent of any B<model> nodes); the third is a reference to an option hash

=item * the B<begin> routine is called at the beginning; the B<node> routine is called for each node; the B<postpar> routine (if defined) is called after parameter B<node> routines have been called; the B<post> routine (if defined) is called after child node B<node> routines have been called; the B<end> routine is called at the end; these routines are not themselves responsible for traversing child nodes

=item * the node object is a reference to a hash that contains keys such as B<path> and B<name>; it is not currently documented

=item * it is safe to store information on the node; any new names should begin B<rrr_> in order to avoid name clashes

=item * these instructions are not expected to be sufficient to write a plugin; it will be necessary to consult the main report tool source code; the plugin interface may change in the future, in which case plugins may need to be adjusted

=item * the following illustrates just about the simplest possible valid plugin; it would be placed in a file called B<foo.pm> and would be used by specifying B<--plugin=foo --report=foo>

 package foo;
 
 sub foo_node
 {
     my ($node) = @_;
     print "$node->{path}\n";
 }
 
 1;

=back

=item B<--quiet>

suppresses informational messages

this used to have the same effect as setting B<--loglevel> to "e" (error) but now it simply suppresses such messages

=item B<--report=html|htmlbbf|(null)|tab|text|xls|xml|xsd|other...>

specifies the report format; one of the following:

=over

=item B<html>

HTML document; see also B<--nolinks> and B<--notemplates>

=item B<htmlbbf>

HTML document containing the information in the BBF CWMP index page; when generating this report, all the XSD and XML files are specified on the command line

the B<htmlbbf> report reads a configuration file whose name can be specified using B<--configfile>

see OD-290 and OD-148 for more details

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

if B<--lastonly> is not specified, DM XML with all imports resolved (apart from bibliographic references and data type definitions); use B<--dtprofile>, optionally with B<--dtspec> and B<--dtuuid>, to generate DT XML for the specified profiles; use B<--canonical> to omit transient information, e.g. dates and times, that makes it harder to compare reports; use B<--components> (perhaps with B<--noobjects> or B<--noparameters>) to generate component definitions

=item B<xml2>

same as the B<xml> report with B<--lastonly> not specified; deprecated (use B<xml> instead)

=item B<xsd>

W3C schema

=item other...

other report types can be supported via B<--plugin>

=back

=item B<--showdiffs>

currently affects only the B<text> and B<html> reports; visually indicates the differences resulting from the last XML file on the command line

for the B<html> report, insertions are shown in blue and deletions are shown in red strikeout; in order to enhance readability, hyperlinks are not shown in a special color (but are still underlined); note that this hyperlink behavior uses B<color=inherit>, which apparently isn't supported by Internet Explorer

is implied by B<--compare>

=item B<--showreadonly>

shows read-only enumeration and pattern values as B<READONLY>; this is enabled by default but can be disabled using B<--noshowreadonly>

this is deprecated because it is enabled by default and therefore has no effect

=item B<--showspec>

currently affects only the B<html> report; generates a B<Spec> rather than a B<Version> column

=item B<--showsyntax>

adds an extra column containing a summary of the parameter syntax; is like the Type column for simple types, but includes additional details for lists

=item B<--showunion>

adds "This object is a member of a union" text to objects that have "1 of n" or "union" semantics; such objects are identified by having B<minEntries=0> and B<maxEntries=1>

=item B<--sortobjects>

currently affects only the B<html> report; reports objects (and profiles) in alphabetical order rather than in the order that they are defined in the XML

=item B<--special=deprecated|imports|key|nonascii|normative|notify|obsoleted|pathref|profile|ref|rfc>

performs special checks, most of which assume that several versions of the same data model have been supplied on the command line, and many of which operate only on the highest version of the data model

=over

=item B<deprecated>, B<obsoleted>

for each profile item (object or parameter) report if it is deprecated or obsoleted

=item B<imports>, B<imports:element>, B<imports:element:name>

lists the components, data types and models that are defined in all the files that were read by the tool

B<element> is B<component>, B<dataType> or B<model> and can be abbreviated, so it is usual to specify just the first letter

B<name> is the first part of the element name (it can be the full element name but this is not necessary); element names which start with an underscore will also be listed

the output format is illustrated by these examples:

 report.pl --special=imports:m:Device:2 tr-181-2-3-0.xml
 model {tr-181-2-3-0}Device:2.3
 model {tr-181-2-3-0}Device:2.2 = {tr-181-2-2-0}Device:2.2
 model {tr-181-2-2-0}Device:2.2
 model {tr-181-2-2-0}Device:2.1 = {tr-181-2-1-0}Device:2.1
 model {tr-181-2-1-0}Device:2.1
 model {tr-181-2-1-0}Device:2.0 = {tr-181-2-0-1}Device:2.0
 model {tr-181-2-0-1}Device:2.0

 report.pl --special=imports:c:UPnP tr-181-2-3-0.xml
 component {tr-157-1-3-0}UPnP = {tr-157-1-2-0}UPnP
 component {tr-157-1-2-0}UPnPDiffs
 component {tr-157-1-2-0}UPnP
 component {tr-157-1-2-0}_UPnP = {tr-157-1-1-0}UPnP {tr-157-1-0-0}
 component {tr-157-1-1-0}UPnP = {tr-157-1-0-0}UPnP
 component {tr-157-1-0-0}UPnP
 component {tr-181-2-0-1}UPnP = {tr-157-1-2-0}UPnP
 component {tr-157-1-4-0}UPnP = {tr-157-1-3-0}UPnP {tr-157-1-2-0}

each line starts with the element name, followed by the element in the form B<{file}name>; then, if the element is imported from another file (possibly using a different name), that is indicated after an equals sign; finally if the actual definition is in a different file, that is indicated in the form B<{file}>

for example, the following line indicates that the B<tr-157-1-2-0> B<_UPnP> component is imported from the B<tr-157-1-1-0> B<UPnP> component, which is actually defined in B<tr-157-1-0-0>

 component {tr-157-1-2-0}_UPnP = {tr-157-1-1-0}UPnP {tr-157-1-0-0}

=item B<key>

for each table with a functional key, report access, path and the key

=item B<nonascii>

check which model, object, parameter or profile descriptions contain characters other than ASCII 9-10 or 32-126; the output is the full path names of all such items, together with the offending descriptions with the invalid characters surrounded by pairs of asterisks

the above list is followed by a list of the invalid characters and how often each one occurred

=item B<normative>

check which model, object, parameter or profile descriptions contain inappropriate use of normative language, i.e. lower-case normative words, or B<MAY NOT>; the output is the full path names of all such items, together with the offending descriptions with the normative words surrounded by pairs of asterisks

the above list is followed by a list of the invalid terms and how often each one occurred

=item B<notify>

check which parameters in the highest version of the data model are not in the "can deny active notify request" table; the output is the full path names of all such parameters, one per line

=item B<pathref>

for each pathRef parameter, report cases where a "CPE-managed, non-fixed" object references another "CPE-managed, non-fixed" object; these are candidate cases for objects that should have the same lifetime

=item B<profile>

check which parameters defined in the highest version of the data model are not in profiles; the output is the full path names of all such parameters, one per line

=item B<rfc>

check which model, object, parameter or profile descriptions mention RFCs without giving references; the output is the full path names of all such items, together with the offending descriptions with the normative words surrounded by pairs of asterisks

this doesn't work very well and isn't particularly useful

=item B<ref>

for each reference parameter, report access, reference type and path

=back

=item B<--thisonly>

outputs only definitions defined in the files on the command line, not those from imported files

=item B<--tr106=s(TR-106)>

indicates the TR-106 version (i.e. the B<bibref> name) to be referenced in any automatically generated description text

the default value is the latest version of TR-106 that is referenced elsewhere in the data model (or B<TR-106> if it is not referenced elsewhere)

=item B<--trpage=s(http://www.broadband-forum.org/technical/download/)>

indicates the location of the PDF versions of BBF standards; is concatenated with the filename (trailing slash is added if necessary)

=item B<--ucprofile=s>...

affects only the B<xml> report; can be specified multiple times; defines use case profiles whose requirements will be checked against the B<--dtprofile> profiles

=item B<--upnpdm>

transforms output (currently HTML only) so it looks like a B<UPnP DM> (Device Management) data model definition

=item B<--ugly>

disables some prettifications, e.g. inserting spaces to encourage line breaks

this is deprecated because it has been replaced with the more specific B<--nohyphenate> and B<--showsyntax>

=item B<--verbose[=i(1)]>

enables verbose output; the higher the level the more the output

this has the same effect as setting B<--loglevel> to "d" (debug) followed by the verbose value minus one, e.g. "d2" for B<--verbose=3>

=item B<--warnbibref[=i(1)]>

enables bibliographic reference warnings (these warnings are also output if B<--verbose> is specified); the higher the level the more warnings

setting it to -1 is the same as setting B<--nowarnbibref> and suppresses various bibref-related errors that would normally be output

previously known as B<--warndupbibref>, which is now deprecated (and will be removed in a future release) because it covers more than just duplicate bibliographic references

=item B<--writonly>

reports only on writable parameters (should, but does not, suppress reports of read-only objects that contain no writable parameters)

=back

=head1 LIMITATIONS

This script is only for illustration of concepts and has many shortcomings.

=cut
