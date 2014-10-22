the simple plugin that is shown in the BBF report tool help text (report.pl --help)

the help output is given below; here's an example of how to run it (substitute an
appropriate --include path):

../../report.pl --include=$HOME/bin/cwmp --plugin=foo --report=foo tr-135-1-3.xml >foo.txt

    --plugin=s...
        can be specified multiple times; defines external plugins that can
        define additional report types

        *   currently each plugin must correspond to a file of the same name
            but with a .pm (Perl Module) extension; for example,
            --plugin=foo must correspond to a file called foo.pm; the
            directories specified via the Perl include path (including the
            current directory) and via --include are searched

        *   each plugin must define a package of the same name and can
            define one of more routines with names of the form rrr_node; rrr
            becomes an additional report type; if only one such routine is
            defined then by convention rrr should be the same as the plugin
            name; for example, foo.pm will always define the foo package and
            will usually define a foo_node routine

        *   the file can optionally also define routines with names of the
            form rrr_init, rrr_begin, rrr_postpar, rrr_post and rrr_end

        *   rrr_init is called after processing command line arguments but
            before reading any of the DM files; it can be used for
            initializing the plugin, e.g. parsing configuration files

        *   each of the other routines is called with three arguments; the
            first is the node on which it is to report; the second is the
            indentation level (0 means the initial call, for which the node
            is the root node, i.e. the parent of any model nodes); the third
            is a reference to an option hash

        *   the begin routine is called at the beginning; the node routine
            is called for each node; the postpar routine (if defined) is
            called after parameter node routines have been called; the post
            routine (if defined) is called after child node node routines
            have been called; the end routine is called at the end; these
            routines are not themselves responsible for traversing child
            nodes

        *   the node object is a reference to a hash that contains keys such
            as path and name; it is not currently documented

        *   it is safe to store information on the node; any new names
            should begin rrr_ in order to avoid name clashes

        *   these instructions are not expected to be sufficient to write a
            plugin; it will be necessary to consult the main report tool
            source code; the plugin interface may change in the future, in
            which case plugins may need to be adjusted

        *   the following illustrates just about the simplest possible valid
            plugin; it would be placed in a file called foo.pm and would be
            used by specifying --plugin=foo --report=foo

             package foo;
 
             sub foo_node
             {
                 my ($node) = @_;
                 print "$node->{path}\n";
             }
 
             1;
