#!/usr/bin/env perl
#
# experiment with algorithm for finding files

use strict;
no strict "refs";
use warnings;

use File::Spec;

my $HOME = $ENV{HOME};

my $dirs = [
    File::Spec->curdir(),
    "$HOME/bin/cwmp-ils",
    "$HOME/bin/cwmp-wts",
    "$HOME/bin/cwmp-trs"
];

sub find_file {
    my ($file) = @_;
    print "find_file $file\n";
        
    my ($tr, $nnn, $i, $a, $c, $label, $ext) =
        $file =~ /^([^-]+)?(?:-(\d+))?(?:-(\d+))?(?:-(\d+))?(?:-(\d+))?(-\d*\D.*)?(\..*)$/;
    if ($tr && $nnn) {
        $i = '*' unless defined $i;
        $a = '*' unless defined $a;
        $c = '*' unless defined $c;
        $label = '' unless defined $label;
        $ext = '' unless defined $ext;

        # XXX not right; need to include the "-" in $i etc here, so there
        #     is nothing when they aren't there; think tr-069-biblio.xml!
        my $file2 = qq{$tr-$nnn-$i-$a-$c$label$ext};
        print "  $file2\n";

        foreach my $dir (@$dirs) {
            print "$dir\n";
            my @files = glob(File::Spec->catfile($dir, $file2));
            foreach my $file (@files) {
                (my $tvol, my $tdir, $file) = File::Spec->splitpath($file);
                my ($ia, $aa, $ca) = $file =~
                    /^\Q$tr\E-\Q$nnn\E-(\d+)-(\d+)-(\d+)\Q$label$ext\E$/;
                if (defined $ia && defined $aa && defined $ca) {
                    print "    $file ($ia, $aa, $ca)\n";
                }
            }
        }
    }
}

# main program
foreach my $file (@ARGV) {
    find_file($file);
}
