#!/usr/bin/perl -w
#
# experiment with white space prettification

use strict;
no strict "refs";

use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use Text::Tabs ();
use XML::LibXML;

# XXX do we need to check descriptions and/or check some "last" children?

my $deftab = 2;

my $catalog = 'catalog.xml';
my $help = 0;
my $tabstop = undef;
GetOptions('catalog:s' => \$catalog,
           'help' => \$help,
           'tabstop:i' => \$tabstop) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(2) if @ARGV != 1;

my $file = $ARGV[0];

my $parser = XML::LibXML->new(catalog => $catalog);

# parse XML file, and determine location of its schema
my $xmltop = parse_file($parser, $file);

# if tabstop not specified, determine it empirically
if (!defined $tabstop) {
    $tabstop = 1;
    my $min_errors = 9999;
    for (my $trial_tabstop = 2; $trial_tabstop <= 8; $trial_tabstop++) {
        my $errors = check($xmltop, {tabstop => $trial_tabstop, quiet => 1});
        if ($errors < $min_errors) {
            $tabstop = $trial_tabstop;
            $min_errors = $errors;
        }
        #print STDERR "#### tabstop $trial_tabstop -> $errors errors\n";
    }
    print STDERR "#### file appears to use tabstop $tabstop\n";
}

my $errors = check($xmltop, {tabstop => $tabstop});
print STDERR "#### $errors errors\n";

# end of main program

# check node indentation and then iterate over its children
sub check
{
    my ($node, $opts) = @_;

    my $error; # used if not supplied via options

    my $first = defined $opts->{first} ? $opts->{first} : 1;
    my $last = defined $opts->{last} ? $opts->{last} : 1;
    # XXX initialised to -1 for document node so top-level node can be 0
    # XXX can't in fact discover if top-level node indentation is wrong?
    my $indent = defined $opts->{indent} ? $opts->{indent} : -1;
    my $tabstop = defined $opts->{tabstop} ? $opts->{tabstop} : $deftab; 
    my $errref = defined $opts->{errref} ? $opts->{errref} : \$error;
    my $quiet = defined $opts->{quiet} ? $opts->{quiet} : 0;

    my $errors = 0;

    my $name = $node->nodeName();
    my $text = ($name eq '#text');
    my $value = $node->toString();

    my @childNodes = $node->childNodes();

    # expand tabs if necessary
    if ($text && $value =~ /\t/) {
        print STDERR "#### text node contains tab(s)\n" unless $quiet;
        my $tvalue = $value;
        $tvalue =~ s/\t/\\t/g;
        $tvalue =~ s/\n/\\n/g;
        #print STDERR "old: [$tvalue]\n" unless $quiet;
        $Text::Tabs::tabstop = $tabstop;
        $value = Text::Tabs::expand($value);
        $tvalue = $value;
        $tvalue =~ s/\n/\\n/g;
        #print STDERR "new: [$tvalue]\n" unless $quiet;
        $errors++;
    }

    my $tvalue = $text ? qq{ |$value|} : '';
    $tvalue =~ s/\n/\\n/g;
    #print STDERR "!!!! $indent $name$tvalue\n" unless $quiet;

    # this will not be text node because never get two consecutive text nodes?
    # XXX not quite right; never get two consecutive text nodes at the same
    #     level but get them as the stack is "unwound"
    if ($$errref) {
        my $tvalue = $value;
        $tvalue =~ s/\n.*//;
        print STDERR "$$errref$tvalue\n" unless $quiet;
        undef $$errref;
    }

    # check text node indentation
    if ($text) {

        # if value contains only spaces, newline and leading space, check that
        # leading space has the correct indent (but not for the last node,
        # for which the indent is expected to be decreased)
        # XXX this might not be right; earlier had special case for last child:
        #     decremented indent
        my $white = ($value =~ /^(?: *\n)+( *)$/);
        if ($white && ($first || !$last)) {
            my $actual = length $1;
            my $expected = $tabstop * $indent;
            if ($actual != $expected) {
                print STDERR "#### bad indentation ($actual spaces should " .
                    "be $expected)\n" unless $quiet;
                $$errref = ' ' x $actual;
                $errors++;
            }
        }

        # element values are the first text nodes at the new level that have
        # no children
        # XXX complicated; do we need the "no children" criterion?
        elsif ($first && !@childNodes) {
            # XXX same check as above for leading whitespace, then check that
            #     each line has at least the expected indentation (if more then
            #     ideally should be in units of indentation?); need to check
            #     trailing whitespace because this indicates whether the
            #     closing tag has the right indentation (it's not a node)
            print STDERR "!!!! content$tvalue\n" unless $quiet;
        }
    }
    
    my $i = 0;
    foreach my $child (@childNodes) {
        $errors += check($child, {first => ($i == 0),
                                  last => ($i == @childNodes - 1) ? 1 : 0,
                                  indent => $indent + 1,
                                  tabstop => $tabstop,
                                  errref => $errref,
                                  quiet => $quiet});
        $i++;
    }

    return $errors;
}

# parse XML file and return top-level element
sub parse_file
{
    my ($parser, $file) = @_;

    my $tree = $parser->parse_file($file);
    my $top = $tree->getDocumentElement;
    # XXX note; returning tree (document node)
    return $tree;
}

=head1 NAME

XXX TBD
