#!/usr/bin/env perl
#
# investigate determination and representation of description differences

use strict;
use warnings;

require "../../report.pl";

my $pairs = [
    [qq{1 2 3 {{bibref|x}}\nanother line},
     qq{A 2  3 {{bibref|y}} new text\n\n\nreplacement line}],

    [qq{Specify the protocol.},
     qq{Specifies the protocol variant used for the interface.  {{enum}}\n}.
     qq{The list MAY include vendor-specific protocols, which MUST use the format defined in {{bibref|TR-106}}.}],

    [qq{Enables or disables this extension, or places it into a quiescent state. {{enum}}.\n}.
     qq{In the {{enum|Quiescent}} state, in-progress sessions remain intact, but no new sessions are allowed. If this parameter is set to {{enum|Quiescent}} in a CPE that does not support the {{enum|Quiescent}} state, it MUST treat it the same as the {{enum|Disable}} state (and indicate {{enum|Disabled|Status}} in {{param|Status}}).},
     qq{Enable or disable this extension.}],

    [qq{Automatically generated, for example by a ESBC that autocreates {{object}} objects},
     qq{Automatically generated, for example by a ESBC that auto-creates client objects}],

    [qq{line 1\nline 2},
     qq{line 1\nline 1a\nline 2}]
    ];

foreach my $pair (@$pairs) {
    print "\n", util_diffs_markup($pair->[0], $pair->[1]), "\n\n";
}
