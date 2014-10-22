#!/usr/bin/env perl
#
# Copyright (C) 2013  Cisco Systems
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

# XXX run with perl -d:NYTProf to find where the time is spent

# XXX should catch signals and delete current target when interrupted?

use strict;
use warnings;

no autovivification qw{fetch exists delete warn};

# XXX uncomment to enable traceback on warnings and errors
#use Carp::Always;
use Data::Dumper;
use File::stat;
use File::Spec;
use File::Touch;
# XXX not used because was so slow
#use Text::Balanced qw{extract_bracketed};

# each src or dst is a tgt (target), keyed by name; later on:
# * dep points to the dep with the rule to build this (populated by get_dep)
# * dsts points to tgts which depend on this (populated by gen_tree)
my $tgts = {};
sub get_tgt {
    my ($name) = @_;
    if (!defined $tgts->{$name}) {
        $tgts->{$name} = {name => $name, dep => undef, dsts => []};
    }
    return $tgts->{$name};
}

# each dst: src relationship is a dep (dependency), keyed by dst
my $deps = {};
sub get_dep {
    my ($dst, $rule) = @_;
    if (!defined $deps->{$dst}) {
        $deps->{$dst} = {dst => get_tgt($dst), srcs => [], rule => $rule};
    } elsif ($rule) {
        if ($deps->{$dst}->{rule}) {
            die "multiple rules for destination $dst";
        }
        $deps->{$dst}->{rule} = $rule;
    }
    $deps->{$dst}->{dst}->{dep} = $deps->{$dst};
    return $deps->{$dst};
}

my $def_tgt;
my $phony = {};
sub add_dep {
    my ($dsts, $srcs, $rule) = @_;
    #print "#### $dsts: $srcs; $rule\n";
    my $dep;
    foreach my $dst (split ' ', $dsts) {
        if ($dst eq '.PHONY') {
            foreach my $src (split ' ', $srcs) {
                $phony->{$src} = 1;
            }
        } else {
            $def_tgt = $dst unless $def_tgt;
            $dep = get_dep($dst, $rule);
            foreach my $src (split ' ', $srcs) {
                if (my $path = is_dep($dst, $src)) {
                    die "recursive $path";
                }
                push @{$dep->{srcs}}, get_tgt($src);
            }
        }
    }
    return $dep;
}

# check for recursive dependencies
sub is_dep {
    my ($dst, $src, $path) = @_;
    $path = $path ? qq{$path -> $dst} : qq{$dst};
    my $dep = $deps->{$dst};
    if (defined $dep) {
        foreach my $src_tgt (@{$dep->{srcs}}) {
            my $tmp = $src_tgt->{name};
            if (defined $deps->{$tmp} &&
                grep {$_->{name} eq $src} @{$deps->{src_tgts}}) {
                return qq{$path -> $tmp};
            } else {
                return is_dep($tmp, $src, $path);
            }
        }
    }
    return qq{};
}

# XXX could initialise with environment variables; if did, would have to think
#     about override behaviour...
my $vars = {};
sub load_vars {
    $vars->{sort} = qq{};
}

sub parse_line {
    my ($line) = @_;

    # look for comment
    # XXX also allow trailing comments?
    return if $line =~ /^\s*#/;
    
    # look for name = value
    my ($name, $value) = ($line =~ /^\s*(\w+)\s*=\s*(.*)/);
    if (defined($name) && defined($value)) {
        #print "#### $name = $value\n";
        $vars->{$name} = $value;
        return;
    }

    # look for dsts: srcs; rule
    my ($dsts, $srcs, $rule) = ($line =~ /^\s*([^:]*):\s*([^;]*);?\s*(.*)/);
    $dsts =~ s/\s*$// if defined $dsts;
    $srcs =~ s/\s*$// if defined $srcs;
    $rule =~ s/\s*$// if defined $rule;

    # variable references are expanded now
    $dsts = expand_vars($dsts) if $dsts;
    $srcs = expand_vars($srcs) if $srcs;
    $rule = expand_vars($rule) if $rule;

    add_dep($dsts, $srcs, $rule) if $dsts;

    # report if line not used (unless blank)
    if (!$dsts) {
        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        print "ignored line $line\n" if $line;
    }
}

# re-implementation of Text::Balanced::extract_bracketed
# ($extracted, $remainder, $prefix) =
#     extract_bracketed($text, $delim_pairs, $prefix_pattern)
# XXX it's better but not much better; general opinion seems to be not to
#     to descend to this C-like level!
sub extract_bracketed {
    my ($text, $delim_pairs, $prefix_pattern) = @_;

    # we only support '()' delim_pairs and '\$' prefix_pattern
    die "unsupported arguments for local extract_bracketed()"
        if $delim_pairs ne '()' || $prefix_pattern ne '\$';

    # require first two characters to be '$('
    die "string doesn't begin with '$(' in local extract_bracketed()"
        if $text !~ /^\$\(/;

    my $i;
    my $plev = 1;
    for ($i = 2; $plev && $i < length($text); $i++) {
        my $c = substr($text, $i, 1);
        $plev++ if $c eq '(';
        $plev-- if $c eq ')';
    }
    die "unbalanced '()' in local extract_bracketed()" if $plev;

    my $prefix    = substr($text, 0, 1);
    my $extracted = substr($text, 1, $i-1);
    my $remainder = substr($text, $i);

    return wantarray ? ($extracted, $remainder, $prefix) : $extracted;
}

sub expand_vars {
    my ($text, $level, $already) = @_;
    $level = 0 unless defined $level;
    $already = {} unless defined $already;

    while (1) {
        # $(name), $(name:subs), $(name special)
        my ($nameref, $name) = $text =~ /(\$\((\w+).*)/;
        last unless $nameref;

        my $temp = extract_bracketed($nameref, '()', '\$');
        die "invalid variable reference (not terminated?) in $nameref"
            unless $temp;
        $nameref = '$' . $temp;

        my $value = $vars->{$name};
        die "undefined variable $name" unless defined($value);

        if (!defined($already->{$name})) {
            $already->{$name} = $level;
        } else {
            die "recursive variable definition $name = $value"
                if $level > $already->{$name};        
        }

        # check for special variable and substitutions
        my ($sep, $rest) = $nameref =~ /\$\($name([: ])?(.*)\)$/;

        $value = expand_vars($value, $level+1, $already);
        $rest = expand_vars($rest, $level+1, $already);

        if (!$sep) {
        }

        # subs: $(name:%=pattern) (substitutes first % in pattern)
        # XXX if syntax is unexpected, quietly ignore what's after colon
        # XXX need to check that even edge cases work the same way as
        #     GNU make
        elsif ($sep eq ':') {
            if ($rest) {
                my ($lhs, $rhs) = $rest =~ /([^=]*)=(.*)/;
                if (defined($lhs) && defined($rhs) && $lhs =~ /^%/) {
                    $lhs =~ s/%//;
                    my $newvalue = '';
                    foreach my $val (split ' ', $value) {
                        $val =~ s/\Q$lhs\E$//;
                        my $new = $rhs;
                        # as for GNU make, only the first % is substituted
                        $new =~ s/%/$val/;
                        $newvalue .= ' ' if $newvalue;
                        $newvalue .= $new;
                    }
                    $value = $newvalue;
                }
            }
        }   
        
        # special
        elsif ($sep eq ' ') {
            if ($name eq 'sort') {
                my %s = ();
                # because I can...
                $value = join ' ', grep {!$s{$_}++} sort split ' ', $rest;
            }
        }

        $text =~ s/\Q$nameref\E/$value/g;
    }
    return $text;
}

# root points to src; src points to dst(s)
my $root = {name => 'root', dsts => []};
sub gen_tree {
    my ($tgt, $level) = @_;
    my $indent = '  ' x $level;
    #print "$indent$tgt:\n";
    my $dep = $deps->{$tgt};

    # if no dep, add tgt: (no srcs or rule)
    if (!$dep) {
        #print "$indent  adding dep\n";
        $dep = add_dep($tgt, '', '');
    }

    # if no srcs, it's a rank 1 (source) file
    if (!@{$dep->{srcs}}) {
        #print "$indent  root -> $tgt\n";
        push @{$root->{dsts}}, get_tgt($tgt) unless
            grep {$_->{name} eq $tgt} @{$root->{dsts}};
    }

    my $dst = $dep->{dst};
    my $rule = $dep->{rule};
    foreach my $src (@{$dep->{srcs}}) {
        #print "$indent  $src->{name} -> $dst->{name}\n";
        push @{$src->{dsts}}, $dst unless
            grep {$_->{name} eq $dst->{name}} @{$src->{dsts}};
        
        gen_tree($src->{name}, $level+1);
    }
}

# XXX it's not really a tree (targets can be reported multiple times)
# XXX can delete this
sub report_tree {
    my ($node, $level) = @_;
    my $indent = '  ' x $level;
    print "$indent$node->{name} $node->{rank}\n";
    foreach my $dst (@{$node->{dsts}}) {
        report_tree($dst, $level+1);
    }
}

my $max_rank;
sub set_ranks {
    my ($node, $rank) = @_;
    $node->{rank} = $rank if !defined($node->{rank}) || $rank > $node->{rank};

    $max_rank = $node->{rank} if
        !defined($max_rank) || $node->{rank} > $max_rank;

    foreach my $dst (@{$node->{dsts}}) {
        set_ranks($dst, $rank+1);
    }
}

my $tgts_by_rank = {};
sub collect_ranks {
    my ($node) = @_;
    my $rank = $node->{rank};
    my $tmp = \$tgts_by_rank->{$rank};
    push @$$tmp, $node unless grep {$_ == $node} @$$tmp;
    foreach my $dst (@{$node->{dsts}}) {
        collect_ranks($dst);
    }
}

sub get_mtime {
    my ($file, $phony) = @_;
    if ($phony) {
        return 0;
    } else {
        my $st = stat($file);
        return $st ? $st->mtime : 0;
    }
}

# if no dependency or no rule, just require it to exist
sub is_up_to_date {
    my ($tgt) = @_;

    my $dep = $tgt->{dep};
    my $rule = $dep ? $dep->{rule} : '';

    my $tgt_mtime = get_mtime($tgt->{name}, $phony->{$tgt->{name}});

    if (!$rule) {
        die "$tgt->{name} doesn't exist (no rule)"
            unless $tgt_mtime || $phony->{$tgt->{name}};
        return 1;
    }

    my $up_to_date = $tgt_mtime ? 1 : 0;
    #print "$tgt->{name} $tgt_mtime: ";
    my $srcs = $dep->{srcs};
    foreach my $src (@{$dep->{srcs}}) {
        my $src_mtime = get_mtime($src->{name}, $phony->{$src->{name}});
        #print "$src_mtime ";
        die "$src->{name} doesn't exist (needed by $dep->{dst}->{name})"
            unless $src_mtime || $phony->{$src->{name}};
        $up_to_date = 0 if $src_mtime > $tgt_mtime;
    }
    #print "\n";

    return $up_to_date;
}

sub exec_cmd {
    my ($cmd) = @_;
    
    # check for known built-in commands (ignore directories)
    my ($path, @args) = split ' ', $cmd;
    my ($vol, $dir, $name) = File::Spec->splitpath($path);
    my $rc;

    # XXX should also handle (at least) cp.pl, extract.pl

    # touch.pl
    # XXX should check there are no options specified (or handle any...)
    if ($name eq 'touch.pl') {
        my $nfiles = @args;
        $rc = (touch(@args) == $nfiles) ? 0 : -1;
    }

    # fall through to system()
    else {
        $rc = system($cmd);
    }
        

    return $rc;
}

sub exec_rule {
    my ($rule) = @_;

    # rule might have leading "@" (don't report command) or "-" (ignore error)
    $rule =~ s/^([@-])//;
    my $quiet  = ($1 && $1 eq '@');
    my $ignore = ($1 && $1 eq '-');

    print "$rule\n" unless $quiet;

    # check whether all the rule's command names have .pl extensions
    # XXX this isn't the right criterion really, but it's nice to use something
    #     that doesn't break GNU make; better to check for "perl xxx"?
    # XXX this assumes there are no escaped semi-colons
    my $all_pl = 1;
    my @cmds = split /\s*;\s*/, $rule;
    foreach my $cmd (@cmds) {
        my ($path) = split ' ', $cmd;
        $all_pl = 0 if $path !~ /\.pl$/;
    }

    # if so, execute each one internally
    my $rc;
    if ($all_pl) {
        foreach my $cmd (@cmds) {
            $rc = exec_cmd($cmd);
            last if $rc != 0;
        }
    }

    # otherwise use system()
    else {
        $rc = system($rule);
    }

    return $rc;
}

sub main {
    my $quiet = 1;

    load_vars();

    while (<ARGV>) {
        parse_line($_);
    }

    gen_tree($def_tgt, 0) if $def_tgt;

    set_ranks($root, 0);
    collect_ranks($root);

    #report_tree($root, 0);

    # XXX should honour "-" and "@" prefixes; also "-B" and "-n"
    for (my $rank = 1; $rank <= $max_rank; $rank++) {
        my $tgts = $tgts_by_rank->{$rank};
        print "$rank\n" unless $quiet;
        foreach my $tgt (@$tgts) {
            my $up_to_date = is_up_to_date($tgt);
            
            print "  $tgt->{name}: " unless $quiet;
            my $dep = $tgt->{dep};
            if (!$dep) {
                print "<no-dep>\n" unless $quiet;
            } else {
                my $src0 = $dep->{srcs}->[0] ?
                    $dep->{srcs}->[0]->{name} : '<no-src>';
                my $srcs = qq{};
                foreach my $src (@{$dep->{srcs}}) {
                    $srcs .= qq{$src->{name} };
                }
                chop $srcs;
                my $rule = $dep->{rule} ? $dep->{rule} : '<no-rule>';
                $rule =~ s/\$\@/$tgt->{name}/g;
                $rule =~ s/\$\</$src0/g;
                $rule =~ s/\$\^/$srcs/g;
                if ($up_to_date) {
                    print "<up-to-date>\n" unless $quiet;
                } else {
                    print "$srcs; $rule\n" unless $quiet;
                    if (exec_rule($rule) != 0) {
                        # XXX should this be unconditional?
                        unlink($tgt->{name});
                        die "$rule failed: $!";
                    }
                    die "$tgt->{name} not created by rule"
                        unless $phony->{$tgt->{name}} || get_mtime($tgt->{name});
                }
            }
        }
    }
}

main();
