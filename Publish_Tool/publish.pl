#!/usr/bin/env perl
#
# Copyright (C) 2013, 2014  Cisco Systems
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

# XXX check mtime and time zones; seems to change with time zone? want it to
#     based on GMT

# XXX need to detect and reject spaces in archive / directory names

# XXX wtdir isn't sufficient; there are two cases: during WT development when
#     want just WTs to be used and TRs to be ignored, and when about to
#     publish when will (or might) be named TR-nnn so want TRs too to be used;
#     should add a --trdir with a TR pattern (that's the only difference) and
#     should search --trdir before --wtdir (integrate this with --ildir)

# XXX re the above, in at least the --trdir case should be laxer wrt which
#     directories to accept; possibly accept all of them?

# XXX add controls over which XML dependencies are used, e.g. whether to
#     include dependencies on support files or on the report tool (by default
#     should do neither of these)

# XXX add control over whether the index file is re-generated (by default yes
#     if needed)

# XXX add index file dependence on OD-148

# XXX workdir (like cwmpdir) should have a cwmp sub-directory; maybe have an
#     option controlling whether index.html is in cwmp (better) or its parent

# XXX make it work with a non-existent or empty or out of date CWMP directory,
#     i.e. create the directory and fetch the ZIP file if need be

# XXX it can't cope with reverting, e.g. briefly had tr-106-1-0-1-types.xml and
#     then reverted to tr-106-1-0-0-types.xml but the 1-0-1 version remained
#     and was used; when copying should check that there is no higher
#     corrigendum

# XXX need to use same message styles and controls as report.pl; in particular
#     don't use "warn"?

# XXX exclude the no-corrigendum files from the ZIP?

# XXX index.html should depend on the config file (OD-148.txt); could put more
#     info into the config file?

# XXX index.html should be directly usable in the BBF CWMP page

# XXX should have option of working in empty output directory; would make it
#     easier when generating updates to upload

# Begin documentation
=head1 NAME

publish.pl - manage the publication of BBF XML

=head1 SYNOPSIS

B<publish.pl>
[--cwmpdir=s(CWMP)]
[--ildir=s()]...
[--od148=s(OD-148.txt)]
[--makevar=n=v]...
[--support=s(tr-069-biblio.xml,tr-106-types.xml)]...
[--workdir=s(Work)]
[--wtdir=s(Publish)]...
[--help]

=item B<--cwmpdir=s(CWMP)>

CWMP directory; contains B<cwmp.zip> and its unzipped contents; defaults to B<CWMP>

if connected to the Internet, the script always checks that B<cwmp.zip> is the same as the file at B<http://www.broadband-forum.org/cwmp/cwmp.zip> and, if not, it downloads it to B<--cwmpdir> and unzips it

the script always checks that the contents of B<--cwmpdir> match the ZIP archive; if not, it clears out the directory and (re-)unzips it

XXX no it doesn't do much of the above

=item B<--ildir=s()>..
directories to be searched for IL directories and ZIP archives; can be specified multiple times; defaults to an empty list

=item B<--od148=s(OD-148.txt)>

the location of B<OD-148> to pass to the BBF Report Tool when generating the CWMP Index

=item B<--makevar=n=v>...

can be specified multiple times; defines default values for some (not all) B<makefile> variables; the following are definitely supported and others might be supported now of in the future:

programs (default)

=over

=item * CP (/bin/cp)

=item * EXTRACT (./extract.pl)

=item * REPORT ($HOME/bin/report.pl)

=item * TOUCH (touch)

=back

flags

=over

=item * CP_FLAGS (-f)

=item * EXTRACT_FLAGS (-js)

=item * REPORT_FLAGS ()

=item * TOUCH_FLAGS ()

=back

note that other flags can (and will) be appended to the above defaults, depending on the type of target

=item B<--support=s(tr-069-biblio.xml,tr-106-types.xml)]...>

support files; can be specified multiple times; defaults to B<tr-069-biblio.xml> and B<tr-106-types.xml>, which are the only support files at the time of writing

support files are not versioned, so it is not an error if a support file exists in both the CWMP directory and in one of the B<--ildir> or B<--wtdir> directories or ZIP archives

note that an omitted issue, amendment or corrigendum number matches the latest issue, amendment or corrigendum; this is why it's OK that they are all omitted in the default values, e.g. B<tr-106-types.xml> will currently match B<tr-106-1-0-0-types.xml>

note that a support file should not exist in more than one of the B<--ildir> or B<--wtdir> directories or ZIP archives; if this happens, a warning is output and the last encountered file is used

=item B<--workdir=s(Work)>

working directory; defaults to B<Work>

=item B<--wtdir=s(Publish)>...

directories to be searched for WT directories and ZIP archives; can be specified multiple times; defaults to a single sub-directory called B<Publish>

if the option is specified without a value (or with an empty value) this disables searching for WT directories and ZIP archives, which means that only the CWMP directory will be processed

only directories and ZIP archives whose names begin with "wt-" or "WT-" will be considered; they are processed in alphabetical order (the order only matters if there are duplicate files, which is only permitted for support files)

all directories are processed first, then all ZIP archives are processed; this means that a given WT can not be present as both a directory and a ZIP archive (because if is there will be duplicates)

when processing directories and ZIP archives, only files whose names end B<.xml> or B<.xsd> and which are in the top-level (sub-)directory are considered

=item B<--help>

requests output of usage information

=cut
# End documentation

use strict;
use warnings;

use Archive::Extract;
use Archive::Zip qw(:ERROR_CODES);
# XXX uncomment to enable traceback on warnings and errors
#use Carp::Always;
use Data::Dumper;
use File::Copy;
use File::Find::Rule;
use File::Path;
use File::Spec;
use File::stat;
use File::Temp;
use File::Touch;
use Getopt::Long;
use Pod::Usage;

# Output indented lines (discarding everything up to the first newline; this
# is because it's assumed called with qq{} with the text starting on the next
# line.
sub output {
    my ($lines) = @_;

    # discard leading whitespace up to the first newline
    $lines =~ s/[ \t]*\n//;

    # -1 retains trailing empty lines
    foreach my $line (split /\n/, $lines, -1) {
        print qq{$line\n};
    }
}

# Get command-line options
sub get_options {

    # XML that defines components (can change)
    # XXX would like to be able to support patterns to the extent of
    #     differentiating il-181-i-a-c.xml (defines model) and
    #     il-181-i-a-c-label.xml (defines component)
    my $comps = ['tr-143.xml', 'tr-157.xml', 'tr-262.xml'];

    # XML that defines components and root data models (this list will never
    # change)
    my $comproots = ['tr-143-1-0.xml', 'tr-157-1-0.xml', 'tr-157-1-1.xml',
                     'tr-157-1-2.xml', 'tr-157-1-3.xml'];

    # XML that looks as though it defines a new major version but doesn't
    # (this list will never change)
    my $notmajors = ['tr-098-1-0.xml', 'tr-181-1-0.xml'];

    # XML that used to define root objects but no longer does (this list will
    # never change)
    my $oldroots = ['tr-069-1-0.xml', 'tr-106-1-2.xml'];

    # XML support files (can change)
    my $support = ['tr-069-biblio.xml', 'tr-106-types.xml'];

    # make variables; any variables not defined here will be substituted as
    # empty strings
    my $makevar = {
        CP => q{/bin/cp},
        CP_FLAGS => q{-f},

        EXTRACT => q{./extract.pl},
        EXTRACT_FLAGS => q{-js},

        REPORT => q{$(HOME)/bin/report.pl},
        REPORT_FLAGS => q{},

        TOUCH => q{touch},
        TOUCH_FLAGS => q{}
    };

    # default options...
    # XXX would prefer cwmpurl to be http://www.broadband-forum.org/cwmp; maybe
    #     the ZIP file should be moved so everything is below there?
    my $options = {
        comps => $comps,
        comproots => $comproots,
        cwmpdir => 'CWMP',
        cwmpurl => 'http://www.broadband-forum.org',
        cwmpzip => 'cwmp.zip',
        ildir => [],
        notmajors => $notmajors,
        od148 => 'OD-148.txt',
        oldroots => $oldroots,
        makevar => $makevar,
        support => $support,
        workdir => 'Work',
        wtdir => []
    };

    # ...can mostly be overridden by command-line options
    # XXX add --comps, --comproots, --notmajors and --oldroots; document them
    pod2usage(1) if
        !GetOptions($options,
                    'cwmpdir=s',
                    'ildir:s@',
                    'od148=s',
                    'makevar:s%',
                    'support:s@',
                    'workdir=s',
                    'wtdir:s@',
                    'help'
        ) || $options->{help};

    # XXX search for OD-148 in cwmpdir and wtdir(s)?
    # XXX add .txt file extension to OD-148 if not specified?

    # if --wtdir was supplied without a value, the value will be an empty
    # string (this disables use of any directories or ZIP archives)
    # if --wtdir wasn't supplied, there will be no value (this causes default
    # of ['Publish']
    my $wtdirs = $options->{wtdir};
    if (@$wtdirs == 1 && $wtdirs->[0] eq '') {
        $options->{wtdir} = [];
    } elsif (!@$wtdirs) {
        $options->{wtdir} = ['Publish'];
    }

    # check that source directories exist
    die "--cwmpdir $options->{cwmpdir} doesn't exist"
        unless -d $options->{cwmpdir};
    foreach my $dir (@{$options->{ildir}}) {
        die "--ildir $dir doesn't exist" unless -d $dir;
    }
    foreach my $dir (@{$options->{wtdir}}) {
        die "--wtdir $dir doesn't exist" unless -d $dir;
    }

    # check that OD-148 exists
    die "--od148 $options->{od148} doesn't exist"
        unless -r $options->{od148};

    return $options;
}

# Checking the CWMP directory...
sub check_cwmpdir {
    my ($cwmpurl, $cwmpzip, $cwmpdir) = @_;

    # full remote CWMP URL and local file name
    my $zipurl = qq{$cwmpurl/$cwmpzip};
    my $zippath = File::Spec->catfile($cwmpdir, $cwmpzip);

    # determine whether connected to the Internet
    # XXX how to check Internet connectivity?
    my $internet = 0;

    # if connected to the Internet, check the remote CWMP ZIP archive
    # modification time
    my $mtime = $internet ? url_mtime($zipurl) : 0;

    # check for existence of local copy of CWMP ZIP archive
    my $zippath_stat = stat($zippath);

    # if not there or local ZIP archive is older than remote one, download it
    # (note that the download retains the modification time)
    my $need_download = !$zippath_stat || $zippath_stat->mtime < $mtime;
    if ($need_download) {
        if ($internet) {
            print STDERR "need to download $cwmpzip but have no Internet\n";
        } else {
            download($zipurl, $zippath);
        }
    }

    # re-check the local modification time (changed if just downloaded)
    $zippath_stat = stat($zippath);

    # check the local ZIP archive unzip time
    # XXX this is a local convention using a magic file whose modification time
    #     is set to that of the most recently unzipped ZIP archive
    my $magic_file = qq{$zippath.unzipped};
    my $magic_stat = stat($magic_file);

    # (re-)unzip if necessary
    # XXX need also to check that the destination directory exists; otherwise
    #     can just delete it and won't notice (or be LESS clever?)
    my $need_unzip = !$magic_stat || $magic_stat->mtime < $zippath_stat->mtime;
    if ($need_unzip) {
        print STDERR "unzipping $zippath\n";
        # XXX need to clear out previous contents (apart from the ZIP)
        unzip($zippath, $cwmpdir);
        my $touch = File::Touch->new(atime => $zippath_stat->atime,
                                     mtime => $zippath_stat->mtime);
        $touch->touch($magic_file);
    }
}

# Download a file from a URL to the specified path.
sub download {
    my ($url, $path) = @_;

    print STDERR "would download $url to $path\n";
}

# Check whether a source file is of interest; returns -1 if not (and error),
# 0 if not (not error) and 1 if so.
sub file_is_of_interest {
    my ($name) = @_;

    # all XSD files are of interest
    return 1 if $name =~ /\.xsd$/;

    # catalog.xml is of interest
    # XXX shouldn't hard code this
    return 1 if $name eq 'catalog.xml';

    # check for "standard" XML files
    my ($tr, $nnn, $i, $a, $c, $label) = parse_file_name($name, '.xml');
    my $full = $label && $label =~ /-(all|full)$/;
    my $rev = $label && $label =~ /^-rev-/i;

    # files that don't start "il-nnn" or "tr-nnn" are unexpected
    return -1 if !$tr || $tr !~ /^(il|tr)$/ || !$nnn;

    # files that have $i and $a but not $c are not of interest
    my $no_corr = defined($i) && defined($a) && !defined($c);
    return 0 if $no_corr;
        
    # "full" files are not of interest
    # XXX "full" and "diffs" etc extensions should be parameterised
    return 0 if $full;

    # "rev" files are not of interest
    # XXX this is really a hack; such files shouldn't really be there
    return -1 if $rev;

    #  files with either all or none of $i, $a and $c are of interest
    my $all_iac = defined($i) && defined($a) && defined($c);
    my $none_iac = !defined($i) && !defined($a) && !defined($c);
    return 1 if $all_iac || $none_iac;

    # nothing else is of interest
    return -1;
}

# Scan the CWMP directory for XML and XSD files to be processed.
sub scan_cwmpdir {
    my ($cwmpdir, $files) = @_;

    # collect all files
    my $paths = matching_files([$cwmpdir], q{\.(xml|xsd)$});

    # select files of interest
    foreach my $path (@$paths) {
        my ($vol, $dir, $name) = File::Spec->splitpath($path);

        my $interest = file_is_of_interest($name);
        if ($interest < 0)  {
            warn "$cwmpdir contains unexpected $name (ignored)";
        } elsif ($interest) {
            add_file($name, $path, $files, {cwmpdir => 1});
        }
    }
}

# Scan a ZIP archive for (top-level) XML and XSD files to be processed.
# XXX add check for file name containing white space to file_is_of_interest? 
sub scan_archive {
    my ($archive, $files) = @_;

    my $zip = Archive::Zip->new();
    my $rc = $zip->read($archive);
    die "can't read $archive" unless $rc == AZ_OK;

    # this finds all files; files in sub-directories are weeded out below
    my @xmls = $zip->membersMatching('\.(xml|xsd)$');

    foreach my $xml (@xmls) {
        my $path = $xml->fileName();
        my ($vol, $dir, $name) = File::Spec->splitpath($path);
        my $interest = file_is_of_interest($name);
        if ($dir =~ /\/.*\//) {
            #warn "$name filename in $archive is in sub-directory (ignored)";
        } elsif ($name =~ / / || $interest < 0) {
            warn "$archive contains unexpected $name (ignored)";
        } elsif ($interest) {
            add_file($name, $archive, $files, {archive => 1});
        }
    }
} 

# Scan a directory for (top-level) XML and XSD files to be processed.
# XXX add check for file name containing white space to file_is_of_interest? 
sub scan_directory {
    my ($directory, $files) = @_;

    my $xmls = matching_files([$directory], '\.(xml|xsd)$', 1);

    foreach my $xml (@$xmls) {
        my $path = $xml;
        my ($vol, $dir, $name) = File::Spec->splitpath($path);
        my $interest = file_is_of_interest($name);
        if ($name =~ / / || $interest < 0) {
            warn "$directory contains unexpected $name (ignored)";
        } elsif ($interest) {
            add_file($name, $path, $files);
        }
    }
} 

# Split the files into categories (latest corrigendum only, except for nones):
# 1. dm0ns: XML data model definitions (amendment = 0) : not components
# 2. dm1ns: XML data model definitions (amendment > 0) : not components
# 3. dm0cs: XML data model definitions (amendment = 0) : components
# 4. dm1cs: XML data model definitions (amendment > 0) : components
# 5. comps: XML component definitions (overlaps with the above)
# 5. supps: XML support files
# 7. xsds:  XSD
# 8. nones: other (including outdated corrigenda)
sub categorize_files {
    my ($files, $allcomps, $allcomproots, $allnotmajors, $allsupport,
        $dm0ns, $dm1ns, $dm0cs, $dm1cs, $comps, $supps, $xsds, $nones) = @_;

    foreach my $file (@$files) {
        my $name = $file->{name};

        # XSD 
        if ($name =~ /\.xsd$/) {
            push @$xsds, $file;
            next;
        }

        # none (a) (is not the latest corrigendum)
        if ($file != $file->{latest_c}) {
            push @$nones, $file;
            next;
        }

        # support files
        # - after  none (a) to exclude old versions of versioned support files
        # - before none (b) because support files aren't necessarily versioned
        if (match_file($name, $allsupport)) {
            push @$supps, $file;
            next;
        }

        # none (b) (doesn't match $tr, $nnn, $i and $a)
        my ($tr, $nnn, $i, $a, $c, $label) = parse_file_name($name, '.xml');
        unless (defined($tr) && defined($nnn) && defined($i) && defined($a)) {
            push @$nones, $file;
            next;
        }

        # remaining files can be both a data model and a component
        my $is_comp = match_file($name, $allcomps);
        my $is_comproot = match_file($name, $allcomproots);
        my $is_notmajor = match_file($name, $allnotmajors);

        # data models
        # note: for comproot always dm1cs (none of them are version x.0) 
        my $dms = !$is_comproot ?
            ((!$is_notmajor && !$a) ? $dm0ns : $dm1ns) : ($dm1cs);
        push @$dms, $file if !$is_comp || $is_comproot;

        # components
        push @$comps, $file if $is_comp;
    }
}

# Parse a file name into tr, nnn, i, a, c (optional), label (optional) and
# extension; label (if present) includes the leading hyphen; extension includes
# the leading dot
sub parse_file_name {
    my ($name, $extmust) = @_;
    my ($tr, $nnn, $i, $a, $c, $label, $ext) =
        $name =~ /^([^-]+)-(\d+)(?:-(\d+))?(?:-(\d+))?(?:-(\d+))?(-\D[^\.]*)?(\..*)$/;
    $tr = $nnn = $i = $a = $c = $label = undef
        if $extmust && $ext && $ext ne $extmust;
    return ($tr, $nnn, $i, $a, $c, $label, $ext);
}

# Parse file name and return (a) without amendment and corrigendum numbers,
# (b) the amendment number, and (c) the corrigendum number.  If there is no
# amendment number, just return the original file name and 2 x undef.
sub file_name_noa {
    my ($name, $extmust) = @_;

    my ($tr, $nnn, $i, $a, $c, $label, $ext) = parse_file_name($name,$extmust);
    if (defined $a) {
        $label = qq{} unless $label;
        my $name_noa = qq{$tr-$nnn-$i$label$ext};
        return ($name_noa, $a, $c);
    } else {
        return ($name, undef, undef);
    }
}

# Parse file name and return (a) name without corrigendum number, and (b) the
# corrigendum number.  If there is no corrigendum number, just return the
# original file name and undef.
sub file_name_noc {
    my ($name, $extmust) = @_;

    my ($tr, $nnn, $i, $a, $c, $label, $ext) = parse_file_name($name,$extmust);
    if (defined $c) {
        $label = qq{} unless $label;
        my $name_noc = qq{$tr-$nnn-$i-$a$label$ext};
        return ($name_noc, $c);
    } else {
        return ($name, undef);
    }
}

# Does a file name match a supplied list?  The files can omit
# Issue, Amendment or Corrigendum (omitted means wild card).
sub match_file {
    my ($name, $others) = @_;

    my ($tr0, $nnn0, $i0, $a0, $c0, $label0, $ext0) = parse_file_name($name);
    $label0 = qq{} if !defined($label0);

    # if doesn't match at all, fall back on direct name comparison
    if (!defined($tr0) || !defined($nnn0)) {
        return grep {$_ eq $name} @$others;
    }

    # otherwise, more detailed comparison
    foreach my $other (@$others) {
        my ($tr1, $nnn1, $i1, $a1, $c1, $label1, $ext1) =
            parse_file_name($other);
        $label1 = qq{} if !defined($label1);

        next unless defined($tr1) && defined($nnn1);
        next unless $tr1 eq $tr0 && $nnn1 eq $nnn0 && $label1 eq $label0 &&
            $ext1 eq $ext0;

        return 1 if !defined($i0) || !defined($i1);
        next if $i0 != $i1;

        return 1 if !defined($a0) || !defined($a1);
        next if $a0 != $a1;

        return 1 if !defined($c0) || !defined($c1);
        next if $c0 != $c1;

        return 1;
    }
    return 0;
}

# Add a file to a list of files, either creating a new entry or else updating
# an existing entry.  Each entry is a hash of the form:
#
# {name => name, locs => [{path, dir, cwmp, arch}]...}
#
# where dir (stored for convenience) is the last component of the directory
# part of the path, and (cwmp, arch) come from the supplied (cwmpdir, archive)
# options.
sub add_file {
    my ($name, $path, $files, $opts) = @_;

    my ($nfile) = grep {$_->{name} eq $name} @$files;
    if (!$nfile) {
        $nfile = {name => $name, locs => []} unless $nfile;
        push @$files, $nfile;
    }

    # will store directory (last component only) for convenience; for an
    # archive, regard the ZIP file name as the directory name
    my ($vol_ignore, $directories, $name_only) = File::Spec->splitpath($path);
    my $dir;
    if ($opts->{archive}) {
        $dir = $name_only;
    } else {
        my @dirs = File::Spec->splitdir($directories);
        $dir = $dirs[-1];
        # splitpath() can return a trailing "/", which can be interpreted as an
        # empty directory name
        $dir = $dirs[-2] unless $dir;
    }

    push @{$nfile->{locs}}, {
        path => $path,
        dir  => $dir,
        cwmp => $opts->{cwmpdir},
        arch => $opts->{archive}
    };

    return $nfile;
}

# check for illegally duplicated files; return the number of errors
# XXX the first argument isn't necessarily just support files
sub check_duplicates {
    my ($support, $files) = @_;

    my $errors = 0;
    foreach my $file (@$files) {
        my $name = $file->{name};
        my $locs = $file->{locs};
        
        # never a problem if file was found only once
        next if @$locs == 1;

        # is file unversioned or 1-0-0?
        my ($xxx1, $xxx2, $i, $a, $c) = parse_file_name($name);
        $i = 1 unless defined $i;
        $a = 0 unless defined $a;
        $c = 0 unless defined $c;
        my $is100 = $i == 1 && $a == 0 && $c == 0;

        # not a problem if so, is a support file and was found in CWMP
        # directory and in one other directory
        my $is_support = $is100 && match_file($name, $support);
        next if $is_support && $locs->[0]->{cwmp} && @$locs == 2;

        warn "$name is in {" . join(', ', map({$_->{dir}} @$locs)) . "}";

        warn "...will use version in " . $locs->[-1]->{dir} if $is_support;
        $errors++ if !$is_support;
    }

    return $errors;
}

# update file objects' {latesta, latestc} attributes to reference the file
# objects that contain the latest (most recent) amendments and corrigenda;
# in many cases the file object will reference itself
sub update_latest {
    my ($files) = @_;

    # go through list populating hashes (keyed by name with omitted amendment
    # and/or corrigendum number) that point to the files with the highest
    # amendment and/or corrigendum numbers
    # XXX the highest amendment logic will take favour tr-181-2-157-0.xml
    #     over tr-181-2-8-0.xml, so hack to consider only a < 99
    my $latest_a = {};
    my $latest_c = {};
    foreach my $file (@$files) {
        my $name = $file->{name};
        my ($name_noa, $a, $c) = file_name_noa($name);
        my ($name_noc) = file_name_noc($name);

        # update latest amendment hash (this is rather messy because we don't
        # assume that the corrigendum number is defined)
        if (defined($a) && $a < 99) {
            if (!defined $latest_a->{$name_noa} ||
                $a > $latest_a->{$name_noa}->{amen} ||
                ($a == $latest_a->{$name_noa}->{amen} && defined($c) &&
                 (!defined $latest_a->{$name_noa}->{corr} ||
                  $c > $latest_a->{$name_noa}->{corr}))) {
                $latest_a->{$name_noa} = {amen => $a, corr => $c,
                                          file => $file};
            }
        }

        # update latest corrigendum hash
        if (defined($c)) {
            if (!defined $latest_c->{$name_noc} ||
                $c > $latest_c->{$name_noc}->{corr}) {
                $latest_c->{$name_noc} = {corr => $c, file => $file};
            }
        }
    }

    # go through list again, updating file objects to point to the latest
    # amendment and corrigendum (many instances will reference themselves)
    foreach my $file (@$files) {
        my $name = $file->{name};
        my ($name_noa, $a, $c) = file_name_noa($name);
        my ($name_noc) = file_name_noc($name);

        if (defined($latest_a->{$name_noa})) {
            $file->{latest_a} = $latest_a->{$name_noa}->{file};
        } else {
            $file->{latest_a} = $file;
        }

        if (defined($latest_c->{$name_noc})) {
            $file->{latest_c} = $latest_c->{$name_noc}->{file};
        } else {
            $file->{latest_c} = $file;
        }
    }
}

# Unzip a file to the specified directory.
# XXX this should clear out the existing directory, just in case a file was
#     removed between ZIP versions
sub unzip {
    my ($archive, $to) = @_;

    my $ae = Archive::Extract->new(archive => $archive);
    return $ae && $ae->extract(to => $to);
}

# Collect the names of all the files in the supplied directory trees
# whose names match the supplied pattern, e.g. supply a pattern of
# "\.zip$" to match ZIP archives.
sub matching_files {
    my ($directories, $pattern, $maxdepth) = @_;
    $maxdepth = 9999 unless defined $maxdepth;

    my @files = File::Find::Rule->extras({follow => 1})->
        mindepth(1)->maxdepth($maxdepth)->file()->
        name(qr/$pattern/i)->in(@$directories);
    my @sorted = sort(@files);
    return \@sorted;
}

# Collect the names of all the directories in the supplied directory trees
# whose names match the supplied pattern, e.g. supply a pattern of
# "^WT-" to match WT directories.
# XXX this is very similar identical to matching_files(); not sure what sort of
#     var to use for file() or directory()
sub matching_directories {
    my ($directories, $pattern, $maxdepth) = @_;
    $maxdepth = 9999 unless defined $maxdepth;

    my @dirs = File::Find::Rule->extras({follow => 1})->
        mindepth(1)->maxdepth($maxdepth)->directory()->
        name(qr/$pattern/i)->in(@$directories);
    my @sorted = sort(@dirs);
    return \@sorted;
}

# take a list of file objects and return a reference to the input sorted by
# file name and with duplicates removed
sub sort_uniq {
    my $seen = {};
    my @sorted = sort {$a->{name} cmp $b->{name}} @_;
    my @uniqed = grep {!$seen->{$_}++} @sorted;
    return \@uniqed;
}

# naively process XML files in order to determine dependencies
# XXX should break out scan_file() routine
sub scan_files {
    my ($files) = @_;

    # generate hashes (a) full file name to file object, and (b) mapping "no
    # corrigendum" file name to latest corrigendum file object
    my $filemap = {};
    my $latest_c = {};
    foreach my $file (@$files) {
        my $name = $file->{name};
        $filemap->{$name} = $file;

        my ($name_noc) = file_name_noc($name);
        $latest_c->{$name_noc} = $file->{latest_c}->{name};
    }

    foreach my $file (@$files) {
        my $name = $file->{name};
        my $path = $file->{locs}->[-1]->{path};

        # XXX can't yet check for archive members; you can do file-like i/o on
        #     them; need to add that
        if ($file->{arch}) {
            warn "$name is in a ZIP; can't yet check its dependencies";
        }

        open my $fd, "<", $path;
        # XXX must check that file was opened (fatal error if not)
        # XXX can exit loop once see anything other than <description> or
        #     <import>
        while (my $line = <$fd>) {
            my ($iname) = ($line =~ /<import\s+.*file="([^"]*)/);
            next unless $iname;

            # if name includes corrigendum number, remove it (it is quite
            # likely an old one and so won't be found)
            my ($iname_noc) = file_name_noc($iname);
            warn "$name: import of file $iname includes corrigendum number " .
                "(removed)" if $iname_noc ne $iname;
            $iname = $iname_noc;

            # replace "no corrigendum" name with latest corrigendum
            $iname = $latest_c->{$iname} if $latest_c->{$iname};

            # look up file object
            my $ifile = $filemap->{$iname};
            warn "$name: imported file $iname not found" unless $ifile;
            push @{$file->{deps}}, $ifile if $ifile;
        }
        close $fd;
    }
}

my $xml_deps_visited = {};

sub get_xml_deps {
    my ($file, $workdir, $alldeps, $depth) = @_;
    $depth = 0 unless defined($depth);

    my $name = $file->{name};
    my $deps = $file->{deps};

    # XXX not sure that this logic is globally correct...
    $xml_deps_visited = {} if $depth == 0;
    return if $xml_deps_visited->{$name};
    $xml_deps_visited->{$name} = 1;

    #my $indent = '  ' x $depth;
    #print STDERR "$indent$name\n";
    #print STDERR "$depth $name\n";

    return unless $deps && @$deps;

    # XXX this sort of grep indicates a problem; should use a hash, especially
    #     if will later sort the keys anyway
    foreach my $dep (@$deps) {
        push @$alldeps, $dep if !grep {$_->{name} eq $dep->{name}} @$alldeps;
        get_xml_deps($dep, $workdir, $alldeps, $depth+1);
    }
}

# generate name of hidden file that is touched to indicate that a source file
# has been copied
sub copied_file {
    my ($dir, $name) = @_;
    return qq{.$dir.$name.copied};
}

# generate name of hidden file that is touched to indicate that a source file
# or product has been created (either copied or generated)
sub created_file {
    my ($dir, $name) = @_;
    return qq{.$dir.$name.created};
}

# generate report tool rule
sub report_rule {
    my ($type, $dir, $source, $target) = @_;

    my $cpfile = copied_file($dir, $source);
    my $crfile = created_file($dir, $target);

    return qq{\$(WORKDIR)/$target \$(WORKDIR)/$crfile: \$(WORKDIR)/$source \$(WORKDIR)/$cpfile; \$(REPORT_$type) --outfile=\$(WORKDIR)/$target \$(WORKDIR)/$source; \$(TOUCH_ALL) \$(WORKDIR)/$crfile};
}

# generate makefile, assuming it will be run in the current directory
# XXX (already noted?) consider making it run in the Work directory
# XXX could check for missing schema files (based on analysis of versions);
#     e.g. cwmp-devicetype-1-2.xsd is currently missing
sub gen_makefile {
    my ($dm0ns, $dm1ns, $dm0cs, $dm1cs, $comps, $supps, $xsds, $nones,
        $cwmpdir, $wtdir, $workdir, $od148, $oldroots, $makevar) = @_;

    # space-separated lists of filenames (used for 'make' variables)
    my $dm0nfiles = join ' ', map {$_->{name}} @$dm0ns;
    my $dm1nfiles = join ' ', map {$_->{name}} @$dm1ns;
    my $dm0cfiles = join ' ', map {$_->{name}} @$dm0cs;
    my $dm1cfiles = join ' ', map {$_->{name}} @$dm1cs;
    my $compfiles = join ' ', map {$_->{name}} @$comps;
    my $suppfiles = join ' ', map {$_->{name}} @$supps;
    my $xsdfiles  = join ' ', map {$_->{name}} @$xsds;
    my $nonefiles = join ' ', map {$_->{name}} @$nones;

    # list of files for which to generate dupe (duplicate) rules
    # XXX should use a hash for the elements (see also other comment that
    #     suggests that we can avoid dupefiles altogether)
    my $dupefiles = {};

    # header
    output qq{
# DO NOT EDIT; auto-generated by XXX
# restricted make format:
# * only supports simple variables (no env vars)
# * only supports rules on the same line (dsts: srcs; rule)
# * only supports \$< and \$@ special variables
# * more...
};
    
    # definitions
    # XXX need some of these values to come from command line options
    # XXX don't assume location of CP and EXTRACT
    # XXX EXTRACT options might still be wrong; want -t to use current time
    #     not the ZIP file modification time? would be analogous with CP
    # XXX add special syntax for internal Perl rules?
    # XXX also define and use a variable for each ZIP or directory source,
    #     possibly also lists of files from each source (even though not
    #     actually needed); can get this info from the notional File class
    # XXX need to define proper rules for the ".copied" files and touching
    my $home = $ENV{HOME};
    my $cp = $makevar->{CP} || qq{};
    my $extract = $makevar->{EXTRACT} || qq{};
    my $report = $makevar->{REPORT} || qq{};
    my $touch = $makevar->{TOUCH} || qq{};
    my $cp_flags = $makevar->{CP_FLAGS} || qq{};
    my $extract_flags = $makevar->{EXTRACT_FLAGS} || qq{};
    my $report_flags = $makevar->{REPORT_FLAGS} || qq{};
    my $touch_flags = $makevar->{TOUCH_FLAGS} || qq{};
    my $phony = qq{.PHONY}; # . mucks up emacs indentation at start of line
    my $firstdep = qq{\$<};
    my $alldeps = qq{\$^};
    my $target = qq{\$@};
    my $report_rule = qq{--outfile=$target $firstdep};
    my $report_rule_all = qq{--outfile=$target $alldeps};
    $wtdir = join ' ', @$wtdir;
    output qq{
HOME    = $home

CWMPDIR = $cwmpdir
WTDIR   = $wtdir
WORKDIR = $workdir

CP = $cp
EXTRACT = $extract
REPORT = $report
TOUCH = $touch

CP_FLAGS = $cp_flags
CP_FLAGS_PRESERVE = -p
EXTRACT_FLAGS = $extract_flags
EXTRACT_FLAGS_PRESERVE = -t
REPORT_FLAGS = $report_flags
REPORT_FLAGS_HTML = --report=html
REPORT_FLAGS_XML = --report=xml
REPORT_FLAGS_INDEX = --report=htmlbbf --configfile=$od148 --cwmppath=''
TOUCH_FLAGS = $touch_flags

REPORT_FLAGS_DEV = --ignore=Internet
REPORT_FLAGS_IGD = --ignore=Device
REPORT_FLAGS_COMP = --nomodels --automodel
REPORT_FLAGS_BIBREF = --allbibrefs
REPORT_FLAGS_DIFFS = --diffs
REPORT_FLAGS_QUIET = XXX

CP_ALL = \$(CP) \$(CP_FLAGS)
CP_PRESERVE = \$(CP_ALL) \$(CP_FLAGS_PRESERVE)
EXTRACT_ALL = \$(EXTRACT) \$(EXTRACT_FLAGS)
EXTRACT_PRESERVE = \$(EXTRACT_ALL) \$(EXTRACT_FLAGS_PRESERVE)
REPORT_ALL = \$(REPORT) \$(REPORT_FLAGS)
REPORT_HTML = \$(REPORT_ALL) \$(REPORT_FLAGS_HTML)
REPORT_HTML_DEV = \$(REPORT_HTML) \$(REPORT_FLAGS_DEV)
REPORT_HTML_IGD = \$(REPORT_HTML) \$(REPORT_FLAGS_IGD)
REPORT_HTML_COMP = \$(REPORT_HTML) \$(REPORT_FLAGS_COMP)
REPORT_HTML_BIBREF = \$(REPORT_HTML) \$(REPORT_FLAGS_BIBREF)
REPORT_HTML_DIFFS = \$(REPORT_HTML) \$(REPORT_FLAGS_DIFFS)
REPORT_HTML_DEV_DIFFS = \$(REPORT_HTML_DEV) \$(REPORT_FLAGS_DIFFS)
REPORT_HTML_IGD_DIFFS = \$(REPORT_HTML_IGD) \$(REPORT_FLAGS_DIFFS)
REPORT_XML = \$(REPORT_ALL) \$(REPORT_FLAGS_XML)
REPORT_INDEX = \$(REPORT_ALL) \$(REPORT_FLAGS_INDEX)
TOUCH_ALL = \$(TOUCH) \$(TOUCH_FLAGS)

CP_RULE = \$(CP_ALL) $firstdep $target
CP_PRESERVE_RULE = \$(CP_PRESERVE) $firstdep $target
EXTRACT_RULE = \$(EXTRACT_ALL) $firstdep $target
EXTRACT_PRESERVE_RULE = \$(EXTRACT_PRESERVE) $firstdep $target
REPORT_HTML_RULE = \$(REPORT_HTML) $report_rule
REPORT_HTML_DEV_RULE = \$(REPORT_HTML_DEV) $report_rule
REPORT_HTML_IGD_RULE = \$(REPORT_HTML_IGD) $report_rule
REPORT_HTML_COMP_RULE = \$(REPORT_HTML_COMP) $report_rule
REPORT_HTML_BIBREF_RULE = \$(REPORT_HTML_BIBREF) $report_rule
REPORT_HTML_DIFFS_RULE = \$(REPORT_HTML_DIFFS) $report_rule
REPORT_HTML_DEV_DIFFS_RULE = \$(REPORT_HTML_DEV_DIFFS) $report_rule
REPORT_HTML_IGD_DIFFS_RULE = \$(REPORT_HTML_IGD_DIFFS) $report_rule
REPORT_XML_RULE = \$(REPORT_XML) $report_rule
REPORT_INDEX_RULE = \$(REPORT_INDEX) $report_rule_all
TOUCH_RULE = \$(TOUCH_ALL) $target

DM0NFILES = $dm0nfiles
DM1NFILES = $dm1nfiles
DM0CFILES = $dm0cfiles
DM1CFILES = $dm1cfiles
COMPFILES = $compfiles
SUPPFILES = $suppfiles
XSDFILES  = $xsdfiles
NONEFILES = $nonefiles

all: mkdirs copy full html dupe index
$phony: all
};

    # rules to ensure that directories exist
    # XXX fix so there is a real non-phony target here, and to create
    #     additional directories
    output qq{
mkdirs: ; \@mkdir -p \$(WORKDIR)
$phony: mkdirs
};

    # rules to copy files to the working directory
    my $copys = sort_uniq(@$dm0ns, @$dm1ns, @$dm0cs, @$dm1cs, @$comps, @$supps,
                          @$xsds, @$nones);
    output qq{
COPYFILES = \$(sort \$(DM0NFILES) \$(DM1NFILES) \$(DM0CFILES) \$(DM1CFILES) \$(COMPFILES) \$(SUPPFILES) \$(XSDFILES) \$(NONEFILES))
copy: \$(COPYFILES:%=\$(WORKDIR)/%)
$phony: copy
};

    foreach my $file (@$copys) {
        my $name = $file->{name};
        my $path = $file->{locs}->[-1]->{path};
        my $dir = $file->{locs}->[-1]->{dir};
        my $cpfile = copied_file($dir, $name);
        my $crfile = created_file($dir, $name);
        # XXX these are problematic because (a) CWMPDIR is scanned so the files
        #     could be at any level, (b) WTDIR is a list of directories
        #     (but it won't break anything)
        $path =~ s/^\Q$cwmpdir\E/\$(CWMPDIR)/;
        $path =~ s/^\Q$wtdir\E/\$(WTDIR)/;
        my $tool = $file->{arch} ? 'EXTRACT' : 'CP';
        # can't use TOUCH_RULE because there are multiple targets
        output qq{
\$(WORKDIR)/$name \$(WORKDIR)/$cpfile \$(WORKDIR)/$crfile: $path; \$(${tool}_PRESERVE) $path \$(WORKDIR)/$name; \$(TOUCH_ALL) \$(WORKDIR)/$cpfile \$(WORKDIR)/$crfile};

        # XXX have to exclude "nones" from copied files because they include
        #     outdated corrigenda that shouldn't be copied!
        $dupefiles->{$name} = [$dir, 1] unless
            grep {$_->{name} eq $name} @$nones;
    }

    # hash mapping XML file name to its products
    # XXX this might not be the right way to do this?
    # XXX this should be able to replace dupefiles?
    my $targets = {};

    # rules to generate "full" XML
    my $fulls = sort_uniq(@$dm0ns, @$dm1ns, @$dm0cs, @$dm1cs);
    output qq{

FULLFILES = \$(sort \$(DM0NFILES) \$(DM1NFILES) \$(DM0CFILES) \$(DM1CFILES))
full: \$(FULLFILES:%.xml=\$(WORKDIR)/%-full.xml)
$phony: full
};
    foreach my $file (@$fulls) {
        my $fullfile = my $name = $file->{name};
        my $dir = $file->{locs}->[-1]->{dir};
        $fullfile =~ s/\.xml$/-full.xml/;
        my $rule = report_rule('XML', $dir, $name, $fullfile);
        output qq{
$rule};
        $dupefiles->{$fullfile} = [$dir, 0];
        push @{$targets->{$name}}, $fullfile;
    }

    # rules to generate HTML
    output qq{

html: htmlfull htmldiffs
$phony: html};

    # rules to generate "full" HTML
    output qq{

htmlfull: htmlfull1 htmlfull2 htmlfull3 htmlfull4
$phony: htmlfull};

    # 1. from XML that contains no components
    my $htmlfull1s = sort_uniq(@$dm0ns, @$dm1ns);
    output qq{

HTMLFULL1FILES = \$(sort \$(DM0NFILES) \$(DM1NFILES))
htmlfull1: \$(HTMLFULL1FILES:%.xml=\$(WORKDIR)/%.html)
$phony: htmlfull1
};

    foreach my $file (@$htmlfull1s) {
        my $htmlfile = my $name = $file->{name};
        my $dir = $file->{locs}->[-1]->{dir};
        $htmlfile =~ s/\.xml$/.html/;
        my $rule = report_rule('HTML', $dir, $name, $htmlfile);
        output qq{
$rule};
        $dupefiles->{$htmlfile} = [$dir, 0];
        push @{$targets->{$name}}, $htmlfile;
    }

    # 2. from XML that contains models and components; need to generate
    #    HTML for both Device:1 (dev) and InternetGatewayDevice:1 (igd)
    my $htmlfull2s = sort_uniq(@$dm0cs, @$dm1cs);
    output qq{

HTMLFULL2FILES = \$(sort \$(DM0CFILES) \$(DM1CFILES))
htmlfull2: \$(HTMLFULL2FILES:%.xml=\$(WORKDIR)/%-dev.html) \$(HTMLFULL2FILES:%.xml=\$(WORKDIR)/%-igd.html)
$phony: htmlfull2
};
    foreach my $file (@$htmlfull2s) {
        my $devhtmlfile = my $igdhtmlfile = my $name = $file->{name};
        my $dir = $file->{locs}->[-1]->{dir};
        $devhtmlfile =~ s/\.xml$/-dev.html/;
        $igdhtmlfile =~ s/\.xml$/-igd.html/;
        my $devrule = report_rule('HTML_DEV', $dir, $name, $devhtmlfile);
        my $igdrule = report_rule('HTML_IGD', $dir, $name, $igdhtmlfile);
        output qq{
$devrule
$igdrule};
        $dupefiles->{$devhtmlfile} = [$dir, 0];
        $dupefiles->{$igdhtmlfile} = [$dir, 0];
        push @{$targets->{$name}}, $devhtmlfile;
        push @{$targets->{$name}}, $igdhtmlfile;
    }

    # 3. from XML that contains components only
    my $htmlfull3s = sort_uniq(@$comps);
    output qq{

HTMLFULL3FILES = \$(sort \$(COMPFILES))
htmlfull3: \$(HTMLFULL3FILES:%.xml=\$(WORKDIR)/%.html)
$phony: htmlfull3
};
    foreach my $file (@$htmlfull3s) {
        my $htmlfile = my $name = $file->{name};
        my $dir = $file->{locs}->[-1]->{dir};
        $htmlfile =~ s/\.xml$/.html/;
        my $rule = report_rule('HTML_COMP', $dir, $name, $htmlfile);
    output qq{
$rule};
        $dupefiles->{$htmlfile} = [$dir, 0];
        push @{$targets->{$name}}, $htmlfile;
    }

    # 4. from XML support files
    # XXX need different options for individual support files; hard code?
    my $htmlfull4s = sort_uniq(@$supps);
    output qq{

HTMLFULL4FILES = \$(sort \$(SUPPFILES))
htmlfull4: \$(HTMLFULL4FILES:%.xml=\$(WORKDIR)/%.html)
$phony: htmlfull4
};
    foreach my $file (@$htmlfull4s) {
        my $htmlfile = my $name = $file->{name};
        my $dir = $file->{locs}->[-1]->{dir};
        $htmlfile =~ s/\.xml$/.html/;
        my $type = ($name =~ /biblio/) ? '_BIBREF' : '';
        my $rule = report_rule(qq{HTML$type}, $dir, $name, $htmlfile);
    output qq{
$rule};
        $dupefiles->{$htmlfile} = [$dir, 0];
        push @{$targets->{$name}}, $htmlfile;
    }

    # rules to generate "diffs" HTML
    output qq{

htmldiffs: htmldiffs1 htmldiffs2
$phony: htmldiffs};

    # 1. from XML that contains no components (amendment > 0)
    my $htmldiffs1s = sort_uniq(@$dm1ns);
    output qq{

HTMLDIFFS1FILES = \$(sort \$(DM1NFILES))
htmldiffs1: \$(HTMLDIFFS1FILES:%.xml=\$(WORKDIR)/%-diffs.html)
$phony: htmldiffs1
};
    foreach my $file (@$htmldiffs1s) {
        my $htmlfile = my $name = $file->{name};
        my $dir = $file->{locs}->[-1]->{dir};
        $htmlfile =~ s/\.xml$/-diffs.html/;
        my $rule = report_rule('HTML_DIFFS', $dir, $name, $htmlfile);
        output qq{
$rule};
        $dupefiles->{$htmlfile} = [$dir, 0];
        push @{$targets->{$name}}, $htmlfile;
    }

    # 2. from XML that contains models and components (amendment > 0)
    # XXX actually this is all of them, because for these files, amendment 0
    #     doesn't mean data model version x.0
    my $htmldiffs2s = sort_uniq(@$dm1cs);
    output qq{

HTMLDIFFS2FILES = \$(sort \$(DM1CFILES))
htmldiffs2: \$(HTMLDIFFS2FILES:%.xml=\$(WORKDIR)/%-dev-diffs.html) \$(HTMLDIFFS2FILES:%.xml=\$(WORKDIR)/%-igd-diffs.html)
$phony: htmldiffs2
};
    foreach my $file (@$htmldiffs2s) {
        my $devhtmlfile = my $igdhtmlfile = my $name = $file->{name};
        my $dir = $file->{locs}->[-1]->{dir};
        $devhtmlfile =~ s/\.xml$/-dev-diffs.html/;
        $igdhtmlfile =~ s/\.xml$/-igd-diffs.html/;
        my $devrule = report_rule('HTML_DEV_DIFFS', $dir, $name, $devhtmlfile);
        my $igdrule = report_rule('HTML_IGD_DIFFS', $dir, $name, $igdhtmlfile);
        output qq{
$devrule
$igdrule};
        $dupefiles->{$devhtmlfile} = [$dir, 0];
        $dupefiles->{$igdhtmlfile} = [$dir, 0];
        push @{$targets->{$name}}, $devhtmlfile;
        push @{$targets->{$name}}, $igdhtmlfile;
    }

    # rules to create duplicate copies (without corrigendum numbers)
    my $dupes;
    foreach my $name (sort keys %$dupefiles) {
        my $dir = $dupefiles->{$name}->[0];
        my ($name_noc, $c) = file_name_noc($name);
        # XXX should use a hash here (even though only used locally)
        push @$dupes, [$name, $name_noc, $dir] if defined($c);
    }
    my $dupefiles_noc = join ' ', map {$_->[1]} @$dupes;
    output qq{

DUPEFILES = $dupefiles_noc
dupe: \$(DUPEFILES:%=\$(WORKDIR)/%)
$phony: dupe
};
    foreach my $dupe (@$dupes) {
        my $name = $dupe->[0];
        my $name_noc = $dupe->[1];
        my $dir = $dupe->[2];
        my $crfile = created_file($dir, $name);
        # XXX this still has the problem that it always re-copies source files;
        #     can this be avoided?
        output qq{
\$(WORKDIR)/$name_noc: \$(WORKDIR)/$crfile; \@\$(CP_PRESERVE) \$(WORKDIR)/$name \$(WORKDIR)/$name_noc};
    }

    # rules for dependencies (note this excludes nones because we don't want to
    # generate dependencies for outdated corrigenda)
    my $dms = sort_uniq(@$dm0ns, @$dm1ns, @$dm0cs, @$dm1cs, @$comps, @$supps);
    scan_files($dms);
    output qq{

deps:
$phony: deps
};
    foreach my $file (@$dms) {
        my $name = $file->{name};
        my $deps = [];
        get_xml_deps($file, $workdir, $deps);
        my $nametargs = $targets->{$name};
        foreach my $targ (@$nametargs) {
            foreach my $dep (@$deps) {
                my $dfile = $dep->{name};
                output qq{
\$(WORKDIR)/$targ: \$(WORKDIR)/$dfile};
            }
        }
    }

    # rule to create index file
    # XXX only the latest amendments of the non-comproot XML is processed;
    #     unfortunately (possibly because of a report tool bug) it is
    #     necessary to exclude files like tr-069-1-0-0.xml which look like
    #     latest amendments but in fact are not
    my $indexfiles = [];
    for my $file (@$dm0ns, @$dm1ns) {
        my $name = $file->{name};
        push @$indexfiles, $name
            if !match_file($name, $oldroots) && $file->{latest_a} == $file;
    }
    $indexfiles = join ' ', sort @$indexfiles;
    output qq{

INDEXFILES = \$(XSDFILES) $indexfiles
index: copy full html \$(WORKDIR)/index.html
$phony: index
};

    # XXX brain-dead index.html dependencies
    foreach my $file ((@$dms, @$xsds)) {
        my $name = $file->{name};
        my $dir = $file->{locs}->[-1]->{dir};
        my $crfile = created_file($dir, $name);
        output qq{
\$(WORKDIR)/index.html: \$(WORKDIR)/$crfile};
    }

    output qq{
\$(WORKDIR)/index.html: ; \$(REPORT_INDEX) --outfile=$target \$(INDEXFILES:%=\$(WORKDIR)/%)};

    # XXX need rule to create new cwmp.zip file

    # XXX for report tool rules, consider cd to workdir
}

# Main program
sub main
{
    my $options = get_options();

    # check the CWMP directory, which might involve downloading cwmp.zip and/or
    # unzipping it
    check_cwmpdir($options->{cwmpurl}, $options->{cwmpzip},
                  $options->{cwmpdir});

    # scan the CWMP directory for XML and XSD files to be processed
    my $files = [];
    scan_cwmpdir($options->{cwmpdir}, $files);

    # determine which ZIP archives will be processed
    # XXX might want to make this less general, e.g. just pass the
    #     names of the ZIP archives or directories directly? 
    my $ilarchives = matching_files($options->{ildir}, "^(IL|il).*\.zip\$", 1);
    my $wtarchives = matching_files($options->{wtdir}, "^(WT|wt).*\.zip\$", 1);
    my @archives = (@$ilarchives, @$wtarchives);

    # XXX should detect when both archive and directory are present and
    #     ignore archive (on the assumption that it's been unzipped)? or
    #     leave it as is because get warnings

    # scan the directories for XML and XSD files to be processed
    my $ildirectories = matching_directories($options->{ildir},
                                             "^(IL|il)-", 1);
    my $wtdirectories = matching_directories($options->{wtdir},
                                             "^(WT|wt)-", 1);
    my @directories = (@$ildirectories, @$wtdirectories);
    foreach my $directory (@directories) {
        scan_directory($directory, $files);
    }

    # scan the ZIP archives for XML and XSD files to be processed
    foreach my $archive (@archives) {
        scan_archive($archive, $files);
    }

    # check for illegally duplicated files
    # XXX don't necessarily want to die; alternative would be command-line
    #     means of controlling behavior
    # XXX note hack to include additional schemas here
    my @allow_duplicates = ("cwmp-datamodel-report.xsd",
                            @{$options->{support}});
    die if check_duplicates(\@allow_duplicates, $files);

    # update file objects to reference the latest amendments and corrigenda
    update_latest($files);

    #print STDERR Dumper(grep {$_->{name} =~ /-(biblio|types)/} @$files);

    # split the files into categories
    # XXX should use a single hash for this
    my $dm0ns = [];
    my $dm1ns = [];
    my $dm0cs = [];
    my $dm1cs = [];
    my $comps = [];
    my $supps = [];
    my $xsds  = [];
    my $nones = [];
    categorize_files($files, $options->{comps}, $options->{comproots},
                     $options->{notmajors}, $options->{support}, $dm0ns,
                     $dm1ns, $dm0cs, $dm1cs, $comps, $supps, $xsds, $nones);

    # sort the files (cosmetic only)
    $dm0ns = sort_uniq(@$dm0ns);
    $dm1ns = sort_uniq(@$dm1ns);
    $dm0cs = sort_uniq(@$dm0cs);
    $dm1cs = sort_uniq(@$dm1cs);
    $comps = sort_uniq(@$comps);
    $supps = sort_uniq(@$supps);
    $xsds  = sort_uniq(@$xsds);
    $nones = sort_uniq(@$nones);

    # generate in-memory restricted makefile
    # XXX currently just writing it to stdout; can pipe to make -f-
    gen_makefile($dm0ns, $dm1ns, $dm0cs, $dm1cs, $comps, $supps, $xsds, $nones,
        $options->{cwmpdir}, $options->{wtdir}, $options->{workdir},
        $options->{od148}, $options->{oldroots}, $options->{makevar});

    # create the working directory if necessary
    # XXX should have option to remove it (dangerous) or check that it's empty?
    #     better just to make sure that the messages are clear
    # XXX suppressed because the makefile creates it if necessary
    #mkpath($options->{workdir});

    # how best to create results; separate directory containing only what is
    # to be uploaded?

    # controls over what to re-generate, e.g. won't always re-generate all HTML

    # also generate cwmp.zip? (would need single directory for that)

    # delete all "omitted corrigendum" files (or some only?)

    # run report.exe to generate products (which? dependencies?)

    # create the copies (two modes? full and delta?)

    # see Report Tool comments
}

# Invoke main program
main();
